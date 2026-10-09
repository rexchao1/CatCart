#!/usr/bin/env python3
"""Draw the textures for the SceneKit 3D world. Pure PIL, fixed seeds.

Run: .venv/bin/python scripts/make_3d_textures.py

Road tiles (1024x1024): u runs across the 6 m road (x = -3 at u=0, +3 at u=1),
v runs along it and repeats every 6 m. They wrap top to bottom only.
Lane centers u = 0.183 / 0.5 / 0.817, separators u = 0.342 / 0.658.

The trick for wrapping: shapes are drawn on a canvas three tiles tall (or
3x3 for textures that wrap both ways), blurred there, then the three bands
are folded on top of each other. Anything that runs off one edge comes back
on the other, blur included.
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parents[1]
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

LANES = (0.183, 0.5, 0.817)
SEPS = (0.342, 0.658)

# Fog / horizon colors, the same as look() in GameScene.swift. Everything from
# FLAT (56%) down in each sky is exactly this color.
HORIZON = {
    "City": (0xF2, 0xC9, 0xA5),
    "Jungle": (0xCF, 0xD8, 0x9E),
    "House": (0xF3, 0xE2, 0xC6),
    "Farm": (0xCD, 0xE7, 0xF6),
}


# ---------------------------------------------------------------- helpers


def hexc(c):
    return "#%02X%02X%02X" % c


def solid(size, color, mode="RGB"):
    return Image.new(mode, size, color)


def noise(size, cells, seed, wrap_x=True):
    """Smooth value noise in 0..255 that wraps top/bottom (and left/right).

    cells = (cx, cy) random values across the image, upscaled bicubic from a
    3x3 tiled grid so the edges match.
    """
    w, h = size
    cx, cy = cells
    rnd = random.Random(seed)
    small = Image.new("L", (cx, cy))
    small.putdata([rnd.randrange(256) for _ in range(cx * cy)])
    big = Image.new("L", (cx * 3, cy * 3))
    for i in range(3):
        for j in range(3):
            big.paste(small, (i * cx, j * cy))
    big = big.resize((w * 3, h * 3), Image.Resampling.BICUBIC)
    out = big.crop((w, h, 2 * w, 2 * h))
    return ImageOps.autocontrast(out, cutoff=1)


def squash(mask, lo, hi):
    """Remap a 0..255 mask into lo..hi."""
    return mask.point(lambda v: int(lo + (hi - lo) * v / 255))


def mix(base, color, mask):
    """Paint color over base through mask (L)."""
    return Image.composite(solid(base.size, color), base, mask)


def shade(base, mask, amount):
    """Darken (amount<0) or lighten (amount>0) base by a mask, soft."""
    target = (0, 0, 0) if amount < 0 else (255, 255, 255)
    m = mask.point(lambda v: int(v * abs(amount)))
    return mix(base, target, m)


class Wrap:
    """RGBA canvas nx by ny tiles; draw in tile coords, fold back to one tile."""

    def __init__(self, size, nx=1, ny=3):
        self.w, self.h = size
        self.nx, self.ny = nx, ny
        self.ox = self.w * (nx // 2)
        self.oy = self.h * (ny // 2)
        self.im = Image.new("RGBA", (self.w * nx, self.h * ny), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def pts(self, pts):
        return [(x + self.ox, y + self.oy) for x, y in pts]

    def box(self, b):
        x0, y0, x1, y1 = b
        return (x0 + self.ox, y0 + self.oy, x1 + self.ox, y1 + self.oy)

    def ellipse(self, b, fill):
        self.d.ellipse(self.box(b), fill=fill)

    def rrect(self, b, r, fill):
        self.d.rounded_rectangle(self.box(b), r, fill=fill)

    def rect(self, b, fill):
        self.d.rectangle(self.box(b), fill=fill)

    def poly(self, pts, fill):
        self.d.polygon(self.pts(pts), fill=fill)

    def line(self, pts, fill, width):
        self.d.line(self.pts(pts), fill=fill, width=width, joint="curve")

    def blur(self, r):
        # Blur premultiplied so edges don't pick up a dark halo.
        pm = self.im.convert("RGBa").filter(ImageFilter.GaussianBlur(r))
        self.im = pm.convert("RGBA")
        self.d = ImageDraw.Draw(self.im)

    def middle(self):
        """For geometry drawn periodically across every tile: keep the center."""
        return self.im.crop((self.ox, self.oy, self.ox + self.w, self.oy + self.h))

    def fold(self):
        out = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        for i in range(self.nx):
            for j in range(self.ny):
                tile = self.im.crop(
                    (i * self.w, j * self.h, (i + 1) * self.w, (j + 1) * self.h)
                )
                out = Image.alpha_composite(out, tile)
        return out


def over(base, layer):
    return Image.alpha_composite(base.convert("RGBA"), layer).convert("RGB")


def band_mask(size, centers, half_width, soft):
    """L mask: 255 inside vertical strips around u centers, soft edges."""
    w, h = size
    row = []
    for x in range(w):
        u = (x + 0.5) / w
        v = 0.0
        for c in centers:
            d = abs(u - c) * w
            t = 1.0 - (d - half_width) / soft
            v = max(v, min(1.0, max(0.0, t)))
        row.append(int(255 * v))
    line = Image.new("L", (w, 1))
    line.putdata(row)
    return line.resize((w, h))


def wobble(v, h, seed, amps=(6, 3), freqs=(2, 5)):
    """Periodic side-to-side wobble in px for row v (wraps at h)."""
    rnd = random.Random(seed)
    out = 0.0
    for a, f in zip(amps, freqs):
        ph = rnd.random() * math.tau
        out += a * math.sin(math.tau * f * v / h + ph)
    return out


def soft_finish(im, r=0.7):
    """Light blur that wraps, so it never leaves a seam at the tile edges."""
    w, h = im.size
    big = Image.new(im.mode, (w * 3, h * 3))
    for i in range(3):
        for j in range(3):
            big.paste(im, (i * w, j * h))
    big = big.filter(ImageFilter.GaussianBlur(r))
    return big.crop((w, h, 2 * w, 2 * h))


# ---------------------------------------------------------------- roads
#
# Each road is 6 m across and repeats every 6 m along the run. The camera sees
# it at a grazing angle with mipmaps on, so detail is big and soft: broad
# mottling, a few readable props (a manhole, a root, a patch), and low-contrast
# grain. High-contrast fine texture would shimmer into moire.

S = 1024


def u2x(u):
    return u * S


def grain(base, seed, dark=-0.08, light=0.06, cells=(160, 160), cells2=(90, 90)):
    """Low-contrast surface grain: a fine darkening and a coarser lightening."""
    base = shade(base, noise((S, S), cells, seed), dark)
    return shade(base, noise((S, S), cells2, seed + 1), light)


def worn(layer, seed, lo=150, hi=255):
    """Multiply an RGBA layer's alpha by soft noise, so paint looks worn."""
    wear = squash(noise(layer.size, (14, 14), seed), lo, hi)
    a = ImageChops.multiply(layer.split()[3], wear)
    layer.putalpha(a)
    return layer


def stone_pts(cx, cy, r, rnd, squash_y=0.8, n=9):
    """Irregular rounded polygon, for stones and pebbles."""
    pts = []
    for k in range(n):
        a = k / n * math.tau + rnd.uniform(-0.15, 0.15)
        rr = r * rnd.uniform(0.75, 1.1)
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr * squash_y))
    return pts


