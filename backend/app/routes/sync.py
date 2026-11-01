"""Synchronisation des téléphones (clients et projets).

Principe (docs/ARCHITECTURE.md §3.4) :
- le téléphone envoie ses enregistrements modifiés avec la version sur laquelle il s'est
  basé (verrouillage optimiste) ; une version périmée produit un conflit, jamais un
  écrasement silencieux ;
- il récupère ensuite tout ce qui a changé depuis son dernier numéro d'ordre (sync_seq),
  suppressions comprises.

Droits : administrateur = toute l'organisation ; collaborateur = projets qu'il a créés ou
dont il est responsable, et clients qu'il a créés ou liés à ces projets ; client = aucun
accès (espace client à venir). La sécurité au niveau des lignes de PostgreSQL limite en
plus chaque requête à l'organisation de l'utilisateur.
"""

import uuid
from datetime import date, datetime
from typing import Annotated, Any, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from pydantic import BaseModel, ConfigDict, EmailStr, Field, ValidationError, field_validator
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..audit import audit
from ..db import get_db
from ..deps import Context, require_staff
from ..models import (
    CLIENT_TYPES,
    CURRENCIES,
    PROJECT_STATUSES,
    PROJECT_TYPES,
    PROPERTY_KINDS,
    Client,
    OrgCounter,
    Organization,
    Project,
    Role,
    User,
)
from ..security import now

router = APIRouter(prefix="/sync", tags=["synchronisation"])

MAX_CHANGES = 200
PAGE_SIZE = 500


# ---------- contenu des enregistrements ----------


