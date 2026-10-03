# Turns Rex's kitten study (art/models/kitten/cat.blend) into the game kitten
# and exports a USD file that scripts/build_kitten.swift turns into
# CatCart/Models/cat_kitten.scn.
#
# Run headless from the repo root:
#   /Applications/Blender.app/Contents/MacOS/Blender -b art/models/kitten/cat.blend \
#       --python scripts/blender/export_kitten.py -- /tmp/cat_kitten.usdc
#
# The .blend is a render study: almost a million triangles, loose objects,
# strand fur, and a tail resting on the floor. A phone game needs about 20k
# triangles and named parts the game can animate, so this script:
# - deletes the studio (floor, cushion, cameras, lights) and the strand fur,
# - turns the thin curves (whiskers, lid edges, mouth) into light meshes,
# - decimates each part to a budget,
# - groups everything into kitten > body > head > (earL, earR, eyeL, eyeR) and
#   body > tail > tailTip, each with its pivot at its joint,
# - builds a new tail held up over the back of the box (the resting tail would
#   poke through the cardboard),
# - renames materials to the names build_kitten.swift colors.
#
# Coordinates are Blender's (Z up), face toward +Y. Units are meters.
# Origin = center of her seat, bottom of the body at Z = 0. The .blend already
# uses that frame, so nothing is moved or scaled.

import bpy
import math
import sys
from mathutils import Vector, Matrix

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "/tmp/cat_kitten.usdc"
scene = bpy.context.scene
obj = bpy.data.objects


def delete(o):
    bpy.data.objects.remove(o, do_unlink=True)


