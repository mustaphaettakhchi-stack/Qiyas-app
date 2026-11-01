from datetime import timedelta

from sqlalchemy import select

from app.models import Invitation, Role

from .conftest import STRONG_PASSWORD, auth, login, make_org, make_user, unique_email


def _admin(client, db, name="Entreprise A"):
    org = make_org(db, name)
    user, secret = make_user(db, org, Role.admin)
    return org, user, login(client, user.email, secret)


def test_invitation_full_flow(client, db):
    _, _, tokens = _admin(client, db)
    email = unique_email("collab")
    r = client.post(
        "/api/v1/invitations",
        headers=auth(tokens),
        json={"email": email, "full_name": "Karim Collaborateur", "role": "collaborator"},
    )
    assert r.status_code == 201, r.text
    data = r.json()
    assert data["email_sent"] is False  # pas de relais SMTP en test
    token = data["invitation_url"].split("#", 1)[1]

    weak = client.post("/api/v1/invitations/accept", json={"token": token, "password": "motdepasse123"})
    assert weak.status_code == 422
    ok = client.post("/api/v1/invitations/accept", json={"token": token, "password": STRONG_PASSWORD})
    assert ok.status_code == 201, ok.text
    again = client.post("/api/v1/invitations/accept", json={"token": token, "password": STRONG_PASSWORD})
    assert again.status_code == 410

    login_r = client.post("/api/v1/auth/login", json={"email": email, "password": STRONG_PASSWORD}).json()
    assert login_r["mfa_setup_required"]


def test_expired_invitation(client, db):
    _, _, tokens = _admin(client, db)
    email = unique_email()
    data = client.post(
        "/api/v1/invitations", headers=auth(tokens),
        json={"email": email, "full_name": "X", "role": "collaborator"},
    ).json()
    inv = db.scalar(select(Invitation).where(Invitation.email == email))
    inv.expires_at = inv.created_at - timedelta(seconds=1)
    db.commit()
    token = data["invitation_url"].split("#", 1)[1]
    r = client.post("/api/v1/invitations/accept", json={"token": token, "password": STRONG_PASSWORD})
    assert r.status_code == 410


def test_client_invitations_wait_for_client_module(client, db):
    _, _, tokens = _admin(client, db)
    r = client.post(
        "/api/v1/invitations", headers=auth(tokens),
        json={"email": unique_email(), "full_name": "Client", "role": "client"},
    )
    assert r.status_code == 422


def test_existing_account_cannot_be_invited(client, db):
    org, admin, tokens = _admin(client, db)
    r = client.post(
        "/api/v1/invitations", headers=auth(tokens),
        json={"email": admin.email, "full_name": "X", "role": "collaborator"},
    )
    assert r.status_code == 409


def test_collaborator_cannot_use_admin_routes(client, db):
    org = make_org(db)
    collab, secret = make_user(db, org, Role.collaborator)
    tokens = login(client, collab.email, secret)
    assert client.get("/api/v1/users", headers=auth(tokens)).status_code == 403
    r = client.post(
        "/api/v1/invitations", headers=auth(tokens),
        json={"email": unique_email(), "full_name": "X", "role": "admin"},
    )
    assert r.status_code == 403


def test_organizations_are_isolated(client, db):
    org_a, admin_a, tokens_a = _admin(client, db, "A")
    org_b, admin_b, tokens_b = _admin(client, db, "B")
    collab_b, _ = make_user(db, org_b, Role.collaborator)
    inv_b = client.post(
        "/api/v1/invitations", headers=auth(tokens_b),
        json={"email": unique_email(), "full_name": "Y", "role": "collaborator"},
    ).json()

    ids_a = {u["id"] for u in client.get("/api/v1/users", headers=auth(tokens_a)).json()}
    assert str(admin_a.id) in ids_a
    assert str(admin_b.id) not in ids_a and str(collab_b.id) not in ids_a

    h = auth(tokens_a)
    assert client.patch(f"/api/v1/users/{collab_b.id}", headers=h, json={"status": "suspended"}).status_code == 404
    assert client.post(f"/api/v1/users/{collab_b.id}/mfa/reset", headers=h).status_code == 404
    assert client.delete(f"/api/v1/invitations/{inv_b['id']}", headers=h).status_code == 404
    assert all(i["id"] != inv_b["id"] for i in client.get("/api/v1/invitations", headers=h).json())


