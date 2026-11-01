"""Connexion, double authentification, renouvellement et fin de session."""

import uuid
from datetime import timedelta
from typing import Annotated

import jwt
from fastapi import APIRouter, Body, Depends, HTTPException, Request, status
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from ..audit import audit, client_ip
from ..config import get_settings
from ..db import get_db
from ..deps import Context, get_context
from ..models import ROLES_REQUIRING_MFA, AuthSession, MfaBackupCode, User, UserStatus
from ..security import (
    ACCESS,
    MFA_SETUP,
    MFA_VERIFY,
    create_jwt,
    decode_jwt,
    decrypt_secret,
    encrypt_secret,
    hash_backup_code,
    hash_password,
    hash_token,
    new_backup_codes,
    new_opaque_token,
    new_totp_secret,
    now,
    password_needs_rehash,
    totp_uri,
    verify_password,
    verify_totp,
)

router = APIRouter(prefix="/auth", tags=["authentification"])

BAD_CREDENTIALS = "Adresse e-mail ou mot de passe incorrect."
BAD_CODE = "Code incorrect ou déjà utilisé."
LOCKED = "Trop de tentatives. Réessayez dans quelques minutes."


# ---------- schémas ----------


class LoginIn(BaseModel):
    email: EmailStr
    password: str = Field(max_length=256)
    device_label: str = Field(default="", max_length=100)


class TokensOut(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class LoginOut(BaseModel):
    """Exactement un des trois cas : jetons, vérification 2FA, ou mise en place de la 2FA."""

    tokens: TokensOut | None = None
    mfa_required: bool = False
    mfa_setup_required: bool = False
    mfa_token: str | None = None


class MfaSetupOut(BaseModel):
    secret: str
    otpauth_uri: str


class MfaConfirmIn(BaseModel):
    mfa_token: str
    code: str = Field(max_length=10)
    device_label: str = Field(default="", max_length=100)


class MfaConfirmOut(BaseModel):
    tokens: TokensOut
    backup_codes: list[str]


class MfaVerifyIn(BaseModel):
    mfa_token: str
    code: str | None = Field(default=None, max_length=10)
    backup_code: str | None = Field(default=None, max_length=20)
    device_label: str = Field(default="", max_length=100)


class RefreshIn(BaseModel):
    refresh_token: str = Field(max_length=200)


class MeOut(BaseModel):
    id: uuid.UUID
    organization_id: uuid.UUID
    email: str
    full_name: str
    roles: list[str]
    totp_enabled: bool
    locale: str


# ---------- outils ----------


def normalize_email(email: str) -> str:
    return email.strip().lower()


def _check_lock(user: User) -> None:
    if user.locked_until and user.locked_until > now():
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, LOCKED)


def _register_failure(db: Session, user: User, request: Request, action: str) -> None:
    settings = get_settings()
    user.failed_login_count += 1
    excess = user.failed_login_count - settings.max_failed_logins
    if excess >= 0:
        user.locked_until = now() + timedelta(minutes=min(2**excess, 60))
    audit(
        db,
        action,
        request=request,
        organization_id=user.organization_id,
        actor_id=user.id,
        entity_table="users",
        entity_id=user.id,
        details={"failed_count": user.failed_login_count, "locked": excess >= 0},
    )
    db.commit()


def _issue_tokens(db: Session, user: User, request: Request, device_label: str) -> TokensOut:
    settings = get_settings()
    refresh = new_opaque_token()
    session = AuthSession(
        organization_id=user.organization_id,
        user_id=user.id,
        refresh_token_hash=hash_token(refresh),
        device_label=device_label,
        ip=client_ip(request),
        user_agent=(request.headers.get("user-agent") or "")[:300],
        expires_at=now() + timedelta(days=settings.refresh_token_days),
    )
    db.add(session)
    db.flush()
    user.failed_login_count = 0
    user.locked_until = None
    user.last_login_at = now()
    audit(
        db,
        "auth.login.success",
        request=request,
        organization_id=user.organization_id,
        actor_id=user.id,
        entity_table="auth_sessions",
        entity_id=session.id,
    )
    db.commit()
    return TokensOut(
        access_token=_access_token(user, session.id),
        refresh_token=refresh,
        expires_in=settings.access_token_minutes * 60,
    )