def select_only(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def apply_mods(o):
    bpy.context.view_layer.objects.active = o
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def tris(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


def decimate(o, budget):
    """Collapse-decimate `o` down to about `budget` triangles."""
    n = tris(o)
    if n <= budget:
        return
    d = o.modifiers.new("decimate", "DECIMATE")
    d.ratio = budget / n
    apply_mods(o)


def join(objs, name):
    """Join meshes into one object called `name`, mesh data `nameMesh`.
    build_kitten.swift finds each part's geometry by that Mesh suffix."""
    select_only(objs)
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    o.data.name = name + "Mesh"
    return o


def curve_to_mesh(o, radius):
    """Thicken a hairline curve so it survives at game size, then mesh it."""
    c = o.data
    c.bevel_depth = radius
    c.bevel_resolution = 0
    c.resolution_u = 2
    select_only([o])
    bpy.ops.object.convert(target="MESH")
    return bpy.context.active_object


def set_origin(o, point):
    """Move the object's pivot to `point` without moving the mesh."""
    p = Vector(point)
    o.data.transform(Matrix.Translation(o.matrix_world.translation - p))
    o.matrix_world = Matrix.Translation(p)
    bpy.context.view_layer.update()


def parent(child, par):
    bpy.context.view_layer.update()
    wm = child.matrix_world.copy()
    child.parent = par
    child.matrix_world = wm
    bpy.context.view_layer.update()


def bake_transform(o):
    """Freeze location/rotation/scale into the vertices (pivot at world 0)."""
    o.data.transform(o.matrix_world)
    o.matrix_world = Matrix.Identity(4)


def material(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    return m


def retarget(o, mapping):
    """Swap the study's material names for the game's."""
    for slot in o.material_slots:
        if slot.material and slot.material.name in mapping:
            slot.material = material(mapping[slot.material.name])


# ---------------------------------------------------------------- clear studio

for o in list(scene.objects):
    if o.type in {"CAMERA", "LIGHT"} or o.name in {
            "Studio floor", "Low display cushion", "Directional short fur",
            "Rounded resting tail"} or o.name.startswith("Subtle toe crease"):
        delete(o)

for o in scene.objects:
    if o.type == "MESH":
        select_only([o])
        apply_mods(o)       # the nose bevel
        bake_transform(o)

NAMES = {
    "Warm dove gray coat": "kittenCoat",
    "Muted inner ear skin": "kittenEarInner",
    "Charcoal rose nose leather": "kittenNose",
    "Dark eyelid and lip": "kittenMouth",
    "Fine gray ivory whiskers": "kittenWhisker",
}

# ---------------------------------------------------------------- face lines

lines = []
for o in list(scene.objects):
    if o.type != "CURVE":
        continue
    if o.name.startswith("Brow whisker"):
        r = 0.0016
    elif o.name.startswith("Whisker"):
        r = 0.0022
    elif o.name.startswith("Mouth line"):
        r = 0.003
    else:   # fine eyelid edge
        r = 0.0035
    m = curve_to_mesh(o, r)
    bake_transform(m)
    lines.append(m)

# ---------------------------------------------------------------- eyes
# The study paints the iris with vertex colors. SceneKit gets plain materials
# instead: dark pupil and rim, golden iris band, plus a small white catchlight
# so the eyes still sparkle under the game's flat lighting.

def split_eye(o):
    ca = o.data.color_attributes["Iris color"]
    pupil = material("kittenPupil")
    iris = material("kittenIris")
    o.data.materials.clear()
    o.data.materials.append(pupil)
    o.data.materials.append(iris)
    for p in o.data.polygons:
        lum = sum(ca.data[v].color[0] for v in p.vertices) / len(p.vertices)
        p.material_index = 1 if lum > 0.05 else 0
    o.data.color_attributes.remove(ca)


eye_parts = {}
for side, name in ((-1, "Left eye"), (1, "Right eye")):
    e = obj[name]
    split_eye(e)
    decimate(e, 900)
    c = Vector((side * 0.098, 0.236, 0.776))     # eye center, from the study
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=1,
                                         location=c + Vector((-0.016, 0.034, 0.012)))
    shine = bpy.context.active_object
    shine.scale = (0.011, 0.005, 0.011)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    shine.data.materials.append(material("kittenShine"))
    eye = join([e, shine], "eyeL" if side < 0 else "eyeR")
    set_origin(eye, c)
    eye_parts[side] = eye

# ---------------------------------------------------------------- ears

ear_parts = {}
for side, name in ((-1, "Left ear"), (1, "Right ear")):
    e = obj[name]
    retarget(e, NAMES)
    ear = join([e], "earL" if side < 0 else "earR")
    set_origin(ear, (side * 0.149, 0.064, 0.865))  # ear base, from the study
    ear_parts[side] = ear

# ---------------------------------------------------------------- head
# Skull plus everything that rides on it and never moves on its own:
# lids, nose, nostrils, mouth, whiskers.

NECK = (0, 0.02, 0.64)

head_mesh = obj["Head cheeks and short muzzle"]
decimate(head_mesh, 5200)
face = [head_mesh]
for o in list(scene.objects):
    if o.type != "MESH":
        continue
    if o.name.startswith("Furred"):
        decimate(o, 400)
        face.append(o)
    elif o.name.startswith("Nostril"):
        decimate(o, 120)
        face.append(o)
    elif o.name == "Nose":
        face.append(o)
face += lines
for o in face:
    retarget(o, NAMES)
head = join(face, "head")
set_origin(head, NECK)

# ---------------------------------------------------------------- body

torso = obj["Torso and haunches"]
decimate(torso, 4400)
legs = [obj["Left foreleg"], obj["Right foreleg"]]
for leg in legs:
    decimate(leg, 1000)
for o in [torso] + legs:
    retarget(o, NAMES)
body = join([torso] + legs, "body")
body.data.transform(Matrix.Translation((0, 0, -min(v.co.z for v in body.data.vertices))))
set_origin(body, (0, 0, 0))

# ---------------------------------------------------------------- tail
# Held up over the back of the box like the old cartoon kitten, so the game's
# sway and lift (KittenCart.tailLift) still work. Split at the rim so the tip
# can swing on its own. Thickness matches the study's tail.


def tube(points, r0, r1, step=0.016):
    """Chain of spheres along a Catmull-Rom path, radius r0 -> r1."""
    pts = [Vector(p) for p in points]
    samples = []
    for i in range(len(pts) - 1):
        p0 = pts[max(i - 1, 0)]
        p1, p2 = pts[i], pts[i + 1]
        p3 = pts[min(i + 2, len(pts) - 1)]
        n = max(2, int((p2 - p1).length / step))
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            samples.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                                  + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    samples.append(pts[-1])
    objs = []
    for i, q in enumerate(samples):
        r = r0 + (r1 - r0) * i / (len(samples) - 1)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=r, location=q)
        objs.append(bpy.context.active_object)
    return objs


def fuse(objs, name, budget):
    o = join(objs, name)
    r = o.modifiers.new("remesh", "REMESH")
    r.mode = "VOXEL"
    r.voxel_size = 0.008
    s = o.modifiers.new("smooth", "SMOOTH")
    s.factor = 0.6
    s.iterations = 8
    apply_mods(o)
    decimate(o, budget)
    bpy.ops.object.shade_smooth()
    o.data.materials.clear()
    o.data.materials.append(material("kittenCoat"))
    return o


JOINT = (0.13, -0.49, 0.5)
tail_path = [(0.0, -0.3, 0.1), (0.05, -0.39, 0.22), (0.1, -0.46, 0.38), JOINT]
tip_path = [JOINT, (0.15, -0.54, 0.46), (0.165, -0.575, 0.36), (0.18, -0.59, 0.29)]
tail = fuse(tube(tail_path, 0.06, 0.057), "tail", 1400)
set_origin(tail, tail_path[0])
tip = fuse(tube(tip_path, 0.057, 0.05), "tailTip", 1000)
set_origin(tip, JOINT)

# ---------------------------------------------------------------- hierarchy

root = bpy.data.objects.new("kitten", None)
scene.collection.objects.link(root)
parent(body, root)
parent(head, body)
for part in (*eye_parts.values(), *ear_parts.values()):
    parent(part, head)
parent(tail, body)
parent(tip, tail)

for o in scene.objects:
    if o.type == "MESH":
        select_only([o])
        bpy.ops.object.shade_smooth()

leftover = [o.name for o in scene.objects if o.parent is None and o is not root]
assert not leftover, f"unparented objects: {leftover}"

total = 0
for o in scene.objects:
    if o.type == "MESH":
        n = tris(o)
        total += n
        print(f"  {o.name:8s} {n:6d} tris  pivot {tuple(round(v, 3) for v in o.matrix_world.translation)}"
              f"  mats {[s.material.name for s in o.material_slots]}")
print("TOTAL TRIS", total)

bpy.ops.wm.usd_export(filepath=OUT, selected_objects_only=False, export_materials=True,
                      export_animation=False, export_uvmaps=False, export_normals=True)
print("wrote", OUT)
