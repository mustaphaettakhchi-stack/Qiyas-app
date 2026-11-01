from sqlalchemy import text

from app.ids import uuid7
from app.models import Role

from .test_sync import _project_change, _pull, _push, _room_change, _staff


def _material(mid, base=None, **extra):
    data = {"name": "Carreau grès cérame 60x60", "category": "floor", "unit": "m2", "waste_rate_bp": 1000,
            "purchase_price_cents": 12000, "sale_price_cents": 18000, "price_note": "Devis fournisseur n°12", **extra}
    return {"entity": "materials", "id": str(mid), "base_version": base, "data": data}


def _work_item(wid, base=None, **extra):
    data = {"code": "SOL-01", "category": "floor", "name": "Carrelage sol posé", "unit": "m2",
            "quantity_basis": "floor", "waste_rate_bp": 1000, "sale_price_cents": None, **extra}
    return {"entity": "work_items", "id": str(wid), "base_version": base, "data": data}


def test_library_is_admin_write_staff_read(client, db):
    org, _, h_admin = _staff(client, db)
    _, _, h_collab = _staff(client, db, Role.collaborator, org=org)
    mid, wid = uuid7(), uuid7()
    res = _push(client, h_admin, _material(mid), _work_item(wid, components=[{"material_id": str(mid), "quantity_per_unit": 1.0}]))
    assert [r["status"] for r in res] == ["applied", "applied"]
    # Le collaborateur lit la bibliothèque, sans les prix d'achat, et ne peut pas la modifier.
    recs = {r["entity"]: r for r in _pull(client, h_collab)["records"]}
    assert recs["materials"]["data"]["purchase_price_cents"] is None
    assert recs["materials"]["data"]["sale_price_cents"] == 18000
    admin_recs = {r["entity"]: r for r in _pull(client, h_admin)["records"]}
    assert admin_recs["materials"]["data"]["purchase_price_cents"] == 12000
    denied = _push(client, h_collab, _work_item(uuid7()))[0]
    assert denied["status"] == "rejected" and "administrateur" in denied["message"]


def test_price_not_set_is_null_never_zero(client, db):
    _, _, h = _staff(client, db)
    rec = _push(client, h, _work_item(uuid7()))[0]["record"]
    assert rec["data"]["sale_price_cents"] is None


def test_count_basis_requires_counted_element(client, db):
    _, _, h = _staff(client, db)
    bad = _push(client, h, _work_item(uuid7(), quantity_basis="count"), _work_item(uuid7(), count_key="prises"))
    assert [r["status"] for r in bad] == ["rejected", "rejected"]
    ok = _push(client, h, _work_item(uuid7(), quantity_basis="count", count_key="prises", unit="u"))[0]
    assert ok["status"] == "applied"


def test_price_history_is_append_only(client, db):
    org, _, h = _staff(client, db)
    mid = uuid7()
    _push(client, h, _material(mid))
    _push(client, h, _material(mid, base=1, sale_price_cents=19500, price_note="Hausse fournisseur"))
    _push(client, h, _material(mid, base=2, name="Carreau 60x60 gris", sale_price_cents=19500))  # prix inchangés : pas de ligne
    hist = client.get(f"/api/v1/library/price-history/materials/{mid}", headers=h).json()
    assert [x["sale_price_cents"] for x in hist] == [19500, 18000]
    assert hist[0]["source_note"] == "Hausse fournisseur"
    from app.db import bind_organization

    bind_organization(db, org.id)
    for sql in ("UPDATE price_history SET sale_price_cents = 1", "DELETE FROM price_history"):
        try:
            db.execute(text(sql))
            db.commit()
            raise AssertionError(sql)
        except Exception as exc:  # noqa: BLE001
            db.rollback()
            assert "insertion seule" in str(exc)


def test_material_in_use_cannot_be_deleted(client, db):
    _, _, h = _staff(client, db)
    mid = uuid7()
    _push(client, h, _material(mid), _work_item(uuid7(), components=[{"material_id": str(mid), "quantity_per_unit": 1}]))
    res = _push(client, h, {"entity": "materials", "id": str(mid), "base_version": 1, "deleted": True, "data": {}})[0]
    assert res["status"] == "rejected"


