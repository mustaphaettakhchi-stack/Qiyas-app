"""Tables d'identité et de traçabilité (lot 1.1).

Spécification : docs/DATABASE_SCHEMA.md §3.1 et §3.8. Les tables métier (clients, projets…)
arrivent avec le lot 1.2.
"""

import enum
import uuid
from datetime import date, datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    Enum,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

from .ids import uuid7


class Base(DeclarativeBase):
    pass


class Role(str, enum.Enum):
    admin = "admin"
    collaborator = "collaborator"
    client = "client"


class UserStatus(str, enum.Enum):
    active = "active"
    suspended = "suspended"


ROLES_REQUIRING_MFA = frozenset({Role.admin, Role.collaborator})


def _enum(e: type[enum.Enum], name: str) -> Enum:
    return Enum(e, name=name, values_callable=lambda x: [m.value for m in x])


class Timestamped:
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid7)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    version: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Organization(Timestamped, Base):
    __tablename__ = "organizations"

    legal_name: Mapped[str] = mapped_column(String(200))
    trade_name: Mapped[str] = mapped_column(String(200), default="")
    ice: Mapped[str | None] = mapped_column(String(15))
    if_number: Mapped[str | None] = mapped_column(String(30))
    rc: Mapped[str | None] = mapped_column(String(30))
    patente: Mapped[str | None] = mapped_column(String(30))
    cnss: Mapped[str | None] = mapped_column(String(30))
    address: Mapped[str] = mapped_column(Text, default="")
    city: Mapped[str] = mapped_column(String(100), default="")
    country: Mapped[str] = mapped_column(String(2), default="MA")
    phone: Mapped[str] = mapped_column(String(30), default="")
    email: Mapped[str] = mapped_column(String(254), default="")
    default_currency: Mapped[str] = mapped_column(String(3), default="MAD")
    estimate_validity_days: Mapped[int] = mapped_column(Integer, default=30)
    estimate_footer: Mapped[str] = mapped_column(Text, default="")
    reference_prefix: Mapped[str] = mapped_column(String(10), default="LMA", server_default="LMA")


class User(Timestamped, Base):
    __tablename__ = "users"

    organization_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("organizations.id"), index=True)
    # Adresse normalisée en minuscules ; unicité globale (l'adresse est l'identifiant de connexion).
    email: Mapped[str] = mapped_column(String(254), unique=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    password_changed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    totp_secret_enc: Mapped[str | None] = mapped_column(Text)
    totp_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    totp_last_step: Mapped[int | None] = mapped_column(BigInteger)
    full_name: Mapped[str] = mapped_column(String(200))
    phone: Mapped[str] = mapped_column(String(30), default="")
    locale: Mapped[str] = mapped_column(String(5), default="fr")
    status: Mapped[UserStatus] = mapped_column(_enum(UserStatus, "user_status"), default=UserStatus.active)
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    failed_login_count: Mapped[int] = mapped_column(Integer, default=0)
    locked_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # Rattachement à une fiche client : la clé étrangère sera ajoutée avec la table clients (lot 1.2).
    client_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))

    roles: Mapped[list["UserRole"]] = relationship(
        back_populates="user", cascade="all, delete-orphan", lazy="selectin"
    )

    @property
    def role_set(self) -> set[Role]:
        return {r.role for r in self.roles}


class UserRole(Base):
    __tablename__ = "user_roles"
    __table_args__ = (
        UniqueConstraint("user_id", "role", "scope_project_id", postgresql_nulls_not_distinct=True),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid7)
    organization_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("organizations.id"), index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    role: Mapped[Role] = mapped_column(_enum(Role, "user_role"))
    # Restriction d'un collaborateur à un projet : clé étrangère ajoutée avec la table projects (lot 1.2).
    scope_project_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    user: Mapped[User] = relationship(back_populates="roles")


