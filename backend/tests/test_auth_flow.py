from datetime import timedelta

import pyotp
from sqlalchemy import select, text

from app.models import AuditLog, AuthSession, Role, User
from app.security import now

from .conftest import STRONG_PASSWORD, auth, login, make_org, make_user, unique_email


def test_health(client):
    assert client.get("/api/v1/health").json() == {"status": "ok"}


def test_unknown_and_wrong_password_give_same_message(client, db):
    org = make_org(db)
    user, _ = make_user(db, org)
    r1 = client.post("/api/v1/auth/login", json={"email": unique_email(), "password": STRONG_PASSWORD})
    r2 = client.post("/api/v1/auth/login", json={"email": user.email, "password": "mauvais-mot-de-passe"})
    assert r1.status_code == r2.status_code == 401
    assert r1.json() == r2.json()


def test_email_is_case_insensitive(client, db):
    org = make_org(db)
    user, secret = make_user(db, org)
    tokens = login(client, user.email.upper(), secret)
    assert client.get("/api/v1/auth/me", headers=auth(tokens)).json()["email"] == user.email


def test_staff_without_totp_must_set_it_up(client, db):
    org = make_org(db)
    user, _ = make_user(db, org, Role.collaborator, with_totp=False)
    r = client.post("/api/v1/auth/login", json={"email": user.email, "password": STRONG_PASSWORD})
    body = r.json()
    assert body["tokens"] is None and body["mfa_setup_required"]

    # Le jeton de mise en place ne donne accès à rien d'autre.
    assert client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {body['mfa_token']}"}).status_code == 401

    setup = client.post("/api/v1/auth/mfa/setup", json={"mfa_token": body["mfa_token"]}).json()
    assert setup["otpauth_uri"].startswith("otpauth://totp/")
    bad = client.post("/api/v1/auth/mfa/confirm", json={"mfa_token": body["mfa_token"], "code": "000000"})
    assert bad.status_code == 401
    ok = client.post(
        "/api/v1/auth/mfa/confirm",
        json={"mfa_token": body["mfa_token"], "code": pyotp.TOTP(setup["secret"]).now()},
    )
    assert ok.status_code == 200, ok.text
    data = ok.json()
    assert len(data["backup_codes"]) == 10
    me = client.get("/api/v1/auth/me", headers=auth(data["tokens"])).json()
    assert me["totp_enabled"] and me["roles"] == ["collaborator"]

    db.refresh(user)
    assert user.totp_enabled and user.totp_secret_enc and setup["secret"] not in user.totp_secret_enc


def test_backup_code_is_single_use(client, db):
    org = make_org(db)
    user, _ = make_user(db, org, with_totp=False)
    mfa_token = client.post(
        "/api/v1/auth/login", json={"email": user.email, "password": STRONG_PASSWORD}
    ).json()["mfa_token"]
    secret = client.post("/api/v1/auth/mfa/setup", json={"mfa_token": mfa_token}).json()["secret"]
    codes = client.post(
        "/api/v1/auth/mfa/confirm", json={"mfa_token": mfa_token, "code": pyotp.TOTP(secret).now()}
    ).json()["backup_codes"]

    def with_backup(code):
        token = client.post(
            "/api/v1/auth/login", json={"email": user.email, "password": STRONG_PASSWORD}
        ).json()["mfa_token"]
        return client.post("/api/v1/auth/mfa/verify", json={"mfa_token": token, "backup_code": code})

    assert with_backup(codes[0]).status_code == 200
    assert with_backup(codes[0]).status_code == 401


def test_totp_code_cannot_be_replayed(client, db):
    org = make_org(db)
    user, secret = make_user(db, org)
    code = pyotp.TOTP(secret).now()
    for expected in (200, 401):
        token = client.post(
            "/api/v1/auth/login", json={"email": user.email, "password": STRONG_PASSWORD}
        ).json()["mfa_token"]
        r = client.post("/api/v1/auth/mfa/verify", json={"mfa_token": token, "code": code})
        assert r.status_code == expected


