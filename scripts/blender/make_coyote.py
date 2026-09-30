# Builds the Cat Cart 3D coyote in Blender, animates a looping gallop, and exports
# everything SceneKit needs as JSON. scripts/build_coyote_scn.swift turns the JSON
# into CatCart/Models/coyote_run.scn.
#
# Run from the repo root (Blender 5.x, headless):
#   /Applications/Blender.app/Contents/MacOS/Blender -b --python scripts/blender/make_coyote.py -- \
#       [out.json] [out.blend]
#   swift scripts/build_coyote_scn.swift out.json CatCart/Models/coyote_run.scn
#
# Why rigid parts and not a skinned rig: SceneKit's USD importer is unreliable with
# skinned animation, but plain node transforms always work. So the coyote is a small
# tree of rigid pieces (body, head, jaw, legs, tail), each with its pivot at its
# joint, and the run cycle is baked as per-node position/rotation keys.
#
# Everything below is written in SceneKit game coordinates: meters, +y up, and the
# coyote faces +z (toward the camera). g2b() converts to Blender (+z up, facing -y).
# Visual reference for proportions and coat colors: NPS photo "Coyote near Madison"
# (public domain), see art/models/SOURCES.txt.

import bpy
import bmesh
import json
import math
import random
import sys
from mathutils import Vector, Quaternion

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_JSON = argv[0] if len(argv) > 0 else "/tmp/coyote_run.json"
OUT_BLEND = argv[1] if len(argv) > 1 else None

FPS = 60
FRAMES = 27          # 27 / 60 = 0.45 s per stride
rng = random.Random(7)


def g2b(v):
    """Game (x, y up, z toward camera) -> Blender (x, y, z up)."""
    return Vector((v[0], -v[2], v[1]))


def b2g(v):
    return [v[0], v[2], -v[1]]


def hexc(h):
    return Vector(((h >> 16 & 255) / 255, (h >> 8 & 255) / 255, (h & 255) / 255))


# sRGB palette, sampled by eye from the reference photo, pushed a bit toward cartoon.
COAT = hexc(0xAE9677)      # tan-gray body
SADDLE = hexc(0x6B5D50)    # darker grizzled back
RUST = hexc(0xB9733C)      # legs, ears, muzzle sides
PALE = hexc(0xEFE4CE)      # throat, belly, cheeks
BLACK = hexc(0x1D1917)
DARK = hexc(0x3B2F27)      # brows, claws, grizzle tips
MOUTH = hexc(0x7A141B)     # back of throat
PALATE = hexc(0xB02A35)
TONGUE = hexc(0xE0566A)
TOOTH = hexc(0xFFFCF2)
AMBER = hexc(0xFFB316)


def srgb_to_linear(c):
    f = lambda x: x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
    return (f(max(0.0, min(1.0, c.x))), f(max(0.0, min(1.0, c.y))), f(max(0.0, min(1.0, c.z))))


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return a * (1 - t) + b * t


def grizzle(c, amt=0.06):
    k = 1 + rng.uniform(-amt, amt)
    return Vector((c.x * k, c.y * k, c.z * k))


