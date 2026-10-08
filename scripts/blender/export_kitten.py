# Turns the kitten study (art/models/kitten/cat.blend, built by
# scripts/blender/make_kitten_v3.py) into the game kitten: kitten.json plus the
# pictures it uses, which scripts/build_kitten.swift packs into
# CatCart/Models/cat_kitten.scn. scripts/build_kitten.sh runs both:
#
#   Blender -b art/models/kitten/cat.blend --python-exit-code 1 \
#       --python scripts/blender/export_kitten.py -- /tmp/kitten
#   swiftc -O -o /tmp/build_kitten scripts/build_kitten.swift
#   /tmp/build_kitten /tmp/kitten/kitten.json CatCart/Models/cat_kitten.scn
#
# The .blend is a render study: half a million triangles, strand fur, a studio,
# and a tail curled on the floor. A phone game wants about 25k triangles in
# named parts it can animate, so this script:
# - deletes the studio, the strand fur, and the resting tail (the study keeps a
#   hidden "Game tail" held up over the box, which is used instead),
# - turns the thin curves (whiskers, lid rims, mouth) into light meshes,
# - cuts each part down to a triangle budget,
# - groups everything into kitten > body > head > (earL, earR, eyeL, eyeR) and
#   body > tail > tailTip, each with its pivot at its joint (the study stores
#   the joints as "pivot" properties on the objects),
# - darkens the coat where light can't reach (under her chin, between her legs,
#   behind the collar) by casting rays from each corner of the mesh,
# - writes, per part and material: positions, normals, colors, texture
#   coordinates, the painted fur length, and which way the fur lies.
#
# Coordinates: Blender is Z up with her facing +Y. SceneKit is Y up and she
# must face -Z, so every position and normal goes (x, y, z) -> (x, z, -y).
# Units are meters. The coat's texture coordinates are meters too, measured
# across the kitten: the fur shader lays its grid of tufts in them.

import bpy
import json
import math
import random
import sys
from pathlib import Path

import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

OUT = Path(sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "/tmp/kitten")
OUT.mkdir(parents=True, exist_ok=True)
scene = bpy.context.scene
objects = bpy.data.objects


def delete(o):
    bpy.data.objects.remove(o, do_unlink=True)


