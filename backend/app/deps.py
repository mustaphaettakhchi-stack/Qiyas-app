"""Authentification et autorisation des requêtes.

Toute route de l'API, sauf la courte liste publique de app/main.py, dépend de
get_context. Le test tests/test_routes_security.py le vérifie.
"""

import uuid
from collections.abc import Callable
from dataclasses import dataclass

import jwt
from fastapi import Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from .db import get_db
from .models import AuthSession, Role, User, UserStatus
from .security import ACCESS, decode_jwt, now


@dataclass(frozen=True)
class Context:
    user: User
    session_id: uuid.UUID
    organization_id: uuid.UUID
    roles: frozenset[Role]

    @property
    def main_role(self) -> Role:
        for r in (Role.admin, Role.collaborator, Role.client):
            if r in self.roles:
                return r
        return Role.client


def _unauthorized(message: str = "Session expirée. Reconnectez-vous.") -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=message,
        headers={"WWW-Authenticate": "Bearer"},
    )


def get_context(request: Request, db: Session = Depends(get_db)) -> Context:
    header = request.headers.get("authorization", "")
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise _unauthorized("Connexion requise.")
    try:
        payload = decode_jwt(token, ACCESS)
        user_id = uuid.UUID(payload["sub"])
        session_id = uuid.UUID(payload["sid"])
    except (jwt.InvalidTokenError, KeyError, ValueError):
        raise _unauthorized() from None

    row = db.execute(
        select(User, AuthSession)
        .join(AuthSession, AuthSession.user_id == User.id)
        .where(
            User.id == user_id,
            AuthSession.id == session_id,
            AuthSession.revoked_at.is_(None),
            AuthSession.expires_at > now(),
            User.deleted_at.is_(None),
            User.status == UserStatus.active,
        )
    ).first()
    if row is None:
        raise _unauthorized()
    user = row[0]
    return Context(
        user=user,
        session_id=session_id,
        organization_id=user.organization_id,
        roles=frozenset(user.role_set),
    )


def require_roles(*allowed: Role) -> Callable[[Context], Context]:
    def checker(ctx: Context = Depends(get_context)) -> Context:
        if not ctx.roles.intersection(allowed):
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Action réservée à un autre profil.")
        return ctx

    return checker


require_admin = require_roles(Role.admin)
require_staff = require_roles(Role.admin, Role.collaborator)
