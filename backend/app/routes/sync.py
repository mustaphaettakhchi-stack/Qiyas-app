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
    CATEGORIES,
    CLIENT_TYPES,
    COUNT_KEYS,
    CURRENCIES,
    QUANTITY_BASES,
    UNITS,
    PROJECT_STATUSES,
    PROJECT_TYPES,
    PROPERTY_KINDS,
    Client,
    Material,
    OrgCounter,
    Organization,
    Project,
    Role,
    PriceHistory,
    Room,
    Supplier,
    User,
    WorkItem,
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


class MetreValidation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    validated_at: datetime
    validated_by: uuid.UUID
    validated_by_name: str = Field(default="", max_length=200)
    fingerprint: str = Field(pattern=r"^[0-9a-f]{64}$")
    rooms: int = Field(ge=0)
    unverified_accepted: int = Field(ge=0)


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
    metre_validation: MetreValidation | None = None


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
    counts: dict[Literal[COUNT_KEYS], float] = Field(default_factory=dict)  # type: ignore[valid-type]

    @model_validator(mode="after")
    def _counts_in_range(self) -> "RoomData":
        if any(v < 0 or v > 100000 for v in self.counts.values()):
            raise ValueError("quantité comptée hors limites")
        return self

    @model_validator(mode="after")
    def _openings_on_existing_walls(self) -> "RoomData":
        for o in self.openings:
            if o.wall >= len(self.walls):
                raise ValueError("ouverture rattachée à un mur inexistant")
        return self


