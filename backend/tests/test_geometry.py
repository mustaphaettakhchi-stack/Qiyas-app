"""Cas de métré partagés avec l'application : les deux implémentations doivent concorder."""

import json
from pathlib import Path

import pytest

from app.geometry import outline, room_measures

CASES = json.loads((Path(__file__).resolve().parents[2] / "shared" / "metre_cases.json").read_text())["cases"]


@pytest.mark.parametrize("case", CASES, ids=[c["name"][:40] for c in CASES])
def test_shared_case(case):
    m = room_measures(case["height"], [tuple(w) for w in case["walls"]], [tuple(o) for o in case["openings"]])
    exp = case["expected"]
    for key in ("perimeter", "floor", "walls", "skirting", "volume", "closure"):
        assert getattr(m, key) == pytest.approx(exp[key], abs=1e-6), key
    assert m.closes is exp["closes"]


def test_self_intersection_detected():
    # « Nœud papillon » : contour fermé mais dont deux murs se croisent.
    bow = outline([5, 3, 5, 3], [306.86989764584405, 306.86989764584405, 53.13010235415598, 53.13010235415598])
    assert bow.closes
    assert bow.self_intersecting
    assert not bow.valid
    # Pièce en L : angle rentrant, aucun croisement.
    assert not outline([6, 2, 2, 2, 4, 4], [90, 90, 270, 90, 90, 90]).self_intersecting


def test_angle_sum_error_reported():
    assert outline([4, 3, 4, 3], [90, 90, 90, 95]).angle_sum_error == pytest.approx(5)
