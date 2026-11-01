import uuid

from sqlalchemy import text

from app.ids import uuid7
from app.models import Role

from .conftest import DB_URL, auth, login, make_org, make_user


def _staff(client, db, role=Role.admin, org=None):
    org = org or make_org(db)
    user, secret = make_user(db, org, role)
    return org, user, auth(login(client, user.email, secret))


def _client_change(cid, name="M. Benali", base=None, deleted=False, **extra):
    return {"entity": "clients", "id": str(cid), "base_version": base, "deleted": deleted,
            "data": {"display_name": name, "phone": "0661000000", "city": "Tanger", **extra}}


def _project_change(pid, client_id=None, base=None, deleted=False, **extra):
    data = {"client_id": str(client_id) if client_id else None, "name": "Rénovation appartement",
            "site_city": "Tanger", **extra}
    return {"entity": "projects", "id": str(pid), "base_version": base, "deleted": deleted, "data": data}


def _push(client, headers, *changes):
    r = client.post("/api/v1/sync/push", headers=headers, json={"changes": list(changes)})
    assert r.status_code == 200, r.text
    return r.json()["results"]


def _pull(client, headers, cursor=0):
    r = client.get(f"/api/v1/sync/pull?cursor={cursor}", headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


def test_create_client_and_project_offline_then_sync(client, db):
    _, _, h = _staff(client, db, Role.collaborator)
    cid, pid = uuid7(), uuid7()
    res = _push(client, h, _client_change(cid), _project_change(pid, cid))
    assert [r["status"] for r in res] == ["applied", "applied"]
    project = res[1]["record"]
    assert project["version"] == 1
    assert project["reference"].startswith("LMA-")
    pulled = _pull(client, h)
    assert {r["id"] for r in pulled["records"]} == {str(cid), str(pid)}
    assert pulled["cursor"] > 0
    assert _pull(client, h, pulled["cursor"])["records"] == []


def test_references_are_sequential_per_organization(client, db):
    _, _, h = _staff(client, db)
    refs = [_push(client, h, _project_change(uuid7()))[0]["record"]["reference"] for _ in range(3)]
    numbers = [int(r.rsplit("-", 1)[1]) for r in refs]
    assert numbers == [1, 2, 3]
    _, _, other = _staff(client, db)
    assert _push(client, other, _project_change(uuid7()))[0]["record"]["reference"].endswith("-0001")


def test_stale_version_is_a_conflict_never_an_overwrite(client, db):
    org, _, h1 = _staff(client, db)
    _, _, h2 = _staff(client, db, org=org)
    cid = uuid7()
    _push(client, h1, _client_change(cid))
    assert _push(client, h1, _client_change(cid, "M. Benali Karim", base=1))[0]["status"] == "applied"
    res = _push(client, h2, _client_change(cid, "Autre nom", base=1))[0]
    assert res["status"] == "conflict"
    assert res["record"]["data"]["display_name"] == "M. Benali Karim"
    assert res["record"]["version"] == 2
    # Résolution « garder ma version » : renvoi sur la version actuelle.
    assert _push(client, h2, _client_change(cid, "Autre nom", base=2))[0]["status"] == "applied"


def test_deletion_propagates_as_tombstone(client, db):
    _, _, h = _staff(client, db)
    pid = uuid7()
    _push(client, h, _project_change(pid))
    cursor = _pull(client, h)["cursor"]
    assert _push(client, h, _project_change(pid, base=1, deleted=True))[0]["status"] == "applied"
    rec = _pull(client, h, cursor)["records"]
    assert len(rec) == 1 and rec[0]["deleted"] is True


def test_created_then_deleted_offline_is_a_noop(client, db):
    _, _, h = _staff(client, db)
    assert _push(client, h, _project_change(uuid7(), deleted=True))[0]["status"] == "applied"
    assert _pull(client, h)["records"] == []


def test_client_with_projects_cannot_be_deleted(client, db):
    _, _, h = _staff(client, db)
    cid = uuid7()
    _push(client, h, _client_change(cid), _project_change(uuid7(), cid))
    res = _push(client, h, _client_change(cid, base=1, deleted=True))[0]
    assert res["status"] == "rejected" and "projets" in res["message"]


def test_invalid_data_rejected_with_readable_message(client, db):
    _, _, h = _staff(client, db)
    res = _push(
        client, h,
        {"entity": "clients", "id": str(uuid7()), "data": {"display_name": ""}},
        {"entity": "projects", "id": str(uuid7()), "data": {"status": "inconnu"}},
        {"entity": "projects", "id": str(uuid7()), "data": {"champ_pirate": 1}},
        {"entity": "projects", "id": str(uuid7()), "data": {"client_id": str(uuid.uuid4())}},
    )
    assert [r["status"] for r in res] == ["rejected"] * 4
    assert all(r["message"] for r in res)


def test_one_rejected_change_does_not_block_the_others(client, db):
    _, _, h = _staff(client, db)
    res = _push(client, h, _project_change(uuid7(), status="inconnu"), _project_change(uuid7()))
    assert [r["status"] for r in res] == ["rejected", "applied"]


def test_collaborators_only_see_their_projects(client, db):
    org, admin, h_admin = _staff(client, db)
    _, karim, h_karim = _staff(client, db, Role.collaborator, org=org)
    _, _, h_sara = _staff(client, db, Role.collaborator, org=org)
    cid, pid = uuid7(), uuid7()
    _push(client, h_karim, _client_change(cid), _project_change(pid, cid))

    assert _pull(client, h_sara)["records"] == []
    # Sara ne peut ni modifier ni « recréer » le projet de Karim.
    assert _push(client, h_sara, _project_change(pid, cid, base=1))[0]["status"] == "rejected"
    assert _push(client, h_sara, _project_change(pid))[0]["status"] == "rejected"
    # L'administrateur voit tout et peut confier le projet à Sara.
    assert len(_pull(client, h_admin)["records"]) == 2
    sara_id = client.get("/api/v1/auth/me", headers=h_sara).json()["id"]
    assert _push(client, h_admin, _project_change(pid, cid, base=1, manager_id=sara_id))[0]["status"] == "applied"
    assert {r["id"] for r in _pull(client, h_sara)["records"]} == {str(cid), str(pid)}
    # Un collaborateur ne peut pas changer le responsable.
    res = _push(client, h_karim, _project_change(pid, cid, base=2, manager_id=str(karim.id)))[0]
    assert res["status"] == "rejected"


def test_organizations_are_isolated(client, db):
    _, _, h_a = _staff(client, db)
    _, _, h_b = _staff(client, db)
    cid = uuid7()
    _push(client, h_a, _client_change(cid))
    assert _pull(client, h_b)["records"] == []
    assert _push(client, h_b, _client_change(cid, base=1))[0]["status"] == "rejected"
    assert _push(client, h_b, _client_change(cid))[0]["status"] == "rejected"
    assert _push(client, h_b, _project_change(uuid7(), cid))[0]["status"] == "rejected"


def test_client_accounts_cannot_sync(client, db):
    org = make_org(db)
    user, _ = make_user(db, org, Role.client, with_totp=False)
    r = client.post("/api/v1/auth/login", json={"email": user.email, "password": "Tanger-chantier-volet-orange-42"})
    h = auth(r.json()["tokens"])
    assert client.get("/api/v1/sync/pull", headers=h).status_code == 403
    assert client.post("/api/v1/sync/push", headers=h, json={"changes": []}).status_code == 403


def test_row_level_security_in_database(client, db):
    """Même une requête SQL sans filtre ne voit que l'organisation fixée dans app.org_id."""
    org_a, _, h_a = _staff(client, db)
    org_b, _, h_b = _staff(client, db)
    _push(client, h_a, _client_change(uuid7(), "Client A"))
    _push(client, h_b, _client_change(uuid7(), "Client B"))
    from sqlalchemy import create_engine

    engine = create_engine(DB_URL)
    with engine.connect() as conn:
        assert conn.execute(text("SELECT count(*) FROM clients")).scalar() == 0
        conn.execute(text("SELECT set_config('app.org_id', :o, false)"), {"o": str(org_a.id)})
        names = {r[0] for r in conn.execute(text("SELECT display_name FROM clients"))}
        assert names == {"Client A"}
        try:
            conn.execute(
                text("INSERT INTO clients (id, organization_id, created_by, updated_by, display_name, type, phone,"
                     " email, address, city, ice, notes, consent_text_version)"
                     " SELECT gen_random_uuid(), :b, created_by, created_by, 'Intrus', 'individual', '', '', '', '',"
                     " '', '', '' FROM clients LIMIT 1"),
                {"b": str(org_b.id)},
            )
            raise AssertionError("insertion dans une autre organisation acceptée")
        except Exception as exc:  # noqa: BLE001
            assert "row-level security" in str(exc)
    engine.dispose()


# ---------- pièces (lot 1.3) ----------


def _room_change(rid, pid, base=None, deleted=False, walls=None, openings=None, **extra):
    data = {
        "project_id": str(pid),
        "name": "Salon",
        "height_m": 2.8,
        "walls": walls or [{"length": l, "angle": 90} for l in (5.2, 4.1, 5.2, 4.1)],
        "openings": openings or [{"type": "door", "wall": 0, "width": 0.83, "height": 2.04}],
        **extra,
    }
    return {"entity": "rooms", "id": str(rid), "base_version": base, "deleted": deleted, "data": data}


def test_room_sync_roundtrip(client, db):
    _, _, h = _staff(client, db, Role.collaborator)
    pid, rid = uuid7(), uuid7()
    res = _push(client, h, _project_change(pid), _room_change(rid, pid))
    assert [r["status"] for r in res] == ["applied", "applied"]
    room = res[1]["record"]["data"]
    assert room["height_m"] == 2.8 and isinstance(room["height_m"], float)
    assert room["walls"][0]["length"] == 5.2
    pulled = {r["entity"] for r in _pull(client, h)["records"]}
    assert pulled == {"projects", "rooms"}


def test_room_measures_stored_by_server(client, db):
    org, _, h = _staff(client, db)
    pid, rid = uuid7(), uuid7()
    l_shape = [{"length": l, "angle": a} for l, a in ((6, 90), (2, 90), (2, 270), (2, 90), (4, 90), (4, 90))]
    _push(client, h, _project_change(pid), _room_change(rid, pid, walls=l_shape, openings=[]))
    from app.db import bind_organization

    bind_organization(db, org.id)
    row = db.execute(
        text("SELECT computed_floor_area_m2, computed_perimeter_m, closure_error_m FROM rooms WHERE id = :i"),
        {"i": str(rid)},
    ).one()
    assert float(row[0]) == 20.0 and float(row[1]) == 20.0 and float(row[2]) == 0.0


def test_invalid_rooms_rejected(client, db):
    _, _, h = _staff(client, db)
    pid = uuid7()
    _push(client, h, _project_change(pid))
    bad = [
        _room_change(uuid7(), pid, walls=[{"length": 3, "angle": 90}, {"length": 3, "angle": 90}]),  # 2 murs
        _room_change(uuid7(), pid, openings=[{"type": "door", "wall": 9, "width": 0.8, "height": 2}]),
        _room_change(uuid7(), pid, walls=[{"length": -1, "angle": 90}] * 4),
        _room_change(uuid7(), pid, height_m=0),
        _room_change(uuid7(), pid, height_source="invente"),
        _room_change(uuid7(), uuid7()),  # projet inexistant
    ]
    assert [r["status"] for r in _push(client, h, *bad)] == ["rejected"] * len(bad)


def test_rooms_follow_project_visibility(client, db):
    org, _, h_admin = _staff(client, db)
    _, karim, h_karim = _staff(client, db, Role.collaborator, org=org)
    _, _, h_sara = _staff(client, db, Role.collaborator, org=org)
    cid, pid, rid = uuid7(), uuid7(), uuid7()
    _push(client, h_karim, _client_change(cid), _project_change(pid, cid), _room_change(rid, pid))
    sara_cursor = _pull(client, h_sara)["cursor"]
    assert _push(client, h_sara, _room_change(uuid7(), pid))[0]["status"] == "rejected"
    assert _push(client, h_sara, _room_change(rid, pid, base=1))[0]["status"] == "rejected"

    # L'administrateur confie le projet à Sara : elle reçoit le projet, son client ET ses pièces,
    # même si son curseur est déjà au-delà de leur création.
    sara_id = client.get("/api/v1/auth/me", headers=h_sara).json()["id"]
    _push(client, h_admin, _project_change(pid, cid, base=1, manager_id=sara_id))
    got = {(r["entity"], r["id"]) for r in _pull(client, h_sara, sara_cursor)["records"]}
    assert got == {("clients", str(cid)), ("projects", str(pid)), ("rooms", str(rid))}


def test_project_deletion_cascades_to_rooms_and_restores(client, db):
    _, _, h = _staff(client, db)
    pid, rid = uuid7(), uuid7()
    _push(client, h, _project_change(pid), _room_change(rid, pid))
    cursor = _pull(client, h)["cursor"]
    _push(client, h, _project_change(pid, base=1, deleted=True))
    recs = {r["entity"]: r for r in _pull(client, h, cursor)["records"]}
    assert recs["projects"]["deleted"] and recs["rooms"]["deleted"]
    cursor = _pull(client, h)["cursor"]
    # Restauration du projet (conflit résolu en « garder ma version ») : la pièce revient aussi.
    assert _push(client, h, _project_change(pid, base=2))[0]["status"] == "applied"
    recs = {r["entity"]: r for r in _pull(client, h, cursor)["records"]}
    assert recs["projects"]["deleted"] is False and recs["rooms"]["deleted"] is False
    # Une pièce ne change pas de projet.
    other = uuid7()
    _push(client, h, _project_change(other))
    version = recs["rooms"]["version"]
    assert _push(client, h, _room_change(rid, other, base=version))[0]["status"] == "rejected"


def test_room_concurrent_edit_is_conflict(client, db):
    org, _, h1 = _staff(client, db)
    _, _, h2 = _staff(client, db, org=org)
    pid, rid = uuid7(), uuid7()
    _push(client, h1, _project_change(pid), _room_change(rid, pid))
    assert _push(client, h1, _room_change(rid, pid, base=1, name="Séjour"))[0]["status"] == "applied"
    res = _push(client, h2, _room_change(rid, pid, base=1, name="Salle à manger"))[0]
    assert res["status"] == "conflict" and res["record"]["data"]["name"] == "Séjour"
