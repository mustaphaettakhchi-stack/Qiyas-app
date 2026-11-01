from app.ids import uuid7
from app.models import Role

from .test_estimates import FP, _project_with_metre, _quote
from .test_sync import _project_change, _push, _staff


def test_dashboard_counts_follow_definitions(client, db):
    org, admin, h = _staff(client, db)
    # Projets : 2 prospects, 1 chiffrage, 1 accepté, 1 en travaux, 1 perdu, 1 supprimé (non compté).
    for status in ("prospect", "visit_planned", "estimating", "won", "in_progress", "lost"):
        _push(client, h, _project_change(uuid7(), status=status))
    gone = uuid7()
    _push(client, h, _project_change(gone, status="in_progress"))
    _push(client, h, _project_change(gone, base=1, deleted=True))

    pid = _project_with_metre(client, h, admin)  # prospect de plus
    e1, e2, e3, e4 = uuid7(), uuid7(), uuid7(), uuid7()
    _push(client, h, _quote(uuid7(), pid, e1))  # brouillon à valider
    _push(client, h, _quote(uuid7(), pid, e2, status="validated", user_id=admin.id))  # à envoyer
    _push(client, h, _quote(uuid7(), pid, e3, status="validated", user_id=admin.id))
    sent_id = uuid7()
    _push(client, h, _quote(sent_id, pid, e4, status="validated", user_id=admin.id))
    _push(client, h, _quote(sent_id, pid, e4, base=1, status="sent", user_id=admin.id, sent_at="2026-11-02T08:00:00Z"))
    # e3 : v1 remplacée par v2 acceptée — seule la v2 compte.
    accepted = uuid7()
    q3 = client.get("/api/v1/sync/pull", headers=h).json()["records"]
    v1 = next(r for r in q3 if r["entity"] == "quotes" and r["data"]["estimate_id"] == str(e3))
    _push(client, h, _quote(v1["id"], pid, e3, base=v1["version"], status="superseded", user_id=admin.id))
    _push(client, h, _quote(accepted, pid, e3, version_no=2, status="validated", user_id=admin.id))
    _push(client, h, _quote(accepted, pid, e3, version_no=2, base=1, status="sent", user_id=admin.id,
                            sent_at="2026-11-02T08:00:00Z"))
    _push(client, h, _quote(accepted, pid, e3, version_no=2, base=2, status="accepted", user_id=admin.id,
                            sent_at="2026-11-02T08:00:00Z", decided_at="2026-11-05T08:00:00Z"))

    d = client.get("/api/v1/dashboard", headers=h).json()
    ttc = _quote(uuid7(), pid, uuid7())["data"]["totals"]["ttc"]
    assert d == {
        "active_sites": 2,
        "prospects": 4,
        "quotes_to_validate": 1,
        "quotes_to_send": 1,
        "quotes_waiting": 1,
        "quotes_accepted": 1,
        "accepted_ttc_year": {"MAD": ttc},
    }


def test_collaborator_dashboard_and_activity_are_limited_to_own_work(client, db):
    org, admin, h_admin = _staff(client, db)
    _, karim, h_karim = _staff(client, db, Role.collaborator, org=org)
    _push(client, h_admin, _project_change(uuid7(), status="in_progress"))
    _push(client, h_karim, _project_change(uuid7(), status="prospect"))
    assert client.get("/api/v1/dashboard", headers=h_karim).json()["active_sites"] == 0
    assert client.get("/api/v1/dashboard", headers=h_karim).json()["prospects"] == 1
    assert client.get("/api/v1/dashboard", headers=h_admin).json()["prospects"] == 1
    assert client.get("/api/v1/dashboard", headers=h_admin).json()["active_sites"] == 1

    karim_acts = client.get("/api/v1/dashboard/activity", headers=h_karim).json()
    assert {a["actor_name"] for a in karim_acts} == {karim.full_name}
    admin_acts = client.get("/api/v1/dashboard/activity", headers=h_admin).json()
    assert {a["actor_name"] for a in admin_acts} == {karim.full_name, admin.full_name}
    assert all(not a["action"].startswith("auth.") for a in admin_acts)
    assert admin_acts[0]["project_reference"] is not None


def test_other_organization_invisible(client, db):
    _, _, h_a = _staff(client, db)
    _, _, h_b = _staff(client, db)
    _push(client, h_a, _project_change(uuid7(), status="in_progress"))
    assert client.get("/api/v1/dashboard", headers=h_b).json()["active_sites"] == 0
    assert client.get("/api/v1/dashboard/activity", headers=h_b).json() == []
