"""Espace client en lecture seule (lot 1.8, USER_FLOWS P8) et messagerie projet.

Un compte client ne voit que les projets rattachés à sa fiche client. Toute autre ressource
répond 404, comme si elle n'existait pas (A8.1). Seuls apparaissent : les devis envoyés
(montants, jamais les déboursés ni les marges), les fichiers explicitement partagés (A8.2),
les grandes étapes du projet et le fil de messages.
"""

import uuid
from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, Field
from sqlalchemy import and_, func, or_, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from ..audit import audit
from ..db import get_db
from ..deps import Context, require_client, require_staff
from ..models import AuditLog, Client, FileObject, Message, MessageRead, Project, QuoteVersion, User
from .sync import _visible

router = APIRouter(tags=["espace client"])

NOT_FOUND = "Élément introuvable."
CLIENT_QUOTE_STATUSES = ("sent", "accepted", "refused", "superseded")
TIMELINE_ACTIONS = ("project.create", "metre.validate", "estimate.send", "estimate.accept", "estimate.refuse")


class ClientProjectOut(BaseModel):
    id: uuid.UUID
    reference: str
    name: str
    status: str
    project_type: str
    site_address: str
    site_city: str
    updated_at: datetime
    unread_messages: int = 0


class ClientQuoteOut(BaseModel):
    id: uuid.UUID
    reference: str | None
    version_no: int
    status: str
    issue_date: date
    validity_days: int
    currency: str
    total_ht_cents: int
    total_ttc_cents: int
    pdf_file_id: uuid.UUID | None


class ClientFileOut(BaseModel):
    id: uuid.UUID
    caption: str
    created_at: datetime


class StepOut(BaseModel):
    occurred_at: datetime
    action: str
    reference: str | None


class ClientProjectDetail(ClientProjectOut):
    quotes: list[ClientQuoteOut]
    photos: list[ClientFileOut]
    timeline: list[StepOut]


class MessageIn(BaseModel):
    body: str = Field(min_length=1, max_length=2000)


class MessageOut(BaseModel):
    id: uuid.UUID
    author_name: str
    from_client: bool
    body: str
    created_at: datetime


class UnreadOut(BaseModel):
    project_id: uuid.UUID
    project_reference: str | None
    project_name: str
    client_name: str
    unread: int
    last_at: datetime


def _project_out(p: Project, unread: int = 0) -> ClientProjectOut:
    return ClientProjectOut(
        id=p.id, reference=p.reference, name=p.name, status=p.status, project_type=p.project_type,
        site_address=p.site_address, site_city=p.site_city, updated_at=p.updated_at, unread_messages=unread,
    )


# ---------- messages non lus ----------


def _unread(db: Session, user_id: uuid.UUID, project_ids, from_client: bool) -> dict[uuid.UUID, tuple[int, datetime]]:
    """Messages de l'autre partie postérieurs à la dernière lecture de [user_id], par projet.

    Pour l'équipe : messages des clients ; pour un client : messages de l'équipe.
    """
    rows = db.execute(
        select(Message.project_id, func.count(), func.max(Message.created_at))
        .outerjoin(MessageRead, and_(MessageRead.project_id == Message.project_id, MessageRead.user_id == user_id))
        .where(
            Message.project_id.in_(project_ids),
            Message.from_client.is_(from_client),
            or_(MessageRead.read_at.is_(None), Message.created_at > MessageRead.read_at),
        )
        .group_by(Message.project_id)
    ).all()
    return {pid: (n, last) for pid, n, last in rows}


def _mark_read(db: Session, ctx: Context, project_id: uuid.UUID) -> None:
    now = db.scalar(select(func.now()))
    db.execute(
        insert(MessageRead)
        .values(user_id=ctx.user.id, project_id=project_id, organization_id=ctx.organization_id, read_at=now)
        .on_conflict_do_update(index_elements=["user_id", "project_id"], set_={"read_at": now})
    )


def _client_project(db: Session, ctx: Context, project_id: uuid.UUID) -> Project:
    project = db.scalar(
        select(Project).where(
            Project.id == project_id,
            Project.organization_id == ctx.organization_id,
            Project.client_id == ctx.user.client_id,
            Project.deleted_at.is_(None),
        )
    )
    if project is None or ctx.user.client_id is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_FOUND)
    return project


@router.get("/client/projects", response_model=list[ClientProjectOut])
def client_projects(ctx: Context = Depends(require_client), db: Session = Depends(get_db)) -> list[ClientProjectOut]:
    if ctx.user.client_id is None:
        return []
    rows = db.scalars(
        select(Project).where(
            Project.organization_id == ctx.organization_id,
            Project.client_id == ctx.user.client_id,
            Project.deleted_at.is_(None),
        ).order_by(Project.updated_at.desc())
    ).all()
    unread = _unread(db, ctx.user.id, [p.id for p in rows], from_client=False) if rows else {}
    return [_project_out(p, unread.get(p.id, (0, None))[0]) for p in rows]


