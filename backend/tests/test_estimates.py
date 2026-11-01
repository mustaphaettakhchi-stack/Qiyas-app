from sqlalchemy import text

from app.ids import uuid7
from app.models import Role
from app.quotes import compute

from .test_sync import _project_change, _pull, _push, _staff

FP = "b" * 64


def _lines():
    return [
        {"id": "l1", "label": "Peinture murs", "unit": "m²", "quantity_basis": "walls_net", "quantity": 163.03,
         "pricing": "direct", "unit_price_cents": 4500, "vat_rate_bp": 2000},
        {"id": "l2", "label": "Nettoyage", "unit": "forfait", "quantity_basis": "manual", "quantity": 1, "manual": True,
         "pricing": "direct", "unit_price_cents": 80000, "vat_rate_bp": 1000},
    ]


def _quote(qid, pid, eid, base=None, status="draft", lines=None, user_id=None, version_no=1, **extra):
    lines = lines if lines is not None else _lines()
    data = {"estimate_id": str(eid), "project_id": str(pid), "version_no": version_no, "status": status,
            "issue_date": "2026-11-01", "validity_days": 30, "deposit_bp": 3000, "lines": lines,
            "metre_fingerprint": FP, **extra}
    t = compute(lines, data.get("discount_bp", 0), data.get("overhead_bp", 0), data.get("margin_bp", 0), data["deposit_bp"])
    data["totals"] = t.as_dict()
    if status != "draft":
        data.setdefault("validated_at", "2026-11-01T10:00:00Z")
        data.setdefault("validated_by", str(user_id))
    return {"entity": "quotes", "id": str(qid), "base_version": base, "data": data}


def _project_with_metre(client, h, user):
    pid = uuid7()
    _push(client, h, _project_change(pid))
    validation = {"validated_at": "2026-11-01T09:00:00Z", "validated_by": str(user.id), "fingerprint": FP,
                  "rooms": 1, "unverified_accepted": 0}
    _push(client, h, _project_change(pid, base=1, metre_validation=validation))
    return pid


def test_draft_then_validation_assigns_number(client, db):
    _, admin, h = _staff(client, db)
    pid, qid, eid = _project_with_metre(client, h, admin), uuid7(), uuid7()
    draft = _push(client, h, _quote(qid, pid, eid))[0]
    assert draft["status"] == "applied" and draft["record"]["reference"] is None
    assert draft["record"]["data"]["totals"]["vat"] == {"1000": 8000, "2000": 146727}  # 733 635 × 20 %
    res = _push(client, h, _quote(qid, pid, eid, base=1, status="validated", user_id=admin.id))[0]
    assert res["status"] == "applied", res
    assert res["record"]["reference"].startswith("DV-2026-") or res["record"]["reference"].startswith("DV-")


def test_validated_quote_is_frozen_in_api_and_database(client, db):
    org, admin, h = _staff(client, db)
    pid, qid, eid = _project_with_metre(client, h, admin), uuid7(), uuid7()
    _push(client, h, _quote(qid, pid, eid, status="validated", user_id=admin.id))
    changed = _lines()
    changed[0]["unit_price_cents"] = 5000
    res = _push(client, h, _quote(qid, pid, eid, base=1, status="validated", user_id=admin.id, lines=changed))[0]
    assert res["status"] == "rejected" and "nouvelle version" in res["message"]
    deleted = _push(client, h, {**_quote(qid, pid, eid, base=1, status="validated", user_id=admin.id), "deleted": True})[0]
    assert deleted["status"] == "rejected"
    # Même une requête SQL directe ne peut pas modifier un devis validé.
    from app.db import bind_organization

    bind_organization(db, org.id)
    try:
        db.execute(text("UPDATE estimate_versions SET discount_bp = 9000 WHERE id = :i"), {"i": str(qid)})
        db.commit()
        raise AssertionError("modification acceptée")
    except Exception as exc:  # noqa: BLE001
        db.rollback()
        assert "devis figé" in str(exc)


