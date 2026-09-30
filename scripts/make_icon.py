#!/usr/bin/env python3
"""App icon: the kitten in her cart on a road under the city sky.

Writes takes to art/options/icon/ and copies the default into the AppIcon set.
Run: .venv/bin/python scripts/make_icon.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "CatCart" / "Assets.xcassets"
OUT = ROOT / "art" / "options" / "icon"
N = 1024


def asset(name):
    return Image.open(next((ASSETS / f"{name}.imageset").glob("*.png"))).convert("RGBA")


def sky(name):
    im = asset(name).convert("RGB")
    return im.resize((N, N * 2)).crop((0, N // 2, N, N + N // 2))


def road(canvas, color, line):
    d = ImageDraw.Draw(canvas)
    horizon = int(N * 0.52)
    d.polygon([(N * 0.44, horizon), (N * 0.56, horizon), (N * 1.15, N), (-N * 0.15, N)], fill=color)
    for sx in (-1, 1):
        x_far = N / 2 + sx * N * 0.02
        x_near = N / 2 + sx * N * 0.22
        d.line([(x_far, horizon + 10), (x_near, N)], fill=line, width=14)


def cat(canvas, width_frac, bottom_frac):
    sprite = asset("playerBack")
    w = int(N * width_frac)
    h = int(sprite.height * w / sprite.width)
    sprite = sprite.resize((w, h), Image.LANCZOS)
    x = (N - w) // 2
    y = int(N * bottom_frac) - h
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse((x + w * 0.08, y + h - 40, x + w * 0.92, y + h + 30), fill=(0, 0, 0, 90))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))
    canvas.alpha_composite(sprite, (x, y))


def take(sky_name, road_color, line, width_frac=0.62, bottom_frac=0.95):
    base = sky(sky_name).convert("RGBA")
    road(base, road_color, line)
    cat(base, width_frac, bottom_frac)
    return base.convert("RGB")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    takes = {
        "city-road": take("skyCity", (0x7D, 0x7A, 0x80), (0xFF, 0xF1, 0xC8)),
        "farm-road": take("skyFarm", (0xD9, 0xB8, 0x86), (0x8C, 0xC8, 0x6A)),
        "city-close": take("skyCity", (0x7D, 0x7A, 0x80), (0xFF, 0xF1, 0xC8), width_frac=0.78, bottom_frac=1.0),
    }
    for name, im in takes.items():
        im.save(OUT / f"{name}.png")
    takes["farm-road"].save(ASSETS / "AppIcon.appiconset" / "AppIcon.png")
    print("wrote", ", ".join(takes), "-> default farm-road")


if __name__ == "__main__":
    main()