class ClientData(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    type: Literal[CLIENT_TYPES] = "individual"  # type: ignore[valid-type]
    display_name: str = Field(min_length=1, max_length=200)
    phone: str = Field(default="", max_length=30)
    email: EmailStr | Literal[""] = ""
    address: str = Field(default="", max_length=2000)
    city: str = Field(default="", max_length=100)
    ice: str = Field(default="", pattern=r"^(\d{15})?$")
    notes: str = Field(default="", max_length=10000)
    consent_at: datetime | None = None
    consent_text_version: str = Field(default="", max_length=20)


class ProjectData(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    client_id: uuid.UUID | None = None
    name: str = Field(default="", max_length=200)
    project_type: Literal[PROJECT_TYPES] = "renovation"  # type: ignore[valid-type]
    property_kind: Literal[PROPERTY_KINDS] | None = None  # type: ignore[valid-type]
    status: Literal[PROJECT_STATUSES] = "prospect"  # type: ignore[valid-type]
    description: str = Field(default="", max_length=10000)
    budget_cents: int | None = Field(default=None, ge=0)
    currency: Literal[CURRENCIES] = "MAD"  # type: ignore[valid-type]
    visit_date: date | None = None
    manager_id: uuid.UUID | None = None
    site_address: str = Field(default="", max_length=2000)
    site_city: str = Field(default="", max_length=100)
    notes: str = Field(default="", max_length=10000)


ENTITIES: dict[str, tuple[type, type[BaseModel]]] = {
    "clients": (Client, ClientData),
    "projects": (Project, ProjectData),
}


class Change(BaseModel):
    entity: Literal["clients", "projects"]
    id: uuid.UUID
    base_version: int | None = Field(default=None, ge=1)
    deleted: bool = False
    data: dict[str, Any] = Field(default_factory=dict)


class PushIn(BaseModel):
    changes: list[Change] = Field(max_length=MAX_CHANGES)


class RecordOut(BaseModel):
    entity: str
    id: uuid.UUID
    version: int
    deleted: bool
    sync_seq: int
    updated_at: datetime
    reference: str | None = None
    data: dict[str, Any]


class ChangeResult(BaseModel):
    entity: str
    id: uuid.UUID
    status: Literal["applied", "conflict", "rejected"]
    message: str | None = None
    record: RecordOut | None = None


class PushOut(BaseModel):
    results: list[ChangeResult]


class PullOut(BaseModel):
    records: list[RecordOut]
    cursor: int
    has_more: bool


# ---------- outils ----------


def _record(entity: str, row: Client | Project) -> RecordOut:
    _, schema = ENTITIES[entity]
    data = {name: getattr(row, name) for name in schema.model_fields}
    return RecordOut(
        entity=entity,
        id=row.id,
        version=row.version,
        deleted=row.deleted_at is not None,
        sync_seq=row.sync_seq,
        updated_at=row.updated_at,
        reference=getattr(row, "reference", None),
        data=data,
    )


def _visible_projects(ctx: Context):  # type: ignore[no-untyped-def]
    q = select(Project).where(Project.organization_id == ctx.organization_id)
    if Role.admin not in ctx.roles:
        q = q.where(or_(Project.created_by == ctx.user.id, Project.manager_id == ctx.user.id))
    return q


def _visible_clients(ctx: Context):  # type: ignore[no-untyped-def]
    q = select(Client).where(Client.organization_id == ctx.organization_id)
    if Role.admin not in ctx.roles:
        linked = (
            select(Project.client_id)
            .where(
                Project.organization_id == ctx.organization_id,
                or_(Project.created_by == ctx.user.id, Project.manager_id == ctx.user.id),
                Project.client_id.is_not(None),
            )
            .scalar_subquery()
        )
        q = q.where(or_(Client.created_by == ctx.user.id, Client.id.in_(linked)))
    return q


def _next_reference(db: Session, organization_id: uuid.UUID) -> str:
    year = now().year
    counter = db.get(OrgCounter, (organization_id, "project", year), with_for_update=True)
    if counter is None:
        counter = OrgCounter(organization_id=organization_id, name="project", year=year, value=0)
        db.add(counter)
    counter.value += 1
    db.flush()
    org = db.get(Organization, organization_id)
    prefix = org.reference_prefix if org else "LMA"
    return f"{prefix}-{year}-{counter.value:04d}"


class _Rejected(Exception):
    pass


def _check_links(db: Session, ctx: Context, entity: str, data: BaseModel) -> None:
    if entity != "projects":
        return
    assert isinstance(data, ProjectData)
    if data.client_id is not None:
        client = db.scalar(_visible_clients(ctx).where(Client.id == data.client_id, Client.deleted_at.is_(None)))
        if client is None:
            raise _Rejected("Le client choisi n'existe pas ou a été supprimé.")
    if data.manager_id is not None and data.manager_id != ctx.user.id:
        if Role.admin not in ctx.roles:
            raise _Rejected("Seul un administrateur peut confier un projet à une autre personne.")
        manager = db.scalar(
            select(User.id).where(
                User.id == data.manager_id, User.organization_id == ctx.organization_id, User.deleted_at.is_(None)
            )
        )
        if manager is None:
            raise _Rejected("Le responsable choisi n'existe pas.")


def _apply(db: Session, ctx: Context, change: Change, request: Request) -> ChangeResult:
    model, schema = ENTITIES[change.entity]
    visible = _visible_clients(ctx) if change.entity == "clients" else _visible_projects(ctx)
    row = db.scalar(visible.where(model.id == change.id).with_for_update())

    def result(st: str, message: str | None = None, r: Client | Project | None = None) -> ChangeResult:
        return ChangeResult(
            entity=change.entity,
            id=change.id,
            status=st,  # type: ignore[arg-type]
            message=message,
            record=_record(change.entity, r) if r is not None else None,
        )

    # --- création ---
    if row is None:
        if change.base_version is not None:
            return result("rejected", "Cet élément n'existe plus sur le serveur ou ne vous est plus accessible.")
        if change.deleted:
            return result("applied")  # créé puis supprimé hors ligne : rien à faire
        data = schema.model_validate(change.data)
        _check_links(db, ctx, change.entity, data)
        values = data.model_dump()
        if change.entity == "projects":
            values["reference"] = _next_reference(db, ctx.organization_id)
            values["manager_id"] = values["manager_id"] or ctx.user.id
        row = model(
            id=change.id,
            organization_id=ctx.organization_id,
            created_by=ctx.user.id,
            updated_by=ctx.user.id,
            **values,
        )
        db.add(row)
        db.flush()
        audit(db, f"{change.entity[:-1]}.create", request=request, organization_id=ctx.organization_id,
              actor_id=ctx.user.id, actor_role=ctx.main_role.value, entity_table=change.entity, entity_id=row.id,
              project_id=row.id if change.entity == "projects" else None)
        db.refresh(row)
        return result("applied", r=row)

    # --- modification ou suppression ---
    if change.base_version != row.version:
        return result("conflict", "Modifié entre-temps par quelqu'un d'autre.", row)

    if change.deleted:
        if row.deleted_at is not None:
            return result("applied", r=row)
        if change.entity == "clients":
            if Role.admin not in ctx.roles:
                raise _Rejected("Seul un administrateur peut supprimer une fiche client.")
            used = db.scalar(
                select(Project.id).where(Project.client_id == row.id, Project.deleted_at.is_(None)).limit(1)
            )
            if used is not None:
                raise _Rejected("Ce client a encore des projets : supprimez-les ou rattachez-les à un autre client.")
        elif Role.admin not in ctx.roles and row.created_by != ctx.user.id:
            raise _Rejected("Seul l'auteur du projet ou un administrateur peut le supprimer.")
        row.deleted_at = now()
        audit(db, f"{change.entity[:-1]}.delete", request=request, organization_id=ctx.organization_id,
              actor_id=ctx.user.id, actor_role=ctx.main_role.value, entity_table=change.entity, entity_id=row.id,
              project_id=row.id if change.entity == "projects" else None)
    else:
        data = schema.model_validate(change.data)
        _check_links(db, ctx, change.entity, data)
        if change.entity == "projects" and Role.admin not in ctx.roles and data.manager_id != row.manager_id:
            raise _Rejected("Seul un administrateur peut changer le responsable d'un projet.")
        if row.deleted_at is not None:
            row.deleted_at = None  # restauration volontaire depuis le téléphone (conflit résolu)
            audit(db, f"{change.entity[:-1]}.restore", request=request, organization_id=ctx.organization_id,
                  actor_id=ctx.user.id, actor_role=ctx.main_role.value, entity_table=change.entity, entity_id=row.id)
        for key, value in data.model_dump().items():
            setattr(row, key, value)
    row.version += 1
    row.updated_by = ctx.user.id
    db.flush()
    db.refresh(row)
    return result("applied", r=row)


def _validation_message(exc: ValidationError) -> str:
    first = exc.errors()[0]
    field = ".".join(str(x) for x in first.get("loc", ()))
    return f"Information invalide ({field})." if field else "Information invalide."


# ---------- routes ----------


@router.post("/push", response_model=PushOut)
def push(
    body: PushIn, request: Request, ctx: Context = Depends(require_staff), db: Session = Depends(get_db)
) -> PushOut:
    """Applique les modifications dans l'ordre reçu. Chaque modification réussit ou échoue seule."""
    results: list[ChangeResult] = []
    for change in body.changes:
        savepoint = db.begin_nested()
        try:
            results.append(_apply(db, ctx, change, request))
            savepoint.commit()
        except (_Rejected, ValidationError, IntegrityError) as exc:
            savepoint.rollback()
            if isinstance(exc, _Rejected):
                message = str(exc)
            elif isinstance(exc, ValidationError):
                message = _validation_message(exc)
            else:
                message = "Enregistrement refusé par le serveur (identifiant déjà utilisé ou lien invalide)."
            results.append(ChangeResult(entity=change.entity, id=change.id, status="rejected", message=message))
    db.commit()
    return PushOut(results=results)


@router.get("/pull", response_model=PullOut)
def pull(
    cursor: Annotated[int, Query(ge=0)] = 0,
    ctx: Context = Depends(require_staff),
    db: Session = Depends(get_db),
) -> PullOut:
    """Enregistrements modifiés après `cursor`, dans l'ordre, suppressions comprises."""
    records: list[RecordOut] = []
    for entity, query in (("clients", _visible_clients(ctx)), ("projects", _visible_projects(ctx))):
        model, _ = ENTITIES[entity]
        rows = db.scalars(query.where(model.sync_seq > cursor).order_by(model.sync_seq).limit(PAGE_SIZE + 1)).all()
        records.extend(_record(entity, r) for r in rows)
    records.sort(key=lambda r: r.sync_seq)
    has_more = len(records) > PAGE_SIZE
    records = records[:PAGE_SIZE]
    next_cursor = records[-1].sync_seq if records else cursor
    return PullOut(records=records, cursor=next_cursor, has_more=has_more)
