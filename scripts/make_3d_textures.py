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

# Fog / horizon colors. The bottom 25% of each sky is exactly this color.
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

S = 1024


def u2x(u):
    return u * S


def road_city():
    rnd = random.Random(101)
    base = solid((S, S), (0x8C, 0x80, 0x76))
    # Big soft mottling, then fine grain kept low contrast.
    base = mix(base, (0x9A, 0x8F, 0x84), squash(noise((S, S), (6, 6), 1), 0, 150))
    base = mix(base, (0x6E, 0x66, 0x60), squash(noise((S, S), (10, 10), 2), 0, 110))
    grain = noise((S, S), (150, 150), 3)
    base = shade(base, squash(grain, 0, 255), -0.10)
    grain2 = noise((S, S), (90, 90), 4)
    base = shade(base, grain2, 0.07)

    # Worn tire darkening, two per lane.
    tracks = band_mask((S, S), [c + o for c in LANES for o in (-0.055, 0.055)], 18, 26)
    base = shade(base, tracks, -0.08)

    # Gutters: darker strip at each edge with a lighter curb lip.
    gut = band_mask((S, S), (0.0, 1.0), 44, 14)
    base = mix(base, (0x5E, 0x57, 0x53), squash(gut, 0, 210))
    lip = band_mask((S, S), (0.0, 1.0), 10, 4)
    base = mix(base, (0xB8, 0xAE, 0xA2), squash(lip, 0, 230))

    # Patches: slightly darker rounded rectangles in lanes.
    wl = Wrap((S, S))
    for _ in range(4):
        lane = rnd.choice(LANES)
        cx = u2x(lane) + rnd.uniform(-60, 60)
        cy = rnd.uniform(0, S)
        pw, ph = rnd.uniform(90, 170), rnd.uniform(120, 260)
        wl.rrect((cx - pw / 2, cy - ph / 2, cx + pw / 2, cy + ph / 2), 18, (0x5C, 0x55, 0x52, 90))
        wl.rrect((cx - pw / 2 + 5, cy - ph / 2 + 5, cx + pw / 2 - 5, cy + ph / 2 - 5), 14, (0x70, 0x68, 0x62, 80))
    wl.blur(2.5)
    base = over(base, wl.fold())

    # Cracks: a few meandering soft lines, 6 px wide.
    wc = Wrap((S, S))
    for _ in range(5):
        x = rnd.uniform(90, S - 90)
        y = rnd.uniform(0, S)
        pts = [(x, y)]
        ang = rnd.uniform(0, math.tau)
        for _ in range(rnd.randint(4, 7)):
            ang += rnd.uniform(-0.9, 0.9)
            step = rnd.uniform(18, 34)
            x += math.cos(ang) * step
            y += math.sin(ang) * step
            pts.append((x, y))
        wc.line(pts, (0x55, 0x4D, 0x48, 95), 7)
    wc.blur(1.6)
    base = over(base, wc.fold())

    # Dashed separators: one dash per 6 m tile, about 2 m long.
    wd = Wrap((S, S))
    dash_len = S / 3
    for sep in SEPS:
        cx = u2x(sep)
        y0 = S * 0.33
        wd.rrect((cx - 11, y0, cx + 11, y0 + dash_len), 10, (0xFF, 0xF6, 0xE2, 235))
    wd.blur(1.8)
    base = over(base, wd.fold())
    return soft_finish(base)