class Part:
    """One rigid piece. Geometry is collected in game coordinates, world space."""

    def __init__(self, name, pivot, parent=None, material="coat"):
        self.name, self.pivot, self.parent, self.material = name, Vector(pivot), parent, material
        self.verts, self.cols, self.faces, self.smooth = [], [], [], []

    def add_vert(self, p, c):
        self.verts.append(Vector(p))
        self.cols.append(Vector(c))
        return len(self.verts) - 1

    def add_face(self, idx, smooth=True):
        self.faces.append(idx)
        self.smooth.append(smooth)

    # -- primitives ---------------------------------------------------------
    def loft(self, rings, color, n=14, hint=(0, 1, 0), smooth=True, caps=(True, True)):
        """Tube through rings [(center, rx, ry)], ellipse cross sections.
        rx runs along 'side', ry along 'up' (perpendicular to the path, near hint).
        color(pos, center, side, up, ang, t) -> color."""
        centers = [Vector(r[0]) for r in rings]
        hint = Vector(hint)
        loops = []
        for i, (c0, rx, ry) in enumerate(rings):
            c = centers[i]
            a = centers[max(i - 1, 0)]
            b = centers[min(i + 1, len(centers) - 1)]
            t = (b - a).normalized()
            side = t.cross(hint)
            if side.length < 1e-4:
                side = t.cross(Vector((0, 0, 1)))
            side.normalize()
            up = side.cross(t).normalized()
            loop = []
            for k in range(n):
                ang = 2 * math.pi * k / n
                p = c + side * (math.cos(ang) * rx) + up * (math.sin(ang) * ry)
                loop.append(self.add_vert(p, color(p, c, side, up, ang, i / (len(rings) - 1))))
            loops.append(loop)
        for i in range(len(loops) - 1):
            A, B = loops[i], loops[i + 1]
            for k in range(n):
                k2 = (k + 1) % n
                self.add_face([A[k], A[k2], B[k2], B[k]], smooth)
        for end, loop, sgn in ((0, loops[0], -1), (1, loops[-1], 1)):
            if not caps[end]:
                continue
            c = centers[0] if end == 0 else centers[-1]
            col = sum((self.cols[j] for j in loop), Vector((0, 0, 0))) / len(loop)
            ci = self.add_vert(c, col)
            for k in range(n):
                k2 = (k + 1) % n
                self.add_face([loop[k2], loop[k], ci] if sgn < 0 else [loop[k], loop[k2], ci], smooth)

    def ellipsoid(self, center, r, color, segs=14, rings=9, rot=None, smooth=True):
        """UV sphere. rot: optional (axis, angle) in game space applied around center."""
        center = Vector(center)
        q = Quaternion(Vector(rot[0]), rot[1]) if rot else Quaternion()
        top = []
        grid = []
        for j in range(1, rings):
            phi = math.pi * j / rings
            row = []
            for k in range(segs):
                th = 2 * math.pi * k / segs
                d = Vector((math.sin(phi) * math.cos(th) * r[0], math.cos(phi) * r[1],
                            math.sin(phi) * math.sin(th) * r[2]))
                p = center + q @ d
                row.append(self.add_vert(p, color(p, (q @ d).normalized())))
            grid.append(row)
        dn = q @ Vector((0, r[1], 0))
        n_top = self.add_vert(center + dn, color(center + dn, dn.normalized()))
        n_bot = self.add_vert(center - dn, color(center - dn, -dn.normalized()))
        for k in range(segs):
            k2 = (k + 1) % segs
            self.add_face([n_top, grid[0][k2], grid[0][k]], smooth)
            self.add_face([n_bot, grid[-1][k], grid[-1][k2]], smooth)
            for j in range(len(grid) - 1):
                self.add_face([grid[j][k], grid[j][k2], grid[j + 1][k2], grid[j + 1][k]], smooth)

    def spike(self, base, tip, radius, base_col, tip_col, sides=5, flat=1.0, flat_axis=None):
        """Cone from base to tip. flat < 1 squashes it along flat_axis (for ears)."""
        base, tip = Vector(base), Vector(tip)
        t = (tip - base).normalized()
        a = Vector(flat_axis) if flat_axis else (Vector((0, 1, 0)) if abs(t.y) < 0.9 else Vector((1, 0, 0)))
        s = t.cross(a).normalized()
        u = s.cross(t).normalized()
        ring = []
        for k in range(sides):
            ang = 2 * math.pi * k / sides
            p = base + s * (math.cos(ang) * radius) + u * (math.sin(ang) * radius * flat)
            ring.append(self.add_vert(p, base_col))
        ti = self.add_vert(tip, tip_col)
        bi = self.add_vert(base - t * radius * 0.3, base_col)
        for k in range(sides):
            k2 = (k + 1) % sides
            self.add_face([ring[k], ring[k2], ti], False)
            self.add_face([ring[k2], ring[k], bi], False)


# -- colour rules ---------------------------------------------------------------

def body_color(p, c, side, up, ang, t):
    s = math.sin(ang)          # +1 top of the tube, -1 belly
    col = mix(COAT, SADDLE, (s - 0.35) / 0.5)
    col = mix(col, PALE, (-s - 0.25) / 0.45)
    if p.z > 0.28:             # throat and chest front go pale
        col = mix(col, PALE, (-s + 0.2) * (p.z - 0.28) / 0.12)
    return grizzle(col, 0.08)