def leaf_pts(x, y, L, W, a):
    ca, sa = math.cos(a), math.sin(a)
    pts = []
    for k in range(12):
        t = k / 11 * math.pi
        pts.append((math.cos(t) * L, math.sin(t) * W))
    for k in range(12):
        t = k / 11 * math.pi
        pts.append((-math.cos(t) * L, -math.sin(t) * W))
    return [(x + px * ca - py * sa, y + px * sa + py * ca) for px, py in pts]


def wobbly_strip(strips, cx, half, seed, fill, inset=0):
    """A continuous strip down the tile with wobbling edges (drawn through
    three tiles, keep the middle)."""
    left, right = [], []
    steps = 64
    for k in range(steps + 1):
        v = k * S / steps
        left.append((cx - half + inset + wobble(v, S, seed), v))
        right.append((cx + half - inset + wobble(v, S, seed + 1), v))
    L = [(x, y - S) for x, y in left] + left[1:] + [(x, y + S) for x, y in left[1:]]
    R = [(x, y - S) for x, y in right] + right[1:] + [(x, y + S) for x, y in right[1:]]
    strips.poly(L + list(reversed(R)), fill)


def root(w, rnd, x0, y0, direction, length, color, hilite):
    """A tree root creeping onto the path: a tapering wobbly line with a highlight."""
    pts = [(x0, y0)]
    ang = direction + rnd.uniform(-0.3, 0.3)
    x, y = x0, y0
    steps = rnd.randint(5, 8)
    for _ in range(steps):
        ang += rnd.uniform(-0.45, 0.45)
        step = length / steps
        x += math.cos(ang) * step
        y += math.sin(ang) * step
        pts.append((x, y))
    n = len(pts)
    for i in range(n - 1):
        t = i / (n - 1)
        wd = int(22 * (1 - t) + 7)
        w.line([pts[i], pts[i + 1]], color + (255,), wd)
        w.ellipse((pts[i][0] - wd / 2, pts[i][1] - wd / 2, pts[i][0] + wd / 2, pts[i][1] + wd / 2), color + (255,))
    for i in range(n - 1):
        t = i / (n - 1)
        wd = max(2, int(7 * (1 - t) + 2))
        a, b = pts[i], pts[i + 1]
        w.line([(a[0], a[1] - 4), (b[0], b[1] - 4)], hilite + (170,), wd)


def road_city():
    """Warm asphalt: broad mottling, fine aggregate, polished wheel tracks, a
    concrete curb with a gutter, a yellow edge line, cream lane dashes, tar
    patches and crack seals, a manhole cover, and a storm drain."""
    rnd = random.Random(101)
    base = solid((S, S), (0x86, 0x7C, 0x74))
    base = mix(base, (0x97, 0x8C, 0x82), squash(noise((S, S), (5, 5), 1), 0, 170))
    base = mix(base, (0x6B, 0x63, 0x5E), squash(noise((S, S), (11, 11), 2), 0, 120))
    base = mix(base, (0x92, 0x84, 0x78), squash(noise((S, S), (3, 7), 5), 0, 70))
    base = grain(base, 3, dark=-0.10, light=0.07, cells=(210, 210), cells2=(120, 120))

    # Lanes: polished wheel tracks a touch lighter, a faint oil line down the middle.
    tracks = band_mask((S, S), [c + o for c in LANES for o in (-0.052, 0.052)], 20, 32)
    base = shade(base, tracks, 0.07)
    oil = band_mask((S, S), LANES, 10, 34)
    base = shade(base, oil, -0.06)

    # Gutter: a dark wet strip at each edge, a concrete curb lip at the very edge.
    gut = band_mask((S, S), (0.0, 1.0), 34, 18)
    base = mix(base, (0x58, 0x54, 0x53), squash(gut, 0, 170))
    lip = band_mask((S, S), (0.0, 1.0), 9, 3)
    base = mix(base, (0xCF, 0xC8, 0xBC), squash(lip, 0, 255))
    seam = band_mask((S, S), (0.0105, 0.9895), 2, 2)
    base = mix(base, (0x4E, 0x4A, 0x48), squash(seam, 0, 160))

    # Tar patches: darker, smoother rounded rectangles with a thin lighter rim.
    wl = Wrap((S, S))
    for lane, cy in [(LANES[0], 140), (LANES[2], 600), (LANES[1], 880)]:
        cx = u2x(lane) + rnd.uniform(-70, 70)
        pw, ph = rnd.uniform(110, 190), rnd.uniform(150, 300)
        wl.rrect((cx - pw / 2 - 4, cy - ph / 2 - 4, cx + pw / 2 + 4, cy + ph / 2 + 4), 22, (0x9A, 0x94, 0x90, 70))
        wl.rrect((cx - pw / 2, cy - ph / 2, cx + pw / 2, cy + ph / 2), 18, (0x5B, 0x57, 0x56, 150))
        wl.rrect((cx - pw / 2 + 8, cy - ph / 2 + 8, cx + pw / 2 - 8, cy + ph / 2 - 8), 14, (0x66, 0x62, 0x60, 90))
    wl.blur(2.0)
    base = over(base, wl.fold())

    # Crack seals: dark glossy tar snakes, soft edged.
    wc = Wrap((S, S))
    for _ in range(6):
        x = rnd.uniform(90, S - 90)
        y = rnd.uniform(0, S)
        pts = [(x, y)]
        ang = rnd.uniform(0, math.tau)
        for _ in range(rnd.randint(5, 9)):
            ang += rnd.uniform(-0.8, 0.8)
            step = rnd.uniform(16, 30)
            x += math.cos(ang) * step
            y += math.sin(ang) * step
            pts.append((x, y))
        wc.line(pts, (0x5A, 0x53, 0x4F, 80), 8)
        wc.line(pts, (0x4A, 0x44, 0x41, 70), 3)
    wc.blur(1.4)
    base = over(base, wc.fold())

    # Manhole cover in the right lane: iron disc, raised rim, two rings, slots.
    wm = Wrap((S, S))
    mx, my, mr = u2x(LANES[2]) + 10, 330, 64
    wm.ellipse((mx - mr - 6, my - mr - 2, mx + mr + 6, my + mr + 8), (0x4A, 0x46, 0x45, 200))
    wm.ellipse((mx - mr, my - mr, mx + mr, my + mr), (0x6E, 0x69, 0x66, 255))
    wm.ellipse((mx - mr + 7, my - mr + 7, mx + mr - 7, my + mr - 7), (0x57, 0x53, 0x51, 255))
    wm.ellipse((mx - mr + 18, my - mr + 18, mx + mr - 18, my + mr - 18), (0x66, 0x61, 0x5E, 255))
    wm.ellipse((mx - mr + 26, my - mr + 26, mx + mr - 26, my + mr - 26), (0x59, 0x55, 0x53, 255))
    for sx in (-1, 1):
        wm.rrect((mx + sx * 22 - 5, my - 12, mx + sx * 22 + 5, my + 12), 4, (0x3A, 0x37, 0x36, 255))
    wm.blur(0.9)
    base = over(base, wm.fold())

    # Storm drain in the left gutter.
    wd0 = Wrap((S, S))
    gx, gy = 26, 700
    wd0.rrect((gx - 16, gy - 48, gx + 16, gy + 48), 3, (0x3E, 0x3A, 0x39, 255))
    for k in range(5):
        yy = gy - 36 + k * 18
        wd0.rect((gx - 12, yy - 3, gx + 12, yy + 3), (0x74, 0x6E, 0x6B, 255))
    wd0.blur(0.7)
    base = over(base, wd0.fold())

    # Paint: a yellow edge line and cream lane dashes (2 m painted, 4 m gap).
    wp = Wrap((S, S))
    for u in (0.045, 0.955):
        cx = u2x(u)
        wp.rect((cx - 5, -S, cx + 5, 2 * S), (0xF2, 0xC6, 0x3C, 220))
    edge = worn(wp.middle(), 7, 140, 255)
    base = over(base, edge)
    wdash = Wrap((S, S))
    dash_len = S / 3
    for sep in SEPS:
        cx = u2x(sep)
        y0 = S * 0.33
        wdash.rrect((cx - 12, y0, cx + 12, y0 + dash_len), 5, (0xFF, 0xF8, 0xE8, 240))
    wdash.blur(1.2)
    base = over(base, worn(wdash.fold(), 8, 170, 255))
    return soft_finish(base, 0.8)


