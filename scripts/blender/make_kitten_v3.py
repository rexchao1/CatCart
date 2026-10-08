"""Cute natural-proportion kitten, revision 3.

Rex, 2026-10-08: "make the cat a lot cuter and more realistic, it looks like a
marshmallow right now." Revision 2 (make_kitten_realistic.py) got the anatomy
right but read as worried in the face, and in the game she was one smooth gray
blob. This revision keeps her a six-month lilac British Shorthair sitting up,
and changes what makes a kitten read as a kitten:

- a round moon face: full cheeks, puffy whisker pads, a short nose, a small chin,
- round golden eyes, a little low and wide on the face, with a painted iris,
  wide pupils, a dark rim, and two catchlights,
- a lilac-pink nose and inner ears (lilac cats have pink-mauve skin, not black),
- small rounded ears set wide, chunkier legs, and round mitten paws with toes,
- the coat painted in a color attribute ("Coat color"): paler muzzle, chin and
  chest, a touch darker on the crown, back, and tail,
- a "Fur length" attribute: long on the cheeks and chest, short on the face and
  paws. The game grows its fur shells from it (scripts/build_kitten.swift).

Run headless from the repo root (Blender 5.2 or the bpy module):
  Blender -b --python-exit-code 1 --python scripts/blender/make_kitten_v3.py -- OUTDIR [--quick] [--nofur] [--norender]

Writes OUTDIR/kitten-cute-v3.blend, OUTDIR/iris.png, and portrait, front, and
rear renders. --quick builds a coarser surface for fast previews, --nofur skips
the render-only strand fur, --norender only saves. The orange collar is added
by scripts/blender/add_collar.py afterward, as before.

Coordinates: Z up, she faces +Y, meters, origin at the middle of her seat with
the bottom of her body at Z = 0. export_kitten.py reads the same frame.
"""
import math
import random
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = Path(next((a for a in args if not a.startswith("--")), "art/options/kitten-cute-v3b")).resolve()
QUICK = "--quick" in args
FUR = "--nofur" not in args
RENDER = "--norender" not in args
OUT.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
rng = random.Random(73)


def lin(c):
    c /= 255
    return c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4


def hex_lin(h):
    return (lin(h >> 16 & 255), lin(h >> 8 & 255), lin(h & 255))


# ---------------------------------------------------------------- palette
# These are the study's render colors. The game reads the same hex values in
# scripts/build_kitten.swift, so a change here should go there too.
COAT_BASE = 0xA39CA2    # warm dove gray, a faint lilac cast
COAT_LIGHT = 0xD3CCCF   # muzzle, chin, chest
COAT_DARK = 0x8A838A    # crown, back, tail
EAR_SKIN = 0xD8A7B0     # pale pink-mauve inside the ears
NOSE = 0xC08A96         # lilac-pink nose leather
LINE = 0x5E4C55         # lid rims and mouth: dark mauve, softer than black
WHISKER = 0xF4F1EC


def material(name, rgb, rough=.7):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*hex_lin(rgb), 1)
    b.inputs["Roughness"].default_value = rough
    m.diffuse_color = (*hex_lin(rgb), 1)
    return m


# Material names are the game's, so the exporter needs no renaming table.
coat = material("kittenCoat", COAT_BASE)
inner = material("kittenEarInner", EAR_SKIN, .6)
nosemat = material("kittenNose", NOSE, .42)
linemat = material("kittenMouth", LINE, .5)
whiskermat = material("kittenWhisker", WHISKER, .5)
shinemat = material("kittenShine", 0xFFFFFF, .2)
creasemat = material("kittenCrease", 0x6F676E, .8)
eyemat = material("kittenEye", 0xD8A040, .12)

# The coat reads its color from the painted attribute, with a fine bump so the
# study renders as short plush fur even without the strand fur.
nt = coat.node_tree
bsdf = nt.nodes["Principled BSDF"]
attr = nt.nodes.new("ShaderNodeAttribute")
attr.attribute_name = "Coat color"
# The attribute holds the game's colors, which are brighter than a studio
# render wants (the game's lights are flatter), so the study dims them.
dim = nt.nodes.new("ShaderNodeMix")
dim.data_type = "RGBA"
dim.blend_type = "MULTIPLY"
dim.inputs["Factor"].default_value = 1
dim.inputs["B"].default_value = (.48, .48, .48, 1)
nt.links.new(attr.outputs["Color"], dim.inputs["A"])
nt.links.new(dim.outputs["Result"], bsdf.inputs["Base Color"])
bsdf.inputs["Sheen Weight"].default_value = .35
bsdf.inputs["Sheen Roughness"].default_value = .35
noise = nt.nodes.new("ShaderNodeTexNoise")
noise.inputs["Scale"].default_value = 160
bump = nt.nodes.new("ShaderNodeBump")
bump.inputs["Strength"].default_value = .18
bump.inputs["Distance"].default_value = .003
nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

