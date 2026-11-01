"""Bibliothèque : historique des prix et import CSV (administrateur).

L'import est « tout ou rien » : si une seule ligne est invalide, rien n'est importé et
chaque erreur est signalée avec son numéro de ligne (USER_FLOWS A5.3).
"""

import csv
import io
import unicodedata
import uuid
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, Field, ValidationError
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..audit import audit
from ..db import get_db
from ..deps import Context, require_admin
from ..ids import uuid7
from ..models import Material, PriceHistory, Supplier, WorkItem
from .sync import Change, _apply, _Rejected, _validation_message

router = APIRouter(prefix="/library", tags=["bibliothèque"])

MAX_LINES = 2000


def _norm(text: str) -> str:
    text = unicodedata.normalize("NFKD", text.strip().lower())
    return "".join(c for c in text if not unicodedata.combining(c)).replace(" ", "_").replace("'", "")


CATEGORIES = {
    "sol": "floor", "sols": "floor", "floor": "floor",
    "mur": "wall", "murs": "wall", "wall": "wall",
    "plafond": "ceiling", "plafonds": "ceiling", "ceiling": "ceiling",
    "menuiserie": "joinery", "menuiseries": "joinery", "joinery": "joinery",
    "electricite": "electricity", "electricity": "electricity",
    "plomberie": "plumbing", "plumbing": "plumbing",
    "maconnerie": "masonry", "masonry": "masonry",
    "autre": "other", "other": "other", "": "other",
}
UNITS = {
    "m": "m", "ml": "m", "m2": "m2", "m²": "m2", "m3": "m3", "m³": "m3", "kg": "kg",
    "l": "l", "litre": "l", "litres": "l", "u": "u", "unite": "u", "unites": "u", "forfait": "forfait", "ff": "forfait",
}
BASES = {
    "sol": "floor", "plafond": "ceiling", "murs_nets": "walls_net", "murs_net": "walls_net", "murs_bruts": "walls_gross",
    "plinthes": "skirting", "perimetre": "perimeter", "volume": "volume", "portes": "doors", "fenetres": "windows",
    "comptage": "count", "saisie": "manual", "libre": "manual", "": "manual",
}
COLUMNS = {
    "work_items": ["code", "categorie", "designation", "description", "unite", "base", "element_compte",
                   "perte_pct", "prix_vente", "main_oeuvre"],
    "materials": ["designation", "categorie", "marque", "reference", "unite", "conditionnement", "perte_pct",
                  "prix_achat", "prix_vente", "fournisseur", "ville"],
}


class ImportIn(BaseModel):
    kind: Literal["work_items", "materials"]
    csv: str = Field(max_length=1_000_000)
    price_note: str = Field(default="Import CSV", max_length=300)


class ImportError_(BaseModel):
    line: int
    message: str


class ImportOut(BaseModel):
    created: int
    errors: list[ImportError_]


class PriceOut(BaseModel):
    recorded_at: datetime
    purchase_price_cents: int | None
    sale_price_cents: int | None
    labour_cost_cents: int | None
    currency: str
    source_note: str


def _cents(text: str, label: str) -> int | None:
    t = text.strip().replace(" ", "").replace(" ", "").replace("MAD", "").replace("DH", "").replace(",", ".")
    if not t:
        return None
    try:
        value = round(float(t) * 100)
    except ValueError:
        raise ValueError(f"{label} illisible : « {text.strip()} »") from None
    if value < 0:
        raise ValueError(f"{label} négatif")
    return value


def _number(text: str, label: str) -> float | None:
    t = text.strip().replace(",", ".")
    if not t:
        return None
    try:
        return float(t)
    except ValueError:
        raise ValueError(f"{label} illisible : « {text.strip()} »") from None


def _map(table: dict[str, str], text: str, label: str) -> str:
    key = _norm(text)
    if key not in table:
        raise ValueError(f"{label} inconnu(e) : « {text.strip()} »")
    return table[key]


