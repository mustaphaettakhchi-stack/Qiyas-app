"""Les tests utilisent une vraie base PostgreSQL (LAMAALAM_TEST_DATABASE_URL).

La base est remise à zéro une fois par session de tests ; chaque test crée ses propres
organisations et adresses e-mail uniques, ce qui évite tout nettoyage (le journal
d'audit refuse d'ailleurs les suppressions).
"""

import os
import uuid

import pytest
from cryptography.fernet import Fernet

DB_URL = os.environ.get(
    "LAMAALAM_TEST_DATABASE_URL",
    "postgresql+psycopg://lamaalam:test@localhost:5433/lamaalam_test",
)
os.environ["LAMAALAM_DATABASE_URL"] = DB_URL
os.environ["LAMAALAM_ENVIRONMENT"] = "test"
os.environ["LAMAALAM_JWT_SECRET"] = "secret-de-test-uniquement-" + "x" * 32
os.environ["LAMAALAM_TOTP_ENCRYPTION_KEY"] = Fernet.generate_key().decode()
for key in ("LAMAALAM_SMTP_HOST", "LAMAALAM_SMTP_FROM"):
    os.environ.pop(key, None)

import pyotp  # noqa: E402
from alembic import command  # noqa: E402
from alembic.config import Config  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import create_engine, text  # noqa: E402
from sqlalchemy.orm import Session  # noqa: E402

from app.main import app  # noqa: E402
from app.models import Organization, Role, User, UserRole  # noqa: E402
from app.security import encrypt_secret, hash_password  # noqa: E402

STRONG_PASSWORD = "Tanger-chantier-volet-orange-42"


@pytest.fixture(scope="session", autouse=True)
def database() -> None:
    engine = create_engine(DB_URL)
    with engine.begin() as conn:
        conn.execute(text("DROP SCHEMA public CASCADE; CREATE SCHEMA public;"))
    engine.dispose()
    cfg = Config(os.path.join(os.path.dirname(__file__), "..", "alembic.ini"))
    cfg.set_main_option("script_location", os.path.join(os.path.dirname(__file__), "..", "migrations"))
    cfg.attributes["database_url"] = DB_URL
    command.upgrade(cfg, "head")


@pytest.fixture()
def db() -> Session:
    engine = create_engine(DB_URL)
    with Session(engine, expire_on_commit=False) as session:
        yield session
    engine.dispose()


@pytest.fixture()
def client() -> TestClient:
    with TestClient(app) as c:
        yield c


def unique_email(prefix: str = "u") -> str:
    return f"{prefix}-{uuid.uuid4().hex[:10]}@exemple.ma"


def make_org(db: Session, name: str = "Entreprise test") -> Organization:
    org = Organization(legal_name=f"{name} {uuid.uuid4().hex[:6]}", trade_name=name)
    db.add(org)
    db.commit()
    return org


def make_user(
    db: Session,
    org: Organization,
    role: Role = Role.admin,
    *,
    with_totp: bool = True,
    email: str | None = None,
) -> tuple[User, str | None]:
    """Crée un utilisateur actif. Renvoie aussi son secret TOTP en clair (pour les tests)."""
    secret = pyotp.random_base32() if with_totp else None
    user = User(
        organization_id=org.id,
        email=email or unique_email(role.value),
        full_name=f"Test {role.value}",
        password_hash=hash_password(STRONG_PASSWORD),
        totp_enabled=with_totp,
        totp_secret_enc=encrypt_secret(secret) if secret else None,
    )
    user.roles.append(UserRole(organization_id=org.id, role=role))
    db.add(user)
    db.commit()
    return user, secret


def login(client: TestClient, email: str, secret: str | None, password: str = STRONG_PASSWORD) -> dict:
    """Connexion complète (mot de passe puis code TOTP). Renvoie les jetons."""
    r = client.post("/api/v1/auth/login", json={"email": email, "password": password})
    assert r.status_code == 200, r.text
    body = r.json()
    if body["tokens"]:
        return body["tokens"]
    assert body["mfa_required"], body
    r = client.post(
        "/api/v1/auth/mfa/verify",
        json={"mfa_token": body["mfa_token"], "code": pyotp.TOTP(secret).now()},
    )
    assert r.status_code == 200, r.text
    return r.json()


def auth(tokens: dict) -> dict:
    return {"Authorization": f"Bearer {tokens['access_token']}"}
