import io
import time

from PIL import Image

from app.ids import uuid7
from app.models import Role
from app.routes.files import _signature

from .conftest import STRONG_PASSWORD, auth, unique_email
from .test_estimates import _project_with_metre, _quote
from .test_sync import _client_change, _project_change, _pull, _push, _staff


def _jpeg_with_gps() -> bytes:
    img = Image.new("RGB", (40, 30), (200, 120, 0))
    exif = img.getexif()
    exif[0x010F] = "Telephone"  # fabricant
    gps = exif.get_ifd(0x8825)
    gps[1] = "N"
    gps[2] = (35.0, 46.0, 0.0)  # Tanger
    gps[3] = "W"
    gps[4] = (5.0, 48.0, 0.0)
    buf = io.BytesIO()
    img.save(buf, format="JPEG", exif=exif)
    return buf.getvalue()


def _has_gps(data: bytes) -> bool:
    with Image.open(io.BytesIO(data)) as img:
        return bool(img.getexif().get_ifd(0x8825))


def _upload(client, h, pid, kind="photo", data=None, **form):
    data = data if data is not None else _jpeg_with_gps()
    files = {"file": ("f", data, "application/octet-stream")}
    fields = {"project_id": str(pid), "kind": kind, **{k: str(v).lower() if isinstance(v, bool) else str(v) for k, v in form.items()}}
    return client.post("/api/v1/files", headers=h, data=fields, files=files)


def _invite_client(client, h_admin, client_id):
    email = unique_email("client")
    inv = client.post("/api/v1/invitations", headers=h_admin,
                      json={"email": email, "full_name": "Client Test", "role": "client", "client_id": str(client_id)})
    assert inv.status_code == 201, inv.text
    token = inv.json()["invitation_url"].split("#", 1)[1]
    assert client.post("/api/v1/invitations/accept", json={"token": token, "password": STRONG_PASSWORD}).status_code == 201
    r = client.post("/api/v1/auth/login", json={"email": email, "password": STRONG_PASSWORD}).json()
    assert r["tokens"] is not None  # double authentification facultative pour un client
    return auth(r["tokens"])


def _scene(client, db):
    """Deux clients A et B d'une même entreprise, chacun avec un projet."""
    org, admin, h = _staff(client, db)
    ca, cb = uuid7(), uuid7()
    _push(client, h, _client_change(ca, "Client A"), _client_change(cb, "Client B"))
    pa = _project_with_metre(client, h, admin)
    _push(client, h, _project_change(pa, ca, base=2,
                                     metre_validation={"validated_at": "2026-11-01T09:00:00Z", "validated_by": str(admin.id),
                                                       "fingerprint": "b" * 64, "rooms": 1, "unverified_accepted": 0}))
    pb = uuid7()
    _push(client, h, _project_change(pb, cb))
    # Devis : un envoyé (visible), un brouillon (invisible).
    sent, draft, eid = uuid7(), uuid7(), uuid7()
    _push(client, h, _quote(sent, pa, eid, status="validated", user_id=admin.id))
    _push(client, h, _quote(sent, pa, eid, base=1, status="sent", user_id=admin.id, sent_at="2026-11-02T08:00:00Z"))
    _push(client, h, _quote(draft, pa, uuid7()))
    pdf = _upload(client, h, pa, kind="quote_pdf", data=b"%PDF-1.4 devis", quote_version_id=sent)
    assert pdf.status_code == 201, pdf.text
    shared = _upload(client, h, pa, visible_to_client=True, caption="Salon avant travaux").json()
    private = _upload(client, h, pa, caption="Photo interne").json()
    photo_b = _upload(client, h, pb, visible_to_client=True).json()
    return {"org": org, "admin": admin, "h": h, "ca": ca, "cb": cb, "pa": pa, "pb": pb, "sent": sent, "draft": draft,
            "pdf": pdf.json(), "shared": shared, "private": private, "photo_b": photo_b,
            "h_a": _invite_client(client, h, ca), "h_b": _invite_client(client, h, cb)}


def test_client_sees_only_own_projects_and_shared_items(client, db):
    s = _scene(client, db)
    projects = client.get("/api/v1/client/projects", headers=s["h_a"]).json()
    assert [p["id"] for p in projects] == [str(s["pa"])]
    d = client.get(f"/api/v1/client/projects/{s['pa']}", headers=s["h_a"]).json()
    assert [q["id"] for q in d["quotes"]] == [str(s["sent"])]  # le brouillon n'apparaît pas
    assert d["quotes"][0]["pdf_file_id"] == s["pdf"]["id"]
    assert [p["id"] for p in d["photos"]] == [s["shared"]["id"]]  # la photo interne n'apparaît pas
    assert "estimate.send" in [t["action"] for t in d["timeline"]]
    # Jamais de déboursé, de marge ni de ligne détaillée dans l'espace client.
    body = str(d)
    for word in ("margin", "overhead", "cost", "lines", "labour", "material"):
        assert word not in body