def road_jungle():
    """A packed dirt path through the jungle: sandy wheel tracks, flat stones
    scattered along the lane ridges, roots creeping in from the sides, mossy
    edges, and leaf litter blown to the verges."""
    rnd = random.Random(202)
    base = solid((S, S), (0xA9, 0x67, 0x3D))
    base = mix(base, (0xC2, 0x80, 0x50), squash(noise((S, S), (5, 5), 11), 0, 170))
    base = mix(base, (0x8C, 0x51, 0x30), squash(noise((S, S), (9, 9), 12), 0, 130))
    base = mix(base, (0x7E, 0x5A, 0x32), squash(noise((S, S), (3, 6), 15), 0, 60))
    base = grain(base, 13, dark=-0.08, light=0.06, cells=(140, 140), cells2=(70, 70))

    # Packed sandy tracks where wheels roll, a damper darker line between them.
    tracks = band_mask((S, S), [c + o for c in LANES for o in (-0.058, 0.058)], 16, 26)
    base = mix(base, (0xCB, 0x92, 0x60), squash(tracks, 0, 120))
    damp = band_mask((S, S), LANES, 8, 30)
    base = mix(base, (0x8A, 0x4E, 0x2E), squash(damp, 0, 70))
    # Low ridges between lanes.
    ridge = band_mask((S, S), SEPS, 16, 22)
    base = mix(base, (0xD2, 0x95, 0x64), squash(ridge, 0, 110))

    # Mossy verges with wobbling edges, and moss blotches spilling onto the dirt.
    strips = Wrap((S, S))
    moss, moss_l, moss_d = (0x5B, 0x7C, 0x2C), (0x7A, 0x9C, 0x38), (0x45, 0x62, 0x22)
    for u, half in ((0.0, 54), (1.0, 54)):
        wobbly_strip(strips, u2x(u), half, 600 + int(u * 2), moss_d + (255,))
        wobbly_strip(strips, u2x(u), half, 600 + int(u * 2), moss + (255,), inset=8)
    strips.blur(1.2)
    base = over(base, strips.middle())
    wmoss = Wrap((S, S))
    for _ in range(26):
        side = rnd.choice((0, 1))
        x = rnd.uniform(40, 120) if side == 0 else rnd.uniform(S - 120, S - 40)
        y = rnd.uniform(0, S)
        r = rnd.uniform(14, 34)
        wmoss.ellipse((x - r, y - r * 0.6, x + r, y + r * 0.6), rnd.choice((moss, moss_l)) + (150,))
    wmoss.blur(4)
    base = over(base, wmoss.fold())

    wp = Wrap((S, S))
    # Roots from the verges.
    bark, bark_l = (0x5E, 0x38, 0x22), (0x86, 0x58, 0x36)
    for side, y in ((0, 120), (1, 560), (0, 790), (1, 300)):
        x0 = 40 if side == 0 else S - 40
        root(wp, rnd, x0, y, 0 if side == 0 else math.pi, rnd.uniform(130, 210), bark, bark_l)
    # Flat stones: loosely along the ridges, a few anywhere.
    def stone(cx, cy, r):
        pts = stone_pts(cx, cy, r, rnd)
        wp.poly([(px + 2, py + 4) for px, py in pts], (0x4E, 0x2E, 0x1C, 130))
        g = rnd.randint(0xB4, 0xD4)
        wp.poly(pts, (g, g - 12, g - 36, 255))
        wp.poly([(cx + (px - cx) * 0.55, cy - 2 + (py - cy) * 0.5) for px, py in pts],
                (min(255, g + 18), min(255, g + 6), g - 18, 255))
    for sep in SEPS:
        y = rnd.uniform(0, 40)
        while y < S:
            stone(u2x(sep) + rnd.uniform(-14, 14), y, rnd.uniform(9, 19))
            y += rnd.uniform(44, 110)
    for _ in range(10):
        stone(rnd.uniform(80, S - 80), rnd.uniform(0, S), rnd.uniform(8, 14))
    # Pebbles.
    for _ in range(90):
        x = rnd.uniform(40, S - 40)
        y = rnd.uniform(0, S)
        r = rnd.uniform(3.5, 7)
        wp.ellipse((x - r, y - r * 0.7 + 2, x + r, y + r * 0.7 + 2), (0x5A, 0x33, 0x20, 90))
        g = rnd.randint(0xAE, 0xD2)
        wp.ellipse((x - r, y - r * 0.7, x + r, y + r * 0.7), (g, g - 18, g - 40, 230))
    # Leaf litter: green, yellow, and a few dead brown leaves, thickest at the edges.
    leaf_cols = [(0x5E, 0xA8, 0x3A), (0x7D, 0xBE, 0x44), (0x3F, 0x8E, 0x3A), (0xC9, 0xA8, 0x3A),
                 (0xB8, 0x6A, 0x2E), (0xD6, 0x8E, 0x3C), (0x8F, 0x5A, 0x2A)]
    for _ in range(64):
        if rnd.random() < 0.6:
            x = rnd.choice((rnd.uniform(20, 150), rnd.uniform(S - 150, S - 20)))
        else:
            x = rnd.uniform(60, S - 60)
        y = rnd.uniform(0, S)
        L = rnd.uniform(14, 26)
        a = rnd.uniform(0, math.tau)
        pts = leaf_pts(x, y, L, L * 0.42, a)
        c = rnd.choice(leaf_cols)
        wp.poly([(px + 2, py + 3) for px, py in pts], (0x50, 0x2C, 0x1A, 90))
        wp.poly(pts, c + (245,))
        # Midrib.
        wp.line([(x - math.cos(a) * L * 0.8, y - math.sin(a) * L * 0.8),
                 (x + math.cos(a) * L * 0.8, y + math.sin(a) * L * 0.8)],
                tuple(max(0, v - 40) for v in c) + (160,), 2)
    wp.blur(1.1)
    base = over(base, wp.fold())
    return soft_finish(base, 0.8)


