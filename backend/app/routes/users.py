"""Gestion des utilisateurs et des invitations (administrateur).

Toutes les requêtes sont filtrées par l'organisation de l'administrateur : une ressource
d'une autre organisation répond 404, comme si elle n'existait pas.
"""

import uuid
from datetime import datetime, timedelta

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request, status
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from ..audit import audit
from ..config import get_settings
from ..db import get_db
from ..deps import Context, require_admin
from ..mailer import send_invitation
from ..models import AuthSession, Invitation, Organization, Role, User, UserRole, UserStatus
from ..security import hash_password, hash_token, new_opaque_token, now, password_problems
from .auth import normalize_email

router = APIRouter(tags=["utilisateurs"])

NOT_FOUND = "Élément introuvable."


# ---------- schémas ----------


class UserOut(BaseModel):
    id: uuid.UUID
    email: str
    full_name: str
    phone: str
    status: UserStatus
    roles: list[Role]
    totp_enabled: bool
    last_login_at: datetime | None


class UserPatch(BaseModel):
    status: UserStatus | None = None
    role: Role | None = None
    full_name: str | None = Field(default=None, min_length=1, max_length=200)
    phone: str | None = Field(default=None, max_length=30)


class InvitationIn(BaseModel):
    email: EmailStr
    full_name: str = Field(min_length=1, max_length=200)
    role: Role


class InvitationOut(BaseModel):
    id: uuid.UUID
    email: str
    full_name: str
    role: Role
    expires_at: datetime
    email_sent: bool | None = None
    # Lien renvoyé une seule fois, à la création, pour transmission manuelle si l'e-mail échoue.
    invitation_url: str | None = None


class AcceptIn(BaseModel):
    token: str = Field(max_length=200)
    password: str = Field(max_length=256)


def _user_out(u: User) -> UserOut:
    return UserOut(
        id=u.id,
        email=u.email,
        full_name=u.full_name,
        phone=u.phone,
        status=u.status,
        roles=sorted(u.role_set, key=lambda r: r.value),
        totp_enabled=u.totp_enabled,
        last_login_at=u.last_login_at,
    )


def _org_user(db: Session, ctx: Context, user_id: uuid.UUID) -> User:
    user = db.scalar(
        select(User).where(
            User.id == user_id,
            User.organization_id == ctx.organization_id,
            User.deleted_at.is_(None),
        )
    )
    if user is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_FOUND)
    return user


def _active_admin_count(db: Session, organization_id: uuid.UUID) -> int:
    return db.scalar(
        select(func.count(func.distinct(User.id)))
        .join(UserRole, UserRole.user_id == User.id)
        .where(
            User.organization_id == organization_id,
            User.status == UserStatus.active,
            User.deleted_at.is_(None),
            UserRole.role == Role.admin,
        )
    ) or 0


def revoke_all_sessions(db: Session, user_id: uuid.UUID, reason: str) -> None:
    db.execute(
        update(AuthSession)
        .where(AuthSession.user_id == user_id, AuthSession.revoked_at.is_(None))
        .values(revoked_at=now(), revoke_reason=reason)
    )


# ---------- utilisateurs ----------


@router.get("/users", response_model=list[UserOut])
def list_users(ctx: Context = Depends(require_admin), db: Session = Depends(get_db)) -> list[UserOut]:
    users = db.scalars(
        select(User)
        .where(User.organization_id == ctx.organization_id, User.deleted_at.is_(None))
        .order_by(User.full_name)
    ).all()
    return [_user_out(u) for u in users]


@router.patch("/users/{user_id}", response_model=UserOut)
def patch_user(
    user_id: uuid.UUID,
    body: UserPatch,
    request: Request,
    ctx: Context = Depends(require_admin),
    db: Session = Depends(get_db),
) -> UserOut:
    user = _org_user(db, ctx, user_id)
    was_admin = Role.admin in user.role_set
    loses_admin = was_admin and (
        (body.role is not None and body.role != Role.admin)
        or body.status == UserStatus.suspended
    )
    if loses_admin and _active_admin_count(db, ctx.organization_id) <= 1:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "Impossible : l'organisation doit garder au moins un administrateur actif.",
        )
    if body.role == Role.client or (Role.client in user.role_set and body.role is not None):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            "Un compte client ne peut pas changer de profil, et inversement.",
        )

    if body.role is not None and user.role_set != {body.role}:
        before = sorted(r.value for r in user.role_set)
        user.roles.clear()
        db.flush()
        user.roles.append(UserRole(organization_id=user.organization_id, role=body.role))
        revoke_all_sessions(db, user.id, "role_change")
        audit(db, "user.role.change", request=request, organization_id=ctx.organization_id,
              actor_id=ctx.user.id, actor_role=ctx.main_role.value, entity_table="users",
              entity_id=user.id, details={"before": before, "after": [body.role.value]})
    if body.status is not None and body.status != user.status:
        user.status = body.status
        if body.status == UserStatus.suspended:
            revoke_all_sessions(db, user.id, "suspended")
        audit(db, "user.status.change", request=request, organization_id=ctx.organization_id,
              actor_id=ctx.user.id, actor_role=ctx.main_role.value, entity_table="users",
              entity_id=user.id, details={"status": body.status.value})
    if body.full_name is not None:
        user.full_name = body.full_name
    if body.phone is not None:
        user.phone = body.phone
    user.version += 1
    db.commit()
    db.refresh(user)
    return _user_out(user)