def leg_color(dark_foot):
    def f(p, c, side, up, ang, t):
        col = mix(RUST, COAT, (p.y - 0.35) / 0.3)
        if dark_foot:
            col = mix(col, RUST * 0.8, (0.12 - p.y) / 0.1)
        return grizzle(col, 0.05)
    return f


def tail_color(p, c, side, up, ang, t):
    col = mix(COAT, SADDLE, (math.sin(ang) - 0.2) / 0.6)
    col = mix(col, PALE, (-math.sin(ang) - 0.4) / 0.4)
    return grizzle(col, 0.08)


def solid(col, jitter=0.0):
    return lambda *a: grizzle(col, jitter)


# -- the coyote -------------------------------------------------------------------
parts = {}


def part(name, pivot, parent=None, material="coat"):
    p = Part(name, pivot, parent, material)
    parts[name] = p
    return p


root = part("coyote", (0, 0, 0))
body = part("body", (0, 0.62, -0.12), "coyote")

# Torso: lean, deep chest, tucked belly, then the neck rising to the head.
body.loft([
    ((0, 0.64, -0.68), 0.07, 0.07),
    ((0, 0.65, -0.62), 0.13, 0.14),
    ((0, 0.66, -0.50), 0.155, 0.165),
    ((0, 0.67, -0.34), 0.135, 0.13),
    ((0, 0.66, -0.16), 0.14, 0.155),
    ((0, 0.63, 0.02), 0.165, 0.20),
    ((0, 0.64, 0.17), 0.165, 0.20),
    ((0, 0.69, 0.30), 0.145, 0.17),
    ((0, 0.75, 0.40), 0.125, 0.145),
    ((0, 0.80, 0.48), 0.115, 0.125),
], body_color, n=16)

# Hackles: a ragged crest of dark-tipped spikes up the neck and over the shoulders.
for i in range(15):
    t = i / 14
    z = 0.44 - t * 0.62
    y_top = 0.92 - t * 0.12 if z > 0.2 else 0.83 - (0.2 - z) * 0.1
    y_top = min(y_top, 0.93)
    for sx in (-1, 1):
        x = sx * (0.035 + 0.05 * rng.random())
        base = Vector((x, y_top - 0.05, z))
        if t > 0.6 and rng.random() < 0.5:
            continue
        ln = (0.09 + 0.08 * math.sin(min(1.0, t * 1.4) * math.pi)) * rng.uniform(0.7, 1.15)
        tip = base + Vector((x * 1.4, ln, -ln * rng.uniform(0.45, 0.8)))
        body.spike(base, tip, 0.04, COAT, DARK, sides=4)

# Ragged belly fringe and chest ruff.
for i in range(6):
    z = 0.2 - i * 0.1
    y = 0.44 + max(0, -z) * 0.25 + (0.03 if z < -0.2 else 0)
    for sx in (-1, 1):
        base = Vector((sx * 0.08, y + 0.05, z + rng.uniform(-0.02, 0.02)))
        tip = base + Vector((sx * 0.03, -0.06 - rng.uniform(0, 0.03), -0.06))
        body.spike(base, tip, 0.035, COAT, SADDLE, sides=4)
for i in range(7):
    x = -0.09 + i * 0.03
    base = Vector((x, 0.56 + abs(x) * 0.4, 0.36))
    tip = base + Vector((x * 0.4, -0.12 - rng.uniform(0, 0.04), 0.06))
    body.spike(base, tip, 0.035, PALE, PALE * 0.85, sides=4)
# Scruffy flank tufts.
for sx in (-1, 1):
    for i in range(4):
        z = 0.1 - i * 0.18
        base = Vector((sx * 0.13, 0.66, z))
        tip = base + Vector((sx * 0.07, 0.03, -0.09))
        body.spike(base, tip, 0.04, COAT, SADDLE, sides=4)

# -- head ---------------------------------------------------------------------
head = part("head", (0, 0.80, 0.46), "body")
HC = Vector((0, 0.88, 0.60))                       # skull centre


def skull_color(p, n):
    col = mix(COAT, SADDLE, (n.y - 0.3) / 0.5)
    col = mix(col, PALE, (-n.y - 0.05) / 0.4)
    if n.z > 0.5 and abs(n.x) < 0.75 and n.y < 0.25:   # pale mask under the eyes
        col = mix(col, PALE, 0.7)
    return grizzle(col, 0.05)


