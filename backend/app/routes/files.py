"""Fichiers : photos partagées avec le client et PDF des devis envoyés (lot 1.8).

- Aucun fichier n'est public. Le téléchargement passe par un lien signé (HMAC), lié à
  l'utilisateur et valable au plus 15 minutes (USER_FLOWS A8.3).
- Le type réel est contrôlé (signature binaire), la taille limitée.
- Pour une photo, le client ne reçoit qu'une copie sans aucune métadonnée (EXIF, GPS)
  (USER_FLOWS A8.4) ; l'original reste interne.
"""

import hashlib
import hmac
import io
import os
import time
import uuid
from datetime import UTC, datetime
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, UploadFile, status
from fastapi.responses import FileResponse
from PIL import Image, ImageOps, UnidentifiedImageError
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..audit import audit
from ..config import get_settings
from ..db import bind_organization, get_db
from ..deps import Context, get_context, require_staff
from ..ids import uuid7
from ..models import FileObject, Project, QuoteVersion, Role, User, UserStatus
from .sync import _visible

router = APIRouter(prefix="/files", tags=["fichiers"])

NOT_FOUND = "Élément introuvable."
SIGNATURES = {b"\xff\xd8\xff": "image/jpeg", b"\x89PNG\r\n\x1a\n": "image/png", b"%PDF-": "application/pdf"}


class FileOut(BaseModel):
    id: uuid.UUID
    project_id: uuid.UUID
    quote_version_id: uuid.UUID | None
    kind: str
    mime_type: str
    size_bytes: int
    caption: str
    visible_to_client: bool
    created_at: datetime


class FilePatch(BaseModel):
    visible_to_client: bool | None = None
    caption: str | None = Field(default=None, max_length=300)


class LinkOut(BaseModel):
    url: str
    expires_at: datetime


def _out(f: FileObject) -> FileOut:
    return FileOut(
        id=f.id, project_id=f.project_id, quote_version_id=f.quote_version_id, kind=f.kind, mime_type=f.mime_type,
        size_bytes=f.size_bytes, caption=f.caption, visible_to_client=f.visible_to_client, created_at=f.created_at,
    )


def _root() -> Path:
    root = Path(get_settings().files_dir)
    root.mkdir(parents=True, exist_ok=True)
    return root


def _write(key: str, data: bytes) -> None:
    path = _root() / key
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_bytes(data)
    os.replace(tmp, path)


def _client_copy(data: bytes, mime: str) -> bytes:
    """Copie de la photo sans aucune métadonnée, orientée correctement."""
    with Image.open(io.BytesIO(data)) as img:
        img = ImageOps.exif_transpose(img)
        out = io.BytesIO()
        if mime == "image/png":
            img.save(out, format="PNG")
        else:
            img.convert("RGB").save(out, format="JPEG", quality=90)
        return out.getvalue()


def _staff_project(db: Session, ctx: Context, project_id: uuid.UUID) -> Project:
    project = db.scalar(_visible("projects", ctx).where(Project.id == project_id, Project.deleted_at.is_(None)))
    if project is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_FOUND)
    return project


