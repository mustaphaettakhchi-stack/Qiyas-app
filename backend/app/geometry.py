"""Géométrie et métré d'une pièce décrite mur par mur.

Même convention et mêmes formules que lib/domain/geometry.dart et calculations.dart côté
application ; les deux implémentations sont vérifiées sur shared/metre_cases.json.
"""

import math
from dataclasses import dataclass

CLOSURE_TOLERANCE = 0.02  # m


@dataclass(frozen=True)
class Outline:
    vertices: list[tuple[float, float]]
    closure_error: float
    area: float
    angle_sum_error: float
    self_intersecting: bool

    @property
    def closes(self) -> bool:
        return self.closure_error <= CLOSURE_TOLERANCE

    @property
    def valid(self) -> bool:
        return self.closes and not self.self_intersecting and len(self.vertices) >= 3


def outline(lengths: list[float], angles: list[float]) -> Outline:
    n = len(lengths)
    if n < 3:
        return Outline([], math.inf, 0.0, 0.0, False)
    pts = [(0.0, 0.0)]
    x = y = heading = 0.0
    for length, angle in zip(lengths, angles):
        x += length * math.cos(heading)
        y += length * math.sin(heading)
        pts.append((x, y))
        heading += math.pi - math.radians(angle)
    end = pts.pop()
    twice = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))
    return Outline(
        vertices=pts,
        closure_error=math.hypot(*end),
        area=abs(twice) / 2,
        angle_sum_error=sum(angles) - (n - 2) * 180,
        self_intersecting=_self_intersects(pts),
    )


def _self_intersects(pts: list[tuple[float, float]]) -> bool:
    n = len(pts)

    def cross(o, a, b):  # type: ignore[no-untyped-def]
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    def segs(a, b, c, d) -> bool:  # type: ignore[no-untyped-def]
        d1, d2, d3, d4 = cross(c, d, a), cross(c, d, b), cross(a, b, c), cross(a, b, d)
        return ((d1 > 1e-9 and d2 < -1e-9) or (d1 < -1e-9 and d2 > 1e-9)) and (
            (d3 > 1e-9 and d4 < -1e-9) or (d3 < -1e-9 and d4 > 1e-9)
        )

    for i in range(n):
        for j in range(i + 1, n):
            if j == i + 1 or (i == 0 and j == n - 1):
                continue
            if segs(pts[i], pts[(i + 1) % n], pts[j], pts[(j + 1) % n]):
                return True
    return False


@dataclass(frozen=True)
class RoomMeasures:
    perimeter: float
    floor: float
    walls: float
    skirting: float
    volume: float
    closure: float
    closes: bool


def room_measures(height: float, walls: list[tuple[float, float]], openings: list[tuple[str, int, float, float]]) -> RoomMeasures:
    """walls : (longueur, angle intérieur) ; openings : (type, indice du mur, largeur, hauteur)."""
    shape = outline([w[0] for w in walls], [w[1] for w in walls])
    perimeter = sum(w[0] for w in walls)
    net = 0.0
    for i, (length, _) in enumerate(walls):
        openings_area = sum(o[2] * o[3] for o in openings if o[1] == i)
        net += max(0.0, length * height - openings_area)
    doors = sum(o[2] for o in openings if o[0] == "door")
    return RoomMeasures(
        perimeter=perimeter,
        floor=shape.area,
        walls=net,
        skirting=max(0.0, perimeter - doors),
        volume=shape.area * height,
        closure=shape.closure_error,
        closes=shape.closes,
    )