def test_client_cannot_reach_another_client_or_staff_routes(client, db):
    s = _scene(client, db)
    h = s["h_a"]
    for url in (f"/api/v1/client/projects/{s['pb']}", f"/api/v1/client/projects/{s['pb']}/messages",
                f"/api/v1/files/{s['photo_b']['id']}/link", f"/api/v1/files/{s['private']['id']}/link",
                f"/api/v1/client/projects/{uuid7()}"):
        assert client.get(url, headers=h).status_code == 404, url
    assert client.post(f"/api/v1/client/projects/{s['pb']}/messages", headers=h, json={"body": "x"}).status_code == 404
    for url in ("/api/v1/sync/pull", f"/api/v1/files/project/{s['pa']}", f"/api/v1/projects/{s['pa']}/messages",
                "/api/v1/dashboard", "/api/v1/users"):
        assert client.get(url, headers=h).status_code == 403, url


def test_signed_links_expire_and_are_bound(client, db):
    s = _scene(client, db)
    link = client.get(f"/api/v1/files/{s['shared']['id']}/link", headers=s["h_a"]).json()
    from datetime import datetime

    remaining = datetime.fromisoformat(link["expires_at"]).timestamp() - time.time()
    assert 0 < remaining <= 15 * 60 + 1
    assert client.get(link["url"]).status_code == 200  # sans session : la signature suffit
    tampered = link["url"].replace("v=client", "v=original")
    assert client.get(tampered).status_code == 403
    # Lien expiré, correctement signé : refusé.
    q = dict(part.split("=") for part in link["url"].split("?")[1].split("&"))
    old = int(time.time()) - 10
    sig = _signature(s["shared"]["id"], old, q["uid"], q["org"], "client")
    expired = f"/api/v1/files/download/{s['shared']['id']}?exp={old}&uid={q['uid']}&org={q['org']}&v=client&sig={sig}"
    assert client.get(expired).status_code == 410
    # Partage retiré : le lien déjà émis ne donne plus rien.
    client.patch(f"/api/v1/files/{s['shared']['id']}", headers=s["h"], json={"visible_to_client": False})
    assert client.get(link["url"]).status_code == 404


def test_client_copy_has_no_gps_original_keeps_it(client, db):
    s = _scene(client, db)
    client_link = client.get(f"/api/v1/files/{s['shared']['id']}/link", headers=s["h_a"]).json()["url"]
    staff_link = client.get(f"/api/v1/files/{s['shared']['id']}/link", headers=s["h"]).json()["url"]
    client_bytes = client.get(client_link).content
    staff_bytes = client.get(staff_link).content
    assert _has_gps(staff_bytes)
    assert not _has_gps(client_bytes)
    with Image.open(io.BytesIO(client_bytes)) as img:
        assert len(img.getexif()) == 0


def test_messages_between_client_and_team(client, db):
    s = _scene(client, db)
    r = client.post(f"/api/v1/client/projects/{s['pa']}/messages", headers=s["h_a"], json={"body": "Quand commencez-vous ?"})
    assert r.status_code == 201
    client.post(f"/api/v1/projects/{s['pa']}/messages", headers=s["h"], json={"body": "Lundi 9 h."})
    seen = client.get(f"/api/v1/client/projects/{s['pa']}/messages", headers=s["h_a"]).json()
    assert [(m["from_client"], m["body"]) for m in seen] == [(True, "Quand commencez-vous ?"), (False, "Lundi 9 h.")]
    assert client.get(f"/api/v1/client/projects/{s['pb']}/messages", headers=s["h_b"]).json() == []
    # L'administrateur voit le message du client dans les dernières opérations.
    activity = client.get("/api/v1/dashboard/activity", headers=s["h"]).json()
    assert any(a["action"] == "message.post" and a["actor_name"] == "Client Test" for a in activity)


def test_upload_rules(client, db):
    s = _scene(client, db)
    h, pa = s["h"], s["pa"]
    assert _upload(client, h, pa, data=b"MZ executable").status_code == 422  # type réel contrôlé
    assert _upload(client, h, pa, kind="quote_pdf", data=b"%PDF-1.4", quote_version_id=s["draft"]).status_code == 422
    again = _upload(client, h, pa, kind="quote_pdf", data=b"%PDF-1.4 devis", quote_version_id=s["sent"])
    assert again.status_code == 201 and again.json()["id"] == s["pdf"]["id"]  # nouvel essai idempotent
    other = _upload(client, h, pa, kind="quote_pdf", data=b"%PDF-1.4 autre", quote_version_id=s["sent"])
    assert other.status_code == 409  # jamais remplacé
    _, _, h_other = _staff(client, db)
    assert _upload(client, h_other, pa).status_code == 404  # autre organisation


def test_client_invitation_rules(client, db):
    org, admin, h = _staff(client, db)
    r = client.post("/api/v1/invitations", headers=h, json={"email": unique_email(), "full_name": "X", "role": "client"})
    assert r.status_code == 422
    _, _, h_other = _staff(client, db)
    foreign = uuid7()
    _push(client, h_other, _client_change(foreign))
    r = client.post("/api/v1/invitations", headers=h,
                    json={"email": unique_email(), "full_name": "X", "role": "client", "client_id": str(foreign)})
    assert r.status_code == 404
    r = client.post("/api/v1/invitations", headers=h,
                    json={"email": unique_email(), "full_name": "X", "role": "collaborator", "client_id": str(foreign)})
    assert r.status_code == 422
