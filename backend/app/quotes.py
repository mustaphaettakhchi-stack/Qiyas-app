"""Calcul des montants d'un devis, en centimes entiers.

Mêmes règles que lib/domain/calculations.dart côté application ; les deux implémentations
sont vérifiées sur shared/quote_cases.json.

- Quantité arrondie au centième ; total de ligne = quantité × prix unitaire, au centime.
- Prix calculé (« cost_plus ») = (fournitures + main-d'œuvre) × (1 + frais) × (1 + marge).
- Remise répartie par taux de TVA, TVA calculée par taux, acompte sur le TTC.
- Tous les arrondis : au plus proche, la moitié vers le haut (comme double.round() en Dart).
"""

import math
from dataclasses import dataclass


def round_half_up(x: float) -> int:
    """Équivalent exact de double.round() en Dart pour une valeur positive."""
    f = math.floor(x)
    return int(f + (1 if x - f >= 0.5 else 0))


def div_half_up(a: int, b: int) -> int:
    return (a + b // 2) // b


def cost_plus_price(material_cents: int, labour_cents: int, overhead_bp: int, margin_bp: int) -> int:
    base = material_cents + labour_cents
    return div_half_up(base * (10000 + overhead_bp) * (10000 + margin_bp), 100_000_000)


def unit_price(line: dict, overhead_bp: int, margin_bp: int) -> int | None:
    if line.get("pricing") == "cost_plus":
        m, lab = line.get("material_cost_cents"), line.get("labour_cost_cents")
        if m is None and lab is None:
            return None
        return cost_plus_price(m or 0, lab or 0, overhead_bp, margin_bp)
    return line.get("unit_price_cents")


def line_total(quantity: float, price_cents: int) -> int:
    return div_half_up(round_half_up(quantity * 100) * price_cents, 100)


@dataclass(frozen=True)
class Totals:
    unit_prices: list[int | None]
    line_totals: list[int]
    subtotal: int
    discount: int
    ht: int
    vat: dict[int, int]
    vat_total: int
    ttc: int
    deposit: int

    def as_dict(self) -> dict:
        return {
            "subtotal": self.subtotal,
            "discount": self.discount,
            "ht": self.ht,
            "vat": {str(k): v for k, v in sorted(self.vat.items())},
            "ttc": self.ttc,
            "deposit": self.deposit,
        }


def compute(lines: list[dict], discount_bp: int, overhead_bp: int, margin_bp: int, deposit_bp: int) -> Totals:
    prices = [unit_price(line, overhead_bp, margin_bp) for line in lines]
    totals = [line_total(line["quantity"], p) if p is not None else 0 for line, p in zip(lines, prices)]
    by_rate: dict[int, int] = {}
    for line, t in zip(lines, totals):
        by_rate[line["vat_rate_bp"]] = by_rate.get(line["vat_rate_bp"], 0) + t
    discount = vat_total = 0
    vat: dict[int, int] = {}
    for rate, sub in by_rate.items():
        d = div_half_up(sub * discount_bp, 10000)
        discount += d
        vat[rate] = div_half_up((sub - d) * rate, 10000)
        vat_total += vat[rate]
    subtotal = sum(totals)
    ht = subtotal - discount
    ttc = ht + vat_total
    return Totals(prices, totals, subtotal, discount, ht, vat, vat_total, ttc, div_half_up(ttc * deposit_bp, 10000))