def road_house():
    """A hallway floor: warm varnished floorboards running along the run, and
    one wide runner rug across all three lanes, its woven stripes marking the
    lane lines."""
    rnd = random.Random(303)
    base = solid((S, S), (0xC9, 0x8B, 0x55))
    # Twelve 0.5 m boards across, the width Scenery.swift uses beside the road,
    # in the same four wood tones. Board ends are staggered.
    n = 12
    bw = S / n
    board_cols = [(0xC9, 0x8B, 0x55), (0xBF, 0x81, 0x50), (0xD2, 0x95, 0x60), (0xB9, 0x7A, 0x48), (0xD8, 0x9E, 0x66)]
    wb = Wrap((S, S))
    for i in range(n):
        x0 = i * bw
        seam = rnd.uniform(0, S)
        split = rnd.uniform(0.4, 0.6)
        c1 = rnd.choice(board_cols)
        c2 = rnd.choice([c for c in board_cols if c != c1])
        wb.rect((x0, seam, x0 + bw, seam + S * split), c1 + (255,))
        wb.rect((x0, seam + S * split, x0 + bw, seam + S), c2 + (255,))
        for sy in (seam, seam + S * split):
            wb.rect((x0, sy - 3, x0 + bw, sy + 3), (0x7A, 0x4E, 0x2C, 230))
            wb.rect((x0, sy + 3, x0 + bw, sy + 9), (0xE0, 0xAE, 0x78, 60))
    wb.blur(0.8)
    base = over(base, wb.fold())
    # Grain streaks: noise stretched along the boards, plus a few soft grain lines.
    base = shade(base, noise((S, S), (120, 5), 31), -0.11)
    base = shade(base, noise((S, S), (70, 3), 32), 0.07)
    wgl = Wrap((S, S))
    for i in range(n):
        for _ in range(3):
            x = i * bw + rnd.uniform(8, bw - 8)
            pts = []
            y = -S
            while y <= 2 * S:
                pts.append((x + wobble(y, S, 700 + i, amps=(3, 1.5), freqs=(1, 3)), y))
                y += 64
            wgl.line(pts, (0x8A, 0x5A, 0x30, 55), 2)
    wgl.blur(1.0)
    base = over(base, wgl.middle())
    # Knots.
    wk = Wrap((S, S))
    for _ in range(5):
        i = rnd.randrange(n)
        x = i * bw + rnd.uniform(14, bw - 14)
        y = rnd.uniform(0, S)
        wk.ellipse((x - 9, y - 14, x + 9, y + 14), (0x8A, 0x58, 0x30, 200))
        wk.ellipse((x - 4, y - 7, x + 4, y + 7), (0x6E, 0x44, 0x24, 220))
    wk.blur(1.0)
    base = over(base, wk.fold())
    # Gaps between boards.
    gaps = band_mask((S, S), [i / n for i in range(n + 1)], 2, 3)
    base = mix(base, (0x7A, 0x4E, 0x2C), squash(gaps, 0, 220))
    # Varnish sheen: a soft lighter streak down the floor.
    sheen = band_mask((S, S), (0.5,), 220, 260)
    base = shade(base, sheen, 0.05)

    # The runner: one wide rug, u = 0.075 .. 0.925, continuous down the hall.
    rw = 0.425 * S
    cx = S / 2
    field = (0xC6, 0x5B, 0x4A)
    field_d = (0xB8, 0x50, 0x42)
    border = (0xF4, 0xE7, 0xCE)
    trim = (0x2E, 0x4B, 0x6B)
    gold = (0xE9, 0xC2, 0x7A)
    strips = Wrap((S, S))
    strips.rect((cx - rw, -S, cx + rw, 2 * S), border + (255,))
    strips.rect((cx - rw + 24, -S, cx + rw - 24, 2 * S), trim + (255,))
    strips.rect((cx - rw + 32, -S, cx + rw - 32, 2 * S), field + (255,))
    strips.rect((cx - rw + 44, -S, cx + rw - 44, 2 * S), gold + (255,))
    strips.rect((cx - rw + 50, -S, cx + rw - 50, 2 * S), field + (255,))
    # Woven lane stripes on the separators: cream with a thin field line inside.
    for sep in SEPS:
        sx = u2x(sep)
        strips.rect((sx - 11, -S, sx + 11, 2 * S), border + (255,))
        strips.rect((sx - 2, -S, sx + 2, 2 * S), field_d + (255,))
    strips.blur(1.0)
    rug = strips.middle()
    # Motifs: one big soft diamond per lane per tile, navy dots on the stripes.
    wr = Wrap((S, S))
    for lane in LANES:
        lx = u2x(lane)
        cy = S * 0.5
        dh, dw = 150, 105
        wr.poly([(lx, cy - dh), (lx + dw, cy), (lx, cy + dh), (lx - dw, cy)], gold + (255,))
        wr.poly([(lx, cy - dh + 16), (lx + dw - 11, cy), (lx, cy + dh - 16), (lx - dw + 11, cy)], field + (255,))
        wr.poly([(lx, cy - 60), (lx + 42, cy), (lx, cy + 60), (lx - 42, cy)], trim + (255,))
        wr.poly([(lx, cy - 26), (lx + 18, cy), (lx, cy + 26), (lx - 18, cy)], border + (255,))
        for dy in (cy - S / 2, cy + S / 2):
            wr.ellipse((lx - 10, dy - 10, lx + 10, dy + 10), border + (255,))
            wr.ellipse((lx - 5, dy - 5, lx + 5, dy + 5), trim + (255,))
    for sep in SEPS:
        sx = u2x(sep)
        for k in range(4):
            dy = (k + 0.5) * S / 4
            wr.poly([(sx, dy - 14), (sx + 7, dy), (sx, dy + 14), (sx - 7, dy)], trim + (255,))
    wr.blur(1.0)
    rug = Image.alpha_composite(rug, wr.fold())
    # Shadow on the floor along the rug's edges.
    sh = Image.new("L", (S, S), 0)
    ImageDraw.Draw(sh).rectangle((cx - rw - 6, 0, cx + rw + 6, S), fill=120)
    sh = sh.filter(ImageFilter.BoxBlur(6))
    base = shade(base, sh, -0.45)
    # Weave texture on the rug.
    rug_rgb = rug.convert("RGB")
    rug_rgb = shade(rug_rgb, noise((S, S), (128, 128), 33), -0.10)
    rug_rgb = shade(rug_rgb, noise((S, S), (40, 40), 34), 0.05)
    rug = Image.merge("RGBA", (*rug_rgb.split(), rug.split()[3]))
    base = over(base, rug)
    return soft_finish(base, 0.6)