def road_jungle():
    rnd = random.Random(202)
    base = solid((S, S), (0xB0, 0x68, 0x3E))
    base = mix(base, (0xC4, 0x7C, 0x4C), squash(noise((S, S), (5, 5), 11), 0, 170))
    base = mix(base, (0x94, 0x55, 0x33), squash(noise((S, S), (9, 9), 12), 0, 130))
    base = shade(base, noise((S, S), (120, 120), 13), -0.08)
    base = shade(base, noise((S, S), (70, 70), 14), 0.06)

    # Two worn, packed tracks per lane: a bit darker and smoother.
    tracks = band_mask((S, S), [c + o for c in LANES for o in (-0.06, 0.06)], 16, 22)
    base = mix(base, (0x8E, 0x4F, 0x30), squash(tracks, 0, 110))

    # Ridges at separators: lighter raised dirt with a stone line.
    ridge = band_mask((S, S), SEPS, 14, 18)
    base = mix(base, (0xD4, 0x94, 0x62), squash(ridge, 0, 170))
    # Edge verge: darker, mossy tint.
    edge = band_mask((S, S), (0.0, 1.0), 40, 30)
    base = mix(base, (0x6E, 0x6A, 0x32), squash(edge, 0, 170))

    wp = Wrap((S, S))
    # Stones along separators.
    for sep in SEPS:
        y = 0.0
        while y < S:
            r = rnd.uniform(9, 14)
            cx = u2x(sep) + rnd.uniform(-5, 5)
            wp.ellipse((cx - r, y - r * 0.8 + 3, cx + r, y + r * 0.8 + 3), (0x5A, 0x33, 0x20, 110))
            g = rnd.randint(0xB8, 0xD2)
            wp.ellipse((cx - r, y - r * 0.8, cx + r, y + r * 0.8), (g, g - 14, g - 34, 255))
            y += r * 2 + rnd.uniform(10, 26)
    # Scattered pebbles.
    for _ in range(70):
        x = rnd.uniform(40, S - 40)
        y = rnd.uniform(0, S)
        r = rnd.uniform(4, 8)
        wp.ellipse((x - r, y - r * 0.7 + 2, x + r, y + r * 0.7 + 2), (0x5A, 0x33, 0x20, 90))
        g = rnd.randint(0xB0, 0xD0)
        wp.ellipse((x - r, y - r * 0.7, x + r, y + r * 0.7), (g, g - 18, g - 40, 230))
    # Small leaves.
    leaf_cols = [(0x5E, 0xA8, 0x3A), (0x7D, 0xBE, 0x44), (0x3F, 0x8E, 0x3A), (0xC9, 0xA8, 0x3A)]
    for _ in range(46):
        # More leaves near the edges.
        if rnd.random() < 0.55:
            x = rnd.choice((rnd.uniform(20, 120), rnd.uniform(S - 120, S - 20)))
        else:
            x = rnd.uniform(60, S - 60)
        y = rnd.uniform(0, S)
        L = rnd.uniform(14, 24)
        W = L * 0.45
        a = rnd.uniform(0, math.tau)
        ca, sa = math.cos(a), math.sin(a)
        pts = []
        for k in range(12):
            t = k / 11 * math.pi
            px = math.cos(t) * L
            py = math.sin(t) * W
            pts.append((px, py))
        for k in range(12):
            t = k / 11 * math.pi
            pts.append((-math.cos(t) * L, -math.sin(t) * W))
        pts = [(x + px * ca - py * sa, y + px * sa + py * ca) for px, py in pts]
        wp.poly([(px + 2, py + 3) for px, py in pts], (0x50, 0x2C, 0x1A, 80))
        wp.poly(pts, rnd.choice(leaf_cols) + (240,))
    wp.blur(1.3)
    base = over(base, wp.fold())
    return soft_finish(base)


