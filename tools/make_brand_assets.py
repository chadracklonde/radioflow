#!/usr/bin/env python3
"""Génère les ressources de marque de Radio Flow à partir du logo d'origine.

    python3 tools/make_brand_assets.py

Entrée  : docs/branding/radio-flow-logo.jpg (emblème + mot-symbole sur fond sombre dégradé)
Sorties : radio_flow/assets/branding/
  logo_emblem.png            emblème détouré (transparent), utilisé dans l'application
  app_icon.png               icône carrée pleine page (iOS, Android ancien)
  app_icon_foreground.png    avant-plan transparent de l'icône adaptative Android
  app_icon_background.png    arrière-plan de l'icône adaptative Android
  app_icon_rounded.png       icône à coins arrondis (Windows)
  app_icon_macos.png         icône au gabarit macOS (coins arrondis + marges)
Nécessite Pillow et NumPy.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs/branding/radio-flow-logo.jpg"
OUT = ROOT / "radio_flow/assets/branding"
OUT.mkdir(parents=True, exist_ok=True)

# Zone de l'emblème dans l'image d'origine (mesurée : le mot-symbole commence plus bas).
EMBLEM_BOX = (500, 370, 1550, 1420)  # x0, y0, x1, y1


def corner_colors(img: np.ndarray, block: int = 24):
    h, w, _ = img.shape
    take = lambda ys, xs: img[ys, xs].reshape(-1, 3).mean(axis=0)
    return (
        take(slice(0, block), slice(0, block)),            # haut-gauche
        take(slice(0, block), slice(w - block, w)),        # haut-droite
        take(slice(h - block, h), slice(0, block)),        # bas-gauche
        take(slice(h - block, h), slice(w - block, w)),    # bas-droite
    )


def gradient(size_w: int, size_h: int, corners) -> np.ndarray:
    """Fond dégradé : interpolation bilinéaire des quatre coins (comme l'image d'origine)."""
    tl, tr, bl, br = corners
    u = np.linspace(0, 1, size_w)[None, :, None]
    v = np.linspace(0, 1, size_h)[:, None, None]
    return (tl * (1 - u) * (1 - v)) + (tr * u * (1 - v)) + (bl * (1 - u) * v) + (br * u * v)


def key_emblem(src: np.ndarray, corners) -> Image.Image:
    """Détoure l'emblème : alpha d'après la luminosité maximale, puis couleur « dé-prémultipliée »
    (sans halo sombre sur les bords)."""
    x0, y0, x1, y1 = EMBLEM_BOX
    h, w, _ = src.shape
    bg_full = gradient(w, h, corners)
    crop = src[y0:y1, x0:x1]
    bg = bg_full[y0:y1, x0:x1]
    maxc = crop.max(axis=2)
    bgmax = bg.max(axis=2)
    alpha = np.clip((maxc - bgmax - 6) / (255.0 - bgmax - 6), 0, 1)
    alpha[alpha < 0.05] = 0  # bruit de compression JPEG
    a = alpha[..., None]
    safe = np.where(a > 0, a, 1)
    color = np.clip((crop - (1 - a) * bg) / safe, 0, 255)
    rgba = np.dstack([color, alpha * 255]).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def tight(img: Image.Image, margin: int) -> Image.Image:
    bbox = img.getchannel("A").point(lambda v: 255 if v > 12 else 0).getbbox()
    cropped = img.crop(bbox)
    side = max(cropped.size) + 2 * margin
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(cropped, ((side - cropped.width) // 2, (side - cropped.height) // 2), cropped)
    return canvas


def place(emblem: Image.Image, canvas: Image.Image, diameter_ratio: float) -> Image.Image:
    size = canvas.width
    d = int(size * diameter_ratio)
    scaled = emblem.resize((d, d), Image.LANCZOS)
    out = canvas.convert("RGBA")
    out.alpha_composite(scaled, ((size - d) // 2, (size - d) // 2))
    return out


def rounded(img: Image.Image, radius_ratio: float, inset: int = 0) -> Image.Image:
    size = img.width
    mask = Image.new("L", (size * 4, size * 4), 0)  # suréchantillonné : bords lisses
    box = (inset * 4, inset * 4, (size - inset) * 4 - 1, (size - inset) * 4 - 1)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=int((size - 2 * inset) * radius_ratio * 4), fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img.convert("RGBA"), (0, 0), mask)
    return out


def main() -> None:
    src = np.asarray(Image.open(SRC).convert("RGB")).astype(float)
    corners = corner_colors(src)
    emblem = tight(key_emblem(src, corners), margin=8)

    emblem.resize((384, 384), Image.LANCZOS).save(OUT / "logo_emblem.png", optimize=True)

    size = 1024
    bg = Image.fromarray(gradient(size, size, corners).astype(np.uint8), "RGB")
    bg.save(OUT / "app_icon_background.png", optimize=True)

    # iOS / Android ancien : carré plein (le système arrondit).
    place(emblem, bg, 0.70).convert("RGB").save(OUT / "app_icon.png", optimize=True)

    # Android adaptatif : flutter_launcher_icons réduit déjà l'avant-plan de 16 % de chaque côté
    # (zone visible = 68 % du canevas). L'emblème doit donc remplir presque tout l'avant-plan :
    # 0,92 x 0,68 = 63 % du canevas final, soit dans la zone sûre (disque central de 66 %).
    place(emblem, Image.new("RGBA", (size, size), (0, 0, 0, 0)), 0.92).save(OUT / "app_icon_foreground.png", optimize=True)

    # Windows : coins arrondis.
    rounded(place(emblem, bg, 0.70), 0.2237).save(OUT / "app_icon_rounded.png", optimize=True)

    # macOS : gabarit Apple (corps de 824 px dans 1024 px, coins arrondis, marges transparentes).
    body = 824
    inner_bg = Image.fromarray(gradient(body, body, corners).astype(np.uint8), "RGB")
    inner = place(emblem, inner_bg, 0.68)
    macos = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    macos.alpha_composite(rounded(inner, 0.2237), ((size - body) // 2, (size - body) // 2))
    macos.save(OUT / "app_icon_macos.png", optimize=True)

    for f in sorted(OUT.glob("*.png")):
        print(f"{f.name:28s} {Image.open(f).size} {f.stat().st_size // 1024} Ko")


if __name__ == "__main__":
    main()