shine_b = shinemat.node_tree.nodes["Principled BSDF"]
shine_b.inputs["Emission Color"].default_value = (1, 1, 1, 1)
shine_b.inputs["Emission Strength"].default_value = 2.5

coat_objects = []


def smooth(obj):
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def ell(name, center, scale, mat=coat, segments=40, rings=28):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return smooth(obj)


def fuse(name, parts, voxel=.005):
    """Joins soft shapes into one continuous surface: remesh, then relax."""
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = parts[0]
    obj.name = name
    obj.data.name = name + " mesh"
    # Bake the joined shapes' offsets into the vertices, so every coordinate
    # below (sockets, paint, raycasts) is in the kitten frame.
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mod = obj.modifiers.new("Continuous anatomy", "REMESH")
    mod.mode = "VOXEL"
    mod.voxel_size = voxel * (1.8 if QUICK else 1)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mod = obj.modifiers.new("Soften transitions", "SMOOTH")
    mod.factor = .55
    mod.iterations = 9
    bpy.ops.object.modifier_apply(modifier=mod.name)
    smooth(obj)
    coat_objects.append(obj)
    return obj


def curve(name, pts, radius, mat, taper=True, res=10):
    data = bpy.data.curves.new(name, "CURVE")
    data.dimensions = "3D"
    data.resolution_u = res
    data.bevel_depth = radius
    data.bevel_resolution = 3
    data.use_fill_caps = True
    spline = data.splines.new("BEZIER")
    spline.bezier_points.add(len(pts) - 1)
    for i, (p, co) in enumerate(zip(spline.bezier_points, pts)):
        p.co = co
        p.handle_left_type = p.handle_right_type = "AUTO"
        p.radius = (1 - i / (len(pts) - 1) * .85) if taper else 1
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    data.materials.append(mat)
    return obj


def bvh(obj):
    m = obj.matrix_world
    return BVHTree.FromPolygons([m @ v.co for v in obj.data.vertices],
                                [p.vertices[:] for p in obj.data.polygons])


# ---------------------------------------------------------------- body
# Seated, weight over the folded haunches, chest a little puffed out (kittens
# have a soft bib), front legs straight down to round paws.
body = fuse("Torso and haunches", [
    ell("Pelvis", (0, -.12, .25), (.25, .265, .255)),
    ell("Ribcage", (0, -.03, .43), (.198, .22, .29)),
    ell("Chest bib", (0, .055, .50), (.158, .15, .19)),
    ell("Shoulders", (0, .025, .58), (.155, .165, .205)),
    ell("Neck", (0, .06, .67), (.134, .14, .18)),
    ell("Left folded thigh", (-.184, -.06, .19), (.14, .21, .185)),
    ell("Right folded thigh", (.184, -.06, .19), (.14, .21, .185)),
    ell("Left rear foot", (-.208, .085, .056), (.09, .15, .058)),
    ell("Right rear foot", (.208, .085, .056), (.09, .15, .058)),
])
for side in (-1, 1):
    fuse("Left foreleg" if side < 0 else "Right foreleg", [
        ell("Upper foreleg", (side * .095, .11, .36), (.072, .088, .19)),
        ell("Forearm", (side * .098, .172, .19), (.059, .064, .17)),
        ell("Front paw", (side * .102, .214, .052), (.075, .103, .055)),
    ], .0035)
    # Three soft creases make four toes on each mitten.
    for dx in (-.028, 0, .028):
        x = side * .102 + dx
        curve("Toe crease", [(x, .313, .036), (x, .306, .062), (x, .29, .078)], .0019, creasemat, res=4)

# ---------------------------------------------------------------- head
# A British Shorthair kitten's face is a circle: wide cheeks, a short muzzle
# made of two puffy whisker pads, and a nose set high between them.
head = fuse("Head cheeks and short muzzle", [
    ell("Skull", (0, .07, .79), (.214, .185, .19)),
    ell("Left cheek", (-.11, .118, .714), (.11, .12, .108)),
    ell("Right cheek", (.11, .118, .714), (.11, .12, .108)),
    ell("Jaw", (0, .14, .668), (.125, .105, .062)),
    ell("Nose bridge", (0, .222, .752), (.05, .052, .085)),
    ell("Left whisker pad", (-.04, .257, .684), (.058, .049, .045)),
    ell("Right whisker pad", (.04, .257, .684), (.058, .049, .045)),
    ell("Chin", (0, .234, .644), (.058, .045, .029)),
], .003)
# A softer forehead than a cartoon dome, rounder than revision 2's flat top.
for v in head.data.vertices:
    if v.co.z > .82:
        v.co.z -= (v.co.z - .82) * .14