def _row_data(kind: str, row: dict[str, str], suppliers: dict[str, uuid.UUID], note: str) -> dict:
    waste = _number(row.get("perte_pct", ""), "taux de perte")
    waste_bp = 0 if waste is None else round(waste * 100)
    if kind == "work_items":
        basis = _map(BASES, row.get("base", ""), "base de quantité")
        return {
            "code": row.get("code", "").strip(),
            "category": _map(CATEGORIES, row.get("categorie", ""), "catégorie"),
            "name": row.get("designation", "").strip(),
            "description": row.get("description", "").strip(),
            "unit": _map(UNITS, row.get("unite", ""), "unité"),
            "quantity_basis": basis,
            "count_key": _norm(row.get("element_compte", "")) or None if basis == "count" else None,
            "waste_rate_bp": waste_bp,
            "sale_price_cents": _cents(row.get("prix_vente", ""), "prix de vente"),
            "labour_cost_cents": _cents(row.get("main_oeuvre", ""), "coût de main-d'œuvre"),
            "price_note": note,
        }
    supplier_name = row.get("fournisseur", "").strip()
    supplier_id = None
    if supplier_name:
        supplier_id = suppliers.get(supplier_name.lower())
        if supplier_id is None:
            raise ValueError(f"fournisseur inconnu : « {supplier_name} » (créez-le d'abord)")
    return {
        "name": row.get("designation", "").strip(),
        "category": _map(CATEGORIES, row.get("categorie", ""), "catégorie"),
        "brand": row.get("marque", "").strip(),
        "reference": row.get("reference", "").strip(),
        "unit": _map(UNITS, row.get("unite", ""), "unité"),
        "pack_size": _number(row.get("conditionnement", ""), "conditionnement"),
        "waste_rate_bp": waste_bp,
        "purchase_price_cents": _cents(row.get("prix_achat", ""), "prix d'achat"),
        "sale_price_cents": _cents(row.get("prix_vente", ""), "prix de vente"),
        "supplier_id": str(supplier_id) if supplier_id else None,
        "city": row.get("ville", "").strip(),
        "price_note": note,
    }


@router.post("/import", response_model=ImportOut)
def import_csv(body: ImportIn, request: Request, ctx: Context = Depends(require_admin), db: Session = Depends(get_db)) -> ImportOut:
    text = body.csv.lstrip("﻿").strip()
    if not text:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Le fichier est vide.")
    header_line = text.splitlines()[0]
    delimiter = "\t" if "\t" in header_line else (";" if ";" in header_line else ",")
    reader = csv.DictReader(io.StringIO(text), delimiter=delimiter)
    reader.fieldnames = [_norm(h) for h in (reader.fieldnames or [])]
    missing = [c for c in COLUMNS[body.kind] if c not in reader.fieldnames]
    if missing:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            f"Colonnes manquantes : {', '.join(missing)}. Colonnes attendues : {';'.join(COLUMNS[body.kind])}.",
        )
    suppliers = {
        name.lower(): sid
        for sid, name in db.execute(
            select(Supplier.id, Supplier.name).where(Supplier.organization_id == ctx.organization_id, Supplier.deleted_at.is_(None))
        )
    }
    errors: list[ImportError_] = []
    created = 0
    savepoint = db.begin_nested()
    for index, row in enumerate(reader, start=2):
        if index - 1 > MAX_LINES:
            errors.append(ImportError_(line=index, message=f"Plus de {MAX_LINES} lignes : découpez le fichier."))
            break
        if not any((v or "").strip() for v in row.values()):
            continue
        try:
            data = _row_data(body.kind, {k: (v or "") for k, v in row.items() if k}, suppliers, body.price_note)
            result = _apply(db, ctx, Change(entity=body.kind, id=uuid7(), data=data), request)
            if result.status != "applied":
                raise _Rejected(result.message or "refusée")
            created += 1
        except ValueError as exc:  # inclut ValidationError
            message = _validation_message(exc) if isinstance(exc, ValidationError) else str(exc)
            errors.append(ImportError_(line=index, message=message))
        except _Rejected as exc:
            errors.append(ImportError_(line=index, message=str(exc)))
    if errors:
        savepoint.rollback()
        return ImportOut(created=0, errors=errors)
    savepoint.commit()
    audit(db, "library.import", request=request, organization_id=ctx.organization_id, actor_id=ctx.user.id,
          actor_role=ctx.main_role.value, details={"kind": body.kind, "created": created})
    db.commit()
    return ImportOut(created=created, errors=[])


@router.get("/price-history/{kind}/{item_id}", response_model=list[PriceOut])
def price_history(
    kind: Literal["materials", "work_items"], item_id: uuid.UUID,
    ctx: Context = Depends(require_admin), db: Session = Depends(get_db),
) -> list[PriceOut]:
    model = Material if kind == "materials" else WorkItem
    exists = db.scalar(select(func.count()).select_from(model).where(model.id == item_id, model.organization_id == ctx.organization_id))
    if not exists:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Élément introuvable.")
    column = PriceHistory.material_id if kind == "materials" else PriceHistory.work_item_id
    rows = db.scalars(select(PriceHistory).where(column == item_id).order_by(PriceHistory.recorded_at.desc())).all()
    return [
        PriceOut(recorded_at=r.recorded_at, purchase_price_cents=r.purchase_price_cents, sale_price_cents=r.sale_price_cents,
                 labour_cost_cents=r.labour_cost_cents, currency=r.currency, source_note=r.source_note)
        for r in rows
    ]