@router.get("/client/projects/{project_id}", response_model=ClientProjectDetail)
def client_project(project_id: uuid.UUID, ctx: Context = Depends(require_client), db: Session = Depends(get_db)) -> ClientProjectDetail:
    p = _client_project(db, ctx, project_id)
    pdfs = {
        f.quote_version_id: f.id
        for f in db.scalars(select(FileObject).where(FileObject.project_id == p.id, FileObject.kind == "quote_pdf",
                                                    FileObject.deleted_at.is_(None)))
    }
    quotes = db.scalars(
        select(QuoteVersion).where(QuoteVersion.project_id == p.id, QuoteVersion.status.in_(CLIENT_QUOTE_STATUSES),
                                   QuoteVersion.deleted_at.is_(None))
        .order_by(QuoteVersion.issue_date.desc(), QuoteVersion.version_no.desc())
    ).all()
    photos = db.scalars(
        select(FileObject).where(FileObject.project_id == p.id, FileObject.kind == "photo",
                                 FileObject.visible_to_client.is_(True), FileObject.deleted_at.is_(None))
        .order_by(FileObject.created_at)
    ).all()
    steps = db.scalars(
        select(AuditLog).where(AuditLog.project_id == p.id, AuditLog.action.in_(TIMELINE_ACTIONS))
        .order_by(AuditLog.occurred_at)
    ).all()
    unread = _unread(db, ctx.user.id, [p.id], from_client=False).get(p.id, (0, None))[0]
    return ClientProjectDetail(
        **_project_out(p, unread).model_dump(),
        quotes=[
            ClientQuoteOut(
                id=q.id, reference=q.reference, version_no=q.version_no, status=q.status, issue_date=q.issue_date,
                validity_days=q.validity_days, currency=q.currency, total_ht_cents=int(q.totals.get("ht", 0)),
                total_ttc_cents=int(q.totals.get("ttc", 0)), pdf_file_id=pdfs.get(q.id),
            )
            for q in quotes
        ],
        photos=[ClientFileOut(id=f.id, caption=f.caption, created_at=f.created_at) for f in photos],
        timeline=[StepOut(occurred_at=a.occurred_at, action=a.action, reference=(a.details or {}).get("reference"))
                  for a in steps],
    )


# ---------- messagerie ----------


def _messages(db: Session, project_id: uuid.UUID) -> list[MessageOut]:
    rows = db.execute(
        select(Message, User.full_name).join(User, User.id == Message.author_id)
        .where(Message.project_id == project_id).order_by(Message.created_at)
    ).all()
    return [MessageOut(id=m.id, author_name=name, from_client=m.from_client, body=m.body, created_at=m.created_at)
            for m, name in rows]


def _read_thread(db: Session, ctx: Context, project_id: uuid.UUID) -> list[MessageOut]:
    out = _messages(db, project_id)
    _mark_read(db, ctx, project_id)
    db.commit()
    return out


def _post(db: Session, ctx: Context, request: Request, project: Project, body: str, from_client: bool) -> MessageOut:
    m = Message(organization_id=ctx.organization_id, project_id=project.id, author_id=ctx.user.id,
                from_client=from_client, body=body.strip())
    db.add(m)
    db.flush()
    _mark_read(db, ctx, project.id)  # écrire dans le fil vaut lecture
    audit(db, "message.post", request=request, organization_id=ctx.organization_id, actor_id=ctx.user.id,
          actor_role=ctx.main_role.value, entity_table="messages", entity_id=m.id, project_id=project.id)
    db.commit()
    db.refresh(m)
    return MessageOut(id=m.id, author_name=ctx.user.full_name, from_client=from_client, body=m.body, created_at=m.created_at)


@router.get("/client/projects/{project_id}/messages", response_model=list[MessageOut])
def client_messages(project_id: uuid.UUID, ctx: Context = Depends(require_client), db: Session = Depends(get_db)) -> list[MessageOut]:
    return _read_thread(db, ctx, _client_project(db, ctx, project_id).id)


@router.post("/client/projects/{project_id}/messages", response_model=MessageOut, status_code=status.HTTP_201_CREATED)
def client_post(
    project_id: uuid.UUID, body: MessageIn, request: Request, ctx: Context = Depends(require_client), db: Session = Depends(get_db)
) -> MessageOut:
    return _post(db, ctx, request, _client_project(db, ctx, project_id), body.body, True)


def _staff_project(db: Session, ctx: Context, project_id: uuid.UUID) -> Project:
    project = db.scalar(_visible("projects", ctx).where(Project.id == project_id, Project.deleted_at.is_(None)))
    if project is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_FOUND)
    return project


@router.get("/projects/{project_id}/messages", response_model=list[MessageOut])
def staff_messages(project_id: uuid.UUID, ctx: Context = Depends(require_staff), db: Session = Depends(get_db)) -> list[MessageOut]:
    return _read_thread(db, ctx, _staff_project(db, ctx, project_id).id)


@router.get("/messages/unread", response_model=list[UnreadOut])
def staff_unread(ctx: Context = Depends(require_staff), db: Session = Depends(get_db)) -> list[UnreadOut]:
    """Fils où un client a écrit depuis la dernière lecture, sur les projets visibles par l'utilisateur."""
    projects = {p.id: p for p in db.scalars(_visible("projects", ctx).where(Project.deleted_at.is_(None)))}
    if not projects:
        return []
    unread = _unread(db, ctx.user.id, list(projects), from_client=True)
    names = dict(db.execute(select(Client.id, Client.display_name).where(
        Client.id.in_({p.client_id for pid, p in projects.items() if pid in unread and p.client_id}))).all())
    out = [
        UnreadOut(project_id=pid, project_reference=projects[pid].reference, project_name=projects[pid].name,
                  client_name=names.get(projects[pid].client_id, ""), unread=n, last_at=last)
        for pid, (n, last) in unread.items()
    ]
    return sorted(out, key=lambda u: u.last_at, reverse=True)


@router.post("/projects/{project_id}/messages", response_model=MessageOut, status_code=status.HTTP_201_CREATED)
def staff_post(
    project_id: uuid.UUID, body: MessageIn, request: Request, ctx: Context = Depends(require_staff), db: Session = Depends(get_db)
) -> MessageOut:
    return _post(db, ctx, request, _staff_project(db, ctx, project_id), body.body, False)
