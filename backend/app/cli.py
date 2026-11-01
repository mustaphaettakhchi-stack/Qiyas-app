"""Commandes d'administration du serveur.

Création du premier administrateur (aucun compte n'existe par défaut) :

    python -m app.cli create-admin --organization "Groupe LAMAALAM" \
        --email adresse@exemple.ma --name "Prénom Nom"

Le mot de passe est demandé de façon masquée. La double authentification sera
configurée à la première connexion depuis l'application.

Trace d'une restauration de sauvegarde (appelée par deploy/restore.sh) :

    python -m app.cli record-restore --archive lamaalam-20261101-0300.tar.age --backup-date 2026-11-01T03:00:00Z
"""

import argparse
import getpass
import sys
from datetime import UTC, datetime

from sqlalchemy import select, text

from .audit import audit
from .db import bind_organization, get_db
from .ids import uuid7
from .models import OrgCounter, Organization, Role, User, UserRole
from .security import hash_password, password_problems


def create_admin(organization: str, email: str, name: str, password: str) -> str:
    email = email.strip().lower()
    db = next(get_db())
    try:
        if db.scalar(select(User.id).where(User.email == email)) is not None:
            raise SystemExit("Un compte existe déjà avec cette adresse.")
        org = db.scalar(select(Organization).where(Organization.legal_name == organization))
        if org is None:
            org = Organization(legal_name=organization, trade_name=organization)
            db.add(org)
            db.flush()
        user = User(organization_id=org.id, email=email, full_name=name, password_hash=hash_password(password))
        user.roles.append(UserRole(organization_id=org.id, role=Role.admin))
        db.add(user)
        db.commit()
        return str(user.id)
    finally:
        db.close()


# Marge de numéros réservés à la restauration : les références attribuées entre la sauvegarde
# et l'incident ne sont connues que des téléphones et des clients ; elles ne doivent jamais être
# réattribuées à une autre fiche. Un trou de numérotation, journalisé, vaut mieux qu'un doublon.
COUNTER_RESERVE = 100
SEQUENCE_JUMP = 1_000_000_000


def record_restore(archive: str, backup_date: str) -> int:
    """Remet le serveur restauré en état de servir les téléphones, puis journalise (SECURITY.md §9).

    1. Séquence de synchronisation avancée d'un milliard : les téléphones, dont le curseur peut
       dépasser la valeur sauvegardée, recevront bien les prochaines modifications.
    2. Compteurs de références (projets, devis) avancés de COUNTER_RESERVE pour l'année en cours.
    3. Nouvelle « époque » par organisation : chaque téléphone détecte la restauration et
       suspend sa synchronisation tant qu'un utilisateur n'a pas pris connaissance de la situation.
    À lancer avec le rôle propriétaire de la base (deploy/restore.sh le fait).
    """
    db = next(get_db())
    try:
        db.execute(text("SELECT setval('sync_seq', (SELECT last_value FROM sync_seq) + :jump)"), {"jump": SEQUENCE_JUMP})
        year = datetime.now(UTC).year
        orgs = db.scalars(select(Organization)).all()
        for org in orgs:
            bind_organization(db, org.id)
            reserved = {}
            for name in ("project", "estimate"):
                counter = db.get(OrgCounter, (org.id, name, year), with_for_update=True)
                if counter is None:
                    counter = OrgCounter(organization_id=org.id, name=name, year=year, value=0)
                    db.add(counter)
                start = counter.value + 1
                counter.value += COUNTER_RESERVE
                reserved[name] = f"{start}-{counter.value}"
            org.sync_epoch = uuid7()
            audit(db, "backup.restore", organization_id=org.id,
                  details={"archive": archive[:200], "backup_date": backup_date[:40], "year": year,
                           "reserved": reserved, "epoch": str(org.sync_epoch)})
        db.commit()
        return len(orgs)
    finally:
        db.close()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m app.cli")
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("create-admin", help="créer un administrateur")
    p.add_argument("--organization", required=True)
    p.add_argument("--email", required=True)
    p.add_argument("--name", required=True)
    p.add_argument(
        "--password-stdin",
        action="store_true",
        help="lire le mot de passe sur l'entrée standard (scripts) au lieu de le demander",
    )
    r = sub.add_parser("record-restore", help="journaliser une restauration de sauvegarde")
    r.add_argument("--archive", required=True)
    r.add_argument("--backup-date", required=True)
    args = parser.parse_args(argv)

    if args.command == "record-restore":
        n = record_restore(args.archive, args.backup_date)
        print(f"Restauration journalisée pour {n} organisation(s).")
        return 0

    if args.command == "create-admin":
        if args.password_stdin:
            password = sys.stdin.readline().rstrip("\n")
        else:
            password = getpass.getpass("Mot de passe : ")
            if password != getpass.getpass("Confirmez le mot de passe : "):
                print("Les deux saisies sont différentes.", file=sys.stderr)
                return 1
        problems = password_problems(password, [args.email, args.name, args.organization])
        if problems:
            print(problems[0], file=sys.stderr)
            return 1
        user_id = create_admin(args.organization, args.email, args.name, password)
        print(f"Administrateur créé ({user_id}). Configurez la double authentification à la première connexion.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