head.ellipsoid(HC, (0.175, 0.145, 0.16), skull_color, segs=16, rings=10)


def muzzle_color(p, c, side, up, ang, t):
    s = math.sin(ang)
    col = mix(RUST, COAT, (s - 0.2) / 0.5)
    if s < -0.35:
        col = PALATE                                  # roof of the open mouth
    return grizzle(col, 0.04)


# Upper jaw / muzzle, long and narrow, a touch raised in a snarl.
head.loft([
    ((0, 0.87, 0.66), 0.115, 0.095),
    ((0, 0.855, 0.76), 0.085, 0.07),
    ((0, 0.85, 0.86), 0.06, 0.05),
    ((0, 0.85, 0.915), 0.042, 0.038),
], muzzle_color, n=14, hint=(0, 1, 0))
head.ellipsoid((0, 0.875, 0.93), (0.042, 0.032, 0.03), solid(BLACK))       # nose
# Throat interior so the open mouth reads dark red, not hollow.
head.ellipsoid((0, 0.80, 0.66), (0.085, 0.06, 0.07), solid(MOUTH))
# Upper teeth along the lip: small teeth plus two big canines.
for i in range(5):
    t = i / 4
    z = 0.70 + t * 0.17
    x = 0.078 - t * 0.04
    for sx in (-1, 1):
        y = 0.80 - 0.004 * i
        head.spike((sx * x, y + 0.02, z), (sx * x, y - 0.03, z + 0.005), 0.012, TOOTH, TOOTH)
for sx in (-1, 1):
    head.spike((sx * 0.052, 0.83, 0.86), (sx * 0.046, 0.72, 0.875), 0.024, TOOTH, TOOTH, sides=6)
head.spike((-0.018, 0.82, 0.905), (-0.018, 0.785, 0.91), 0.011, TOOTH, TOOTH)
head.spike((0.018, 0.82, 0.905), (0.018, 0.785, 0.91), 0.011, TOOTH, TOOTH)

# Eye sockets: dark rims and angry brows slanting down to the nose.
for sx in (-1, 1):
    head.ellipsoid((sx * 0.075, 0.915, 0.715), (0.052, 0.042, 0.03), solid(DARK), segs=10, rings=6)
    head.ellipsoid((sx * 0.085, 0.968, 0.712), (0.075, 0.02, 0.03), solid(DARK), segs=10, rings=6,
                   rot=((0, 0, 1), sx * 0.45))
    head.ellipsoid((sx * 0.078, 0.915, 0.744), (0.013, 0.02, 0.008), solid(BLACK), segs=8, rings=5)
# Nose-bridge snarl wrinkles.
for i in range(3):
    head.ellipsoid((0, 0.915 - i * 0.012, 0.78 + i * 0.035), (0.055 - i * 0.01, 0.011, 0.012),
                   solid(SADDLE * 0.8), segs=8, rings=5)

# Ears: big, pointed, pinned back and out. Rust outside, pale inside.
for sx in (-1, 1):
    base = Vector((sx * 0.1, 0.985, 0.56))
    tip = Vector((sx * 0.27, 1.13, 0.43))
    head.spike(base, tip, 0.08, RUST, DARK, sides=4, flat=0.35, flat_axis=(0, 0, 1))
    head.spike(base + Vector((sx * 0.01, 0.01, 0.025)), tip + Vector((-sx * 0.02, -0.03, 0.03)),
               0.05, PALE, RUST, sides=4, flat=0.3, flat_axis=(0, 0, 1))
# Cheek ruff: pale tufts flaring sideways, the ragged face frame of the 2D art.
for sx in (-1, 1):
    for i in range(4):
        y = 0.80 + i * 0.045
        base = Vector((sx * 0.13, y, 0.6))
        tip = Vector((sx * (0.25 + 0.02 * (i % 2)), y - 0.035 + 0.01 * i, 0.52))
        head.spike(base, tip, 0.04, PALE if i < 2 else COAT, COAT if i < 2 else SADDLE, sides=4)
# Scruff on top of the head.
for i in range(3):
    base = Vector(((i - 1) * 0.045, 1.0, 0.54))
    head.spike(base, base + Vector(((i - 1) * 0.02, 0.07, -0.08)), 0.03, SADDLE, DARK, sides=4)