def road_house():
    rnd = random.Random(303)
    base = solid((S, S), (0xD8, 0x9A, 0x52))
    # Boards along v: 16 boards across.
    n = 16
    bw = S / n
    board_cols = [(0xDE, 0xA2, 0x58), (0xD0, 0x92, 0x4A), (0xE6, 0xAE, 0x64), (0xC9, 0x8B, 0x46)]
    wb = Wrap((S, S))
    for i in range(n):
        x0 = i * bw
        # Each board column has a seam (board end) at a staggered spot.
        seam = rnd.uniform(0, S)
        c1 = rnd.choice(board_cols)
        c2 = rnd.choice(board_cols)
        wb.rect((x0, seam, x0 + bw, seam + S * 0.55), c1 + (255,))
        wb.rect((x0, seam + S * 0.55, x0 + bw, seam + S), c2 + (255,))
        wb.rect((x0, seam - 3, x0 + bw, seam + 3), (0x8A, 0x55, 0x2A, 200))
        wb.rect((x0, seam + S * 0.55 - 3, x0 + bw, seam + S * 0.55 + 3), (0x8A, 0x55, 0x2A, 200))
    wb.blur(0.8)
    base = over(base, wb.fold())
    # Grain streaks: noise stretched along v.
    grain = noise((S, S), (110, 6), 31)
    base = shade(base, grain, -0.12)
    base = shade(base, noise((S, S), (60, 4), 32), 0.08)
    # Gaps between boards.
    gaps = band_mask((S, S), [i / n for i in range(n + 1)], 2, 3)
    base = mix(base, (0x86, 0x52, 0x28), squash(gaps, 0, 200))

    # Three runner rugs, one per lane. Wood shows between them as the separator.
    rug = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rw = 0.268 * S / 2  # half width
    field = (0xD9, 0x8A, 0x7E)
    border = (0xF6, 0xEA, 0xD2)
    inner = (0x8C, 0xB8, 0xA6)
    gold = (0xEE, 0xCB, 0x86)
    # Continuous rug strips go on their own canvas, drawn through all three
    # tiles, keeping the middle. Motifs go on a folded canvas on top.
    strips = Wrap((S, S))
    wr = Wrap((S, S))
    for lane in LANES:
        cx = u2x(lane)
        strips.rect((cx - rw, -S, cx + rw, 2 * S), border + (255,))
        strips.rect((cx - rw + 16, -S, cx + rw - 16, 2 * S), inner + (255,))
        strips.rect((cx - rw + 26, -S, cx + rw - 26, 2 * S), field + (255,))
        # Diamonds down the middle, 2 per tile, kept small so the rug stays calm.
        for k in range(2):
            cy = (k + 0.5) * S / 2
            dh, dwid = 70, rw - 70
            wr.poly([(cx, cy - dh), (cx + dwid, cy), (cx, cy + dh), (cx - dwid, cy)], gold + (255,))
            wr.poly([(cx, cy - dh + 18), (cx + dwid - 18, cy), (cx, cy + dh - 18), (cx - dwid + 18, cy)], field + (255,))
            wr.poly([(cx, cy - 34), (cx + 30, cy), (cx, cy + 34), (cx - 30, cy)], inner + (255,))
            # Little cream dots between diamonds.
            dy = cy + S / 4
            wr.ellipse((cx - 9, dy - 9, cx + 9, dy + 9), border + (255,))
            for sx in (-1, 1):
                ex = cx + sx * (rw - 44)
                wr.ellipse((ex - 7, dy - 7, ex + 7, dy + 7), gold + (255,))
        # Border stitch blocks.
        for k in range(16):
            cy = (k + 0.5) * S / 16
            for sx in (-1, 1):
                ex = cx + sx * (rw - 8)
                wr.rect((ex - 4, cy - 12, ex + 4, cy + 12), inner + (255,))
    strips.blur(1.0)
    wr.blur(1.0)
    rug = Image.alpha_composite(strips.middle(), wr.fold())
    # Soft shadow under the rugs on the wood.
    sh = Image.new("L", (S, S), 0)
    shd = ImageDraw.Draw(sh)
    for lane in LANES:
        cx = u2x(lane)
        shd.rectangle((cx - rw - 5, 0, cx + rw + 5, S), fill=110)
    sh = sh.filter(ImageFilter.BoxBlur(5))
    base = shade(base, sh, -0.5)
    # Rug fabric texture.
    fab = noise((S, S), (130, 130), 33)
    rug_rgb = rug.convert("RGB")
    rug_rgb = shade(rug_rgb, fab, -0.10)
    rug = Image.merge("RGBA", (*rug_rgb.split(), rug.split()[3]))
    base = over(base, rug)
    return soft_finish(base, 0.6)


