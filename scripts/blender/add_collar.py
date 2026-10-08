# Adds the orange collar to Rex's kitten study (art/models/kitten/cat.blend),
# then renders a front and a rear preview next to it.
#
#   /Applications/Blender.app/Contents/MacOS/Blender -b art/models/kitten/cat.blend \
#       --python scripts/blender/add_collar.py -- /tmp/collar-preview
#
# Run it as often as you like: it deletes the old "Collar ..." objects first.
# Pass --nosave to only render, --norender to skip the previews.
# scripts/blender/make_kitten_v3.py runs it with both, before it saves. The objects are named so export_kitten.py can
# fold them into the head (the collar leans with her head in the game):
#   Collar strap  (material kittenCollar)
#   Collar stitch (kittenCollarStitch)
#   Collar buckle (kittenBell, the gold)
#   Collar bell, Collar bell loop (kittenBell), Collar bell slit (kittenBellSlit)
#
# Coordinates are Blender's (Z up, she faces +Y).
#
# The collar is snug (Rex, 2026-10-08: "make its collar tighter"). It sits up
# where her neck is narrowest, just under her jaw, and instead of a fixed oval
# the strap follows her actual neck: every few degrees around it, a ray finds
# her surface (body, and the jaw at the front) a little above, at, and below the
# strap's line, and the strap's inner face sits GAP outside the outermost one.
# Without her body in the file it falls back to the old oval.

import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = next((a for a in args if not a.startswith("--")), "/tmp/collar-preview")
SAVE = "--nosave" not in args
RENDER = "--norender" not in args

CENTER = Vector((0.0, -0.005, 0.62))
RX, RY = 0.165, 0.2             # the old fixed oval, if there's no body to fit
TILT = math.radians(-11)        # front sits lower, under the chin
WIDTH, THICK = 0.05, 0.013      # strap height and thickness
GAP = 0.002                     # room between her neck and the strap's inside
ROT = Matrix.Rotation(TILT, 3, "X")
UP = ROT @ Vector((0, 0, 1))

scene = bpy.context.scene
for o in list(bpy.data.objects):
    if o.name.startswith("Collar"):
        bpy.data.objects.remove(o, do_unlink=True)


def mat(name, rgb, rough=0.55, metal=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    m.diffuse_color = (*rgb, 1)
    return m


def srgb(h):
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(h >> 16 & 255), lin(h >> 8 & 255), lin(h & 255))


ORANGE = mat("kittenCollar", srgb(0xFF7A12), rough=0.6)
STITCH = mat("kittenCollarStitch", srgb(0xFFE6B8), rough=0.8)
GOLD = mat("kittenBell", srgb(0xE8B63A), rough=0.28, metal=0.9)
SLIT = mat("kittenBellSlit", srgb(0x3A2A10), rough=0.8)


def new_obj(name, bm, material):
    me = bpy.data.meshes.new(name + "Mesh")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    scene.collection.objects.link(o)
    me.materials.append(material)
    for p in me.polygons:
        p.use_smooth = True
    return o


def neck_surfaces():
    """Ray trees for her body and head, or [] if this file has no kitten."""
    dg = bpy.context.evaluated_depsgraph_get()
    found = [bpy.data.objects.get(n) for n in ("Torso and haunches", "Head cheeks and short muzzle")]
    return [(BVHTree.FromObject(o, dg), o.matrix_world) for o in found if o is not None]


def fit_radii(steps=96):
    """The strap centerline's distance from CENTER at each of `steps` angles
    around her neck, snug to it, smoothed so the strap runs clean."""
    trees = neck_surfaces()
    if not trees:
        return None
    radii = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        d = ROT @ Vector((math.sin(t), math.cos(t), 0))
        outer = 0.0
        for lift in (-WIDTH * 0.45, 0.0, WIDTH * 0.45):
            c = CENTER + UP * lift
            for tree, mw in trees:
                inv = mw.inverted()
                hit = tree.ray_cast(inv @ (c + d * 0.6), (inv.to_3x3() @ -d).normalized(), 0.6)
                if hit[0] is not None:
                    outer = max(outer, ((mw @ hit[0]) - c).dot(d))
        radii.append(outer + GAP + THICK / 2)
    # Smooth over a few neighbors, but never inward of what was measured.
    return [max(radii[i], sum(radii[(i + k) % steps] for k in range(-3, 4)) / 7) for i in range(steps)]


RADII = fit_radii()


def centerline(t, lift=0.0):
    if RADII is None:
        x, y = RX * math.sin(t), RY * math.cos(t)
    else:
        f = (t / (2 * math.pi)) % 1 * len(RADII)
        i = int(f)
        r = RADII[i % len(RADII)] * (1 - (f - i)) + RADII[(i + 1) % len(RADII)] * (f - i)
        x, y = r * math.sin(t), r * math.cos(t)
    return Vector((x, y, lift))


def ring_point(t, lift=0.0):
    """Point on the strap centerline at angle t (0 = front), tilted, plus the
    outward normal in the same frame."""
    p = centerline(t, lift)
    # Outward normal: square to the strap's direction, in the collar's plane.
    e = 0.002
    along = centerline(t + e) - centerline(t - e)
    n = Vector((along.y, -along.x, 0)).normalized()
    if n.dot(Vector((p.x, p.y, 0))) < 0:
        n = -n
    return CENTER + ROT @ p, ROT @ n, UP


