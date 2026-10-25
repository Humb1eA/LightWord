#!/usr/bin/env python3
"""Draw the 1024x1024 app icon into the asset catalog.

Usage:
    python tools/make_icon.py

Requires Pillow. Re-run after changing the palette; the PNG is committed so a
normal build does not depend on Pillow.
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
SIZE = 1024

TOP = (72, 84, 232)
BOTTOM = (126, 92, 240)
INK = (46, 54, 150)
WHITE = (255, 255, 255)

FONT_CANDIDATES = [
    r"C:\Windows\Fonts\segoeuib.ttf",
    r"C:\Windows\Fonts\arialbd.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    raise SystemExit("no usable bold font found")


def gradient() -> Image.Image:
    image = Image.new("RGB", (SIZE, SIZE), TOP)
    draw = ImageDraw.Draw(image)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        color = tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
        draw.line([(0, y), (SIZE, y)], fill=color)
    return image


def rounded_card(size: int, radius: int, fill) -> Image.Image:
    card = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(card).rounded_rectangle(
        [(0, 0), (size - 1, size - 1)], radius=radius, fill=fill
    )
    return card


def main() -> int:
    canvas = gradient().convert("RGBA")

    # Soft shadow behind the card.
    shadow = rounded_card(600, 84, (20, 24, 80, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    canvas.alpha_composite(shadow, (212, 232))

    # Two offset cards: the pile reads as a deck of word cards.
    back = rounded_card(560, 80, (255, 255, 255, 90))
    back = back.rotate(-8, resample=Image.BICUBIC, expand=False)
    canvas.alpha_composite(back, (238, 222))

    front = rounded_card(560, 80, (255, 255, 255, 255))
    front = front.rotate(-8, resample=Image.BICUBIC, expand=False)
    canvas.alpha_composite(front, (250, 236))

    # "Aa" on the front card.
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    big = load_font(300)
    draw.text((400, 470), "A", font=big, fill=INK, anchor="mm")
    small = load_font(190)
    draw.text((600, 520), "a", font=small, fill=(120, 128, 220), anchor="mm")
    layer = layer.rotate(-8, center=(SIZE / 2, SIZE / 2), resample=Image.BICUBIC)
    canvas.alpha_composite(layer)

    # Accent underline on the card.
    bar = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(bar).rounded_rectangle(
        [(358, 640), (668, 664)], radius=12, fill=(126, 140, 246, 255)
    )
    bar = bar.rotate(-8, center=(SIZE / 2, SIZE / 2), resample=Image.BICUBIC)
    canvas.alpha_composite(bar)

    final = canvas.convert("RGB")
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    final.save(TARGET, format="PNG", optimize=True)
    print(f"wrote {TARGET.relative_to(ROOT)} ({TARGET.stat().st_size / 1024:.1f} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