def road_farm():
    """A farm track: sunny dirt with gravel, two packed tire ruts per lane, grass
    strips between lanes and along the verges, with tufts, clover, and little
    wildflowers."""
    rnd = random.Random(404)
    base = solid((S, S), (0xD9, 0xB2, 0x76))
    base = mix(base, (0xE8, 0xC9, 0x8E), squash(noise((S, S), (5, 5), 41), 0, 170))
    base = mix(base, (0xC2, 0x98, 0x5E), squash(noise((S, S), (9, 9), 42), 0, 130))
    base = mix(base, (0xB6, 0x8E, 0x5A), squash(noise((S, S), (3, 7), 45), 0, 60))
    base = grain(base, 43, dark=-0.07, light=0.06, cells=(150, 150), cells2=(80, 80))

    # Tire ruts: packed darker groove, crumbly lighter lips either side.
    lips = band_mask((S, S), [c + o for c in LANES for o in (-0.088, -0.034, 0.034, 0.088)], 5, 12)
    base = mix(base, (0xF0, 0xD6, 0xA0), squash(lips, 0, 110))
    ruts = band_mask((S, S), [c + o for c in LANES for o in (-0.061, 0.061)], 11, 16)
    base = mix(base, (0xB0, 0x86, 0x54), squash(ruts, 0, 150))
    rutc = band_mask((S, S), [c + o for c in LANES for o in (-0.061, 0.061)], 4, 8)
    base = mix(base, (0xA2, 0x7A, 0x4A), squash(rutc, 0, 90))

    green = (0x6C, 0xB8, 0x3E)
    green_d = (0x4E, 0x96, 0x30)
    green_l = (0x92, 0xCE, 0x52)
    wg = Wrap((S, S))
    strips = Wrap((S, S))
    for i, (u, half) in enumerate([(SEPS[0], 15), (SEPS[1], 15), (0.0, 50), (1.0, 50)]):
        cx = u2x(u)
        wobbly_strip(strips, cx, half, 500 + i * 2, green_d + (255,))
        wobbly_strip(strips, cx, half, 500 + i * 2, green + (255,), inset=4)
        # Blades poking out of the strip edges.
        for _ in range(30):
            v = rnd.uniform(0, S)
            side = rnd.choice((-1, 1))
            xw = wobble(v, S, 500 + i * 2 + (1 if side > 0 else 0))
            ex = cx + side * (half - 2) + xw
            ln = rnd.uniform(10, 20)
            wg.poly([(ex, v - 6), (ex + side * ln, v + rnd.uniform(-8, 8)), (ex, v + 6)],
                    rnd.choice((green, green_l)) + (255,))
        # Clover and wildflowers in the verges.
        if half > 20:
            for _ in range(22):
                v = rnd.uniform(0, S)
                x = cx + rnd.uniform(-half + 6, half - 6)
                r = rnd.uniform(4, 7)
                wg.ellipse((x - r, v - r, x + r, v + r), (0x3E, 0x82, 0x2C, 200))
            for _ in range(9):
                v = rnd.uniform(0, S)
                x = cx + rnd.uniform(-half + 10, half - 10)
                c = rnd.choice(((0xFF, 0xE2, 0x5A), (0xFF, 0xFF, 0xFF), (0xF7, 0x9A, 0xC4)))
                for k in range(5):
                    a = k / 5 * math.tau
                    wg.ellipse((x + math.cos(a) * 4 - 3.5, v + math.sin(a) * 4 - 3.5,
                                x + math.cos(a) * 4 + 3.5, v + math.sin(a) * 4 + 3.5), c + (255,))
                wg.ellipse((x - 2.5, v - 2.5, x + 2.5, v + 2.5), (0xF2, 0xA6, 0x2C, 255))
    # Loose grass tufts in the dirt, mostly between the ruts.
    for _ in range(30):
        x = rnd.uniform(60, S - 60)
        y = rnd.uniform(0, S)
        wg.ellipse((x - 14, y + 2, x + 14, y + 10), (0x8A, 0x66, 0x3A, 90))
        for b in range(6):
            a = -math.pi / 2 + (b - 2.5) * 0.34 + rnd.uniform(-0.1, 0.1)
            ln = rnd.uniform(14, 24)
            tx = x + math.cos(a) * ln
            ty = y + math.sin(a) * ln * 0.8
            wg.poly([(x - 4, y + 5), (tx, ty), (x + 4, y + 5)], rnd.choice((green, green_l, green_d)) + (255,))
    # Gravel: pebbles and a few bigger stones, settled in the ruts.
    for _ in range(110):
        lane = rnd.choice(LANES)
        if rnd.random() < 0.6:
            x = u2x(lane + rnd.choice((-0.061, 0.061))) + rnd.uniform(-14, 14)
        else:
            x = rnd.uniform(60, S - 60)
        y = rnd.uniform(0, S)
        r = rnd.uniform(3, 7)
        g = rnd.randint(0xB8, 0xE6)
        wg.ellipse((x - r, y - r * 0.7 + 1.5, x + r, y + r * 0.7 + 1.5), (0x8A, 0x66, 0x3A, 110))
        wg.ellipse((x - r, y - r * 0.7, x + r, y + r * 0.7), (g, g - 12, g - 32, 230))
    for _ in range(14):
        x = rnd.uniform(80, S - 80)
        y = rnd.uniform(0, S)
        pts = stone_pts(x, y, rnd.uniform(8, 13), rnd, squash_y=0.7)
        wg.poly([(px + 2, py + 3) for px, py in pts], (0x7E, 0x5C, 0x34, 120))
        g = rnd.randint(0xC0, 0xDE)
        wg.poly(pts, (g, g - 14, g - 36, 255))
    # Straw bits.
    for _ in range(36):
        x = rnd.uniform(40, S - 40)
        y = rnd.uniform(0, S)
        a = rnd.uniform(0, math.tau)
        ln = rnd.uniform(14, 30)
        wg.line([(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)], (0xF2, 0xD8, 0x7A, 200), 3)
    strips.blur(1.2)
    base = over(base, strips.middle())
    wg.blur(1.1)
    base = over(base, wg.fold())
    return soft_finish(base, 0.8)


# ---------------------------------------------------------------- carpet, rope

C = 512


def carpet(dark=False, seed=0):
    top = (0xEB, 0xCF, 0xA0)
    if dark:
        top = (0xC8, 0xA0, 0x6C)
    base = solid((C, C), top)
    base = shade(base, noise((C, C), (6, 6), 60 + seed), -0.07)
    # Fluffy loops: mid and fine noise, lightened and darkened.
    base = shade(base, noise((C, C), (64, 64), 61 + seed), -0.13)
    base = shade(base, noise((C, C), (96, 96), 62 + seed), 0.10)
    base = shade(base, noise((C, C), (40, 40), 63 + seed), -0.07)
    # Tufts: soft specks, wrapped both ways.
    rnd = random.Random(64 + seed)
    w = Wrap((C, C), nx=3, ny=3)
    for _ in range(420):
        x, y = rnd.uniform(0, C), rnd.uniform(0, C)
        r = rnd.uniform(3, 6)
        if rnd.random() < 0.5:
            w.ellipse((x - r, y - r, x + r, y + r), (255, 250, 238, 70))
        else:
            w.ellipse((x - r, y - r, x + r, y + r), (0x9A, 0x84, 0x62, 45))
    w.blur(1.5)
    base = over(base, w.fold())
    return soft_finish(base, 0.5)