# Eyes: their own node with a lightly glowing material so they read at distance.
eyes = part("eyes", (0, 0.915, 0.72), "head", material="eyes")
for sx in (-1, 1):
    eyes.ellipsoid((sx * 0.076, 0.915, 0.732), (0.036, 0.032, 0.018), solid(AMBER), segs=12, rings=7)

# -- lower jaw ----------------------------------------------------------------
jaw = part("jaw", (0, 0.80, 0.62), "head")


def jaw_color(p, c, side, up, ang, t):
    s = math.sin(ang)
    col = mix(PALE, RUST, (s + 0.2) / 0.9)
    if s > 0.45:
        col = PALATE
    return grizzle(col, 0.04)


jaw.loft([
    ((0, 0.785, 0.62), 0.095, 0.05),
    ((0, 0.77, 0.72), 0.075, 0.04),
    ((0, 0.768, 0.82), 0.052, 0.032),
    ((0, 0.77, 0.87), 0.036, 0.026),
], jaw_color, n=12)
jaw.ellipsoid((0, 0.795, 0.75), (0.05, 0.016, 0.09), solid(TONGUE))
for i in range(4):
    t = i / 3
    z = 0.68 + t * 0.15
    x = 0.07 - t * 0.035
    for sx in (-1, 1):
        jaw.spike((sx * x, 0.79, z), (sx * x, 0.825, z), 0.011, TOOTH, TOOTH)
for sx in (-1, 1):
    jaw.spike((sx * 0.04, 0.78, 0.845), (sx * 0.044, 0.875, 0.835), 0.021, TOOTH, TOOTH, sides=6)

# -- legs -----------------------------------------------------------------------
FRONT_Z, HIND_Z, LEG_X = 0.17, -0.50, 0.115
for sx, side in ((-1, "L"), (1, "R")):
    x = sx * LEG_X
    up = part(f"frontUpper{side}", (x, 0.70, FRONT_Z), "body")
    up.loft([((x, 0.74, FRONT_Z - 0.02), 0.07, 0.085), ((x, 0.58, FRONT_Z), 0.07, 0.07),
             ((x, 0.40, FRONT_Z + 0.01), 0.045, 0.05)], leg_color(False), n=12, hint=(0, 0, 1))
    lo = part(f"frontLower{side}", (x, 0.41, FRONT_Z + 0.01), f"frontUpper{side}")
    lo.loft([((x, 0.43, FRONT_Z + 0.01), 0.045, 0.048), ((x, 0.20, FRONT_Z), 0.035, 0.035),
             ((x, 0.07, FRONT_Z + 0.01), 0.033, 0.033)], leg_color(True), n=10, hint=(0, 0, 1))
    lo.ellipsoid((x, 0.41, FRONT_Z + 0.01), (0.05, 0.05, 0.05), lambda p, n: leg_color(False)(p, 0, 0, 0, 0, 0), segs=10, rings=6)   # elbow
    lo.ellipsoid((x, 0.04, FRONT_Z + 0.04), (0.045, 0.035, 0.065), solid(RUST * 0.85, 0.04), segs=10, rings=6)
    for k in (-1, 0, 1):
        lo.spike((x + k * 0.022, 0.03, FRONT_Z + 0.09), (x + k * 0.026, 0.005, FRONT_Z + 0.135),
                 0.01, DARK, BLACK, sides=4)

    hu = part(f"hindUpper{side}", (x, 0.66, HIND_Z), "body")
    hu.ellipsoid((x + sx * 0.015, 0.59, HIND_Z + 0.02), (0.075, 0.14, 0.12), lambda p, n: grizzle(
        mix(mix(COAT, SADDLE, (n.y - 0.3) / 0.5), RUST, (0.55 - p.y) / 0.15), 0.06), segs=12, rings=8)
    hu.loft([((x, 0.55, HIND_Z + 0.03), 0.06, 0.07), ((x, 0.40, HIND_Z + 0.09), 0.045, 0.05)],
            leg_color(False), n=10, hint=(0, 0, 1))
    hl = part(f"hindLower{side}", (x, 0.40, HIND_Z + 0.09), f"hindUpper{side}")
    hl.loft([((x, 0.41, HIND_Z + 0.09), 0.044, 0.046), ((x, 0.20, HIND_Z - 0.03), 0.034, 0.036),
             ((x, 0.14, HIND_Z - 0.04), 0.033, 0.034), ((x, 0.06, HIND_Z + 0.0), 0.032, 0.032)],
            leg_color(True), n=10, hint=(0, 0, 1))
    hl.ellipsoid((x, 0.40, HIND_Z + 0.09), (0.05, 0.052, 0.05), lambda p, n: leg_color(False)(p, 0, 0, 0, 0, 0), segs=10, rings=6)  # knee
    hl.ellipsoid((x, 0.035, HIND_Z + 0.03), (0.042, 0.033, 0.06), solid(RUST * 0.85, 0.04), segs=10, rings=6)
    for k in (-1, 0, 1):
        hl.spike((x + k * 0.02, 0.028, HIND_Z + 0.08), (x + k * 0.024, 0.005, HIND_Z + 0.12),
                 0.009, DARK, BLACK, sides=4)

