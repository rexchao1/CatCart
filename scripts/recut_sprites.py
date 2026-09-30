#!/usr/bin/env python3
"""Cut original green-screen takes onto transparent PNGs and restore imagesets."""

from collections import deque
from pathlib import Path
import shutil

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = Path(
    "/Users/rexchao/.grok/sessions/"
    "%2FUsers%2Frexchao%2FProjects%2FGames%2Fbraingame/"
    "01a09e95-16fe-7611-b196-3fc9ba0327d1/images"
)
OPTIONS = ROOT / "art" / "options"
ASSETS = ROOT / "CatCart" / "Assets.xcassets"

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

ORIGINALS = {
    "player/sitting-small-wheels.png": ("16.jpg", "playerBack", False),
    "coyote/snarl-open.png": ("14.jpg", "coyoteOpen", False),
    "coyote/snarl-mid.png": ("38.jpg", "coyoteMid", False),
    "coyote/snarl-closed.png": ("37.jpg", "coyoteClosed", False),
    "food/chicken.png": ("17.jpg", "wetFood", False),
    "cattree/cubby.png": ("18.jpg", "catTree", False),
    "scenery/sideCity.png": ("45.jpg", "sideCity", False),
    "scenery/sideJungle.png": ("44.jpg", "sideJungle", True),
    "scenery/sideHouse.png": ("46.jpg", "sideHouse", True),
    "scenery/sideFarm.png": ("43.jpg", "sideFarm", False),
    "ui/panel-paws.png": ("28.jpg", "uiPanel", False),
    "ui/button-paw.png": ("33.jpg", "uiButton", False),
    "ui/hud-bar.png": ("36.jpg", "uiHud", False),
}


def sample_key(pix, w: int, h: int) -> tuple[int, int, int]:
    samples = [pix[4, 4], pix[w - 5, 4], pix[4, h - 5], pix[w - 5, h - 5]]
    return (
        sum(s[0] for s in samples) // 4,
        sum(s[1] for s in samples) // 4,
        sum(s[2] for s in samples) // 4,
    )


def dist(c, key) -> int:
    return abs(c[0] - key[0]) + abs(c[1] - key[1]) + abs(c[2] - key[2])


def greenness(c) -> int:
    r, g, b = c[0], c[1], c[2]
    return int(g) - max(int(r), int(b))


def is_screen(c, key, protect_leaves: bool) -> bool:
    r, g, b = c[0], c[1], c[2]
    # Warm lamp glow is yellow, not the key.
    if r > 190 and r + 8 >= g and b < 120:
        return False
    d = dist((r, g, b), key)
    if protect_leaves:
        return d <= 74
    if d <= 120:
        return True
    if greenness(c) > 22 and abs(r - key[0]) < 70 and b < key[2] + 40:
        return True
    return False


def key_green(im: Image.Image, protect_leaves: bool = False) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    pix = im.load()
    key = sample_key(pix, w, h)

    seen = bytearray(w * h)
    q: deque[tuple[int, int]] = deque()

    def seed(x: int, y: int) -> None:
        i = y * w + x
        if seen[i]:
            return
        seen[i] = 1
        q.append((x, y))

    for x in range(w):
        seed(x, 0)
        seed(x, h - 1)
    for y in range(h):
        seed(0, y)
        seed(w - 1, y)

    while q:
        x, y = q.popleft()
        c = pix[x, y]
        if not is_screen(c, key, protect_leaves):
            continue
        pix[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h:
                i = ny * w + nx
                if not seen[i]:
                    seen[i] = 1
                    q.append((nx, ny))

    hole = 62 if protect_leaves else 130
    for y in range(h):
        for x in range(w):
            c = pix[x, y]
            if c[3] == 0:
                continue
            gn = greenness(c)
            if dist(c, key) <= hole and gn > 16:
                pix[x, y] = (0, 0, 0, 0)
                continue
            if protect_leaves:
                if dist(c, key) <= 80 and abs(c[0] - key[0]) < 40 and gn > 14:
                    pix[x, y] = (0, 0, 0, 0)
            elif gn > 24 and c[2] < 100:
                pix[x, y] = (0, 0, 0, 0)

    clear_next = []
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            c = pix[x, y]
            if c[3] == 0 or greenness(c) < 22:
                continue
            nclear = sum(
                1
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1))
                if pix[x + dx, y + dy][3] == 0
            )
            if nclear >= 2:
                clear_next.append((x, y))
    for x, y in clear_next:
        pix[x, y] = (0, 0, 0, 0)

    for y in range(1, h - 1):
        for x in range(1, w - 1):
            r, g, b, a = pix[x, y]
            if a == 0:
                continue
            if not any(pix[x + dx, y + dy][3] == 0 for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1))):
                continue
            if g > r + 6 and g > b + 6:
                g2 = min(g, max(r, b) + 12)
                pix[x, y] = (r, g2, b, a)
    return im


def crop_alpha(im: Image.Image, pad: int = 8) -> Image.Image:
    bbox = im.getbbox()
    if not bbox:
        return im
    l, t, r, b = bbox
    l = max(0, l - pad)
    t = max(0, t - pad)
    r = min(im.width, r + pad)
    b = min(im.height, b + pad)
    return im.crop((l, t, r, b))


def write_imageset(name: str, im: Image.Image) -> None:
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    for leftover in folder.iterdir():
        if leftover.name != "Contents.json":
            leftover.unlink()
    filename = f"{name}.png"
    im.save(folder / filename, "PNG")
    (folder / "Contents.json").write_text(IMAGESET_JSON % filename)
    print("imageset", name, im.size)


def main() -> None:
    for rel, (src_name, imageset, protect) in ORIGINALS.items():
        im = crop_alpha(key_green(Image.open(SRC / src_name), protect_leaves=protect))
        out = OPTIONS / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        im.save(out, "PNG")
        write_imageset(imageset, im)

    stale = [
        "playerBack 1.imageset",
        "coyoteSpriteFrames.imageset",
        "obstacleCrate.imageset",
        "roadTile.imageset",
        "streetBackground.imageset",
    ]
    for name in stale:
        folder = ASSETS / name
        if folder.exists():
            shutil.rmtree(folder)
            print("removed", name)


if __name__ == "__main__":
    main()