def _access_token(user: User, session_id: uuid.UUID) -> str:
    return create_jwt(
        user.id,
        ACCESS,
        get_settings().access_token_minutes,
        sid=str(session_id),
        org=str(user.organization_id),
        roles=sorted(r.value for r in user.role_set),
    )


def _user_from_mfa_token(db: Session, token: str, typ: str) -> User:
    try:
        payload = decode_jwt(token, typ)
        user_id = uuid.UUID(payload["sub"])
    except (jwt.InvalidTokenError, KeyError, ValueError):
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED, "Étape expirée. Recommencez la connexion."
        ) from None
    user = db.get(User, user_id)
    if user is None or user.status != UserStatus.active or user.deleted_at is not None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Étape expirée. Recommencez la connexion.")
    return user


# ---------- routes publiques ----------


@router.post("/login", response_model=LoginOut)
def login(body: LoginIn, request: Request, db: Session = Depends(get_db)) -> LoginOut:
    email = normalize_email(body.email)
    user = db.scalar(select(User).where(User.email == email, User.deleted_at.is_(None)))
    if user is None:
        verify_password(None, body.password)  # durée constante
        audit(db, "auth.login.failed", request=request, details={"reason": "unknown_account"})
        db.commit()
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, BAD_CREDENTIALS)

    _check_lock(user)
    if not verify_password(user.password_hash, body.password):
        _register_failure(db, user, request, "auth.login.failed")
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, BAD_CREDENTIALS)
    if user.status != UserStatus.active:
        audit(db, "auth.login.refused", request=request, organization_id=user.organization_id,
              actor_id=user.id, details={"reason": "suspended"})
        db.commit()
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, BAD_CREDENTIALS)

    if password_needs_rehash(user.password_hash):
        user.password_hash = hash_password(body.password)

    minutes = get_settings().mfa_token_minutes
    if user.totp_enabled:
        db.commit()
        return LoginOut(mfa_required=True, mfa_token=create_jwt(user.id, MFA_VERIFY, minutes))
    if user.role_set & ROLES_REQUIRING_MFA:
        db.commit()
        return LoginOut(mfa_setup_required=True, mfa_token=create_jwt(user.id, MFA_SETUP, minutes))
    return LoginOut(tokens=_issue_tokens(db, user, request, body.device_label))


@router.post("/mfa/setup", response_model=MfaSetupOut)
def mfa_setup(
    mfa_token: Annotated[str, Body(embed=True)], db: Session = Depends(get_db)
) -> MfaSetupOut:
    user = _user_from_mfa_token(db, mfa_token, MFA_SETUP)
    if user.totp_enabled:
        raise HTTPException(status.HTTP_409_CONFLICT, "La double authentification est déjà active.")
    secret = new_totp_secret()
    user.totp_secret_enc = encrypt_secret(secret)
    db.commit()
    return MfaSetupOut(secret=secret, otpauth_uri=totp_uri(secret, user.email))


@router.post("/mfa/confirm", response_model=MfaConfirmOut)
def mfa_confirm(body: MfaConfirmIn, request: Request, db: Session = Depends(get_db)) -> MfaConfirmOut:
    user = _user_from_mfa_token(db, body.mfa_token, MFA_SETUP)
    _check_lock(user)
    if user.totp_enabled or not user.totp_secret_enc:
        raise HTTPException(status.HTTP_409_CONFLICT, "Recommencez la mise en place de la double authentification.")
    step = verify_totp(decrypt_secret(user.totp_secret_enc), body.code, user.totp_last_step)
    if step is None:
        _register_failure(db, user, request, "auth.mfa.failed")
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, BAD_CODE)
    user.totp_enabled = True
    user.totp_last_step = step
    db.execute(update(MfaBackupCode).where(MfaBackupCode.user_id == user.id).values(used_at=now()))
    codes = new_backup_codes()
    db.add_all(MfaBackupCode(user_id=user.id, code_hash=hash_backup_code(c)) for c in codes)
    audit(db, "auth.mfa.enabled", request=request, organization_id=user.organization_id,
          actor_id=user.id, entity_table="users", entity_id=user.id)
    tokens = _issue_tokens(db, user, request, body.device_label)
    return MfaConfirmOut(tokens=tokens, backup_codes=codes)