# -- tail -----------------------------------------------------------------------
tail_pts = [Vector((0, 0.66, -0.64)), Vector((0, 0.62, -0.80)), Vector((0, 0.575, -0.96)),
            Vector((0, 0.53, -1.13))]
tail_r = [(0.045, 0.06), (0.075, 0.085), (0.085, 0.09), (0.02, 0.02)]
prev = "body"
for i in range(3):
    a, b = tail_pts[i], tail_pts[i + 1]
    tp = part(f"tail{i + 1}", a, prev)
    mid = (a + b) / 2
    ra, rb = tail_r[i], tail_r[i + 1]
    rm = ((ra[0] + rb[0]) / 2 * 1.08, (ra[1] + rb[1]) / 2 * 1.08)
    if i < 2:
        tp.loft([(a - (b - a) * 0.15, ra[0] * 0.9, ra[1] * 0.9), (mid, *rm), (b + (b - a) * 0.12, rb[0], rb[1])],
                tail_color, n=12)
    else:
        def tip_color(p, c, side, up, ang, t):
            return grizzle(mix(tail_color(p, c, side, up, ang, t), BLACK, (t - 0.25) / 0.3), 0.05)
        tp.loft([(a - (b - a) * 0.15, ra[0], ra[1]), (mid, rm[0] * 1.05, rm[1] * 1.05),
                 (a + (b - a) * 0.8, 0.05, 0.05), (b, 0.012, 0.012)], tip_color, n=12)
    for k in range(3):
        f = (k + 0.5) / 3
        base = a + (b - a) * f
        for sx in (-1, 1):
            tip = base + Vector((sx * 0.07, rng.uniform(-0.03, 0.04), -0.08))
            tc = BLACK if i == 2 else SADDLE
            tp.spike(base, tip, 0.04, COAT if i < 2 else DARK, tc, sides=4)
    prev = f"tail{i + 1}"

# -- run cycle ----------------------------------------------------------------------
TAU = 2 * math.pi


def pose(p):
    """Local (offset, (rx, ry, rz)) per part at stride phase p in [0, 1)."""
    out = {}
    s = math.sin
    out["body"] = ((0, 0.035 * math.cos(TAU * p), 0), (0.07 * s(TAU * p), 0, 0.03 * s(TAU * p + 0.6)))
    out["head"] = ((0, 0, 0), (0.06 - 0.09 * s(TAU * p), 0, -0.03 * s(TAU * p + 0.6)))
    snap = sum(math.exp(-(((p - 0.5 + k) / 0.075) ** 2)) for k in (-1, 0, 1))
    out["jaw"] = ((0, 0, 0), (0.62 - 0.5 * snap, 0, 0))
    for side, ph in (("L", 0.0), ("R", 0.09)):
        q = p + ph
        out[f"frontUpper{side}"] = ((0, 0, 0), (0.6 * s(TAU * q), 0, 0))
        out[f"frontLower{side}"] = ((0, 0, 0), (1.1 * max(0.0, -math.cos(TAU * q)) ** 1.5, 0, 0))
        out[f"hindUpper{side}"] = ((0, 0, 0), (-0.55 * s(TAU * q), 0, 0))
        out[f"hindLower{side}"] = ((0, 0, 0), (-0.25 + 0.95 * max(0.0, math.cos(TAU * q)) ** 1.5, 0, 0))
    for i in range(3):
        lag = 0.12 * (i + 1)
        out[f"tail{i + 1}"] = ((0, 0, 0), ((0.28 if i == 0 else 0.0) + 0.16 * s(TAU * (p - lag)),
                                           0.18 * s(TAU * (p - lag - 0.1)), 0))
    return out


