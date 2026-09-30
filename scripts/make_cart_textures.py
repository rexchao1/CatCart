#!/usr/bin/env python3
"""Textures for the 3D La Croix cart: box wrap, box ends, cardboard inside, can wrap.

The name is set in type (Brush Script, navy) so it spells right, instead of
hoping an image generator does. Deterministic. Writes imagesets into
CatCart/Assets.xcassets.

Run: .venv/bin/python scripts/make_cart_textures.py
"""

import json
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "CatCart" / "Assets.xcassets"
FONTS = Path("/System/Library/Fonts")

NAVY = (0x1C, 0x2F, 0x66)
ICE = (0xD4, 0xEE, 0xFA)
ICE_TOP = (0xEC, 0xF8, 0xFE)
WAVE = (0x6C, 0xBE, 0xE6)
WAVE_DEEP = (0x3F, 0x9C, 0xD6)
KRAFT = (0xD9, 0xC0, 0x96)


def script_font(size):
    return ImageFont.truetype(str(FONTS / "Supplemental" / "Brush Script.ttf"), size)


def sans_font(size):
    # Avenir Next Demi Bold lives at index 2 in the collection.
    return ImageFont.truetype(str(FONTS / "Avenir Next.ttc"), size, index=2)


def vertical_gradient(size, top, bottom):
    w, h = size
    im = Image.new("RGB", size)
    px = im.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = c
    return im


def waves(im, seed, band_top):
    """Two layers of rolling water along the bottom, plus fizz bubbles."""
    w, h = im.size
    rnd = random.Random(seed)
    d = ImageDraw.Draw(im)
    for color, base, amp, freq, phase in (
        (WAVE, band_top, 0.05, 2.0, 0.0),
        (WAVE_DEEP, band_top + 0.12, 0.04, 3.0, 1.3),
    ):
        pts = []
        for i in range(0, w + 8, 8):
            x = i
            y = h * (base + amp * math.sin(phase + freq * math.tau * i / w))
            pts.append((x, y))
        pts += [(w, h), (0, h)]
        d.polygon(pts, fill=color)
    # White crest line on the top wave.
    crest = [(i, h * (band_top + 0.05 * math.sin(2.0 * math.tau * i / w)) - 3) for i in range(0, w + 8, 8)]
    d.line(crest, fill=(255, 255, 255), width=max(4, h // 60))
    # Fizz: little bubbles rising above the water.
    for _ in range(int(w * 0.06)):
        x = rnd.uniform(0, w)
        y = rnd.uniform(h * (band_top - 0.35), h * (band_top + 0.25))
        r = rnd.uniform(h * 0.008, h * 0.022)
        d.ellipse((x - r, y - r, x + r, y + r), outline=(255, 255, 255), width=max(2, int(r / 3)))


def logo(im, center, height, subtitle=True):
    """Navy 'LaCroix' in a brush script, with a soft white halo so it reads on blue."""
    w, h = im.size
    font = script_font(int(height))
    text = "LaCroix"
    layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    box = d.textbbox((0, 0), text, font=font)
    tw, th = box[2] - box[0], box[3] - box[1]
    x = center[0] - tw / 2 - box[0]
    y = center[1] - th / 2 - box[1]
    halo = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(halo).text((x, y), text, font=font, fill=(255, 255, 255, 230),
                              stroke_width=int(height * 0.07), stroke_fill=(255, 255, 255, 230))
    halo = halo.filter(ImageFilter.GaussianBlur(height * 0.03))
    d.text((x, y), text, font=font, fill=NAVY + (255,))
    im.paste(halo, (0, 0), halo)
    im.paste(layer, (0, 0), layer)
    if subtitle:
        sub = sans_font(int(height * 0.2))
        s = "S P A R K L I N G   W A T E R"
        sb = ImageDraw.Draw(im).textbbox((0, 0), s, font=sub)
        sx = center[0] - (sb[2] - sb[0]) / 2
        sy = center[1] + th / 2 + height * 0.1
        ImageDraw.Draw(im).text((sx, sy), s, font=sub, fill=NAVY)


def cart_side():
    # Long side of the box: 1.3 m x 0.5 m.
    im = vertical_gradient((1040, 400), ICE_TOP, ICE)
    waves(im, 11, 0.74)
    logo(im, (520, 150), 170)
    corner = sans_font(26)
    ImageDraw.Draw(im).text((30, 22), "12 CANS", font=corner, fill=NAVY)
    return im


def cart_end():
    # Short end of the box: 0.95 m x 0.5 m.
    im = vertical_gradient((760, 400), ICE_TOP, ICE)
    waves(im, 12, 0.74)
    logo(im, (380, 150), 130, subtitle=False)
    return im


def kraft():
    rnd = random.Random(21)
    im = Image.new("RGB", (256, 256), KRAFT)
    d = ImageDraw.Draw(im)
    for _ in range(900):
        x, y = rnd.uniform(0, 256), rnd.uniform(0, 256)
        c = tuple(max(0, min(255, v + rnd.randint(-14, 10))) for v in KRAFT)
        d.ellipse((x - 2, y - 1, x + 2, y + 1), fill=c)
    # Corrugation lines.
    for y in range(0, 256, 16):
        d.line([(0, y), (256, y)], fill=(0xC9, 0xAE, 0x82), width=2)
    return im.filter(ImageFilter.GaussianBlur(0.8))


def can_side():
    im = vertical_gradient((512, 256), ICE_TOP, ICE)
    waves(im, 31, 0.70)
    logo(im, (256, 100), 80, subtitle=False)
    return im


def save(name, im):
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    im.save(folder / f"{name}.png")
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")


def main():
    save("cartSide", cart_side())
    save("cartEnd", cart_end())
    save("cartKraft", kraft())
    save("canWrap", can_side())
    print("wrote cartSide, cartEnd, cartKraft, canWrap")


if __name__ == "__main__":
    main()