def test_csv_import_all_or_nothing_with_line_numbers(client, db):
    _, _, h = _staff(client, db)
    csv_ok = (
        "code;categorie;designation;description;unite;base;element_compte;perte_pct;prix_vente;main_oeuvre\n"
        "PEI-01;Murs;Peinture murs 2 couches;;m²;murs_nets;;5;45,00;20\n"
        "ELE-01;Électricité;Prise de courant;;u;comptage;prises;0;;\n"
    )
    r = client.post("/api/v1/library/import", headers=h, json={"kind": "work_items", "csv": csv_ok})
    assert r.status_code == 200 and r.json() == {"created": 2, "errors": []}
    recs = [x for x in _pull(client, h)["records"] if x["entity"] == "work_items"]
    by_code = {x["data"]["code"]: x["data"] for x in recs}
    assert by_code["PEI-01"]["unit"] == "m2" and by_code["PEI-01"]["waste_rate_bp"] == 500
    assert by_code["PEI-01"]["sale_price_cents"] == 4500
    assert by_code["ELE-01"]["sale_price_cents"] is None  # prix vide = non renseigné

    csv_bad = (
        "code;categorie;designation;description;unite;base;element_compte;perte_pct;prix_vente;main_oeuvre\n"
        "A;Murs;Enduit;;m²;murs_nets;;0;30;\n"
        "B;Murs;Sans unité;;;murs_nets;;0;30;\n"
        "C;Murs;Prix faux;;m²;murs_nets;;0;trente;\n"
    )
    r = client.post("/api/v1/library/import", headers=h, json={"kind": "work_items", "csv": csv_bad}).json()
    assert r["created"] == 0
    assert [e["line"] for e in r["errors"]] == [3, 4]
    codes = {x["data"]["code"] for x in _pull(client, h)["records"] if x["entity"] == "work_items"}
    assert "A" not in codes  # rien n'est importé si une ligne est fausse


def test_csv_import_admin_only_and_columns_checked(client, db):
    org, _, h_admin = _staff(client, db)
    _, _, h_collab = _staff(client, db, Role.collaborator, org=org)
    assert client.post("/api/v1/library/import", headers=h_collab, json={"kind": "materials", "csv": "x"}).status_code == 403
    r = client.post("/api/v1/library/import", headers=h_admin, json={"kind": "materials", "csv": "nom;prix\nA;1"})
    assert r.status_code == 422 and "Colonnes manquantes" in r.json()["detail"]


def test_metre_validation_stored_and_audited(client, db):
    org, user, h = _staff(client, db)
    pid = uuid7()
    _push(client, h, _project_change(pid), _room_change(uuid7(), pid, counts={"prises": 4, "points_eau": 1}))
    validation = {"validated_at": "2026-11-01T10:00:00Z", "validated_by": str(user.id), "validated_by_name": "Admin",
                  "fingerprint": "a" * 64, "rooms": 1, "unverified_accepted": 2}
    rec = _push(client, h, _project_change(pid, base=1, metre_validation=validation))[0]
    assert rec["status"] == "applied"
    assert rec["record"]["data"]["metre_validation"]["unverified_accepted"] == 2
    bad = _push(client, h, _project_change(pid, base=2, metre_validation={**validation, "fingerprint": "court"}))[0]
    assert bad["status"] == "rejected"
    from app.db import bind_organization

    bind_organization(db, org.id)
    actions = db.execute(
        text("SELECT action, details->>'unverified_accepted' FROM audit_logs WHERE project_id = :p"), {"p": str(pid)}
    ).all()
    assert ("metre.validate", "2") in [tuple(a) for a in actions]
    rooms = [r for r in _pull(client, h)["records"] if r["entity"] == "rooms"]
    assert rooms[0]["data"]["counts"] == {"prises": 4.0, "points_eau": 1.0}
    bad_count = _push(client, h, _room_change(uuid7(), pid, counts={"inconnu": 1}))[0]
    assert bad_count["status"] == "rejected"