@router.post("", response_model=FileOut, status_code=status.HTTP_201_CREATED)
async def upload(
    request: Request,
    project_id: uuid.UUID = Form(...),
    kind: str = Form(...),
    quote_version_id: uuid.UUID | None = Form(default=None),
    visible_to_client: bool = Form(default=False),
    caption: str = Form(default="", max_length=300),
    file: UploadFile = File(...),
    ctx: Context = Depends(require_staff),
    db: Session = Depends(get_db),
) -> FileOut:
    settings = get_settings()
    _staff_project(db, ctx, project_id)
    data = await file.read(settings.max_upload_bytes + 1)
    if len(data) > settings.max_upload_bytes:
        raise HTTPException(status.HTTP_413_CONTENT_TOO_LARGE, "Fichier trop volumineux (15 Mo au plus).")
    mime = next((m for sig, m in SIGNATURES.items() if data.startswith(sig)), None)
    expected = {"photo": {"image/jpeg", "image/png"}, "quote_pdf": {"application/pdf"}}.get(kind)
    if expected is None or mime not in expected:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Type de fichier refusé.")
    sha = hashlib.sha256(data).hexdigest()

    if kind == "quote_pdf":
        quote = db.scalar(
            _visible("quotes", ctx).where(QuoteVersion.id == quote_version_id, QuoteVersion.project_id == project_id)
        )
        if quote is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_FOUND)
        if quote.status not in ("sent", "accepted", "refused"):
            # 422 et non 409 : pour l'application, 409 signifie « PDF déjà déposé ».
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Seul le PDF d'un devis envoyé est déposé.")
        existing = db.scalar(select(FileObject).where(FileObject.quote_version_id == quote.id))
        if existing is not None:
            if existing.sha256 == sha:
                return _out(existing)  # nouvel essai après coupure : même fichier
            raise HTTPException(status.HTTP_409_CONFLICT, "Le PDF de ce devis a déjà été déposé.")
        visible_to_client = True
    elif quote_version_id is not None:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Une photo n'est pas rattachée à un devis.")

    file_id = uuid7()
    key = f"{ctx.organization_id}/{file_id}"
    client_key = None
    if kind == "photo":
        try:
            client_data = _client_copy(data, mime)
        except (UnidentifiedImageError, OSError):
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Image illisible.") from None
        client_key = f"{key}-client"
        _write(client_key, client_data)
    _write(key, data)
    row = FileObject(
        id=file_id, organization_id=ctx.organization_id, project_id=project_id, quote_version_id=quote_version_id,
        kind=kind, storage_key=key, client_storage_key=client_key, mime_type=mime, size_bytes=len(data), sha256=sha,
        caption=caption.strip(), visible_to_client=visible_to_client, created_by=ctx.user.id,
    )
    db.add(row)
    db.flush()
    audit(db, "file.upload", request=request, organization_id=ctx.organization_id, actor_id=ctx.user.id,
          actor_role=ctx.main_role.value, entity_table="files", entity_id=row.id, project_id=project_id,
          details={"kind": kind, "visible_to_client": visible_to_client})
    db.commit()
    db.refresh(row)
    return _out(row)


@router.get("/project/{project_id}", response_model=list[FileOut])
def list_project_files(project_id: uuid.UUID, ctx: Context = Depends(require_staff), db: Session = Depends(get_db)) -> list[FileOut]:
    _staff_project(db, ctx, project_id)
    rows = db.scalars(
        select(FileObject).where(FileObject.project_id == project_id, FileObject.deleted_at.is_(None))
        .order_by(FileObject.created_at)
    ).all()
    return [_out(f) for f in rows]


@router.patch("/{file_id}", response_model=FileOut)
def patch_file(
    file_id: uuid.UUID, body: FilePatch, request: Request, ctx: Context = Depends(require_staff), db: Session = Depends(get_db)
) -> FileOut:
    row = db.scalar(select(FileObject).where(FileObject.id == file_id, FileObject.deleted_at.is_(None)))
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_FOUND)
    _staff_project(db, ctx, row.project_id)
    if body.visible_to_client is not None and row.kind == "photo" and body.visible_to_client != row.visible_to_client:
        row.visible_to_client = body.visible_to_client
        audit(db, "file.share" if body.visible_to_client else "file.unshare", request=request,
              organization_id=ctx.organization_id, actor_id=ctx.user.id, actor_role=ctx.main_role.value,
              entity_table="files", entity_id=row.id, project_id=row.project_id)
    if body.caption is not None:
        row.caption = body.caption.strip()
    db.commit()
    return _out(row)


# ---------- liens signés ----------