def test_status_workflow_and_audit(client, db):
    org, admin, h = _staff(client, db)
    pid, qid, eid = _project_with_metre(client, h, admin), uuid7(), uuid7()
    _push(client, h, _quote(qid, pid, eid, status="validated", user_id=admin.id))
    assert _push(client, h, _quote(qid, pid, eid, base=1, status="draft"))[0]["status"] == "rejected"
    assert _push(client, h, _quote(qid, pid, eid, base=1, status="accepted", user_id=admin.id))[0]["status"] == "rejected"
    sent = _push(client, h, _quote(qid, pid, eid, base=1, status="sent", user_id=admin.id, sent_at="2026-11-02T08:00:00Z"))[0]
    assert sent["status"] == "applied"
    accepted = _push(client, h, _quote(qid, pid, eid, base=2, status="accepted", user_id=admin.id,
                                       sent_at="2026-11-02T08:00:00Z", decided_at="2026-11-05T08:00:00Z",
                                       decision_note="Accord téléphonique"))[0]
    assert accepted["status"] == "applied"
    from app.db import bind_organization

    bind_organization(db, org.id)
    actions = [r[0] for r in db.execute(
        text("SELECT action FROM audit_logs WHERE entity_id = :i ORDER BY occurred_at"), {"i": str(qid)})]
    # Création et validation dans la même transaction : même horodatage, ordre indifférent.
    assert set(actions[:2]) == {"estimate.create", "estimate.validate"}
    assert actions[2:] == ["estimate.send", "estimate.accept"]


def test_new_version_keeps_number_with_suffix(client, db):
    _, admin, h = _staff(client, db)
    pid, eid = _project_with_metre(client, h, admin), uuid7()
    v1, v2 = uuid7(), uuid7()
    first = _push(client, h, _quote(v1, pid, eid, status="validated", user_id=admin.id))[0]["record"]["reference"]
    res = _push(client, h,
                _quote(v1, pid, eid, base=1, status="superseded", user_id=admin.id),
                _quote(v2, pid, eid, version_no=2, status="validated", user_id=admin.id))
    assert [r["status"] for r in res] == ["applied", "applied"]
    assert res[1]["record"]["reference"] == f"{first}-v2"


def test_validation_rules(client, db):
    org, admin, h = _staff(client, db)
    _, _, h_collab = _staff(client, db, Role.collaborator, org=org)
    pid = _project_with_metre(client, h, admin)
    no_price = _lines()
    no_price[0]["unit_price_cents"] = None
    cases = [
        (h, _quote(uuid7(), pid, uuid7(), status="validated", user_id=admin.id, lines=no_price), "prix"),
        (h, _quote(uuid7(), pid, uuid7(), status="validated", user_id=admin.id, lines=[]), "sans ligne"),
        (h, _quote(uuid7(), pid, uuid7(), status="validated", user_id=admin.id, metre_fingerprint="c" * 64), "métré"),
    ]
    for headers, change, word in cases:
        res = _push(client, headers, change)[0]
        assert res["status"] == "rejected" and word in res["message"], res
    # Un collaborateur prépare le brouillon mais ne valide pas.
    qid, eid = uuid7(), uuid7()
    assert _push(client, h_collab, _quote(qid, pid, eid))[0]["status"] == "rejected"  # projet non confié
    collab_pid = uuid7()
    _push(client, h_collab, _project_change(collab_pid))
    assert _push(client, h_collab, _quote(qid, collab_pid, eid))[0]["status"] == "applied"


def test_totals_mismatch_rejected(client, db):
    _, admin, h = _staff(client, db)
    pid = _project_with_metre(client, h, admin)
    change = _quote(uuid7(), pid, uuid7())
    change["data"]["totals"]["ttc"] += 1
    res = _push(client, h, change)[0]
    assert res["status"] == "rejected" and "Écart de calcul" in res["message"]


def test_eur_requires_rate(client, db):
    _, admin, h = _staff(client, db)
    pid = _project_with_metre(client, h, admin)
    assert _push(client, h, _quote(uuid7(), pid, uuid7(), currency="EUR"))[0]["status"] == "rejected"
    ok = _push(client, h, _quote(uuid7(), pid, uuid7(), currency="EUR", exchange_rate_e4=108500,
                                 exchange_rate_date="2026-11-01", exchange_rate_source="Bank Al-Maghrib"))[0]
    assert ok["status"] == "applied"
    pulled = [r for r in _pull(client, h)["records"] if r["entity"] == "quotes"]
    assert any(r["data"]["exchange_rate_e4"] == 108500 for r in pulled)