# ---------------------------------------------------------------- eyes
# Each eye is a domed cap with a painted iris (iris.png). The face behind the
# opening is pushed back into a socket, so the cap sits in the head instead of
# on it, and a dark rim and a furred lid cover the join. Big, round, and a bit
# low and wide is what reads as a kitten; the slight outward turn is real.
EYE_X, EYE_Y0, EYE_Z = .103, .30, .772
# Rex, 2026-10-08: "make its eyes smaller" (they were .058 by .054 with a .024
# dome; that take is in art/options/kitten-cute-v3).
EYE_A, EYE_B = .048, .045          # half width and half height of the opening
DOME = .02                         # how far the cornea bulges
TURN, LIFT = math.radians(17), math.radians(5)


def eye_frame(side):
    """Rotation from eye space (x out, y forward, z up) to the kitten."""
    rz = Matrix.Rotation(-side * TURN, 3, "Z")
    rx = Matrix.Rotation(LIFT, 3, "X")
    flip = Matrix(((side, 0, 0), (0, 1, 0), (0, 0, 1)))
    return rz @ rx @ flip


def outline(t):
    """The eye opening at angle t, in eye space: round, the outer corner a touch up."""
    x = EYE_A * math.cos(t)
    z = EYE_B * math.sin(t) * abs(math.sin(t)) ** .1
    return x, z + x * .07


