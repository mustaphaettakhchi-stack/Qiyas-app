"""Recompose la ligne de texte du logo (correction d'orthographe demandée par Group LAMAALAM, 01/11/2026).

Seule la ligne « group lamaalm » est effacée (remplie avec le fond d'origine #EFEFEF) puis
réécrite ; la maison, le monogramme « GL » et les couleurs ne sont pas modifiés.

Police : Arimo (SIL Open Font License 1.1), graisse 560, interlettrage -0,035 em, couleur
#3C2E2A relevée sur le logo d'origine. La police n'est pas embarquée dans l'application.

Usage :
    curl -sSLo Arimo.ttf "https://raw.githubusercontent.com/google/fonts/main/ofl/arimo/Arimo%5Bwght%5D.ttf"
    python3 tool/branding/corriger_texte_logo.py Arimo.ttf
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2] / "assets" / "branding"
SRC = ROOT / "logo_lamaalam_sans_telephone.png"
BG = (239, 239, 239)
INK = (60, 46, 42)
ERASE = (428, 520)  # lignes de l'ancien texte ; le « L » orange s'arrête à la ligne 422
BAND = (437, 515)  # zone verticale d'origine du texte, jambages compris
LEFT, RIGHT = 11, 521  # marges horizontales d'origine
S = 4  # suréchantillonnage


def build(font_path: str, text: str, out: Path, wght: int = 560, track_em: float = -0.035) -> None:
    base = Image.open(SRC).convert("RGB")
    w = base.width

    def layout(size: int):
        f = ImageFont.truetype(font_path, size)
        f.set_variation_by_axes([wght])
        xs = [f.getlength(text[:i]) + i * track_em * size for i in range(len(text))]
        return f, xs, xs[-1] + f.getlength(text[-1])

    size = 83 * S  # hauteur d'x de l'original, réduite si le texte est trop large
    while True:
        f, xs, width = layout(size)
        if width <= (RIGHT - LEFT) * S:
            break
        size -= 1
    img = base.copy()
    ImageDraw.Draw(img).rectangle([0, ERASE[0], w, ERASE[1]], fill=BG)
    h = BAND[1] - BAND[0]
    layer = Image.new("L", (w * S, h * S), 0)
    draw = ImageDraw.Draw(layer)
    bb = f.getbbox(text)
    y0 = (h * S - (bb[3] - bb[1])) // 2 - bb[1]
    x0 = (w * S - width) / 2
    for ch, x in zip(text, xs):
        draw.text((x0 + x, y0), ch, font=f, fill=255)
    layer = layer.resize((w, h), Image.LANCZOS)
    img.paste(Image.new("RGB", layer.size, INK), (0, BAND[0]), layer)
    img.save(out, optimize=True)
    img.resize((512, 512), Image.LANCZOS).save(out.with_name(out.stem + "_512.png"), optimize=True)


if __name__ == "__main__":
    font = sys.argv[1]
    build(font, "Group LAMAALAM", ROOT / "logo_lamaalam_corrige.png")
    build(font, "group lamaalam", ROOT / "logo_lamaalam_corrige_minuscules.png")