class MfaBackupCode(Base):
    __tablename__ = "mfa_backup_codes"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid7)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    code_hash: Mapped[str] = mapped_column(String(64))
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class AuthSession(Base):
    __tablename__ = "auth_sessions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid7)
    organization_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("organizations.id"), index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    refresh_token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    previous_token_hash: Mapped[str | None] = mapped_column(String(64), index=True)
    device_label: Mapped[str] = mapped_column(String(100), default="")
    ip: Mapped[str | None] = mapped_column(String(45))
    user_agent: Mapped[str] = mapped_column(String(300), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    last_used_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    revoke_reason: Mapped[str | None] = mapped_column(String(50))


class Invitation(Base):
    __tablename__ = "invitations"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid7)
    organization_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("organizations.id"), index=True)
    email: Mapped[str] = mapped_column(String(254))
    full_name: Mapped[str] = mapped_column(String(200))
    role: Mapped[Role] = mapped_column(_enum(Role, "user_role", ))
    client_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    invited_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


# ---------- clients et projets (lot 1.2) ----------

CLIENT_TYPES = ("individual", "company")
PROJECT_TYPES = ("renovation", "new_build", "extension", "interior", "exterior", "commercial")
PROPERTY_KINDS = ("apartment", "house", "villa", "land", "commercial", "other")
PROJECT_STATUSES = (
    "prospect", "visit_planned", "estimating", "estimate_sent", "won", "in_progress", "delivered", "lost", "archived",
)
CURRENCIES = ("MAD", "EUR")


def _in(column: str, values: tuple[str, ...]) -> str:
    return f"{column} IN ({', '.join(repr(v) for v in values)})"


class Synced:
    """Colonnes communes aux tables synchronisées avec les téléphones.

    sync_seq est attribué par un déclencheur PostgreSQL à chaque écriture, sous un verrou
    par organisation : l'ordre des numéros est l'ordre de validation des transactions.
    """

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    organization_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("organizations.id"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    created_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    updated_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))
    version: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    sync_seq: Mapped[int] = mapped_column(BigInteger, server_default="0", index=True)


class Client(Synced, Base):
    __tablename__ = "clients"
    __table_args__ = (CheckConstraint(_in("type", CLIENT_TYPES), name="ck_clients_type"),)

    type: Mapped[str] = mapped_column(String(20), default="individual")
    display_name: Mapped[str] = mapped_column(String(200))
    phone: Mapped[str] = mapped_column(String(30), default="")
    email: Mapped[str] = mapped_column(String(254), default="")
    address: Mapped[str] = mapped_column(Text, default="")
    city: Mapped[str] = mapped_column(String(100), default="")
    ice: Mapped[str] = mapped_column(String(15), default="")
    notes: Mapped[str] = mapped_column(Text, default="")
    consent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    consent_text_version: Mapped[str] = mapped_column(String(20), default="")


class Project(Synced, Base):
    __tablename__ = "projects"
    __table_args__ = (
        UniqueConstraint("organization_id", "reference", name="uq_projects_reference"),
        CheckConstraint(_in("project_type", PROJECT_TYPES), name="ck_projects_type"),
        CheckConstraint(f"property_kind IS NULL OR {_in('property_kind', PROPERTY_KINDS)}", name="ck_projects_kind"),
        CheckConstraint(_in("status", PROJECT_STATUSES), name="ck_projects_status"),
        CheckConstraint(_in("currency", CURRENCIES), name="ck_projects_currency"),
        CheckConstraint("budget_cents IS NULL OR budget_cents >= 0", name="ck_projects_budget"),
    )

    reference: Mapped[str] = mapped_column(String(30))
    client_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("clients.id"), index=True)
    name: Mapped[str] = mapped_column(String(200), default="")
    project_type: Mapped[str] = mapped_column(String(20), default="renovation")
    property_kind: Mapped[str | None] = mapped_column(String(20))
    status: Mapped[str] = mapped_column(String(20), default="prospect")
    description: Mapped[str] = mapped_column(Text, default="")
    budget_cents: Mapped[int | None] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default="MAD")
    visit_date: Mapped[date | None] = mapped_column(Date)
    manager_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id"), index=True)
    site_address: Mapped[str] = mapped_column(Text, default="")
    site_city: Mapped[str] = mapped_column(String(100), default="")
    notes: Mapped[str] = mapped_column(Text, default="")
    # Validation du métré (lot 1.4) : date, auteur, empreinte des cotes, cotes non vérifiées acceptées.
    metre_validation: Mapped[dict | None] = mapped_column(JSONB)