head_tree = bvh(head)
eye_centers = {}
for side in (-1, 1):
    frame = eye_frame(side)
    fwd = frame @ Vector((0, 1, 0))
    start = Vector((side * EYE_X, EYE_Y0, EYE_Z))
    hit, *_ = head_tree.ray_cast(start, -fwd)
    # Sink the cap so its rim is just under the face and its top stands out.
    c = hit - fwd * (DOME * .35)
    eye_centers[side] = c

    rings, steps = 22, 96
    verts, uvs = [c + fwd * DOME], [(.5, .5)]
    for k in range(1, rings + 1):
        r = k / rings
        for j in range(steps):
            t = 2 * math.pi * j / steps
            x, z = outline(t)
            x, z = x * r, z * r
            h = DOME * (1 - r * r)
            verts.append(c + frame @ Vector((x, h, z)))
            # The iris picture covers the opening. u runs outward for both eyes,
            # so the painted lid shadow and fibers mirror like a real face.
            uvs.append((.5 + .5 * r * math.cos(t), .5 + .5 * r * math.sin(t)))
    faces = [(0, 1 + j, 1 + (j + 1) % steps) for j in range(steps)]
    for k in range(rings - 1):
        for j in range(steps):
            a = 1 + k * steps + j
            b = 1 + k * steps + (j + 1) % steps
            # Same turning direction as the center fan: out, along, back in.
            faces.append((a, a + steps, b + steps, b))
    # Faces must point out of the eye, toward the viewer (the game culls back
    # faces). Mirroring for the left eye flips the winding, so check it.
    a0, a1, a2 = (verts[i] for i in faces[0])
    if (a1 - a0).cross(a2 - a0) @ fwd < 0:
        faces = [f[::-1] for f in faces]
    mesh = bpy.data.meshes.new("Eye cap mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    uv = mesh.uv_layers.new(name="UVMap")
    for p in mesh.polygons:
        for li in p.loop_indices:
            uv.data[li].uv = uvs[mesh.loops[li].vertex_index]
    mesh.materials.append(eyemat)
    eye = bpy.data.objects.new("Left eye" if side < 0 else "Right eye", mesh)
    scene.collection.objects.link(eye)
    eye["pivot"] = c          # the game blinks each eye around this point
    smooth(eye)

    # The socket: face vertices in front of the cap move behind it.
    inv = frame.inverted()
    for v in head.data.vertices:
        local = inv @ (v.co - c)
        x, z = local.x, local.z
        q = (x / (EYE_A * 1.08)) ** 2 + ((z - x * .07) / (EYE_B * 1.08)) ** 2
        if q < 1:
            r2 = min(1, q)
            surface = DOME * (1 - r2) - .006
            if local.y > surface:
                v.co = c + frame @ Vector((x, surface, z))

    # Catchlights: a big soft one up and toward her left on both eyes (the
    # same window lights both), and a small one low on the other side.
    shine = EYE_A / .058           # catchlights shrink with the eye
    for name, (wx, wz, rx, rz) in (("Eye shine", (-.30, .40, .0125 * shine, .0105 * shine)),
                                   ("Eye shine small", (.36, -.30, .0055 * shine, .0048 * shine))):
        lx = wx * EYE_A * side          # world-left for both eyes
        lz = wz * EYE_B
        r = min(1, math.hypot(lx / EYE_A, lz / EYE_B))
        p = c + frame @ Vector((lx, DOME * (1 - r * r) + .0012, lz))
        n = (frame @ Vector((2 * lx * DOME / EYE_A ** 2, 1, 2 * lz * DOME / EYE_B ** 2))).normalized()
        bpy.ops.mesh.primitive_circle_add(vertices=14, radius=1, fill_type="TRIFAN", location=(0, 0, 0))
        disc = bpy.context.object
        disc.name = name
        disc.scale = (rx, rz, 1)
        bpy.ops.object.transform_apply(scale=True)
        # The circle faces +Z; turn it to face along the cap's normal there.
        disc.matrix_world = Matrix.Translation(p) @ n.to_track_quat("Z", "Y").to_matrix().to_4x4()
        disc.data.materials.append(shinemat)
        smooth(disc)

    # Lid rim (dark, like every cat's) and a furred lid just outside it.
    for k, (r, rad, mat, nm) in enumerate(((1.0, .0042, linemat, "Eye rim"),
                                           (1.07, .0062, coat, "Furred lid"))):
        pts = []
        for j in range(25):
            t = 2 * math.pi * j / 24
            x, z = outline(t)
            pts.append(c + frame @ Vector((x * r, .0012 + k * .002, z * r)))
        rim = curve(nm, pts[:-1], rad, mat, taper=False, res=3)
        rim.data.splines[0].use_cyclic_u = True
        if mat is coat:
            bpy.ops.object.select_all(action="DESELECT")
            rim.select_set(True)
            bpy.context.view_layer.objects.active = rim
            bpy.ops.object.convert(target="MESH")
            coat_objects.append(bpy.context.object)

head_tree = bvh(head)

# ---------------------------------------------------------------- nose and mouth
# A small shield-shaped nose, wider at the top, set high on the muzzle.
hit, *_ = head_tree.ray_cast(Vector((0, .6, .705)), Vector((0, -1, 0)))
ny, nz = hit.y, .705
W = .036
verts = [(-W, ny - .004, nz + .012), (W, ny - .004, nz + .012), (W * .56, ny + .014, nz),
         (0, ny + .02, nz - .021), (-W * .56, ny + .014, nz), (-W * .7, ny - .012, nz - .006),
         (W * .7, ny - .012, nz - .006), (0, ny - .006, nz - .026)]
faces = [(0, 1, 2, 3, 4), (0, 5, 6, 1), (5, 7, 6), (0, 4, 3, 7, 5), (1, 6, 7, 3, 2)]
mesh = bpy.data.meshes.new("Nose mesh")
mesh.from_pydata(verts, [], faces)
mesh.validate()
mesh.materials.append(nosemat)
nose = bpy.data.objects.new("Nose", mesh)
scene.collection.objects.link(nose)
mod = nose.modifiers.new("Soft nose edges", "BEVEL")
mod.width = .0065
mod.segments = 3
mod = nose.modifiers.new("Rounded nose", "SUBSURF")
mod.levels = 1
smooth(nose)
for side in (-1, 1):
    ell("Nostril", (side * .016, ny + .012, nz - .006), (.0068, .0032, .0034), linemat, 12, 8)

# Mouth: a short line down from the nose, then a soft upturned curve each side.
mouth_top = Vector((0, ny + .012, nz - .025))
for side in (-1, 1):
    pts = [(0, mouth_top.y, mouth_top.z), (0, mouth_top.y - .002, mouth_top.z - .016),
           (side * .018, mouth_top.y - .010, mouth_top.z - .025), (side * .036, mouth_top.y - .024, mouth_top.z - .02)]
    pts = [Vector(p) for p in pts]
    # Lay each point onto the face so the line follows the muzzle.
    snapped = []
    for p in pts:
        h, *_ = head_tree.ray_cast(p + Vector((0, .08, 0)), Vector((0, -1, 0)))
        snapped.append((h or p) + Vector((0, .0015, 0)))
    curve("Mouth line", snapped, .0019, linemat, res=6)

# Whiskers: long, white, fanning from the pads with a gentle droop.
for side in (-1, 1):
    for i in range(6):
        z = .676 + (i - 2.5) * .0062
        x = side * (.048 + (i % 2) * .01)
        h, *_ = head_tree.ray_cast(Vector((x, .6, z)), Vector((0, -1, 0)))
        y = h.y - .003 if h else .29
        spread = (i - 2.5)
        curve("Whisker", [(x, y, z), (side * .11, y + .012, z + .004 + spread * .004),
                          (side * .2, y - .002, z + spread * .014),
                          (side * (.29 + (.02 if i % 2 else 0)), y - .04, z + spread * .026 - .012)],
              .0007, whiskermat)
    # Three short brow whiskers over each eye, up and out.
    for i in range(3):
        x0 = side * (.085 + i * .016)
        h, *_ = head_tree.ray_cast(Vector((x0, .6, .842)), Vector((0, -1, 0)))
        y0 = (h.y if h else .24) - .002
        curve("Brow whisker", [(x0, y0, .842), (x0 + side * .03, y0 + .02, .875 + i * .004),
                               (x0 + side * .065, y0 + .02, .9 + i * .008)], .0005, whiskermat)

# ---------------------------------------------------------------- ears
# Small, round-tipped, set wide on the skull, tipped a little out and forward.
# Each is a cupped shell: a thick furred rim and a pink, recessed bowl. Ear
# space is x across (outward), y forward, z up, mirrored for the left ear.
EAR_X = .16
for side in (-1, 1):
    hit, *_ = head_tree.ray_cast(Vector((side * EAR_X, .045, 1.3)), Vector((0, 0, -1)))
    base = hit - Vector((0, 0, .014))
    outline_pts = []
    for j in range(17):
        a = math.pi * j / 16
        x = -.062 * math.cos(a)
        # Round shoulders up to a soft, round tip.
        z = .104 * math.sin(a) ** 1.25
        x += .014 * math.sin(a) ** 3       # the tip leans outward
        outline_pts.append(Vector((x, 0, z)))
    verts, faces, mats = [], [], []
    center = Vector((.004, .012, .04))
    n = len(outline_pts)
    for r in (1, .82, .58, .3):
        for q in outline_pts:
            p = q * r + center * (1 - r)
            p.y -= (1 - r) * .024            # the bowl dips back
            verts.append(p)
    verts.append(center + Vector((0, -.028, 0)))
    for ring in range(3):
        for j in range(n - 1):
            faces.append((ring * n + j, ring * n + j + 1, (ring + 1) * n + j + 1, (ring + 1) * n + j))
            mats.append(0 if ring == 0 else 1)
    for j in range(n - 1):
        faces.append((3 * n + j, 3 * n + j + 1, 4 * n))
        mats.append(1)
    if side < 0:
        # Mirroring turns faces inside out; turn them back so the pink bowl
        # faces forward on both ears.
        faces = [f[::-1] for f in faces]
    flip = Matrix(((side, 0, 0), (0, 1, 0), (0, 0, 1)))
    frame = Matrix.Rotation(side * math.radians(10), 3, "Y") @ Matrix.Rotation(-side * math.radians(12), 3, "Z") \
        @ Matrix.Rotation(math.radians(-8), 3, "X") @ flip
    placed = []
    for v in verts:
        w = base + frame @ v
        # Bend the base onto the skull: the head curves down toward the side,
        # so without this the outer corner of the ear floats above it.
        h, *_ = head_tree.ray_cast(Vector((w.x, w.y, 1.3)), Vector((0, 0, -1)))
        if h is not None:
            w.z += (h.z - .014 - base.z) * max(0, 1 - v.z / .06)
        placed.append(w)
    mesh = bpy.data.meshes.new("Cupped ear mesh")
    mesh.from_pydata(placed, [], faces)
    mesh.materials.append(coat)
    mesh.materials.append(inner)
    obj = bpy.data.objects.new("Left ear" if side < 0 else "Right ear", mesh)
    scene.collection.objects.link(obj)
    obj["pivot"] = base           # the game flicks each ear around its base
    for p, m in zip(mesh.polygons, mats):
        p.material_index = m
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new("Rounded ear contour", "SUBSURF")
    mod.levels = 2
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mod = obj.modifiers.new("Ear thickness", "SOLIDIFY")
    mod.thickness = .016
    mod.offset = -1
    mod.material_offset = -1
    bpy.ops.object.modifier_apply(modifier=mod.name)
    smooth(obj)
    coat_objects.append(obj)

# ---------------------------------------------------------------- tails
# The study's tail is thick with a round tip, curled forward beside her feet.
tail = curve("Resting tail", [(.08, -.30, .118), (.28, -.28, .075), (.355, -.08, .06), (.32, .16, .052),
                              (.23, .295, .046), (.08, .34, .043)], .064, coat, False)
bpy.context.view_layer.objects.active = tail
bpy.ops.object.select_all(action="DESELECT")
tail.select_set(True)
bpy.ops.object.convert(target="MESH")
tail_mesh = bpy.context.object
fuse("Rounded resting tail", [tail_mesh, ell("Rounded tail tip", (.08, .34, .043), (.064, .064, .058))], .0035)

# The game's tail is held up over the back of the box instead, so the La Croix
# name stays readable and the game can sway it. It's split at JOINT so the tip
# swings on its own. Hidden in the renders; export_kitten.py uses it.
GAME_TAIL_JOINT = (0.13, -0.49, 0.5)
GAME_TAIL = [(0.0, -0.3, 0.1), (0.05, -0.39, 0.22), (0.1, -0.46, 0.38), GAME_TAIL_JOINT]
GAME_TAIL_TIP = [GAME_TAIL_JOINT, (0.15, -0.54, 0.46), (0.165, -0.575, 0.36), (0.18, -0.592, 0.285)]


def game_tail(name, path, r0, r1):
    """A chain of spheres along a smooth path, fused into one tube."""
    pts = [Vector(p) for p in path]
    samples = []
    for i in range(len(pts) - 1):
        p0, p1, p2, p3 = pts[max(i - 1, 0)], pts[i], pts[i + 1], pts[min(i + 2, len(pts) - 1)]
        steps = max(2, int((p2 - p1).length / .016))
        for k in range(steps):
            t = k / steps
            samples.append(.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                                 + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    samples.append(pts[-1])
    balls = [ell("Tail bead", q, (r0 + (r1 - r0) * i / (len(samples) - 1),) * 3, segments=16, rings=10)
             for i, q in enumerate(samples)]
    obj = fuse(name, balls, .006)
    obj.hide_render = True
    obj["pivot"] = pts[0]
    return obj


game_tail("Game tail", GAME_TAIL, .066, .062)
game_tail("Game tail tip", GAME_TAIL_TIP, .062, .056)

# ---------------------------------------------------------------- coat paint
# One function paints every coat surface into attributes on the mesh, which
# export_kitten.py carries into the game, so the study and the game agree.
# p and n are in the kitten frame.


def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0), 1)
    return t * t * (3 - 2 * t)