@router.post("/mfa/verify", response_model=TokensOut)
def mfa_verify(body: MfaVerifyIn, request: Request, db: Session = Depends(get_db)) -> TokensOut:
    user = _user_from_mfa_token(db, body.mfa_token, MFA_VERIFY)
    _check_lock(user)
    if not user.totp_enabled or not user.totp_secret_enc:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Étape expirée. Recommencez la connexion.")
    if body.code:
        step = verify_totp(decrypt_secret(user.totp_secret_enc), body.code, user.totp_last_step)
        if step is None:
            _register_failure(db, user, request, "auth.mfa.failed")
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, BAD_CODE)
        user.totp_last_step = step
    elif body.backup_code:
        backup = db.scalar(
            select(MfaBackupCode).where(
                MfaBackupCode.user_id == user.id,
                MfaBackupCode.code_hash == hash_backup_code(body.backup_code),
                MfaBackupCode.used_at.is_(None),
            )
        )
        if backup is None:
            _register_failure(db, user, request, "auth.mfa.failed")
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, BAD_CODE)
        backup.used_at = now()
        audit(db, "auth.mfa.backup_code_used", request=request,
              organization_id=user.organization_id, actor_id=user.id)
    else:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Saisissez le code à 6 chiffres.")
    return _issue_tokens(db, user, request, body.device_label)


@router.post("/refresh", response_model=TokensOut)
def refresh(body: RefreshIn, request: Request, db: Session = Depends(get_db)) -> TokensOut:
    token_hash = hash_token(body.refresh_token)
    session = db.scalar(
        select(AuthSession).where(AuthSession.refresh_token_hash == token_hash).with_for_update()
    )
    if session is None:
        reused = db.scalar(select(AuthSession).where(AuthSession.previous_token_hash == token_hash))
        if reused is not None and reused.revoked_at is None:
            # Un jeton déjà remplacé est présenté à nouveau : il a pu être volé.
            reused.revoked_at = now()
            reused.revoke_reason = "refresh_reuse"
            audit(db, "auth.refresh.reuse_detected", request=request,
                  organization_id=reused.organization_id, actor_id=reused.user_id,
                  entity_table="auth_sessions", entity_id=reused.id)
            db.commit()
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Session expirée. Reconnectez-vous.")

    user = db.get(User, session.user_id)
    if (
        session.revoked_at is not None
        or session.expires_at <= now()
        or user is None
        or user.status != UserStatus.active
        or user.deleted_at is not None
    ):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Session expirée. Reconnectez-vous.")

    new_refresh = new_opaque_token()
    session.previous_token_hash = token_hash
    session.refresh_token_hash = hash_token(new_refresh)
    session.last_used_at = now()
    db.commit()
    return TokensOut(
        access_token=_access_token(user, session.id),
        refresh_token=new_refresh,
        expires_in=get_settings().access_token_minutes * 60,
    )


# ---------- routes authentifiées ----------


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(request: Request, ctx: Context = Depends(get_context), db: Session = Depends(get_db)) -> None:
    session = db.get(AuthSession, ctx.session_id)
    if session is not None and session.revoked_at is None:
        session.revoked_at = now()
        session.revoke_reason = "logout"
        audit(db, "auth.logout", request=request, organization_id=ctx.organization_id,
              actor_id=ctx.user.id, entity_table="auth_sessions", entity_id=session.id)
        db.commit()


@router.get("/me", response_model=MeOut)
def me(ctx: Context = Depends(get_context)) -> MeOut:
    u = ctx.user
    return MeOut(
        id=u.id,
        organization_id=u.organization_id,
        email=u.email,
        full_name=u.full_name,
        roles=sorted(r.value for r in ctx.roles),
        totp_enabled=u.totp_enabled,
        locale=u.locale,
    )