class Room(Synced, Base):
    """Pièce décrite mur par mur (lot 1.3).

    Murs et ouvertures sont stockés en JSONB dans la fiche de la pièce : la pièce est
    l'unité de synchronisation et de conflit (voir docs/DATABASE_SCHEMA.md). Les surfaces
    sont recalculées par le serveur à chaque écriture (app/geometry.py).
    """

    __tablename__ = "rooms"
    __table_args__ = (
        CheckConstraint("height_m > 0 AND height_m <= 20", name="ck_rooms_height"),
        CheckConstraint("height_source IN ('manual', 'laser', 'default')", name="ck_rooms_height_source"),
    )

    project_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("projects.id"), index=True)
    name: Mapped[str] = mapped_column(String(100), default="")
    level_name: Mapped[str] = mapped_column(String(30), default="RDC")
    height_m: Mapped[float] = mapped_column(Numeric(6, 3))
    height_source: Mapped[str] = mapped_column(String(10), default="manual")
    walls: Mapped[list] = mapped_column(JSONB, default=list)
    openings: Mapped[list] = mapped_column(JSONB, default=list)
    plan_x: Mapped[float | None] = mapped_column(Numeric(8, 2))
    plan_y: Mapped[float | None] = mapped_column(Numeric(8, 2))
    counts: Mapped[dict] = mapped_column(JSONB, default=dict)
    computed_floor_area_m2: Mapped[float] = mapped_column(Numeric(10, 3), default=0)
    computed_perimeter_m: Mapped[float] = mapped_column(Numeric(10, 3), default=0)
    closure_error_m: Mapped[float] = mapped_column(Numeric(8, 3), default=0)
    calc_version: Mapped[int] = mapped_column(Integer, default=1)


# ---------- bibliothèque (lot 1.5) ----------

UNITS = ("m", "m2", "m3", "kg", "l", "u", "forfait")
CATEGORIES = ("floor", "wall", "ceiling", "joinery", "electricity", "plumbing", "masonry", "other")
QUANTITY_BASES = (
    "floor", "ceiling", "walls_net", "walls_gross", "skirting", "perimeter", "volume", "doors", "windows", "count", "manual",
)
COUNT_KEYS = (
    "prises", "interrupteurs", "points_lumineux", "points_eau", "evacuations", "sanitaires", "placards",
    "cloisons_m2", "demolition_m2", "reprises_m2", "ouvertures_a_creer",
)


class Supplier(Synced, Base):
    __tablename__ = "suppliers"

    name: Mapped[str] = mapped_column(String(200))
    contact_name: Mapped[str] = mapped_column(String(200), default="")
    phone: Mapped[str] = mapped_column(String(30), default="")
    email: Mapped[str] = mapped_column(String(254), default="")
    address: Mapped[str] = mapped_column(Text, default="")
    city: Mapped[str] = mapped_column(String(100), default="")
    ice: Mapped[str] = mapped_column(String(15), default="")
    notes: Mapped[str] = mapped_column(Text, default="")