def game_quat(r):
    rx, ry, rz = r
    return (Quaternion((0, 0, 1), ry) @ Quaternion((1, 0, 0), rx) @ Quaternion((0, -1, 0), rz))


# -- into Blender ------------------------------------------------------------------
scene = bpy.context.scene
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
scene.render.fps = FPS
scene.frame_start, scene.frame_end = 0, FRAMES - 1

mat = bpy.data.materials.new("coyote")
objs = {}
for name, pt in parts.items():
    if pt.verts:
        me = bpy.data.meshes.new(name)
        me.from_pydata([g2b(v - pt.pivot) for v in pt.verts], [], pt.faces)
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)   # every piece is closed: point outward
        bm.to_mesh(me)
        bm.free()
        me.polygons.foreach_set("use_smooth", pt.smooth)
        ca = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        for i, c in enumerate(pt.cols):
            ca.data[i].color = (*srgb_to_linear(c), 1.0)   # SceneKit and Blender want linear
        me.materials.append(mat)
        me.update()
        ob = bpy.data.objects.new(name, me)
    else:
        ob = bpy.data.objects.new(name, None)
    scene.collection.objects.link(ob)
    ob.rotation_mode = "QUATERNION"
    objs[name] = ob
for name, pt in parts.items():
    ob = objs[name]
    if pt.parent:
        ob.parent = objs[pt.parent]
        ob.location = g2b(pt.pivot - parts[pt.parent].pivot)
    else:
        ob.location = g2b(pt.pivot)

rest = {n: objs[n].location.copy() for n in objs}
for f in range(FRAMES + 1):
    pz = pose(f / FRAMES)
    for n, (off, rot) in pz.items():
        ob = objs[n]
        ob.location = rest[n] + g2b(off)
        ob.rotation_quaternion = game_quat(rot)
        ob.keyframe_insert("location", frame=f)
        ob.keyframe_insert("rotation_quaternion", frame=f)

# -- export --------------------------------------------------------------------------
out = {"fps": FPS, "frames": FRAMES, "duration": FRAMES / FPS, "parts": [], "anim": {}}
tris = 0
for name, pt in parts.items():
    ob = objs[name]
    entry = {"name": name, "parent": pt.parent, "material": pt.material,
             "position": b2g(rest[name])}
    if ob.type == "MESH":
        me = ob.data
        me.calc_loop_triangles()
        col = me.color_attributes["Col"].data
        cn = me.corner_normals
        V, N, C, I, cache = [], [], [], [], {}
        for lt in me.loop_triangles:
            for li in lt.loops:
                vi = me.loops[li].vertex_index
                nrm = cn[li].vector
                key = (vi, round(nrm.x, 4), round(nrm.y, 4), round(nrm.z, 4))
                if key not in cache:
                    cache[key] = len(V) // 3
                    V += b2g(me.vertices[vi].co)
                    N += b2g(nrm)
                    C += list(col[vi].color)
                I.append(cache[key])
        tris += len(me.loop_triangles)
        entry.update({"vertices": [round(v, 5) for v in V], "normals": [round(v, 4) for v in N],
                      "colors": [round(v, 4) for v in C], "indices": I})
    out["parts"].append(entry)

for name in pose(0):
    ob = objs[name]
    pos, rot = [], []
    for f in range(FRAMES + 1):
        scene.frame_set(f)
        m = ob.matrix_basis
        pos.append([round(v, 5) for v in b2g(m.to_translation())])
        q = m.to_quaternion()
        g = b2g((q.x, q.y, q.z))
        rot.append([round(g[0], 5), round(g[1], 5), round(g[2], 5), round(q.w, 5)])
    out["anim"][name] = {"position": pos, "orientation": rot}

with open(OUT_JSON, "w") as fh:
    json.dump(out, fh)
print(f"coyote: {len(parts)} nodes, {tris} triangles -> {OUT_JSON}")
if OUT_BLEND:
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
    print(f"saved {OUT_BLEND}")