@router.post("/users/{user_id}/mfa/reset", status_code=status.HTTP_204_NO_CONTENT)
def reset_mfa(
    user_id: uuid.UUID, request: Request, ctx: Context = Depends(require_admin), db: Session = Depends(get_db)
) -> None:
    """Pour un collaborateur qui a perdu son téléphone : il devra reconfigurer la 2FA."""
    user = _org_user(db, ctx, user_id)
    user.totp_enabled = False
    user.totp_secret_enc = None
    user.totp_last_step = None
    revoke_all_sessions(db, user.id, "mfa_reset")
    audit(db, "user.mfa.reset", request=request, organization_id=ctx.organization_id,
          actor_id=ctx.user.id, actor_role=ctx.main_role.value, entity_table="users", entity_id=user.id)
    db.commit()


# ---------- invitations ----------


@router.post("/invitations", response_model=InvitationOut, status_code=status.HTTP_201_CREATED)
def create_invitation(
    body: InvitationIn,
    request: Request,
    background: BackgroundTasks,
    ctx: Context = Depends(require_admin),
    db: Session = Depends(get_db),
) -> InvitationOut:
    if body.role == Role.client:
        # Un compte client doit être rattaché à une fiche client : disponible avec le lot 1.2.
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            "Les comptes clients seront disponibles avec la gestion des clients.",
        )
    email = normalize_email(body.email)
    if db.scalar(select(User.id).where(User.email == email)) is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Un compte existe déjà avec cette adresse.")

    settings = get_settings()
    # Une seule invitation en cours par adresse et par organisation.
    db.execute(
        update(Invitation)
        .where(
            Invitation.organization_id == ctx.organization_id,
            Invitation.email == email,
            Invitation.accepted_at.is_(None),
            Invitation.revoked_at.is_(None),
        )
        .values(revoked_at=now())
    )
    token = new_opaque_token()
    inv = Invitation(
        organization_id=ctx.organization_id,
        email=email,
        full_name=body.full_name.strip(),
        role=body.role,
        token_hash=hash_token(token),
        invited_by=ctx.user.id,
        expires_at=now() + timedelta(hours=settings.invitation_hours),
    )
    db.add(inv)
    db.flush()
    audit(db, "invitation.create", request=request, organization_id=ctx.organization_id,
          actor_id=ctx.user.id, actor_role=ctx.main_role.value, entity_table="invitations",
          entity_id=inv.id, details={"role": body.role.value})
    db.commit()

    url = f"{settings.public_base_url.rstrip('/')}/invitation#{token}"
    org = db.get(Organization, ctx.organization_id)
    org_name = (org.trade_name or org.legal_name) if org else "LAMAALAM"
    if settings.smtp_configured:
        background.add_task(send_invitation, email, inv.full_name, org_name, url, settings.invitation_hours)
    return InvitationOut(
        id=inv.id,
        email=inv.email,
        full_name=inv.full_name,
        role=inv.role,
        expires_at=inv.expires_at,
        email_sent=settings.smtp_configured,
        invitation_url=url,
    )


@router.get("/invitations", response_model=list[InvitationOut])
def list_invitations(ctx: Context = Depends(require_admin), db: Session = Depends(get_db)) -> list[InvitationOut]:
    rows = db.scalars(
        select(Invitation)
        .where(
            Invitation.organization_id == ctx.organization_id,
            Invitation.accepted_at.is_(None),
            Invitation.revoked_at.is_(None),
            Invitation.expires_at > now(),
        )
        .order_by(Invitation.created_at.desc())
    ).all()
    return [
        InvitationOut(id=i.id, email=i.email, full_name=i.full_name, role=i.role, expires_at=i.expires_at)
        for i in rows
    ]


@router.delete("/invitations/{invitation_id}", status_code=status.HTTP_204_NO_CONTENT)
def revoke_invitation(
    invitation_id: uuid.UUID, request: Request, ctx: Context = Depends(require_admin), db: Session = Depends(get_db)
) -> None:
    inv = db.scalar(
        select(Invitation).where(
            Invitation.id == invitation_id, Invitation.organization_id == ctx.organization_id
        )
    )
    if inv is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_FOUND)
    if inv.revoked_at is None and inv.accepted_at is None:
        inv.revoked_at = now()
        audit(db, "invitation.revoke", request=request, organization_id=ctx.organization_id,
              actor_id=ctx.user.id, actor_role=ctx.main_role.value, entity_table="invitations", entity_id=inv.id)
        db.commit()


@router.post("/invitations/accept", status_code=status.HTTP_201_CREATED)
def accept_invitation(body: AcceptIn, request: Request, db: Session = Depends(get_db)) -> dict:
    """Route publique : le jeton d'invitation tient lieu d'autorisation."""
    inv = db.scalar(
        select(Invitation).where(Invitation.token_hash == hash_token(body.token)).with_for_update()
    )
    if inv is None or inv.accepted_at or inv.revoked_at or inv.expires_at <= now():
        raise HTTPException(
            status.HTTP_410_GONE,
            "Ce lien d'invitation n'est plus valable. Demandez une nouvelle invitation.",
        )
    problems = password_problems(body.password, [inv.email, inv.full_name, "lamaalam"])
    if problems:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, problems[0])
    if db.scalar(select(User.id).where(User.email == inv.email)) is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Un compte existe déjà avec cette adresse.")

    user = User(
        organization_id=inv.organization_id,
        email=inv.email,
        full_name=inv.full_name,
        password_hash=hash_password(body.password),
        client_id=inv.client_id,
    )
    user.roles.append(UserRole(organization_id=inv.organization_id, role=inv.role))
    db.add(user)
    inv.accepted_at = now()
    db.flush()
    audit(db, "invitation.accept", request=request, organization_id=inv.organization_id,
          actor_id=user.id, entity_table="users", entity_id=user.id, details={"role": inv.role.value})
    db.commit()
    return {"status": "ok", "message": "Compte créé. Connectez-vous pour configurer la double authentification."}