def sisal():
    # Horizontal wrapped bands; each band a rope with diagonal twist.
    bands = 12
    bh = C / bands
    period = C / 24  # twist repeats 24 times across -> wraps left/right
    light = (0xE2, 0xB8, 0x6A)
    dark = (0x9A, 0x6E, 0x34)
    fib = noise((C, C), (180, 24), 71)
    fib_px = fib.load()
    out = Image.new("RGB", (C, C))
    px = out.load()
    for y in range(C):
        band = int(y // bh)
        t = (y - band * bh) / bh
        roundness = math.sin(math.pi * t) ** 0.55  # 0 at the gap, 1 at the crown
        for x in range(C):
            # Diagonal strands; alternate lean every band for a wrapped look.
            lean = 1 if band % 2 == 0 else -1
            s = 0.5 + 0.5 * math.sin(math.tau * (x / period + lean * t * 0.9))
            k = 0.18 + 0.62 * roundness + 0.2 * s * roundness
            k += (fib_px[x, y] - 128) / 255 * 0.14
            k = max(0.0, min(1.0, k))
            px[x, y] = tuple(int(dark[i] + (light[i] - dark[i]) * k) for i in range(3))
    return soft_finish(out, 0.6)


# ---------------------------------------------------------------- sprites


def blob_shadow():
    n = 256
    im = Image.new("RGBA", (n, n))
    px = im.load()
    c = (n - 1) / 2
    for y in range(n):
        for x in range(n):
            d = math.hypot(x - c, y - c) / (n / 2)
            if d >= 1:
                a = 0.0
            else:
                t = 1 - d
                a = 0.55 * (t * t * (3 - 2 * t))
            px[x, y] = (0, 0, 0, int(round(a * 255)))
    return im


def puff_dot():
    n = 128
    im = Image.new("RGBA", (n, n))
    px = im.load()
    c = (n - 1) / 2
    for y in range(n):
        for x in range(n):
            d = math.hypot(x - c, y - c) / (n / 2)
            if d >= 1:
                a = 0.0
            else:
                t = 1 - d
                a = min(1.0, (t * t * (3 - 2 * t)) * 1.25)
            px[x, y] = (255, 255, 255, int(round(a * 255)))
    return im


# ---------------------------------------------------------------- skies
#
# Each sky is a tall painted picture hung 200 m in front of the camera
# (buildCamera / sizeSky in GameScene.swift). Where it lands on screen:
# - The run camera holds the sky at a 3 degree tilt, so the far horizon
#   (where the fogged road ends, about 120 m out) crosses the picture around
#   v = 0.48 .. 0.53 from the top.
# - Everything from FLAT (v = 0.56) down is exactly the world's fog color, so
#   the road and the fogged scenery melt into it with no seam.
# - A distant silhouette layer (skyline, canopy, hills) sits just above the
#   fog, v = 0.36 .. 0.56, painted in haze so it reads as far away behind the
#   real 3D scenery. Clouds and the sun live above v = 0.42.

SKY_W, SKY_H = 768, 1536
FLAT = 0.56


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def lerpf(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def gradient(stops, t):
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            k = (t - t0) / (t1 - t0) if t1 > t0 else 0
            k = k * k * (3 - 2 * k)
            return lerp(c0, c1, k)
    return stops[-1][1]


def sky_gradient(stops, horizon):
    """Vertical gradient; stops are in 0..1 of the part above FLAT, then flat fog."""
    w, h = SKY_W, SKY_H
    flat = int(h * FLAT)
    im = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(im)
    stops = stops + [(1.0, horizon)]
    for y in range(h):
        c = horizon if y >= flat else gradient(stops, y / (flat - 1))
        d.line([(0, y), (w, y)], fill=c)
    return im


def glow(im, cx, cy, r, color, strength, power=2.0):
    """Add a soft radial glow (screen-like additive mix toward color)."""
    import numpy as np
    w, h = im.size
    yy, xx = np.mgrid[0:h, 0:w].astype("float32")
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
    a = np.clip(1 - d, 0, 1) ** power * strength
    px = np.asarray(im).astype("float32")
    col = np.array(color, dtype="float32").reshape(1, 1, 3)
    out = px + (col - px) * a[..., None]
    return Image.fromarray(np.clip(out, 0, 255).astype("uint8"))


def haze_fill(mask, top_color, horizon, y_top, y_flat):
    """Color a silhouette mask with a vertical gradient: top_color at y_top fading
    to exactly the fog color at y_flat (atmospheric perspective)."""
    import numpy as np
    w, h = mask.size
    yy = np.mgrid[0:h, 0:w][0].astype("float32")
    t = np.clip((yy - y_top) / max(1.0, (y_flat - y_top)), 0, 1)
    t = t * t * (3 - 2 * t)
    a = np.array(top_color, dtype="float32").reshape(1, 1, 3)
    b = np.array(horizon, dtype="float32").reshape(1, 1, 3)
    rgb = a + (b - a) * t[..., None]
    layer = Image.fromarray(np.clip(rgb, 0, 255).astype("uint8")).convert("RGBA")
    layer.putalpha(mask)
    return layer


def silhouette(im, draw_fn, tint, horizon, y_top, blur=1.5, strength=1.0):
    """Draw shapes (draw_fn(ImageDraw) on an L mask) as a hazy far layer.
    tint is how far from fog the top of the layer gets (0..1 toward `dark`)."""
    w, h = im.size
    flat = int(h * FLAT)
    mask = Image.new("L", (w, h), 0)
    draw_fn(ImageDraw.Draw(mask))
    # Nothing below the flat band.
    ImageDraw.Draw(mask).rectangle((0, flat, w, h), fill=0)
    mask = mask.filter(ImageFilter.GaussianBlur(blur))
    if strength < 1:
        mask = mask.point(lambda v: int(v * strength))
    layer = haze_fill(mask, tint, horizon, y_top, flat)
    return over(im, layer)


def clouds(im, count, seed, lit, shade_col, y0, y1, scale0=0.7, scale1=1.2, alpha=235):
    """Puffy clouds with a lit top and a shaded underside, kept above the fog band."""
    w, h = im.size
    rnd = random.Random(seed)
    flat = int(h * FLAT)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    shade_col = lerp(lit, shade_col, 0.55)
    for _ in range(count):
        cx = rnd.uniform(-40, w + 40)
        cy = rnd.uniform(y0, y1)
        # Lower clouds are nearer the horizon: smaller and flatter.
        far = (cy - y0) / max(1, (y1 - y0))
        sc = rnd.uniform(scale0, scale1) * (1.0 - 0.45 * far)
        cw = 160 * sc
        puffs = []
        for _ in range(rnd.randint(4, 7)):
            bx = cx + rnd.uniform(-cw * 0.8, cw * 0.8)
            br = rnd.uniform(34, 60) * sc * (1 - 0.5 * abs(bx - cx) / (cw + 1))
            puffs.append((bx, br))
        c = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(c)
        # Shaded body, offset down a little.
        d.rounded_rectangle((cx - cw, cy - 6 * sc, cx + cw, cy + 30 * sc), 24 * sc, fill=shade_col + (alpha,))
        for bx, br in puffs:
            d.ellipse((bx - br, cy - br * 1.0 + 8 * sc, bx + br, cy + br * 0.7), fill=shade_col + (alpha,))
        # Lit tops.
        d.rounded_rectangle((cx - cw + 6 * sc, cy - 8 * sc, cx + cw - 6 * sc, cy + 14 * sc), 22 * sc,
                            fill=lit + (alpha,))
        for bx, br in puffs:
            d.ellipse((bx - br * 0.92, cy - br * 1.15, bx + br * 0.92, cy + br * 0.25), fill=lit + (alpha,))
        c = blur_rgba(c, 3.5)
        layer = Image.alpha_composite(layer, c)
    cut = Image.new("L", (w, h), 255)
    ImageDraw.Draw(cut).rectangle((0, flat - 90, w, h), fill=0)
    cut = cut.filter(ImageFilter.GaussianBlur(30))
    ImageDraw.Draw(cut).rectangle((0, flat, w, h), fill=0)
    layer.putalpha(ImageChops.multiply(layer.split()[3], cut))
    return over(im, layer)


def sun_rays(im, cx, cy, color, seed, count=7, strength=0.10):
    """Faint light shafts fanning down from the sun."""
    w, h = im.size
    rnd = random.Random(seed)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(count):
        a = rnd.uniform(math.pi * 0.15, math.pi * 0.85)
        spread = rnd.uniform(0.03, 0.07)
        L = rnd.uniform(500, 900)
        pts = [(cx, cy), (cx + math.cos(a - spread) * L, cy + math.sin(a - spread) * L),
               (cx + math.cos(a + spread) * L, cy + math.sin(a + spread) * L)]
        d.polygon(pts, fill=color + (int(255 * strength),))
    layer = blur_rgba(layer, 26)
    flat = int(h * FLAT)
    cut = Image.new("L", (w, h), 255)
    ImageDraw.Draw(cut).rectangle((0, flat - 120, w, h), fill=0)
    cut = cut.filter(ImageFilter.GaussianBlur(40))
    ImageDraw.Draw(cut).rectangle((0, flat, w, h), fill=0)
    layer.putalpha(ImageChops.multiply(layer.split()[3], cut))
    return over(im, layer)


def blur_rgba(layer, r):
    """Blur an RGBA layer premultiplied, so soft edges don't pick up a dark halo."""
    return layer.convert("RGBa").filter(ImageFilter.GaussianBlur(r)).convert("RGBA")


def finish_sky(im, horizon):
    """The flat band must be the fog color to the pixel."""
    w, h = im.size
    flat = int(h * FLAT)
    ImageDraw.Draw(im).rectangle((0, flat, w, h), fill=horizon)
    return im


def sky_city():
    hz = HORIZON["City"]
    im = sky_gradient([(0.0, (0x3F, 0x93, 0xE4)), (0.38, (0x8D, 0xC6, 0xF1)), (0.66, (0xDA, 0xDC, 0xE6)),
                       (0.86, (0xF8, 0xD4, 0xB6))], hz)
    w, h = im.size
    # Late-afternoon sun low on the right, with a wide warm glow.
    im = glow(im, w * 0.74, h * 0.42, 720, (0xFF, 0xE3, 0xB8), 0.55, power=2.4)
    im = glow(im, w * 0.74, h * 0.42, 150, (0xFF, 0xF6, 0xE0), 0.9, power=1.2)
    im = glow(im, w * 0.74, h * 0.42, 54, (0xFF, 0xFF, 0xF4), 1.0, power=0.7)
    # Far skyline, two layers of haze.
    rnd = random.Random(811)
    flat = int(h * FLAT)

    def towers(d, y_base, hmin, hmax, wmin, wmax, gap, antenna):
        x = -20
        while x < w + 20:
            bw = rnd.uniform(wmin, wmax)
            bh = rnd.uniform(hmin, hmax)
            top = y_base - bh
            d.rectangle((x, top, x + bw, y_base + 10), fill=255)
            if rnd.random() < 0.35:
                # Setback crown.
                d.rectangle((x + bw * 0.25, top - bh * 0.18, x + bw * 0.75, top), fill=255)
            if antenna and rnd.random() < 0.3:
                d.rectangle((x + bw * 0.5 - 2, top - rnd.uniform(30, 70), x + bw * 0.5 + 2, top), fill=255)
            x += bw + rnd.uniform(0, gap)

    far_tint = lerp(hz, (0xB6, 0x9C, 0xA8), 0.42)
    near_tint = lerp(hz, (0x9C, 0x80, 0x92), 0.55)
    im = silhouette(im, lambda d: towers(d, flat - 40, 60, 220, 28, 70, 10, False), far_tint, hz,
                    flat - 290, blur=2.5)
    im = silhouette(im, lambda d: towers(d, flat - 10, 40, 150, 36, 90, 26, True), near_tint, hz,
                    flat - 200, blur=1.4)
    im = clouds(im, 7, 81, (0xFF, 0xFB, 0xF4), lerp(hz, (0xC9, 0xB4, 0xC4), 0.5), h * 0.06, h * 0.40)
    return finish_sky(im, hz)


def sky_jungle():
    hz = HORIZON["Jungle"]
    im = sky_gradient([(0.0, (0x1C, 0x86, 0x8A)), (0.42, (0x66, 0xBA, 0xA2)), (0.78, (0xB6, 0xD6, 0xA2))], hz)
    w, h = im.size
    flat = int(h * FLAT)
    # Bright sun high up behind the canopy, with rays through the mist.
    im = glow(im, w * 0.30, h * 0.22, 640, (0xE8, 0xF4, 0xC8), 0.5, power=2.2)
    im = glow(im, w * 0.30, h * 0.22, 120, (0xFF, 0xFC, 0xE6), 0.85, power=1.1)
    im = sun_rays(im, w * 0.30, h * 0.22, (0xFF, 0xF6, 0xD0), 821, count=8, strength=0.14)
    rnd = random.Random(822)

    def mountains(d, y_base, hmin, hmax, wmin, wmax):
        x = -100
        while x < w + 100:
            mw = rnd.uniform(wmin, wmax)
            mh = rnd.uniform(hmin, hmax)
            peak = (x + mw * rnd.uniform(0.35, 0.65), y_base - mh)
            d.polygon([(x - mw * 0.3, y_base + 20), peak, (x + mw * 1.3, y_base + 20)], fill=255)
            x += mw * rnd.uniform(0.5, 0.8)

    def canopy(d, y_base, rmin, rmax, step):
        x = -60
        while x < w + 60:
            r = rnd.uniform(rmin, rmax)
            cy = y_base - r * rnd.uniform(0.3, 0.7)
            d.ellipse((x - r, cy - r, x + r, cy + r), fill=255)
            d.rectangle((x - r, cy, x + r, y_base + 20), fill=255)
            x += rnd.uniform(step * 0.6, step)

    im = silhouette(im, lambda d: mountains(d, flat - 60, 140, 300, 220, 380), lerp(hz, (0x6E, 0x9E, 0x9A), 0.5),
                    hz, flat - 360, blur=3)
    im = silhouette(im, lambda d: canopy(d, flat - 20, 60, 120, 110), lerp(hz, (0x5E, 0x8E, 0x4E), 0.5), hz,
                    flat - 180, blur=2)
    im = silhouette(im, lambda d: canopy(d, flat + 10, 40, 80, 90), lerp(hz, (0x4E, 0x80, 0x44), 0.55), hz,
                    flat - 100, blur=1.4)
    # Mist drifting in front of the canopy.
    mist = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(mist)
    for _ in range(9):
        mx = rnd.uniform(-100, w + 100)
        my = rnd.uniform(flat - 150, flat - 20)
        mw = rnd.uniform(200, 420)
        d.ellipse((mx - mw, my - 22, mx + mw, my + 22), fill=hz + (150,))
    mist = blur_rgba(mist, 18)
    im = over(im, mist)
    im = clouds(im, 3, 83, (0xF6, 0xFB, 0xEE), lerp(hz, (0x9A, 0xB8, 0xA0), 0.5), h * 0.08, h * 0.30,
                scale0=0.8, scale1=1.1, alpha=190)
    return finish_sky(im, hz)


def sky_house():
    hz = HORIZON["House"]
    im = sky_gradient([(0.0, (0xFF, 0xF3, 0xDC)), (0.4, (0xFB, 0xE2, 0xBA)), (0.78, (0xF6, 0xE2, 0xC2))], hz)
    w, h = im.size
    flat = int(h * FLAT)
    # Warm light pouring in from a window out of frame, upper left.
    im = glow(im, w * 0.22, h * 0.14, 700, (0xFF, 0xF8, 0xE6), 0.6, power=2.0)
    im = glow(im, w * 0.22, h * 0.14, 220, (0xFF, 0xFD, 0xF2), 0.6, power=1.2)
    rnd = random.Random(831)
    # The far end of the hall: a tall arched doorway with a lit room beyond, and
    # faint wall panels either side, all in haze.
    wall_tint = lerp(hz, (0xC9, 0xA8, 0x86), 0.3)

    def far_wall(d):
        d.rectangle((0, flat - 330, w, flat + 20), fill=255)

    def arch_hole(d):
        ax, aw, ah = w * 0.5, 150, 300
        d.rounded_rectangle((ax - aw, flat - ah, ax + aw, flat + 40), aw, fill=255)

    wall = Image.new("L", (w, h), 0)
    far_wall(ImageDraw.Draw(wall))
    hole = Image.new("L", (w, h), 0)
    arch_hole(ImageDraw.Draw(hole))
    wall = ImageChops.subtract(wall, hole)
    # Soft edge where the wall meets the ceiling.
    fade = Image.new("L", (w, h), 255)
    ImageDraw.Draw(fade).rectangle((0, 0, w, flat - 330), fill=0)
    fade = fade.filter(ImageFilter.GaussianBlur(70))
    wall = ImageChops.multiply(wall, fade)
    ImageDraw.Draw(wall).rectangle((0, flat, w, h), fill=0)
    im = over(im, haze_fill(wall, wall_tint, hz, flat - 330, flat))
    # Light spilling from the doorway.
    im = glow(im, w * 0.5, flat - 120, 300, (0xFF, 0xF6, 0xDC), 0.7, power=1.5)
    # Dust motes / bokeh in the window light.
    motes = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(motes)
    for _ in range(26):
        x = rnd.uniform(0, w)
        y = rnd.uniform(h * 0.04, h * 0.42)
        r = rnd.uniform(6, 20)
        d.ellipse((x - r, y - r, x + r, y + r), fill=(0xFF, 0xFA, 0xE8, rnd.randint(40, 90)))
    motes = blur_rgba(motes, 5)
    im = over(im, motes)
    return finish_sky(im, hz)


def sky_farm():
    hz = HORIZON["Farm"]
    im = sky_gradient([(0.0, (0x25, 0x82, 0xE2)), (0.45, (0x72, 0xBC, 0xF2)), (0.82, (0xBC, 0xDE, 0xF6))], hz)
    w, h = im.size
    flat = int(h * FLAT)
    im = glow(im, w * 0.26, h * 0.26, 700, (0xE6, 0xF2, 0xFF), 0.45, power=2.4)
    im = glow(im, w * 0.26, h * 0.26, 140, (0xFF, 0xFC, 0xEC), 0.9, power=1.1)
    im = glow(im, w * 0.26, h * 0.26, 56, (0xFF, 0xFF, 0xF8), 1.0, power=0.7)
    rnd = random.Random(842)

    def hills(d, y_base, hmin, hmax, wmin, wmax):
        x = -200
        while x < w + 200:
            hw = rnd.uniform(wmin, wmax)
            hh = rnd.uniform(hmin, hmax)
            d.ellipse((x - hw, y_base - hh, x + hw, y_base + hh), fill=255)
            x += hw * rnd.uniform(0.7, 1.1)

    def trees(d, y_base, count, rmin, rmax):
        for _ in range(count):
            x = rnd.uniform(0, w)
            r = rnd.uniform(rmin, rmax)
            d.ellipse((x - r, y_base - r * 2.2, x + r, y_base - r * 0.2), fill=255)
            d.rectangle((x - r * 0.15, y_base - r, x + r * 0.15, y_base + 4), fill=255)

    def barn(d, x, y_base, s):
        # Gambrel barn and a silo, as a flat shape.
        bw, bh = 90 * s, 50 * s
        d.rectangle((x - bw / 2, y_base - bh, x + bw / 2, y_base + 4), fill=255)
        d.polygon([(x - bw / 2 - 6 * s, y_base - bh), (x - bw * 0.3, y_base - bh - 26 * s),
                   (x, y_base - bh - 36 * s), (x + bw * 0.3, y_base - bh - 26 * s),
                   (x + bw / 2 + 6 * s, y_base - bh)], fill=255)
        sx = x + bw / 2 + 26 * s
        d.rectangle((sx - 13 * s, y_base - 92 * s, sx + 13 * s, y_base + 4), fill=255)
        d.ellipse((sx - 13 * s, y_base - 104 * s, sx + 13 * s, y_base - 80 * s), fill=255)

    def windmill(d, x, y_base, s):
        d.polygon([(x - 8 * s, y_base + 4), (x + 8 * s, y_base + 4), (x + 3 * s, y_base - 110 * s),
                   (x - 3 * s, y_base - 110 * s)], fill=255)
        hub = (x, y_base - 112 * s)
        for k in range(4):
            a = k * math.pi / 2 + 0.4
            d.line([hub, (hub[0] + math.cos(a) * 34 * s, hub[1] + math.sin(a) * 34 * s)], fill=255, width=int(4 * s))

    im = silhouette(im, lambda d: hills(d, flat - 30, 70, 150, 220, 420), lerp(hz, (0x7E, 0xA8, 0xB8), 0.5), hz,
                    flat - 200, blur=3)
    im = silhouette(im, lambda d: (hills(d, flat + 30, 50, 100, 260, 460), trees(d, flat - 40, 14, 10, 20),
                                   barn(d, w * 0.68, flat - 46, 0.9), windmill(d, w * 0.2, flat - 50, 0.8)),
                    lerp(hz, (0x5E, 0x96, 0x72), 0.55), hz, flat - 150, blur=1.6)
    im = clouds(im, 8, 82, (0xFF, 0xFF, 0xFF), lerp(hz, (0xA8, 0xBE, 0xD4), 0.55), h * 0.05, h * 0.42,
                scale0=0.8, scale1=1.4)
    return finish_sky(im, hz)


def skies():
    return {
        "skyCity": sky_city(),
        "skyJungle": sky_jungle(),
        "skyHouse": sky_house(),
        "skyFarm": sky_farm(),
    }


# ---------------------------------------------------------------- output


def save(name, im):
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    fn = f"{name}.png"
    im.save(folder / fn, optimize=True)
    (folder / "Contents.json").write_text(IMAGESET_JSON % fn)
    print(f"wrote {name} {im.size[0]}x{im.size[1]}")


def main(groups=("roads", "carpet", "effects", "skies")):
    """Run with group names (roads, carpet, effects, skies) to redraw only those."""
    if "roads" in groups:
        save("roadCity", road_city())
        save("roadJungle", road_jungle())
        save("roadHouse", road_house())
        save("roadFarm", road_farm())
    if "carpet" in groups:
        save("carpetTop", carpet(False, 0))
        save("carpetSide", carpet(True, 5))
        save("sisalRope", sisal())
    if "effects" in groups:
        save("blobShadow", blob_shadow())
        save("puffDot", puff_dot())
    if "skies" in groups:
        for name, im in skies().items():
            save(name, im)
        for k, c in HORIZON.items():
            print(f"horizon {k}: {hexc(c)}")


if __name__ == "__main__":
    import sys

    main(tuple(sys.argv[1:]) or ("roads", "carpet", "effects", "skies"))