def select_only(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def tris(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


# ---------------------------------------------------------------- clear the studio

STUDIO = {"Studio floor", "Low display cushion", "Directional short fur", "Rounded resting tail"}
for o in list(scene.objects):
    if o.type in {"CAMERA", "LIGHT"} or o.name in STUDIO:
        delete(o)

# ---------------------------------------------------------------- curves to meshes
# Hairline curves vanish at game size, so they get thicker first.
THICK = {"Brow whisker": .0016, "Whisker": .0022, "Mouth line": .0032, "Eye rim": .0046,
         "Toe crease": .003}
for o in list(scene.objects):
    if o.type != "CURVE":
        continue
    c = o.data
    c.bevel_depth = next((r for k, r in THICK.items() if o.name.startswith(k)), c.bevel_depth)
    c.bevel_resolution = 0
    c.resolution_u = 3
    select_only(o)
    bpy.ops.object.convert(target="MESH")

# ---------------------------------------------------------------- budgets
BUDGET = {"Head cheeks and short muzzle": 5200, "Torso and haunches": 4400, "Left foreleg": 1100,
          "Right foreleg": 1100, "Left ear": 700, "Right ear": 700, "Left eye": 700, "Right eye": 700,
          "Game tail": 1400, "Game tail tip": 1000, "Furred lid": 300, "Nostril": 40,
          "Collar strap": 1400, "Collar stitch": 360, "Collar bell": 300}
for o in list(scene.objects):
    if o.type != "MESH":
        continue
    select_only(o)
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    # Freeze location, rotation, and scale into the vertices.
    o.data.transform(o.matrix_world)
    o.matrix_world = Matrix.Identity(4)
    budget = next((b for k, b in BUDGET.items() if o.name.startswith(k)), None)
    n = tris(o)
    if budget and n > budget:
        d = o.modifiers.new("decimate", "DECIMATE")
        d.ratio = budget / n
        bpy.ops.object.modifier_apply(modifier=d.name)

# ---------------------------------------------------------------- parts
# Which part each object rides on, and where each part's joint is.


def part_of(o):
    name = o.name
    x = sum((v.co.x for v in o.data.vertices), 0) / max(1, len(o.data.vertices))
    if name.startswith(("Left eye", "Right eye", "Eye shine")):
        return "eyeL" if x < 0 else "eyeR"
    if name.startswith("Left ear"):
        return "earL"
    if name.startswith("Right ear"):
        return "earR"
    if name.startswith("Game tail tip"):
        return "tailTip"
    if name.startswith("Game tail"):
        return "tail"
    if name.startswith(("Torso", "Left foreleg", "Right foreleg", "Toe crease")):
        return "body"
    # The skull and everything on it: lids, nose, mouth, whiskers, and the
    # collar (it leans with her head in the game).
    return "head"


def pivot(name, fallback):
    o = objects.get(name)
    return Vector(o["pivot"]) if o and "pivot" in o else Vector(fallback)


PARENT = {"kitten": None, "body": "kitten", "head": "body", "earL": "head", "earR": "head",
          "eyeL": "head", "eyeR": "head", "tail": "body", "tailTip": "tail"}
PIVOT = {"kitten": Vector(), "body": Vector(),
         "head": pivot("Head cheeks and short muzzle", (0, .02, .64)),
         "earL": pivot("Left ear", (-.16, .045, .88)), "earR": pivot("Right ear", (.16, .045, .88)),
         "eyeL": pivot("Left eye", (-.103, .27, .772)), "eyeR": pivot("Right eye", (.103, .27, .772)),
         "tail": pivot("Game tail", (0, -.3, .1)), "tailTip": pivot("Game tail tip", (.13, -.49, .5))}

meshes = [o for o in scene.objects if o.type == "MESH"]
# Sit her bottom on Z = 0, like the old export, so the game's seat height holds.
floor = min(v.co.z for o in meshes if part_of(o) == "body" for v in o.data.vertices)
lift = Vector((0, 0, -floor))
for o in meshes:
    o.data.transform(Matrix.Translation(lift))
for k in PIVOT:
    if k != "kitten":
        PIVOT[k] = PIVOT[k] + lift

# ---------------------------------------------------------------- ambient occlusion
# For each coat vertex, cast rays over the half of the sky above its surface and
# count how many hit the kitten within 15 cm. Crevices come out darker, which is
# most of what makes a soft gray shape read as a body instead of a balloon.
all_verts, all_faces = [], []
for o in meshes:
    base = len(all_verts)
    all_verts += [v.co.copy() for v in o.data.vertices]
    all_faces += [[base + i for i in p.vertices] for p in o.data.polygons]
tree = BVHTree.FromPolygons(all_verts, all_faces)
rng = random.Random(5)
RAYS = 20
dirs = []
for i in range(RAYS):
    # Cosine-weighted directions around +Z, rotated onto each normal below.
    u1, u2 = (i + .5) / RAYS, rng.random()
    r, a = math.sqrt(u1), 2 * math.pi * u2
    dirs.append(Vector((r * math.cos(a), r * math.sin(a), math.sqrt(1 - u1))))


def occlusion(p, n):
    rot = Vector((0, 0, 1)).rotation_difference(n).to_matrix()
    hit = 0
    for d in dirs:
        loc, *_ = tree.ray_cast(p + n * .003, rot @ d, .15)
        hit += loc is not None
    return hit / RAYS


# ---------------------------------------------------------------- write

def game(v):
    return (v.x, v.z, -v.y)


def cube_uv(p, n):
    """Texture coordinates for the coat, in meters, from whichever side of a box
    the face looks toward. The offsets keep the three sides' grids apart."""
    ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
    if ax >= ay and ax >= az:
        return (p.y + .37, p.z + .11)
    if ay >= az:
        return (p.x + .71, p.z + .53)
    return (p.x + .19, p.y + .83)


NOSE = Vector((0, .36, .70)) + lift
TAIL_ROOT = Vector((0, -.2, .05)) + lift


def comb(p, n, part):
    """Which way the fur lies at p: back from the nose on her head, out along
    the tail, down and a little back everywhere else. Flattened onto the
    surface; the game leans each shell of fur along it."""
    if part == "head":
        g = p - NOSE
    elif part.startswith("tail"):
        g = p - TAIL_ROOT
    else:
        g = Vector((0, -.35, -1))
    t = g - n * g.dot(n)
    return t.normalized() if t.length > 1e-6 else Vector()


groups = {}
for o in meshes:
    me = o.data
    me.calc_loop_triangles()
    part = part_of(o)
    origin = PIVOT[part]
    coat_col = me.color_attributes.get("Coat color")
    fur_len = me.attributes.get("Fur length")
    uv_layer = me.uv_layers.active
    ao = {}
    for tri in me.loop_triangles:
        mat = me.materials[tri.material_index].name
        is_coat = mat == "kittenCoat"
        fn = tri.normal
        g = groups.setdefault((part, mat), {"part": part, "material": mat, "keys": {}, "vertices": [],
                                             "normals": [], "colors": [], "uv": [], "fur": [], "comb": [],
                                             "indices": []})
        for li, vi in zip(tri.loops, tri.vertices):
            p = me.vertices[vi].co
            n = me.corner_normals[li].vector.normalized()
            if is_coat and coat_col:
                if vi not in ao:
                    ao[vi] = 1 - .62 * occlusion(p, me.vertices[vi].normal.normalized())
                c = coat_col.data[vi].color
                color = (c[0] * ao[vi], c[1] * ao[vi], c[2] * ao[vi], 1)
                uv = cube_uv(p, fn)
                fur = fur_len.data[vi].value if fur_len else 1
                lie = comb(p, n, part)
            else:
                color = (1, 1, 1, 1)
                # SceneKit's picture origin is the top left, Blender's the bottom left.
                uv = (uv_layer.data[li].uv.x, 1 - uv_layer.data[li].uv.y) if uv_layer else (0, 0)
                fur = 0
                lie = Vector()
            pos = game(p - origin)
            nrm = game(n)
            key = tuple(round(x, 5) for x in (*pos, *nrm, *uv)) + tuple(round(x, 3) for x in color[:3])
            index = g["keys"].get(key)
            if index is None:
                index = len(g["vertices"]) // 3
                g["keys"][key] = index
                g["vertices"] += [round(x, 6) for x in pos]
                g["normals"] += [round(x, 5) for x in nrm]
                g["colors"] += [round(x, 5) for x in color]
                g["uv"] += [round(x, 5) for x in uv]
                g["fur"].append(round(fur, 3))
                g["comb"] += [round(x, 4) for x in game(lie)]
            g["indices"].append(index)

# The iris picture lives in the .blend; write it beside the JSON.
iris = bpy.data.images["iris"]
iris.filepath_raw = str(OUT / "iris.png")
iris.file_format = "PNG"
iris.save()

# A soft gray grain for the coat: gentle blotches a few millimeters across,
# repeating every meter. It gives the skin under the fur some life.
size = 256
gr = np.random.default_rng(3)
noise = gr.random((size, size)).astype(np.float32)
for _ in range(3):   # blur by averaging with shifted copies (wraps, so it tiles)
    noise = (noise + np.roll(noise, 1, 0) + np.roll(noise, -1, 0) + np.roll(noise, 1, 1) + np.roll(noise, -1, 1)) / 5
noise = (noise - noise.min()) / (noise.max() - noise.min())
value = .88 + .12 * noise
grain = bpy.data.images.new("fur-grain", size, size, alpha=False)
grain.pixels.foreach_set(np.stack([value, value, value, np.ones_like(value)], -1).ravel())
grain.filepath_raw = str(OUT / "fur-grain.png")
grain.file_format = "PNG"
grain.save()

parts = [{"name": k, "parent": PARENT[k],
          "position": game(PIVOT[k] - (PIVOT[PARENT[k]] if PARENT[k] else Vector()))} for k in PARENT]
out = {"parts": parts, "textures": {"iris": "iris.png", "grain": "fur-grain.png"},
       "groups": [{k: v for k, v in g.items() if k != "keys"} for g in groups.values()]}
(OUT / "kitten.json").write_text(json.dumps(out))

# The game culls back faces, so a part wound inside out vanishes (an eye cap
# facing backward shows the dark socket behind it). Her eyes must face her front.
for g in groups.values():
    if g["material"] == "kittenEye":
        v, ix = g["vertices"], g["indices"]
        forward = 0
        for t in range(0, len(ix), 3):
            a, b, c = (Vector(v[ix[t + k] * 3:ix[t + k] * 3 + 3]) for k in range(3))
            forward += (b - a).cross(c - a).z < 0      # SceneKit: she faces -Z
        assert forward > .9 * len(ix) / 3, f"{g['part']} faces backward"

total = 0
for g in groups.values():
    t = len(g["indices"]) // 3
    total += t
    print(f"  {g['part']:8s} {g['material']:20s} {t:6d} tris {len(g['vertices']) // 3:6d} verts")
print("TOTAL TRIS", total)
assert total < 32000, total
print("wrote", OUT / "kitten.json")