def test_lockout_after_repeated_failures(client, db):
    org = make_org(db)
    user, secret = make_user(db, org)
    for _ in range(5):
        r = client.post("/api/v1/auth/login", json={"email": user.email, "password": "mauvais-mot-de-passe"})
        assert r.status_code == 401
    r = client.post("/api/v1/auth/login", json={"email": user.email, "password": STRONG_PASSWORD})
    assert r.status_code == 429
    failures = db.scalars(
        select(AuditLog).where(AuditLog.actor_id == user.id, AuditLog.action == "auth.login.failed")
    ).all()
    assert len(failures) == 5


def test_mfa_code_failures_also_lock(client, db):
    org = make_org(db)
    user, _ = make_user(db, org)
    for _ in range(5):
        token = client.post(
            "/api/v1/auth/login", json={"email": user.email, "password": STRONG_PASSWORD}
        ).json()["mfa_token"]
        client.post("/api/v1/auth/mfa/verify", json={"mfa_token": token, "code": "000000"})
    r = client.post("/api/v1/auth/login", json={"email": user.email, "password": STRONG_PASSWORD})
    assert r.status_code == 429


def test_refresh_rotation_and_reuse_detection(client, db):
    org = make_org(db)
    user, secret = make_user(db, org)
    first = login(client, user.email, secret)
    second = client.post("/api/v1/auth/refresh", json={"refresh_token": first["refresh_token"]})
    assert second.status_code == 200
    second = second.json()
    assert second["refresh_token"] != first["refresh_token"]

    # Réutilisation de l'ancien jeton : la session entière est révoquée.
    assert client.post("/api/v1/auth/refresh", json={"refresh_token": first["refresh_token"]}).status_code == 401
    assert client.post("/api/v1/auth/refresh", json={"refresh_token": second["refresh_token"]}).status_code == 401
    assert client.get("/api/v1/auth/me", headers=auth(second)).status_code == 401


def test_logout_revokes_access_immediately(client, db):
    org = make_org(db)
    user, secret = make_user(db, org)
    tokens = login(client, user.email, secret)
    assert client.post("/api/v1/auth/logout", headers=auth(tokens)).status_code == 204
    assert client.get("/api/v1/auth/me", headers=auth(tokens)).status_code == 401
    assert client.post("/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]}).status_code == 401


def test_expired_session_rejected(client, db):
    org = make_org(db)
    user, secret = make_user(db, org)
    tokens = login(client, user.email, secret)
    session = db.scalar(select(AuthSession).where(AuthSession.user_id == user.id))
    session.expires_at = now() - timedelta(seconds=1)
    db.commit()
    assert client.get("/api/v1/auth/me", headers=auth(tokens)).status_code == 401


def test_audit_log_is_append_only(db):
    org = make_org(db)
    make_user(db, org)
    db.add(AuditLog(organization_id=org.id, action="test.event"))
    db.commit()
    for sql in ("UPDATE audit_logs SET action = 'x'", "DELETE FROM audit_logs", "TRUNCATE audit_logs"):
        try:
            db.execute(text(sql))
            db.commit()
            raise AssertionError(f"{sql} aurait dû être refusé")
        except Exception as exc:  # noqa: BLE001
            db.rollback()
            assert "insertion seule" in str(exc)


def test_no_secret_in_database(client, db):
    org = make_org(db)
    user, secret = make_user(db, org)
    tokens = login(client, user.email, secret)
    row = db.scalar(select(User).where(User.id == user.id))
    assert STRONG_PASSWORD not in row.password_hash
    session = db.scalar(select(AuthSession).where(AuthSession.user_id == user.id))
    assert session.refresh_token_hash != tokens["refresh_token"]


def test_invitation_page_is_static(client):
    r = client.get("/invitation")
    assert r.status_code == 200
    assert "J'ai reçu un lien" in r.text
    assert client.get("/reinitialisation").status_code == 200
    assert r.headers["cache-control"] == "no-store"
