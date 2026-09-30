#!/usr/bin/env python3
"""Cut generated art onto transparent PNGs, fill the options folder, and
copy the gameplay defaults into the Xcode asset catalog."""

from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = Path(
    "/Users/rexchao/.grok/sessions/"
    "%2FUsers%2Frexchao%2FProjects%2FGames%2Fbraingame/"
    "01a09e95-16fe-7611-b196-3fc9ba0327d1/images"
)
ASSETS = ROOT / "CatCart" / "Assets.xcassets"
OPTIONS = ROOT / "art" / "options"

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


def flood_key(im: Image.Image, tol: int = 52) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    pix = im.load()
    samples = [pix[4, 4], pix[w - 5, 4], pix[4, h - 5], pix[w - 5, h - 5]]
    br = sum(s[0] for s in samples) // 4
    bg = sum(s[1] for s in samples) // 4
    bb = sum(s[2] for s in samples) // 4
    green = bg > br + 12 and bg > bb + 12
    magenta = br > bg + 20 and bb > bg + 8
    limit = tol * 3

    def is_bg(x: int, y: int) -> bool:
        r, g, b, _a = pix[x, y]
        if abs(r - br) + abs(g - bg) + abs(b - bb) > limit:
            return False
        if green:
            return g > r + 6 and g > b + 6
        if magenta:
            return r > g + 12 and b > g + 4
        return True

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
        if not is_bg(x, y):
            continue
        pix[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h:
                i = ny * w + nx
                if not seen[i]:
                    seen[i] = 1
                    q.append((nx, ny))

    for y in range(h):
        for x in range(w):
            r, g, b, a = pix[x, y]
            if a == 0:
                continue
            if green and g > r + 18 and g > b + 18:
                g = min(g, max(r, b) + 10)
                pix[x, y] = (r, g, b, a)
            if magenta and r > g + 30 and b > g + 10:
                pix[x, y] = (0, 0, 0, 0)
    return im


def crop_alpha(im: Image.Image, pad: int = 10) -> Image.Image:
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
    filename = f"{name}.png"
    im.save(folder / filename, "PNG")
    (folder / "Contents.json").write_text(IMAGESET_JSON % filename)


def save_option(rel: str, im: Image.Image) -> None:
    path = OPTIONS / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, "PNG")
    print("option", rel, im.size)


def keyed(name: str) -> Image.Image:
    return crop_alpha(flood_key(Image.open(SRC / name)))


def rgb(name: str) -> Image.Image:
    return Image.open(SRC / name).convert("RGB")


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    OPTIONS.mkdir(parents=True, exist_ok=True)

    # Player cart options. Default gameplay sprite is sitting-small-wheels.
    player = {
        "player/sitting-small-wheels.png": keyed("16.jpg"),
        "player/sitting-big-wheels.png": keyed("24.jpg"),
        "player/sitting-wrapped-case.png": keyed("35.jpg"),
        "player/laying-small-wheels.png": keyed("29.jpg"),
        "player/laying-big-wheels.png": keyed("26.jpg"),
        "player/jump-out.png": keyed("31.jpg"),
    }
    for rel, im in player.items():
        save_option(rel, im)

    coyotes = {
        "coyote/snarl-open.png": keyed("14.jpg"),
        "coyote/snarl-mid.png": keyed("38.jpg"),
        "coyote/snarl-closed.png": keyed("37.jpg"),
        "coyote/side-cartoon.png": keyed("27.jpg"),
    }
    for rel, im in coyotes.items():
        save_option(rel, im)

    food = {
        "food/chicken.png": keyed("17.jpg"),
        "food/salmon.png": keyed("22.jpg"),
    }
    for rel, im in food.items():
        save_option(rel, im)

    trees = {
        "cattree/cubby.png": keyed("18.jpg"),
        "cattree/long-runway.png": keyed("30.jpg"),
    }
    for rel, im in trees.items():
        save_option(rel, im)

    bgs = {
        "backgrounds/jungle-path.jpg": rgb("15.jpg"),
        "backgrounds/jungle-stones.jpg": rgb("32.jpg"),
        "backgrounds/city-taxi.jpg": rgb("19.jpg"),
        "backgrounds/city-clear.jpg": rgb("23.jpg"),
        "backgrounds/house-hall.jpg": rgb("21.jpg"),
        "backgrounds/farm-lane.jpg": rgb("20.jpg"),
    }
    for rel, im in bgs.items():
        path = OPTIONS / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        im.save(path, "JPEG", quality=92)
        print("option", rel, im.size)

    ui = {
        "ui/panel-paws.png": keyed("28.jpg"),
        "ui/panel-cans.png": keyed("34.jpg"),
        "ui/button-paw.png": keyed("33.jpg"),
        "ui/hud-bar.png": keyed("36.jpg"),
    }
    for rel, im in ui.items():
        save_option(rel, im)

    (OPTIONS / "CHOICES.txt").write_text(
        """Pick what you like. Delete the rest.
The game currently uses the files marked DEFAULT in CatCart/Assets.xcassets.

PLAYER (rear view, lilac British Shorthair kitten in a light-blue 12-pack cart)
  sitting-small-wheels.png   DEFAULT
  sitting-big-wheels.png
  sitting-wrapped-case.png   sealed 12-pack wrap, cat popping out the top
  laying-small-wheels.png
  laying-big-wheels.png
  jump-out.png               3/4 hop, not used in-game yet

COYOTE
  snarl-open/mid/closed.png  DEFAULT animation frames (face cycle)
  side-cartoon.png

FOOD
  chicken.png                DEFAULT collectible
  salmon.png

CAT TREE (the 'train')
  cubby.png                  DEFAULT one-lane rideable tree
  long-runway.png            long perspective track, extra option

BACKGROUNDS (cycle every 10s: city, jungle, house, farm)
  city-clear.jpg             DEFAULT city
  jungle-path.jpg            DEFAULT jungle
  house-hall.jpg             DEFAULT house
  farm-lane.jpg              DEFAULT farm
  city-taxi.jpg              extra
  jungle-stones.jpg          extra

UI
  panel-paws.png             DEFAULT overlay panel
  button-paw.png             DEFAULT
  hud-bar.png                DEFAULT
  panel-cans.png
"""
    )

    # Gameplay defaults
    write_imageset("playerBack", player["player/sitting-small-wheels.png"])
    write_imageset("coyoteOpen", coyotes["coyote/snarl-open.png"])
    write_imageset("coyoteMid", coyotes["coyote/snarl-mid.png"])
    write_imageset("coyoteClosed", coyotes["coyote/snarl-closed.png"])
    write_imageset("wetFood", food["food/chicken.png"])
    write_imageset("catTree", trees["cattree/cubby.png"])
    write_imageset("bgCity", bgs["backgrounds/city-clear.jpg"].convert("RGBA"))
    write_imageset("bgJungle", bgs["backgrounds/jungle-path.jpg"].convert("RGBA"))
    write_imageset("bgHouse", bgs["backgrounds/house-hall.jpg"].convert("RGBA"))
    write_imageset("bgFarm", bgs["backgrounds/farm-lane.jpg"].convert("RGBA"))
    write_imageset("uiPanel", ui["ui/panel-paws.png"])
    write_imageset("uiButton", ui["ui/button-paw.png"])
    write_imageset("uiHud", ui["ui/hud-bar.png"])
    print("xcassets defaults written")


if __name__ == "__main__":
    main()