class SupplierData(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    name: str = Field(min_length=1, max_length=200)
    contact_name: str = Field(default="", max_length=200)
    phone: str = Field(default="", max_length=30)
    email: EmailStr | Literal[""] = ""
    address: str = Field(default="", max_length=2000)
    city: str = Field(default="", max_length=100)
    ice: str = Field(default="", pattern=r"^(\d{15})?$")
    notes: str = Field(default="", max_length=5000)


PRICE = Field(default=None, ge=0, le=10**12)


class MaterialData(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    supplier_id: uuid.UUID | None = None
    category: Literal[CATEGORIES] = "other"  # type: ignore[valid-type]
    name: str = Field(min_length=1, max_length=200)
    brand: str = Field(default="", max_length=100)
    reference: str = Field(default="", max_length=100)
    unit: Literal[UNITS] = "u"  # type: ignore[valid-type]
    pack_size: float | None = Field(default=None, gt=0, le=100000)
    waste_rate_bp: int = Field(default=0, ge=0, le=10000)
    purchase_price_cents: int | None = PRICE
    sale_price_cents: int | None = PRICE
    currency: Literal[CURRENCIES] = "MAD"  # type: ignore[valid-type]
    city: str = Field(default="", max_length=100)
    price_note: str = Field(default="", max_length=300)


class Component(BaseModel):
    model_config = ConfigDict(extra="forbid")

    material_id: uuid.UUID
    quantity_per_unit: float = Field(gt=0, le=100000)


class WorkItemData(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    code: str = Field(default="", max_length=30)
    category: Literal[CATEGORIES] = "other"  # type: ignore[valid-type]
    name: str = Field(min_length=1, max_length=200)
    description: str = Field(default="", max_length=5000)
    unit: Literal[UNITS] = "u"  # type: ignore[valid-type]
    quantity_basis: Literal[QUANTITY_BASES] = "manual"  # type: ignore[valid-type]
    count_key: Literal[COUNT_KEYS] | None = None  # type: ignore[valid-type]
    waste_rate_bp: int = Field(default=0, ge=0, le=10000)
    labour_cost_cents: int | None = PRICE
    sale_price_cents: int | None = PRICE
    currency: Literal[CURRENCIES] = "MAD"  # type: ignore[valid-type]
    components: list[Component] = Field(default_factory=list, max_length=50)
    is_active: bool = True
    price_note: str = Field(default="", max_length=300)

    @model_validator(mode="after")
    def _count_key_matches_basis(self) -> "WorkItemData":
        if (self.quantity_basis == "count") != (self.count_key is not None):
            raise ValueError("la base « comptage » exige un élément compté, et lui seul")
        return self


LIBRARY = frozenset({"suppliers", "materials", "work_items"})
PRICE_FIELDS = ("purchase_price_cents", "sale_price_cents", "labour_cost_cents")

ENTITIES: dict[str, tuple[type, type[BaseModel]]] = {
    "clients": (Client, ClientData),
    "projects": (Project, ProjectData),
    "rooms": (Room, RoomData),
    "suppliers": (Supplier, SupplierData),
    "materials": (Material, MaterialData),
    "work_items": (WorkItem, WorkItemData),
}

# Ordre d'envoi et de réception : un enregistrement après ceux auxquels il fait référence.
ORDER = ("suppliers", "materials", "work_items", "clients", "projects", "rooms")


class Change(BaseModel):
    entity: Literal["clients", "projects", "rooms", "suppliers", "materials", "work_items"]
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


def _record(entity: str, row: Any, ctx: Context | None = None) -> RecordOut:
    _, schema = ENTITIES[entity]
    data = {name: _plain(getattr(row, name)) for name in schema.model_fields}
    if entity == "projects" and data.get("metre_validation") is not None:
        data["metre_validation"] = MetreValidation.model_validate(data["metre_validation"]).model_dump(mode="json")
    # Les prix d'achat ne sont communiqués qu'aux administrateurs (DATABASE_SCHEMA §4).
    if "purchase_price_cents" in data and (ctx is None or Role.admin not in ctx.roles):
        data["purchase_price_cents"] = None
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
    if entity in LIBRARY:
        model, _ = ENTITIES[entity]
        return select(model).where(model.organization_id == ctx.organization_id)
    return {"clients": _visible_clients, "projects": _visible_projects, "rooms": _visible_rooms}[entity](ctx)


def _record_prices(db: Session, ctx: Context, entity: str, row: Any, before: dict[str, Any] | None) -> None:
    """Ajoute une ligne à l'historique des prix si un prix a changé (ou à la création)."""
    if entity not in ("materials", "work_items"):
        return
    current = {f: getattr(row, f, None) for f in PRICE_FIELDS}
    if before is not None and all(before.get(f) == current[f] for f in PRICE_FIELDS):
        return
    if before is None and all(v is None for v in current.values()):
        return
    row.price_updated_at = now()
    db.add(PriceHistory(
        organization_id=ctx.organization_id,
        material_id=row.id if entity == "materials" else None,
        work_item_id=row.id if entity == "work_items" else None,
        purchase_price_cents=current["purchase_price_cents"],
        sale_price_cents=current["sale_price_cents"],
        labour_cost_cents=current["labour_cost_cents"],
        currency=row.currency,
        supplier_id=getattr(row, "supplier_id", None),
        city=getattr(row, "city", "") or "",
        source_note=row.price_note,
        recorded_by=ctx.user.id,
    ))


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
    if entity == "materials":
        assert isinstance(data, MaterialData)
        if data.supplier_id is not None and db.scalar(
            select(Supplier.id).where(Supplier.id == data.supplier_id, Supplier.deleted_at.is_(None))
        ) is None:
            raise _Rejected("Le fournisseur choisi n'existe pas ou a été supprimé.")
        return
    if entity == "work_items":
        assert isinstance(data, WorkItemData)
        for c in data.components:
            if db.scalar(select(Material.id).where(Material.id == c.material_id, Material.deleted_at.is_(None))) is None:
                raise _Rejected("Un matériau de la composition n'existe pas ou a été supprimé.")
        return
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

    if change.entity in LIBRARY and Role.admin not in ctx.roles:
        raise _Rejected("Seul un administrateur peut modifier la bibliothèque.")

    def result(st: str, message: str | None = None, r: Any = None) -> ChangeResult:
        return ChangeResult(
            entity=change.entity,
            id=change.id,
            status=st,  # type: ignore[arg-type]
            message=message,
            record=_record(change.entity, r, ctx) if r is not None else None,
        )

    # --- création ---
    if row is None:
        if change.base_version is not None:
            return result("rejected", "Cet élément n'existe plus sur le serveur ou ne vous est plus accessible.")
        if change.deleted:
            return result("applied")  # créé puis supprimé hors ligne : rien à faire
        data = schema.model_validate(change.data)
        _check_links(db, ctx, change.entity, data)
        values = _values(data)
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
        _record_prices(db, ctx, change.entity, row, None)
        if change.entity == "projects":
            _audit_metre(db, ctx, request, row, None)  # type: ignore[arg-type]
        if change.entity not in ("rooms",) and change.entity not in LIBRARY:
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
        elif change.entity == "suppliers":
            if db.scalar(select(Material.id).where(Material.supplier_id == row.id, Material.deleted_at.is_(None)).limit(1)):
                raise _Rejected("Ce fournisseur est encore utilisé par des matériaux.")
        elif change.entity == "materials":
            used = db.scalar(
                select(WorkItem.id).where(
                    WorkItem.deleted_at.is_(None),
                    WorkItem.components.contains([{"material_id": str(row.id)}]),
                ).limit(1)
            )
            if used:
                raise _Rejected("Ce matériau entre dans la composition d'ouvrages : retirez-le d'abord.")
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
        values = _values(data)
        if change.entity == "rooms":
            values.update(_computed_room_values(data))  # type: ignore[arg-type]
        prices_before = {f: getattr(row, f, None) for f in PRICE_FIELDS}
        metre_before = getattr(row, "metre_validation", None)
        for key, value in values.items():
            setattr(row, key, value)
        _record_prices(db, ctx, change.entity, row, prices_before)
        if change.entity == "projects":
            _audit_metre(db, ctx, request, row, metre_before)  # type: ignore[arg-type]
        if regained:
            db.flush()
            _resequence(db, row)  # type: ignore[arg-type]
    row.version += 1
    row.updated_by = ctx.user.id
    db.flush()
    db.refresh(row)
    return result("applied", r=row)


JSON_FIELDS = ("walls", "openings", "counts", "components", "metre_validation")


def _values(data: BaseModel) -> dict[str, Any]:
    """Valeurs à écrire : objets Python pour les colonnes typées, JSON pour les colonnes JSONB."""
    values = data.model_dump()
    as_json = data.model_dump(mode="json")
    for key in JSON_FIELDS:
        if key in values:
            values[key] = as_json[key]
    return values


def _audit_metre(db: Session, ctx: Context, request: Request, row: Project, before: Any) -> None:
    after = row.metre_validation
    if after == before:
        return
    audit(db, "metre.validate" if after else "metre.invalidate", request=request, organization_id=ctx.organization_id,
          actor_id=ctx.user.id, actor_role=ctx.main_role.value, entity_table="projects", entity_id=row.id,
          project_id=row.id, details={"fingerprint": (after or {}).get("fingerprint"),
                                      "unverified_accepted": (after or {}).get("unverified_accepted")})


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
    for entity in ORDER:
        query = _visible(entity, ctx)
        model, _ = ENTITIES[entity]
        rows = db.scalars(query.where(model.sync_seq > cursor).order_by(model.sync_seq).limit(PAGE_SIZE + 1)).all()
        records.extend(_record(entity, r, ctx) for r in rows)
    records.sort(key=lambda r: r.sync_seq)
    has_more = len(records) > PAGE_SIZE
    records = records[:PAGE_SIZE]
    next_cursor = records[-1].sync_seq if records else cursor
    return PullOut(records=records, cursor=next_cursor, has_more=has_more)