def road_farm():
    rnd = random.Random(404)
    base = solid((S, S), (0xDC, 0xB8, 0x7C))
    base = mix(base, (0xE8, 0xC8, 0x8E), squash(noise((S, S), (5, 5), 41), 0, 170))
    base = mix(base, (0xC4, 0x9C, 0x62), squash(noise((S, S), (9, 9), 42), 0, 120))
    base = shade(base, noise((S, S), (120, 120), 43), -0.07)
    base = shade(base, noise((S, S), (70, 70), 44), 0.06)

    # Tire ruts: darker groove with a light lip on the outside.
    lips = band_mask((S, S), [c + o for c in LANES for o in (-0.09, 0.09)], 6, 14)
    base = mix(base, (0xEE, 0xD2, 0x9C), squash(lips, 0, 80))
    ruts = band_mask((S, S), [c + o for c in LANES for o in (-0.06, 0.06)], 12, 18)
    base = mix(base, (0xB4, 0x8A, 0x56), squash(ruts, 0, 140))

    green = (0x6C, 0xB8, 0x3E)
    green_d = (0x4E, 0x96, 0x30)
    green_l = (0x92, 0xCE, 0x52)
    wg = Wrap((S, S))
    strips = Wrap((S, S))
    # Wobbly grass strips at separators and wider verges at the edges.
    for i, (u, half) in enumerate([(SEPS[0], 14), (SEPS[1], 14), (0.0, 46), (1.0, 46)]):
        cx = u2x(u)
        left, right = [], []
        steps = 64
        for k in range(steps + 1):
            v = k * S / steps
            wl = wobble(v, S, 500 + i * 2)
            wr_ = wobble(v, S, 501 + i * 2)
            left.append((cx - half + wl, v))
            right.append((cx + half + wr_, v))
        # The strip is continuous, so draw it through all three tiles on
        # its own canvas and keep the middle (no seam line, blur wraps).
        L = [(x, y - S) for x, y in left] + left[1:] + [(x, y + S) for x, y in left[1:]]
        R = [(x, y - S) for x, y in right] + right[1:] + [(x, y + S) for x, y in right[1:]]
        strips.poly(L + list(reversed(R)), green_d + (255,))
        strips.poly([(x + 4, y) for x, y in L] + list(reversed([(x - 4, y) for x, y in R])), green + (255,))
        # Blades poking out of the strip edges.
        for k in range(26):
            v = rnd.uniform(0, S)
            side = rnd.choice((-1, 1))
            xw = wobble(v, S, 500 + i * 2 + (1 if side > 0 else 0))
            ex = cx + side * (half - 2) + xw
            ln = rnd.uniform(10, 18)
            wg.poly([(ex, v - 6), (ex + side * ln, v + rnd.uniform(-8, 8)), (ex, v + 6)], rnd.choice((green, green_l)) + (255,))
    # Loose grass tufts in the dirt.
    for _ in range(26):
        x = rnd.uniform(60, S - 60)
        y = rnd.uniform(0, S)
        wg.ellipse((x - 14, y + 2, x + 14, y + 10), (0x8A, 0x66, 0x3A, 90))
        for b in range(5):
            a = -math.pi / 2 + (b - 2) * 0.38 + rnd.uniform(-0.1, 0.1)
            ln = rnd.uniform(14, 22)
            tx = x + math.cos(a) * ln
            ty = y + math.sin(a) * ln * 0.8
            wg.poly([(x - 4, y + 5), (tx, ty), (x + 4, y + 5)], rnd.choice((green, green_l, green_d)) + (255,))
    # A few pebbles.
    for _ in range(40):
        x = rnd.uniform(60, S - 60)
        y = rnd.uniform(0, S)
        r = rnd.uniform(4, 7)
        g = rnd.randint(0xC8, 0xE4)
        wg.ellipse((x - r, y - r * 0.7, x + r, y + r * 0.7), (g, g - 10, g - 30, 220))
    strips.blur(1.2)
    base = over(base, strips.middle())
    wg.blur(1.2)
    base = over(base, wg.fold())
    return soft_finish(base)


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


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def gradient(stops, t):
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            k = (t - t0) / (t1 - t0) if t1 > t0 else 0
            k = k * k * (3 - 2 * k)
            return lerp(c0, c1, k)
    return stops[-1][1]