def mixc(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


BASE, LIGHT, DARK = hex_lin(COAT_BASE), hex_lin(COAT_LIGHT), hex_lin(COAT_DARK)
COLLAR_CENTER = Vector((0, -.005, .62))
COLLAR_UP = Matrix.Rotation(math.radians(-11), 3, "X") @ Vector((0, 0, 1))
MUZZLE = Vector((0, .27, .675))
CHEST = Vector((0, .16, .48))


def coat_paint(p, n):
    """(color, fur length) for a point p with normal n, both in the kitten frame.
    Fur length is a factor on the game's shell depth: 1 is the back of her coat."""
    c = BASE
    fur = 1.0
    on_head = p.z > .6 and p.y > -.2
    if on_head:
        # Crown and back of the head a touch darker, muzzle and chin pale.
        c = mixc(c, DARK, smoothstep(.55, 1, n.z) * .35 + smoothstep(.2, .9, -n.y) * .3)
        d = (p - MUZZLE).length
        c = mixc(c, LIGHT, smoothstep(.12, .045, d) * .9)
        c = mixc(c, LIGHT, smoothstep(.69, .63, p.z) * smoothstep(.0, .5, n.y) * .7)
        # Fur: short on the face front, plush on the cheeks.
        fur = .45 + .75 * smoothstep(.08, .16, abs(p.x)) * smoothstep(.85, .7, p.z)
        fur = max(fur, .9 * smoothstep(.3, -.4, n.y))   # back of the head
        fur = max(fur, .8 * smoothstep(.4, .9, n.z))      # crown
        eye = min((p - eye_centers[-1]).length, (p - eye_centers[1]).length)
        fur = min(fur, .25 + 6 * (eye - EYE_A - .007))
        fur = max(fur, .25)
        # Shortest around the mouth and nose, so the mouth line still shows.
        fur = min(fur, .2 + 4 * max(0, d - .03))
    else:
        back = smoothstep(.0, .8, -n.y) * .55 + smoothstep(.55, 1, n.z) * .3 * smoothstep(.3, .6, p.z)
        c = mixc(c, DARK, min(back, .7))
        bib = smoothstep(.0, .6, n.y) * smoothstep(.17, .06, abs(p.x)) * smoothstep(.22, .36, p.z) \
            * smoothstep(.66, .52, p.z)
        c = mixc(c, LIGHT, bib * .75)
        fur = 1.0 + .45 * bib
        if p.z < .12 and p.y > .1:      # paws
            fur = .55
    # The collar is snug in the fur around her neck: keep the fur short in the
    # band it covers. The band tilts with the collar (front lower); CENTER and
    # TILT match scripts/blender/add_collar.py.
    collar = p - COLLAR_CENTER
    if abs(collar.dot(COLLAR_UP)) < .045 and abs(p.y) < .26:
        fur = min(fur, .3)
    # A soft shade underneath, like light that doesn't reach.
    shade = 1 - .16 * smoothstep(.2, 1, -n.z)
    # A little low-frequency variation so it isn't one flat color.
    wobble = 1 + .035 * math.sin(p.x * 31 + p.z * 17) * math.sin(p.y * 23 - p.z * 11)
    return tuple(min(1, v * shade * wobble) for v in c), fur


def paint(obj, tail_dark=False, ear=False):
    me = obj.data
    col = me.color_attributes.get("Coat color") or me.color_attributes.new("Coat color", "FLOAT_COLOR", "POINT")
    fur = me.attributes.get("Fur length") or me.attributes.new("Fur length", "FLOAT", "POINT")
    m = obj.matrix_world
    nm = m.to_3x3().inverted().transposed()
    for i, v in enumerate(me.vertices):
        c, f = coat_paint(m @ v.co, (nm @ v.normal).normalized())
        if tail_dark:
            c = mixc(c, DARK, .45)
            f = 1.05
        if ear:
            f = .35      # short fur on the ears, so they keep their thin shape
        col.data[i].color = (*c, 1)
        fur.data[i].value = f


for o in coat_objects:
    paint(o, tail_dark="tail" in o.name.lower(), ear=o.name.endswith(" ear"))
    if o.name == "Head cheeks and short muzzle":
        o["pivot"] = (0, .02, .64)       # her neck: the game leans her head here

# ---------------------------------------------------------------- iris


def make_iris(path, size=512):
    """Paints the iris: warm gold with fibers, a dark outer ring, a big soft
    pupil, and the shadow of the upper lid. It is the whole visible eye; cats
    show almost no white. Saved as an sRGB PNG the game embeds too."""
    rs = np.random.default_rng(11)
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    u = (x + .5) / size * 2 - 1
    v = 1 - (y + .5) / size * 2          # +v is up
    r = np.sqrt(u * u + v * v)
    th = np.arctan2(v, u)

    def srgb_hex(h):
        return np.array([(h >> 16 & 255), (h >> 8 & 255), (h & 255)], np.float32) / 255

    inner_c, mid_c, outer_c, ring_c = (srgb_hex(0xF6D35E), srgb_hex(0xE2A93A),
                                       srgb_hex(0xBF7A22), srgb_hex(0x4A2E12))
    t1 = np.clip((r - .35) / .3, 0, 1)[..., None]
    t2 = np.clip((r - .62) / .26, 0, 1)[..., None]
    col = inner_c * (1 - t1) + mid_c * t1
    col = col * (1 - t2) + outer_c * t2
    # Fibers: streaks running out from the pupil.
    fib = np.zeros_like(r)
    for freq in (23, 41, 67, 109, 173):
        phase = rs.uniform(0, 2 * np.pi, 3)
        fib += np.sin(th * freq + phase[0] + np.sin(r * 9 + phase[1]) * .6) / math.sqrt(freq)
    fib /= np.abs(fib).max()
    col *= (1 + .16 * fib)[..., None]
    # A bright, jagged collarette just outside the pupil.
    coll = np.exp(-((r - (.5 + .03 * np.sin(th * 13))) / .05) ** 2)
    col = col * (1 - .25 * coll[..., None]) + srgb_hex(0xFFE59A) * .25 * coll[..., None]
    # The dark limbal ring at the edge.
    ring = np.clip((r - .86) / .14, 0, 1)[..., None] ** 1.3
    col = col * (1 - ring) + ring_c * ring
    # Pupil: a tall soft oval, wide like an excited kitten's.
    pr = np.sqrt((u / .37) ** 2 + (v / .47) ** 2)
    pupil = np.clip((1.06 - pr) / .12, 0, 1)[..., None]
    col = col * (1 - pupil) + srgb_hex(0x0D0B0E) * pupil
    # The upper lid's shadow across the top of the eye.
    lid = np.clip((v - .25) / .75, 0, 1) ** 1.4
    col *= (1 - .45 * lid)[..., None]
    col = np.clip(col, 0, 1)
    img = bpy.data.images.new("iris", size, size, alpha=False)
    rgba = np.concatenate([col, np.ones_like(r)[..., None]], axis=-1)
    # Blender images are bottom row first.
    img.pixels.foreach_set(rgba[::-1].astype(np.float32).ravel())
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()
    # Packed into the .blend, so the file carries its own iris.
    img.source = "FILE"
    img.pack()
    return img


iris = make_iris(OUT / "iris.png")
nt = eyemat.node_tree
b = nt.nodes["Principled BSDF"]
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = iris
nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
b.inputs["Coat Weight"].default_value = 1
b.inputs["Coat Roughness"].default_value = .03
b.inputs["Coat IOR"].default_value = 1.38

# ---------------------------------------------------------------- strand fur (render only)
# Fine tapered fibers so the study renders like a plush kitten. The game never
# sees these; it grows shell fur from "Fur length" instead.
if FUR:
    fur_mats = [material("Fur shade " + str(i), v, .84) for i, v in
                enumerate((0x9C959B, 0xA59EA4, 0xB0A9AE, 0xBDB6BA))]
    verts, faces, idx = [], [], []
    for obj in coat_objects:
        if obj.hide_render:
            continue
        me = obj.data
        me.calc_loop_triangles()
        mw = obj.matrix_world
        nm = mw.to_3x3().inverted().transposed()
        col = me.color_attributes["Coat color"]
        furlen = me.attributes["Fur length"]
        for tri in me.loop_triangles:
            if me.materials[tri.material_index] != coat:
                continue
            a, b2, c2 = [mw @ me.vertices[i].co for i in tri.vertices]
            area = (b2 - a).cross(c2 - a).length * .5
            count = int(area * 48000 + rng.random())
            ns = [(nm @ me.vertices[i].normal).normalized() for i in tri.vertices]
            fl = sum(furlen.data[i].value for i in tri.vertices) / 3
            light = sum(col.data[i].color[0] for i in tri.vertices) / 3
            for _ in range(count):
                u_, v_ = rng.random(), rng.random()
                if u_ + v_ > 1:
                    u_, v_ = 1 - u_, 1 - v_
                p = a + u_ * (b2 - a) + v_ * (c2 - a)
                n = (ns[0] * (1 - u_ - v_) + ns[1] * u_ + ns[2] * v_).normalized()
                direction = Vector((p.x * .3, 0, -.8)) if p.z < .63 else Vector((p.x * 2, -.2, -.18))
                tangent = (direction - n * direction.dot(n)).normalized()
                length = rng.uniform(.007, .016) * fl
                along = (n * .75 + tangent * .65).normalized()
                across = along.cross(Vector((.13, .73, .31))).normalized()
                width = rng.uniform(.00016, .0003)
                i0 = len(verts)
                verts.extend((p - across * width, p + across * width, p + along * length * .55 + n * .001,
                              p + along * length))
                faces.extend(((i0, i0 + 1, i0 + 2), (i0 + 1, i0 + 3, i0 + 2)))
                shade = min(3, max(0, int((light - BASE[0]) * 40 + 1.5 + rng.random() * 1.2)))
                idx.extend((shade, shade))
    mesh = bpy.data.meshes.new("Directional short fur mesh")
    mesh.from_pydata(verts, [], faces)
    for m in fur_mats:
        mesh.materials.append(m)
    for face, i in zip(mesh.polygons, idx):
        face.material_index = i
    obj = bpy.data.objects.new("Directional short fur", mesh)
    scene.collection.objects.link(obj)

# ---------------------------------------------------------------- collar
# The orange collar and gold bell come from add_collar.py, unchanged: the neck
# is the same size as revision 2's, which it was fitted to.
collar_script = Path(__file__).with_name("add_collar.py")
saved_argv = sys.argv
sys.argv = ["blender", "--", str(OUT), "--nosave", "--norender"]
exec(compile(collar_script.read_text(), str(collar_script), "exec"),
     {"__name__": "__main__", "__file__": str(collar_script)})
sys.argv = saved_argv

# ---------------------------------------------------------------- studio
floor_mat = material("Warm studio floor", 0xB2B0A6)
ell("Low display cushion", (0, 0, -.035), (.63, .59, .047), floor_mat)
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.061))
bpy.context.object.name = "Studio floor"
bpy.context.object.data.materials.append(floor_mat)


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def camera(name, loc, target, scale):
    data = bpy.data.cameras.new(name)
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = loc
    aim(obj, target)
    data.type = "ORTHO"
    data.ortho_scale = scale
    return obj


