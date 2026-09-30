#!/usr/bin/env python3
"""Build wrapping ground tiles from generated textures, plus a drawn wood floor."""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "CatCart" / "Assets.xcassets"
OUT = ROOT / "art" / "options" / "ground"
PREV = ROOT / "art" / "options" / "ground" / "_preview"

IMAGESET_JSON = """{
  "images" : [
    {
      "filename" : "%s",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

SRC = Path(
    "/Users/rexchao/.grok/sessions/"
    "%2FUsers%2Frexchao%2FProjects%2FGames%2Fbraingame/"
    "01a09e95-16fe-7611-b196-3fc9ba0327d1/images"
)


def make_seamless(im: Image.Image, overlap: int = 96) -> Image.Image:
    im = im.convert("RGB").resize((512, 512), Image.Resampling.LANCZOS)
    w, h = im.size
    rolled = ImageChops.offset(im, w // 2, h // 2)
    # Plus-shaped soft mask over the new center seams.
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    md.rectangle((w // 2 - overlap, 0, w // 2 + overlap, h), fill=255)
    md.rectangle((0, h // 2 - overlap, w, h // 2 + overlap), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(overlap / 2.2))
    blurred = rolled.filter(ImageFilter.GaussianBlur(2.2))
    healed = Image.composite(blurred, rolled, mask)
    final = ImageChops.offset(healed, -(w // 2), -(h // 2))
    # Kill remaining 2px edge hairline.
    ring = final.filter(ImageFilter.SMOOTH_MORE)
    edge = Image.new("L", (w, h), 0)
    ed = ImageDraw.Draw(edge)
    ed.rectangle((0, 0, w, 3), fill=255)
    ed.rectangle((0, h - 4, w, h), fill=255)
    ed.rectangle((0, 0, 3, h), fill=255)
    ed.rectangle((w - 4, 0, w, h), fill=255)
    final = Image.composite(ring, final, edge)
    return ImageEnhance.Contrast(final).enhance(1.04)


def make_wood() -> Image.Image:
    w = h = 512
    im = Image.new("RGB", (w, h), (196, 140, 82))
    d = ImageDraw.Draw(im)
    plank = 64
    for i, x in enumerate(range(0, w, plank)):
        base = (186 + (i % 3) * 8, 128 + (i % 3) * 6, 72 + (i % 2) * 8)
        d.rectangle((x, 0, x + plank - 3, h), fill=base)
        for y in range(0, h, 18):
            shade = tuple(max(0, c - 10) for c in base)
            d.line((x + 6, y, x + plank - 10, y + 14), fill=shade, width=1)
        d.rectangle((x + plank - 3, 0, x + plank, h), fill=(120, 78, 42))
    return make_seamless(im, overlap=8)


def tile2x2(im: Image.Image) -> Image.Image:
    w, h = im.size
    out = Image.new("RGB", (w * 2, h * 2))
    for x, y in ((0, 0), (w, 0), (0, h), (w, h)):
        out.paste(im, (x, y))
    return out


def write_imageset(name: str, im: Image.Image) -> None:
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    filename = f"{name}.png"
    im.save(folder / filename, "PNG")
    (folder / "Contents.json").write_text(IMAGESET_JSON % filename)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    PREV.mkdir(parents=True, exist_ok=True)
    tiles = {
        "groundCity": make_seamless(Image.open(SRC / "42.jpg")),
        "groundJungle": make_seamless(Image.open(SRC / "40.jpg")),
        "groundFarm": make_seamless(Image.open(SRC / "39.jpg")),
        "groundHouse": make_wood(),
    }
    for name, tile in tiles.items():
        tile.save(OUT / f"{name}.png")
        tile2x2(tile).save(PREV / f"{name}_2x2.png")
        write_imageset(name, tile)
        print(name, tile.size)


if __name__ == "__main__":
    main()