def sky(stops, horizon, clouds=0, seed=0, cloud_tint=(255, 255, 255)):
    w, h = 512, 1024
    flat = int(h * 0.75)
    im = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(im)
    stops = stops + [(1.0, horizon)]
    for y in range(h):
        if y >= flat:
            c = horizon
        else:
            c = gradient(stops, y / (flat - 1))
        d.line([(0, y), (w, y)], fill=c)
    if clouds:
        rnd = random.Random(seed)
        wc = Wrap((w, h), nx=3, ny=1)
        for _ in range(clouds):
            cx = rnd.uniform(0, w)
            cy = rnd.uniform(90, 460)
            scale = rnd.uniform(0.6, 1.15) * (1.0 - 0.35 * (cy - 90) / 370)
            cw = 150 * scale
            # Flat bottom, puffy top.
            wc.rrect((cx - cw, cy - 10 * scale, cx + cw, cy + 22 * scale), 20 * scale, (238, 240, 248, 235))
            for _ in range(5):
                bx = cx + rnd.uniform(-cw * 0.75, cw * 0.75)
                br = rnd.uniform(28, 52) * scale
                wc.ellipse((bx - br, cy - br * 1.1, bx + br, cy + br * 0.6), cloud_tint + (245,))
        wc.blur(4)
        layer = wc.fold()
        # Keep clouds off the flat horizon band.
        cut = Image.new("L", (w, h), 255)
        ImageDraw.Draw(cut).rectangle((0, flat - 60, w, h), fill=0)
        cut = cut.filter(ImageFilter.GaussianBlur(20))
        cut = ImageChops.multiply(cut, Image.new("L", (w, h), 255))
        ImageDraw.Draw(cut).rectangle((0, flat, w, h), fill=0)
        a = ImageChops.multiply(layer.split()[3], cut)
        layer.putalpha(a)
        im = over(im, layer)
    return im


def skies():
    return {
        "skyCity": sky(
            [(0.0, (0x6F, 0xB2, 0xE8)), (0.4, (0xB2, 0xD6, 0xF0)), (0.62, (0xE8, 0xDC, 0xDA)), (0.82, (0xF6, 0xD6, 0xBA))],
            HORIZON["City"], clouds=5, seed=81, cloud_tint=(255, 250, 244),
        ),
        "skyJungle": sky(
            [(0.0, (0x2F, 0x9E, 0x94)), (0.5, (0x7C, 0xC2, 0xA6)), (0.8, (0xB8, 0xD8, 0xA6))],
            HORIZON["Jungle"],
        ),
        "skyHouse": sky(
            [(0.0, (0xFF, 0xF4, 0xDE)), (0.35, (0xF8, 0xDE, 0xB4)), (0.7, (0xF6, 0xE0, 0xC0))],
            HORIZON["House"],
        ),
        "skyFarm": sky(
            [(0.0, (0x2F, 0x92, 0xEA)), (0.5, (0x7C, 0xC0, 0xF2)), (0.8, (0xB8, 0xDE, 0xF6))],
            HORIZON["Farm"], clouds=6, seed=82,
        ),
    }


# ---------------------------------------------------------------- output


def save(name, im):
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    fn = f"{name}.png"
    im.save(folder / fn, optimize=True)
    (folder / "Contents.json").write_text(IMAGESET_JSON % fn)
    print(f"wrote {name} {im.size[0]}x{im.size[1]}")


def main():
    save("roadCity", road_city())
    save("roadJungle", road_jungle())
    save("roadHouse", road_house())
    save("roadFarm", road_farm())
    save("carpetTop", carpet(False, 0))
    save("carpetSide", carpet(True, 5))
    save("sisalRope", sisal())
    save("blobShadow", blob_shadow())
    save("puffDot", puff_dot())
    for name, im in skies().items():
        save(name, im)
    for k, c in HORIZON.items():
        print(f"horizon {k}: {hexc(c)}")


if __name__ == "__main__":
    main()
