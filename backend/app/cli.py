"""Commandes d'administration du serveur.

Création du premier administrateur (aucun compte n'existe par défaut) :

    python -m app.cli create-admin --organization "Groupe LAMAALAM" \
        --email adresse@exemple.ma --name "Prénom Nom"

Le mot de passe est demandé de façon masquée. La double authentification sera
configurée à la première connexion depuis l'application.
"""

import argparse
import getpass
import sys

from sqlalchemy import select

from .db import get_db
from .models import Organization, Role, User, UserRole
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
    args = parser.parse_args(argv)

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