def _signature(file_id: str, exp: int, uid: str, org: str, variant: str) -> str:
    key = hashlib.sha256(b"lamaalam-file-link:" + get_settings().jwt_secret.encode()).digest()
    return hmac.new(key, f"{file_id}.{exp}.{uid}.{org}.{variant}".encode(), hashlib.sha256).hexdigest()


def client_can_see(db: Session, ctx: Context, row: FileObject) -> bool:
    """Un client ne voit que les fichiers partagés de ses propres projets."""
    if not row.visible_to_client or ctx.user.client_id is None:
        return False
    project = db.get(Project, row.project_id)
    if project is None or project.deleted_at is not None or project.client_id != ctx.user.client_id:
        return False
    if row.kind == "quote_pdf":
        quote = db.get(QuoteVersion, row.quote_version_id)
        return quote is not None and quote.status in ("sent", "accepted", "refused", "superseded")
    return True


@router.get("/{file_id}/link", response_model=LinkOut)
def file_link(file_id: uuid.UUID, request: Request, ctx: Context = Depends(get_context), db: Session = Depends(get_db)) -> LinkOut:
    row = db.scalar(select(FileObject).where(FileObject.id == file_id, FileObject.deleted_at.is_(None)))
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_FOUND)
    if Role.client in ctx.roles and not ctx.roles & {Role.admin, Role.collaborator}:
        if not client_can_see(db, ctx, row):
            raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_FOUND)
        variant = "client" if row.client_storage_key else "original"
        audit(db, "file.download", request=request, organization_id=ctx.organization_id, actor_id=ctx.user.id,
              actor_role="client", entity_table="files", entity_id=row.id, project_id=row.project_id)
        db.commit()
    else:
        _staff_project(db, ctx, row.project_id)
        variant = "original"
    exp = int(time.time()) + get_settings().file_link_minutes * 60
    uid, org = str(ctx.user.id), str(ctx.organization_id)
    sig = _signature(str(row.id), exp, uid, org, variant)
    url = f"/api/v1/files/download/{row.id}?exp={exp}&uid={uid}&org={org}&v={variant}&sig={sig}"
    return LinkOut(url=url, expires_at=datetime.fromtimestamp(exp, UTC))


@router.get("/download/{file_id}")
def download(
    file_id: uuid.UUID,
    exp: int = Query(...),
    uid: uuid.UUID = Query(...),
    org: uuid.UUID = Query(...),
    v: str = Query(..., pattern="^(client|original)$"),
    sig: str = Query(..., max_length=64),
    db: Session = Depends(get_db),
) -> FileResponse:
    """Route publique : la signature tient lieu d'autorisation, pour une durée limitée."""
    expected = _signature(str(file_id), exp, str(uid), str(org), v)
    if not hmac.compare_digest(expected, sig):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Lien invalide.")
    if exp < time.time() or exp > time.time() + get_settings().file_link_minutes * 60 + 5:
        raise HTTPException(status.HTTP_410_GONE, "Lien expiré. Rouvrez le document depuis l'application.")
    user = db.get(User, uid)
    if user is None or user.status != UserStatus.active or user.deleted_at is not None:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Lien invalide.")
    bind_organization(db, org)
    row = db.scalar(select(FileObject).where(FileObject.id == file_id, FileObject.deleted_at.is_(None)))
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_FOUND)
    key = row.client_storage_key if v == "client" and row.client_storage_key else row.storage_key
    if v == "client" and row.kind == "photo" and not row.visible_to_client:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_FOUND)  # partage retiré entre-temps
    mime = "image/jpeg" if v == "client" and row.kind == "photo" and row.mime_type == "image/jpeg" else row.mime_type
    return FileResponse(
        _root() / key,
        media_type=mime,
        filename=f"{row.kind}-{row.id}.{'pdf' if row.kind == 'quote_pdf' else ('png' if mime == 'image/png' else 'jpg')}",
        headers={"Cache-Control": "no-store"},
    )
