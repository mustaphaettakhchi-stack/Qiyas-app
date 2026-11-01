"""Tableau de bord : indicateurs et dernières opérations (lot 1.7).

Les indicateurs sont calculés sur les données visibles par l'utilisateur, avec les mêmes
définitions que l'application (lib/domain/dashboard.dart), qui les calcule hors connexion.

- Chantiers actifs : projets « accepté » ou « travaux en cours ».
- Prospects : projets « prospect », « visite prévue » ou « chiffrage en cours ».
- Devis : seule la dernière version de chaque devis compte (les versions remplacées sont ignorées).
"""

import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..db import get_db
from ..deps import Context, require_staff
from ..models import AuditLog, Project, QuoteVersion, Role, User
from ..security import now
from .sync import _visible

router = APIRouter(prefix="/dashboard", tags=["tableau de bord"])

ACTIVE = {"won", "in_progress"}
PROSPECT = {"prospect", "visit_planned", "estimating"}

# Opérations montrées dans « Dernières opérations » (les connexions n'y figurent pas).
ACTIVITY_ACTIONS = (
    "project.create", "project.delete", "client.create", "client.delete", "metre.validate",
    "estimate.create", "estimate.validate", "estimate.send", "estimate.accept", "estimate.refuse",
    "invitation.accept", "library.import", "message.post", "file.share", "backup.restore",
)


class DashboardOut(BaseModel):
    active_sites: int
    prospects: int
    quotes_to_validate: int
    quotes_to_send: int
    quotes_waiting: int
    quotes_accepted: int
    accepted_ttc_year: dict[str, int]


class ActivityOut(BaseModel):
    occurred_at: datetime
    action: str
    actor_name: str
    project_id: uuid.UUID | None
    project_reference: str | None
    details: dict


@router.get("", response_model=DashboardOut)
def dashboard(ctx: Context = Depends(require_staff), db: Session = Depends(get_db)) -> DashboardOut:
    projects = db.scalars(_visible("projects", ctx).where(Project.deleted_at.is_(None))).all()
    alive = {p.id for p in projects}
    latest: dict[uuid.UUID, QuoteVersion] = {}
    for q in db.scalars(_visible("quotes", ctx).where(QuoteVersion.deleted_at.is_(None))):
        if q.project_id in alive and (q.estimate_id not in latest or q.version_no > latest[q.estimate_id].version_no):
            latest[q.estimate_id] = q
    by_status: dict[str, int] = {}
    accepted_ttc: dict[str, int] = {}
    year = now().year
    for q in latest.values():
        by_status[q.status] = by_status.get(q.status, 0) + 1
        if q.status == "accepted" and q.decided_at is not None and q.decided_at.year == year:
            accepted_ttc[q.currency] = accepted_ttc.get(q.currency, 0) + int((q.totals or {}).get("ttc", 0))
    return DashboardOut(
        active_sites=sum(1 for p in projects if p.status in ACTIVE),
        prospects=sum(1 for p in projects if p.status in PROSPECT),
        quotes_to_validate=by_status.get("draft", 0),
        quotes_to_send=by_status.get("validated", 0),
        quotes_waiting=by_status.get("sent", 0),
        quotes_accepted=by_status.get("accepted", 0),
        accepted_ttc_year=accepted_ttc,
    )


@router.get("/activity", response_model=list[ActivityOut])
def activity(
    limit: int = Query(default=20, ge=1, le=100),
    ctx: Context = Depends(require_staff),
    db: Session = Depends(get_db),
) -> list[ActivityOut]:
    """Administrateur : opérations de toute l'organisation ; collaborateur : les siennes."""
    q = (
        select(AuditLog, User.full_name, Project.reference)
        .outerjoin(User, User.id == AuditLog.actor_id)
        .outerjoin(Project, Project.id == AuditLog.project_id)
        .where(AuditLog.organization_id == ctx.organization_id, AuditLog.action.in_(ACTIVITY_ACTIONS))
        .order_by(AuditLog.occurred_at.desc())
        .limit(limit)
    )
    if Role.admin not in ctx.roles:
        q = q.where(AuditLog.actor_id == ctx.user.id)
    return [
        ActivityOut(
            occurred_at=log.occurred_at,
            action=log.action,
            actor_name=name or "",
            project_id=log.project_id,
            project_reference=ref,
            details={k: v for k, v in (log.details or {}).items() if k in ("reference", "ttc", "currency", "kind", "created")},
        )
        for log, name, ref in db.execute(q)
    ]