def test_last_admin_is_protected(client, db):
    _, admin, tokens = _admin(client, db)
    r = client.patch(f"/api/v1/users/{admin.id}", headers=auth(tokens), json={"role": "collaborator"})
    assert r.status_code == 409
    r = client.patch(f"/api/v1/users/{admin.id}", headers=auth(tokens), json={"status": "suspended"})
    assert r.status_code == 409


def test_suspension_and_role_change_revoke_sessions(client, db):
    org, _, admin_tokens = _admin(client, db)
    collab, secret = make_user(db, org, Role.collaborator)
    collab_tokens = login(client, collab.email, secret)
    assert client.get("/api/v1/auth/me", headers=auth(collab_tokens)).status_code == 200

    r = client.patch(f"/api/v1/users/{collab.id}", headers=auth(admin_tokens), json={"status": "suspended"})
    assert r.status_code == 200 and r.json()["status"] == "suspended"
    assert client.get("/api/v1/auth/me", headers=auth(collab_tokens)).status_code == 401
    r = client.post("/api/v1/auth/login", json={"email": collab.email, "password": STRONG_PASSWORD})
    assert r.status_code == 401


def test_promotion_to_admin(client, db):
    org, _, admin_tokens = _admin(client, db)
    collab, secret = make_user(db, org, Role.collaborator)
    r = client.patch(f"/api/v1/users/{collab.id}", headers=auth(admin_tokens), json={"role": "admin"})
    assert r.status_code == 200 and r.json()["roles"] == ["admin"]
    new_tokens = login(client, collab.email, secret)
    assert client.get("/api/v1/users", headers=auth(new_tokens)).status_code == 200


def test_password_reset_by_admin(client, db):
    org, _, admin_tokens = _admin(client, db)
    collab, secret = make_user(db, org, Role.collaborator)
    old_tokens = login(client, collab.email, secret)

    r = client.post(f"/api/v1/users/{collab.id}/password-reset", headers=auth(admin_tokens))
    assert r.status_code == 201, r.text
    token = r.json()["reset_url"].split("#", 1)[1]
    assert "/reinitialisation#" in r.json()["reset_url"]

    weak = client.post("/api/v1/password-reset/accept", json={"token": token, "password": "motdepasse123"})
    assert weak.status_code == 422
    new_password = "Ruelle-indigo-panier-marbre-93"
    ok = client.post("/api/v1/password-reset/accept", json={"token": token, "password": new_password})
    assert ok.status_code == 200
    # Lien à usage unique, anciennes sessions fermées, ancien mot de passe refusé.
    assert client.post("/api/v1/password-reset/accept", json={"token": token, "password": new_password}).status_code == 410
    assert client.get("/api/v1/auth/me", headers=auth(old_tokens)).status_code == 401
    assert client.post("/api/v1/auth/login", json={"email": collab.email, "password": STRONG_PASSWORD}).status_code == 401
    # La double authentification reste exigée.
    body = client.post("/api/v1/auth/login", json={"email": collab.email, "password": new_password}).json()
    assert body["mfa_required"] and body["tokens"] is None


def test_password_reset_is_admin_only_and_isolated(client, db):
    org_a, _, tokens_a = _admin(client, db, "A")
    org_b, _, _ = _admin(client, db, "B")
    collab_a, secret = make_user(db, org_a, Role.collaborator)
    collab_b, _ = make_user(db, org_b, Role.collaborator)
    assert client.post(f"/api/v1/users/{collab_b.id}/password-reset", headers=auth(tokens_a)).status_code == 404
    collab_tokens = login(client, collab_a.email, secret)
    assert client.post(f"/api/v1/users/{collab_a.id}/password-reset", headers=auth(collab_tokens)).status_code == 403


def test_new_reset_link_revokes_previous(client, db):
    org, _, admin_tokens = _admin(client, db)
    collab, _ = make_user(db, org, Role.collaborator)
    first = client.post(f"/api/v1/users/{collab.id}/password-reset", headers=auth(admin_tokens)).json()
    client.post(f"/api/v1/users/{collab.id}/password-reset", headers=auth(admin_tokens))
    token = first["reset_url"].split("#", 1)[1]
    r = client.post("/api/v1/password-reset/accept", json={"token": token, "password": "Ruelle-indigo-panier-marbre-93"})
    assert r.status_code == 410
