import json
from pathlib import Path

import pytest

from app.quotes import compute, round_half_up

CASES = json.loads((Path(__file__).resolve().parents[2] / "shared" / "quote_cases.json").read_text())["cases"]


@pytest.mark.parametrize("case", CASES, ids=[c["name"][:40] for c in CASES])
def test_shared_quote_case(case):
    t = compute(case["lines"], case["discount_bp"], case["overhead_bp"], case["margin_bp"], case["deposit_bp"])
    e = case["expected"]
    assert t.line_totals == e["line_totals"]
    if "unit_prices" in e:
        assert t.unit_prices == e["unit_prices"]
    assert (t.subtotal, t.discount, t.ht, t.vat_total, t.ttc, t.deposit) == (
        e["subtotal"], e["discount"], e["ht"], e["vat_total"], e["ttc"], e["deposit"])
    assert {str(k): v for k, v in t.vat.items()} == e["vat"]


def test_round_half_up_matches_dart():
    assert [round_half_up(x) for x in (0.5, 1.5, 2.5, 100.49999999999999, 2.4999)] == [1, 2, 3, 100, 2]
