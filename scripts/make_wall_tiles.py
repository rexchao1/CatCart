#!/usr/bin/env python3
"""Seamless roadside wall tiles for the 1/z shoulder strips."""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "CatCart" / "Assets.xcassets"
OUT = ROOT / "art" / "options" / "walls"
PREV = OUT / "_preview"
SRC = Path(
    "/Users/rexchao/.grok/sessions/"
    "%2FUsers%2Frexchao%2FProjects%2FGames%2Fbraingame/"
    "01a0a20e-bb35-7ce0-98b7-c00915c6aaf0/images"
)

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

MAP = {
    "wallCity": SRC / "16.jpg",
    "wallJungle": SRC / "13.jpg",
    "wallHouse": SRC / "15.jpg",
    "wallFarm": SRC / "14.jpg",
}


def make_seamless(im: Image.Image, overlap: int = 80) -> Image.Image:
    im = im.convert("RGB").resize((512, 512), Image.Resampling.LANCZOS)
    w, h = im.size
    rolled = ImageChops.offset(im, w // 2, h // 2)
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    md.rectangle((w // 2 - overlap, 0, w // 2 + overlap, h), fill=255)
    md.rectangle((0, h // 2 - overlap, w, h // 2 + overlap), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(overlap / 2.2))
    healed = Image.composite(rolled.filter(ImageFilter.GaussianBlur(2.4)), rolled, mask)
    final = ImageChops.offset(healed, -(w // 2), -(h // 2))
    ring = final.filter(ImageFilter.SMOOTH_MORE)
    edge = Image.new("L", (w, h), 0)
    ed = ImageDraw.Draw(edge)
    ed.rectangle((0, 0, w, 3), fill=255)
    ed.rectangle((0, h - 4, w, h), fill=255)
    ed.rectangle((0, 0, 3, h), fill=255)
    ed.rectangle((w - 4, 0, w, h), fill=255)
    final = Image.composite(ring, final, edge)
    return ImageEnhance.Contrast(final).enhance(1.05)


def tile2x2(im: Image.Image) -> Image.Image:
    w, h = im.size
    out = Image.new("RGB", (w * 2, h * 2))
    for x, y in ((0, 0), (w, 0), (0, h), (w, h)):
        out.paste(im, (x, y))
    return out


def write_imageset(name: str, im: Image.Image) -> None:
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    fname = f"{name}.png"
    im.save(folder / fname, "PNG")
    (folder / "Contents.json").write_text(IMAGESET_JSON % fname)
    im.save(OUT / fname, "PNG")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    PREV.mkdir(parents=True, exist_ok=True)
    for name, src in MAP.items():
        im = make_seamless(Image.open(src))
        write_imageset(name, im)
        tile2x2(im).save(PREV / f"{name}_2x2.png", "PNG")
        print("wrote", name, src.name)


if __name__ == "__main__":
    main()