hero = camera("Portrait camera", (1.1, 3, 1.5), (0, .035, .49), 1.43)
front = camera("Front camera", (0, 3, 1.2), (0, .04, .51), 1.38)
face = camera("Face camera", (.35, 3, .95), (0, .1, .76), .62)
rear = camera("Rear camera", (-1.6, -3, 1.5), (0, 0, .5), 1.43)
for name, loc, power, size, rgb in (
        ("Window key", (-2, 3, 3), 170, 2.3, (1, .94, .88)),
        ("Soft fill", (2, 1, 1.7), 55, 2, (.85, .91, 1)),
        ("Fur rim", (.7, -2, 2.5), 150, 1.7, (1, .94, .87))):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = power
    data.shape = "DISK"
    data.size = size
    data.color = rgb
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = loc
    aim(obj, (0, 0, .5))
scene.world = bpy.data.worlds.new("Studio world")
scene.world.color = (.13, .13, .13)
scene.render.engine = "CYCLES"
scene.cycles.samples = 24 if QUICK else 64
scene.cycles.use_denoising = True
scene.render.resolution_x = scene.render.resolution_y = 640 if QUICK else 1200
scene.view_settings.view_transform = "AgX"
scene.render.image_settings.file_format = "PNG"
scene.camera = hero

bpy.context.preferences.filepaths.save_version = 0
blend = OUT / "kitten-cute-v3.blend"
bpy.ops.wm.save_as_mainfile(filepath=str(blend))
print("saved", blend)
if RENDER:
    for cam, name in ((hero, "portrait"), (front, "front"), (face, "face"), (rear, "rear")):
        scene.camera = cam
        scene.render.filepath = str(OUT / (name + ".png"))
        bpy.ops.render.render(write_still=True)
print("Study complete:", OUT)
