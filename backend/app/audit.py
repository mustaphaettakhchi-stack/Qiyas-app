import uuid

from fastapi import Request
from sqlalchemy.orm import Session

from .models import AuditLog


def client_ip(request: Request | None) -> str | None:
    if request is None or request.client is None:
        return None
    # Derrière Caddy, l'adresse réelle est transmise par le proxy (uvicorn --proxy-headers).
    return request.client.host


def audit(
    db: Session,
    action: str,
    *,
    request: Request | None = None,
    organization_id: uuid.UUID | None = None,
    actor_id: uuid.UUID | None = None,
    actor_role: str | None = None,
    entity_table: str | None = None,
    entity_id: uuid.UUID | None = None,
    project_id: uuid.UUID | None = None,
    details: dict | None = None,
) -> None:
    """Ajoute une ligne au journal. Ne jamais y mettre de mot de passe, jeton ou donnée sensible."""
    db.add(
        AuditLog(
            organization_id=organization_id,
            actor_id=actor_id,
            actor_role=actor_role,
            action=action,
            entity_table=entity_table,
            entity_id=entity_id,
            project_id=project_id,
            ip=client_ip(request),
            details=details or {},
        )
    )
