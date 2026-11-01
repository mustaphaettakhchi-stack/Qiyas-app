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
from decimal import Decimal
from typing import Annotated, Any, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from pydantic import BaseModel, ConfigDict, EmailStr, Field, ValidationError, model_validator
from sqlalchemy import or_, select, update
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
    Room,
    User,
)
from ..geometry import room_measures
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


SOURCES = Literal["manual", "laser", "default"]


class WallData(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str = Field(default="", max_length=64)
    length: float = Field(ge=0, le=200)
    length_source: SOURCES = "manual"
    angle: float = Field(default=90, gt=0, lt=360)


class OpeningData(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str = Field(default="", max_length=64)
    type: Literal["door", "window"]
    wall: int = Field(ge=-1)
    width: float = Field(ge=0, le=20)
    height: float = Field(ge=0, le=20)
    width_source: SOURCES = "manual"
    height_source: SOURCES = "manual"


class RoomData(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    project_id: uuid.UUID
    name: str = Field(default="", max_length=100)
    level_name: str = Field(default="RDC", max_length=30)
    height_m: float = Field(gt=0, le=20)
    height_source: SOURCES = "manual"
    walls: list[WallData] = Field(min_length=3, max_length=64)
    openings: list[OpeningData] = Field(default_factory=list, max_length=100)
    plan_x: float | None = Field(default=None, ge=0, le=10000)
    plan_y: float | None = Field(default=None, ge=0, le=10000)

    @model_validator(mode="after")
    def _openings_on_existing_walls(self) -> "RoomData":
        for o in self.openings:
            if o.wall >= len(self.walls):
                raise ValueError("ouverture rattachée à un mur inexistant")
        return self


ENTITIES: dict[str, tuple[type, type[BaseModel]]] = {
    "clients": (Client, ClientData),
    "projects": (Project, ProjectData),
    "rooms": (Room, RoomData),
}


class Change(BaseModel):
    entity: Literal["clients", "projects", "rooms"]
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


def _plain(value: Any) -> Any:
    return float(value) if isinstance(value, Decimal) else value


def _record(entity: str, row: Client | Project | Room) -> RecordOut:
    _, schema = ENTITIES[entity]
    data = {name: _plain(getattr(row, name)) for name in schema.model_fields}
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


def _visible_rooms(ctx: Context):  # type: ignore[no-untyped-def]
    projects = _visible_projects(ctx).with_only_columns(Project.id).scalar_subquery()
    return select(Room).where(Room.organization_id == ctx.organization_id, Room.project_id.in_(projects))


def _visible(entity: str, ctx: Context):  # type: ignore[no-untyped-def]
    return {"clients": _visible_clients, "projects": _visible_projects, "rooms": _visible_rooms}[entity](ctx)


def _computed_room_values(data: "RoomData") -> dict[str, Any]:
    m = room_measures(
        data.height_m,
        [(w.length, w.angle) for w in data.walls],
        [(o.type, o.wall, o.width, o.height) for o in data.openings],
    )
    return {
        "computed_floor_area_m2": round(m.floor, 3),
        "computed_perimeter_m": round(m.perimeter, 3),
        "closure_error_m": round(min(m.closure, 9999.0), 3),
        "calc_version": 1,
    }


def _resequence(db: Session, project: Project) -> None:
    """Renvoie aux téléphones le client et les pièces d'un projet qui vient de devenir visible
    pour quelqu'un (changement de responsable, restauration) : leur numéro d'ordre est
    renouvelé par le déclencheur, sans changer leur version."""
    db.execute(update(Room).where(Room.project_id == project.id).values(updated_at=Room.updated_at))
    if project.client_id is not None:
        db.execute(update(Client).where(Client.id == project.client_id).values(updated_at=Client.updated_at))


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
    if entity == "rooms":
        assert isinstance(data, RoomData)
        project = db.scalar(
            _visible_projects(ctx).where(Project.id == data.project_id, Project.deleted_at.is_(None))
        )
        if project is None:
            raise _Rejected("Le projet de cette pièce n'existe pas, a été supprimé ou ne vous est pas accessible.")
        return
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
    row = db.scalar(_visible(change.entity, ctx).where(model.id == change.id).with_for_update())

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
        if change.entity == "rooms":
            values.update(_computed_room_values(data))  # type: ignore[arg-type]
        row = model(
            id=change.id,
            organization_id=ctx.organization_id,
            created_by=ctx.user.id,
            updated_by=ctx.user.id,
            **values,
        )
        db.add(row)
        db.flush()
        if change.entity != "rooms":
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
        elif change.entity == "projects" and Role.admin not in ctx.roles and row.created_by != ctx.user.id:
            raise _Rejected("Seul l'auteur du projet ou un administrateur peut le supprimer.")
        row.deleted_at = now()
        if change.entity == "projects":
            # Les pièces suivent le projet ; même horodatage pour pouvoir les restaurer ensemble.
            for room in db.scalars(select(Room).where(Room.project_id == row.id, Room.deleted_at.is_(None))):
                room.deleted_at = row.deleted_at
                room.version += 1
                room.updated_by = ctx.user.id
        audit(db, f"{change.entity[:-1]}.delete", request=request, organization_id=ctx.organization_id,
              actor_id=ctx.user.id, actor_role=ctx.main_role.value, entity_table=change.entity, entity_id=row.id,
              project_id=row.id if change.entity == "projects" else None)
    else:
        data = schema.model_validate(change.data)
        _check_links(db, ctx, change.entity, data)
        if change.entity == "projects" and Role.admin not in ctx.roles and data.manager_id != row.manager_id:
            raise _Rejected("Seul un administrateur peut changer le responsable d'un projet.")
        if change.entity == "rooms" and data.project_id != row.project_id:  # type: ignore[attr-defined]
            raise _Rejected("Une pièce ne peut pas changer de projet.")
        regained = change.entity == "projects" and (
            row.deleted_at is not None or data.manager_id != row.manager_id  # type: ignore[attr-defined]
        )
        if row.deleted_at is not None:
            if change.entity == "projects":
                for room in db.scalars(select(Room).where(Room.project_id == row.id, Room.deleted_at == row.deleted_at)):
                    room.deleted_at = None
                    room.version += 1
                    room.updated_by = ctx.user.id
            row.deleted_at = None  # restauration volontaire depuis le téléphone (conflit résolu)
            audit(db, f"{change.entity[:-1]}.restore", request=request, organization_id=ctx.organization_id,
                  actor_id=ctx.user.id, actor_role=ctx.main_role.value, entity_table=change.entity, entity_id=row.id)
        values = data.model_dump()
        if change.entity == "rooms":
            values.update(_computed_room_values(data))  # type: ignore[arg-type]
        for key, value in values.items():
            setattr(row, key, value)
        if regained:
            db.flush()
            _resequence(db, row)  # type: ignore[arg-type]
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
    for entity in ("clients", "projects", "rooms"):
        query = _visible(entity, ctx)
        model, _ = ENTITIES[entity]
        rows = db.scalars(query.where(model.sync_seq > cursor).order_by(model.sync_seq).limit(PAGE_SIZE + 1)).all()
        records.extend(_record(entity, r) for r in rows)
    records.sort(key=lambda r: r.sync_seq)
    has_more = len(records) > PAGE_SIZE
    records = records[:PAGE_SIZE]
    next_cursor = records[-1].sync_seq if records else cursor
    return PullOut(records=records, cursor=next_cursor, has_more=has_more)
