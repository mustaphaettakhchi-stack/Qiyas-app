from sqlalchemy import text

from app import cli
from app.ids import uuid7

from .test_estimates import _project_with_metre
from .test_sync import _project_change, _pull, _push, _staff


def test_restore_is_recorded_for_every_organization(client, db, capsys):
    _, _, h1 = _staff(client, db)
    _, _, h2 = _staff(client, db)
    assert cli.main(["record-restore", "--archive", "lamaalam-20261101-030000.tar.age",
                     "--backup-date", "2026-11-01T03:00:00Z"]) == 0
    assert "Restauration journalisée" in capsys.readouterr().out
    for h in (h1, h2):
        activity = client.get("/api/v1/dashboard/activity", headers=h).json()
        restore = [a for a in activity if a["action"] == "backup.restore"]
        assert restore, activity


def test_restore_moves_sequence_counters_and_epoch(client, db):
    _, admin, h = _staff(client, db)
    pid = _project_with_metre(client, h, admin)
    before = _pull(client, h)
    assert before["epoch"] is None
    ref_before = next(r["reference"] for r in before["records"] if r["id"] == str(pid))
    seq_before = db.execute(text("SELECT last_value FROM sync_seq")).scalar()

    cli.record_restore("archive.tar.age", "2026-11-01T03:00:00Z")

    after = _pull(client, h, before["cursor"])
    assert after["epoch"] is not None
    assert client.get("/api/v1/sync/epoch", headers=h).json() == {"epoch": after["epoch"]}
    # Les prochaines modifications passent bien au-delà de tout curseur de téléphone.
    assert db.execute(text("SELECT last_value FROM sync_seq")).scalar() >= seq_before + cli.SEQUENCE_JUMP
    # Les 100 références suivantes sont réservées : jamais de doublon avec un numéro déjà donné.
    new = uuid7()
    rec = _push(client, h, _project_change(new))[0]["record"]
    assert int(rec["reference"].rsplit("-", 1)[1]) >= int(ref_before.rsplit("-", 1)[1]) + cli.COUNTER_RESERVE