def profile(w, th, r=0.0045, steps=3):
    """Rounded rectangle, (outward, up) pairs."""
    hw, ht = w / 2, th / 2
    pts = []
    for cx, cz, a0 in ((ht - r, hw - r, 0), (-ht + r, hw - r, 90),
                       (-ht + r, -hw + r, 180), (ht - r, -hw + r, 270)):
        for k in range(steps + 1):
            a = math.radians(a0 + 90 * k / steps)
            pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return pts


def sweep(name, prof, material, t0=0, t1=2 * math.pi, segs=96, closed=True, grow=0.0):
    bm = bmesh.new()
    rings = []
    n = segs if closed else segs + 1
    for i in range(n):
        t = t0 + (t1 - t0) * i / segs
        c, nrm, up = ring_point(t)
        rings.append([bm.verts.new(c + nrm * (o + grow) + up * z) for o, z in prof])
    m = len(prof)
    for i in range(len(rings) if closed else len(rings) - 1):
        a, b = rings[i], rings[(i + 1) % len(rings)]
        for j in range(m):
            bm.faces.new((a[j], a[(j + 1) % m], b[(j + 1) % m], b[j]))
    if not closed:
        for r in (rings[0], rings[-1]):
            bm.faces.new(r)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_obj(name, bm, material)


# Strap, and a thin lighter stitch line along each edge (just proud of the surface).
sweep("Collar strap", profile(WIDTH, THICK), ORANGE)
for side, nm in ((1, "Collar stitch top"), (-1, "Collar stitch bottom")):
    s = 0.0016
    pf = [(THICK / 2 + 0.0008 + dx, side * (WIDTH / 2 - 0.0095) + dz)
          for dx, dz in ((s, s), (-s, s), (-s, -s), (s, -s))]
    sweep(nm, pf, STITCH, segs=120)

# Buckle: a gold frame on the strap, on her right side of the chest (t = 50 deg).
bt = math.radians(48)
c, nrm, up = ring_point(bt)
tang = nrm.cross(up)
bm = bmesh.new()
bmesh.ops.create_cube(bm, size=1.0)
for v in bm.verts:
    v.co = Vector((v.co.x * 0.014, v.co.y * 0.022, v.co.z * 0.044))   # x outward, y along, z up
bmesh.ops.bevel(bm, geom=list(bm.edges), offset=0.0025, segments=2, affect="EDGES")
buckle = new_obj("Collar buckle", bm, GOLD)
frame = Matrix((nrm, tang, up)).transposed()
buckle.matrix_world = Matrix.Translation(c + nrm * (THICK / 2 + 0.005)) @ frame.to_4x4()
buckle.name = "Collar buckle"

# Bell: dead front, hanging from a small ring through the strap.
c, nrm, up = ring_point(0.0)
R = 0.032
bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=14, radius=R)
bell = new_obj("Collar bell", bm, GOLD)
bell.location = c + nrm * (THICK / 2 + 0.012) + up * -(WIDTH / 2 + R * 0.55)
bell.name = "Collar bell"
# Hanging below a snug strap, the bell would sit in her chest fur: bring it
# forward until its back clears her (plus a little for the fur).
for tree, mw in neck_surfaces():
    inv = mw.inverted()
    hit = tree.ray_cast(inv @ (bell.location + nrm * 0.5), (inv.to_3x3() @ -nrm).normalized(), 0.6)
    if hit[0] is not None:
        clear = ((mw @ hit[0]) - bell.location).dot(nrm) + R + 0.006
        if clear > 0:
            bell.location += nrm * clear

# Slit: a dark thin band across the lower half of the bell, facing forward.
bm = bmesh.new()
bmesh.ops.create_cube(bm, size=1.0)
for v in bm.verts:
    v.co = Vector((v.co.x * 0.026, v.co.y * 0.012, v.co.z * 0.0045))
slit = new_obj("Collar bell slit", bm, SLIT)
slit.location = bell.location + Vector((0, R * 0.92, -R * 0.35))
slit.rotation_euler = (TILT * 0.0, 0, 0)

# Hanging loop: a small gold ring from strap to bell.
bm = bmesh.new()
bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=0.006, radius2=0.006, depth=0.026)
loop = new_obj("Collar bell loop", bm, GOLD)
loop.location = (c + nrm * (THICK / 2 + 0.008)) + up * -(WIDTH / 2 - 0.004)

bpy.context.view_layer.update()

# --------------------------------------------------------------------- preview
if SAVE:
    bpy.ops.wm.save_mainfile()
    print("saved", bpy.data.filepath)

if RENDER:
    os.makedirs(OUT, exist_ok=True)
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 700, 700
    scene.render.film_transparent = False
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = 16
    for shot, cam_name in (("front", "Front camera"), ("rear", "Rear camera")):
        cam = bpy.data.objects.get(cam_name)
        if cam is None:
            continue
        # Look at the neck so the collar fills the frame.
        cam.location = (0.0, 1.25, 0.95) if shot == "front" else (-0.35, -1.25, 1.05)
        d = CENTER + Vector((0, 0, 0.02)) - cam.location
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = 85
        scene.camera = cam
        scene.render.filepath = os.path.join(OUT, shot + ".png")
        bpy.ops.render.render(write_still=True)
        print("rendered", scene.render.filepath)