class Material(Synced, Base):
    """Matériau ou fourniture. Un prix NULL signifie « non renseigné » : jamais de valeur par défaut."""

    __tablename__ = "materials"
    __table_args__ = (
        CheckConstraint(_in("unit", UNITS), name="ck_materials_unit"),
        CheckConstraint(_in("category", CATEGORIES), name="ck_materials_category"),
        CheckConstraint(_in("currency", CURRENCIES), name="ck_materials_currency"),
        CheckConstraint("waste_rate_bp BETWEEN 0 AND 10000", name="ck_materials_waste"),
        CheckConstraint("purchase_price_cents IS NULL OR purchase_price_cents >= 0", name="ck_materials_purchase"),
        CheckConstraint("sale_price_cents IS NULL OR sale_price_cents >= 0", name="ck_materials_sale"),
    )

    supplier_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("suppliers.id"), index=True)
    category: Mapped[str] = mapped_column(String(20), default="other")
    name: Mapped[str] = mapped_column(String(200))
    brand: Mapped[str] = mapped_column(String(100), default="")
    reference: Mapped[str] = mapped_column(String(100), default="")
    unit: Mapped[str] = mapped_column(String(10), default="u")
    pack_size: Mapped[float | None] = mapped_column(Numeric(12, 3))
    waste_rate_bp: Mapped[int] = mapped_column(Integer, default=0)
    purchase_price_cents: Mapped[int | None] = mapped_column(BigInteger)
    sale_price_cents: Mapped[int | None] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default="MAD")
    city: Mapped[str] = mapped_column(String(100), default="")
    price_note: Mapped[str] = mapped_column(String(300), default="")
    price_updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class WorkItem(Synced, Base):
    """Ouvrage de la bibliothèque : désignation, unité, base de quantité, perte, prix."""

    __tablename__ = "work_items"
    __table_args__ = (
        CheckConstraint(_in("unit", UNITS), name="ck_work_items_unit"),
        CheckConstraint(_in("category", CATEGORIES), name="ck_work_items_category"),
        CheckConstraint(_in("quantity_basis", QUANTITY_BASES), name="ck_work_items_basis"),
        CheckConstraint(f"count_key IS NULL OR {_in('count_key', COUNT_KEYS)}", name="ck_work_items_count_key"),
        CheckConstraint("(quantity_basis = 'count') = (count_key IS NOT NULL)", name="ck_work_items_count_basis"),
        CheckConstraint(_in("currency", CURRENCIES), name="ck_work_items_currency"),
        CheckConstraint("waste_rate_bp BETWEEN 0 AND 10000", name="ck_work_items_waste"),
        CheckConstraint("sale_price_cents IS NULL OR sale_price_cents >= 0", name="ck_work_items_sale"),
        CheckConstraint("labour_cost_cents IS NULL OR labour_cost_cents >= 0", name="ck_work_items_labour"),
    )

    code: Mapped[str] = mapped_column(String(30), default="")
    category: Mapped[str] = mapped_column(String(20), default="other")
    name: Mapped[str] = mapped_column(String(200))
    description: Mapped[str] = mapped_column(Text, default="")
    unit: Mapped[str] = mapped_column(String(10), default="u")
    quantity_basis: Mapped[str] = mapped_column(String(20), default="manual")
    count_key: Mapped[str | None] = mapped_column(String(30))
    waste_rate_bp: Mapped[int] = mapped_column(Integer, default=0)
    labour_cost_cents: Mapped[int | None] = mapped_column(BigInteger)
    sale_price_cents: Mapped[int | None] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default="MAD")
    components: Mapped[list] = mapped_column(JSONB, default=list)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    price_note: Mapped[str] = mapped_column(String(300), default="")
    price_updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class PriceHistory(Base):
    """Historique des prix, en insertion seule (déclencheur), alimenté par le serveur."""

    __tablename__ = "price_history"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid7)
    organization_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("organizations.id"), index=True)
    material_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("materials.id"), index=True)
    work_item_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("work_items.id"), index=True)
    purchase_price_cents: Mapped[int | None] = mapped_column(BigInteger)
    sale_price_cents: Mapped[int | None] = mapped_column(BigInteger)
    labour_cost_cents: Mapped[int | None] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3))
    supplier_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("suppliers.id"))
    city: Mapped[str] = mapped_column(String(100), default="")
    source_note: Mapped[str] = mapped_column(String(300), default="")
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    recorded_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))


class OrgCounter(Base):
    """Compteurs de numérotation par organisation (références de projets, puis devis et factures)."""

    __tablename__ = "org_counters"

    organization_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("organizations.id"), primary_key=True)
    name: Mapped[str] = mapped_column(String(30), primary_key=True)
    year: Mapped[int] = mapped_column(Integer, primary_key=True)
    value: Mapped[int] = mapped_column(Integer, default=0)


class PasswordReset(Base):
    """Lien de réinitialisation du mot de passe créé par un administrateur."""

    __tablename__ = "password_resets"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid7)
    organization_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("organizations.id"), index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    created_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class AuditLog(Base):
    """Journal en insertion seule : un déclencheur PostgreSQL refuse UPDATE, DELETE et TRUNCATE."""

    __tablename__ = "audit_logs"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid7)
    organization_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("organizations.id"), index=True)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True)
    actor_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    actor_role: Mapped[str | None] = mapped_column(String(20))
    action: Mapped[str] = mapped_column(String(60), index=True)
    entity_table: Mapped[str | None] = mapped_column(String(60))
    entity_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    project_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    ip: Mapped[str | None] = mapped_column(String(45))
    details: Mapped[dict] = mapped_column(JSONB, default=dict)
