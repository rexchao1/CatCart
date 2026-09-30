# Builds the 3D kitten (Rex's blue-gray British Shorthair) in Blender and
# exports a USD file that scripts/build_kitten.swift turns into
# CatCart/Models/cat_kitten.scn.
#
# Run headless from the repo root:
#   /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
#       --python scripts/blender/make_cat.py -- /path/to/cat_kitten.usdc
#
# How the shapes are made: every soft part (head, body, tail) is a pile of
# overlapping ellipsoids. A voxel remesh fuses them into one skin, a smooth
# pass rounds the seams like plush, and a decimate brings it under budget.
#
# Coordinates here are Blender's (Z up). The face looks toward +Y, which the
# USD export turns into SceneKit's -Z (away from the game camera).
# Units are meters. Origin = center of her seat, bottom of the body at Z = 0.

import bpy
import bmesh
import math
import sys
from mathutils import Vector, Matrix

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "/tmp/cat_kitten.usdc"

# ---------------------------------------------------------------- helpers

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def material(name, rgb):
    m = bpy.data.materials.new(name)
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*[srgb_to_lin(c) for c in rgb], 1)
    bsdf.inputs["Roughness"].default_value = 0.8
    return m


def srgb_to_lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


MAT = {
    "coat": material("kittenCoat", (142, 148, 163)),
    "muzzle": material("kittenMuzzle", (190, 190, 202)),
    "earInner": material("kittenEarInner", (206, 168, 178)),
    "iris": material("kittenIris", (226, 134, 44)),
    "pupil": material("kittenPupil", (24, 20, 26)),
    "shine": material("kittenShine", (255, 255, 255)),
    "nose": material("kittenNose", (140, 118, 132)),
    "mouth": material("kittenMouth", (80, 72, 84)),
    "whisker": material("kittenWhisker", (240, 240, 246)),
}


def ellipsoid(center, radii, rot=(0, 0, 0), segs=24, rings=16):
    """A UV sphere scaled into an ellipsoid, as a bmesh-free mesh object."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=rings, radius=1,
                                         location=center, rotation=rot)
    o = bpy.context.active_object
    o.scale = radii
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return o


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    o.data.name = name + "Mesh"
    return o


def apply_mods(o):
    bpy.context.view_layer.objects.active = o
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def fuse(objs, name, voxel=0.011, smooth=12, tris=4000, mat="coat"):
    """Union ellipsoids into one plush skin with about `tris` triangles."""
    o = join(objs, name)
    r = o.modifiers.new("remesh", "REMESH")
    r.mode = "VOXEL"
    r.voxel_size = voxel
    s = o.modifiers.new("smooth", "SMOOTH")
    s.factor = 0.6
    s.iterations = smooth
    apply_mods(o)
    faces = len(o.data.polygons)
    d = o.modifiers.new("decimate", "DECIMATE")
    d.ratio = min(1.0, tris / max(1, faces * 2))
    apply_mods(o)
    bpy.ops.object.shade_smooth()
    o.data.materials.clear()
    o.data.materials.append(MAT[mat])
    return o


def set_origin(o, point):
    """Move the object's pivot to `point` without moving the mesh."""
    p = Vector(point)
    o.data.transform(Matrix.Translation(o.location - p))
    o.location = p
    bpy.context.view_layer.update()


def parent(child, par):
    bpy.context.view_layer.update()
    wm = child.matrix_world.copy()
    child.parent = par
    child.matrix_world = wm
    bpy.context.view_layer.update()


def tube(points, r0, r1, step=0.018):
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
            q = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                       + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
            samples.append(q)
    samples.append(pts[-1])
    objs = []
    for i, q in enumerate(samples):
        t = i / (len(samples) - 1)
        r = r0 + (r1 - r0) * t
        objs.append(ellipsoid(q, (r, r, r), segs=12, rings=8))
    return objs


# ---------------------------------------------------------------- body
# Compact, chunky loaf sitting upright. Width ~0.74 across the haunches.

body_parts = [
    ellipsoid((0, -0.03, 0.27), (0.27, 0.26, 0.29)),        # torso
    ellipsoid((0, 0.02, 0.15), (0.29, 0.28, 0.16)),         # wide belly/base
    ellipsoid((-0.2, -0.05, 0.14), (0.16, 0.21, 0.14)),     # haunch L
    ellipsoid((0.2, -0.05, 0.14), (0.16, 0.21, 0.14)),      # haunch R
    ellipsoid((0, 0.13, 0.36), (0.19, 0.14, 0.18)),         # chest ruff
    ellipsoid((-0.1, 0.19, 0.16), (0.075, 0.08, 0.16)),     # front leg L
    ellipsoid((0.1, 0.19, 0.16), (0.075, 0.08, 0.16)),      # front leg R
    ellipsoid((-0.1, 0.25, 0.045), (0.075, 0.1, 0.05)),     # front paw L
    ellipsoid((0.1, 0.25, 0.045), (0.075, 0.1, 0.05)),      # front paw R
    ellipsoid((0, 0.0, 0.47), (0.17, 0.16, 0.12)),          # neck/shoulders
]
body = fuse(body_parts, "body", tris=4200)
# sit exactly on the seat: lowest point of the body at Z = 0
body.data.transform(Matrix.Translation((0, 0, -min(v.co.z for v in body.data.vertices))))
set_origin(body, (0, 0, 0))

# ---------------------------------------------------------------- head
# Big and round, cheeks low and wide. Center HC; pivot at the neck.

HC = Vector((0, 0.06, 0.63))
NECK = Vector((0, 0.02, 0.45))


def h(x, y, z):
    return (HC.x + x, HC.y + y, HC.z + z)


head_parts = [
    ellipsoid(h(0, 0, 0.02), (0.285, 0.25, 0.25)),          # skull
    ellipsoid(h(-0.115, 0.08, -0.075), (0.17, 0.16, 0.14)),  # cheek L
    ellipsoid(h(0.115, 0.08, -0.075), (0.17, 0.16, 0.14)),   # cheek R
    ellipsoid(h(0, 0.1, -0.1), (0.14, 0.14, 0.12)),          # jaw/chin fill
]
head = fuse(head_parts, "head", smooth=22, tris=5200)

muzzle_parts = [
    ellipsoid(h(-0.047, 0.215, -0.085), (0.062, 0.05, 0.048)),
    ellipsoid(h(0.047, 0.215, -0.085), (0.062, 0.05, 0.048)),
    ellipsoid(h(0, 0.195, -0.135), (0.05, 0.04, 0.03)),
]
muzzle = fuse(muzzle_parts, "muzzle", voxel=0.006, smooth=6, tris=1200, mat="muzzle")

nose = ellipsoid(h(0, 0.262, -0.047), (0.03, 0.018, 0.02), segs=16, rings=10)
bm = bmesh.new()
bm.from_mesh(nose.data)
for v in bm.verts:   # a soft upside-down triangle: narrower at the bottom
    dz = v.co.z - (HC.z - 0.047)
    v.co.x *= 1.0 + dz * 18
bm.to_mesh(nose.data)
bm.free()
bpy.context.view_layer.objects.active = nose
bpy.ops.object.shade_smooth()
nose.data.materials.append(MAT["nose"])
nose.name = "nose"

# Little "w" mouth: two short tori arcs under the nose.
mouth_objs = []
for sx in (-1, 1):
    bpy.ops.mesh.primitive_torus_add(major_radius=0.022, minor_radius=0.0045,
                                     major_segments=16, minor_segments=6,
                                     location=h(sx * 0.021, 0.253, -0.085),
                                     rotation=(math.radians(90), 0, 0))
    t = bpy.context.active_object
    bm = bmesh.new()
    bm.from_mesh(t.data)
    # keep only the lower half of the ring (a smile arc)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y > -0.004], context="VERTS")
    bm.to_mesh(t.data)
    bm.free()
    mouth_objs.append(t)
mouth = join(mouth_objs, "mouth")
bpy.ops.object.shade_smooth()
mouth.data.materials.append(MAT["mouth"])

# Whiskers: thin pale strands fanning out from each whisker pad.
whiskers = []
for sx in (-1, 1):
    for k, (lift, spread) in enumerate(((0.03, 8), (0.0, 0), (-0.028, -9))):
        start = Vector(h(sx * 0.07, 0.23, -0.08 + lift * 0.4))
        direction = Vector((sx * 1.0, 0.18, math.tan(math.radians(spread)))).normalized()
        length = 0.12
        mid = start + direction * (length / 2)
        bpy.ops.mesh.primitive_cylinder_add(vertices=5, radius=0.003, depth=length, location=mid)
        w = bpy.context.active_object
        w.rotation_mode = "QUATERNION"
        w.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(direction)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        w.data.materials.append(MAT["whisker"])
        whiskers.append(w)
whisk = join(whiskers, "whiskers")

face_extra = join([muzzle, nose, mouth, whisk], "face")
head = join([head, face_extra], "head")
set_origin(head, NECK)
parent(head, body)

# ---------------------------------------------------------------- eyes
# Big round copper eyes, a big pupil and one white shine. Each eye is its own
# node (pivot at the eye center) so the game can blink by scaling Y.

EYE_R = 0.072


def make_eye(side):
    x = side * 0.115
    c = Vector(h(x, 0.212, -0.015))
    yaw = -side * math.radians(24)
    tilt = math.radians(6)
    rot = Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(tilt, 4, "X")
    fwd = rot @ Vector((0, 1, 0))
    iris = ellipsoid(c, (EYE_R, 0.035, EYE_R), segs=24, rings=14)
    iris.data.materials.append(MAT["iris"])
    pupil = ellipsoid(c + fwd * 0.012, (0.047, 0.028, 0.052), segs=20, rings=12)
    pupil.data.materials.append(MAT["pupil"])
    shine = ellipsoid(c + fwd * 0.03 + Vector((-side * 0.0 - 0.018, 0, 0.022)),
                      (0.017, 0.012, 0.017), segs=12, rings=8)
    shine.data.materials.append(MAT["shine"])
    shine2 = ellipsoid(c + fwd * 0.03 + Vector((0.016, 0, -0.018)),
                       (0.008, 0.006, 0.008), segs=10, rings=6)
    shine2.data.materials.append(MAT["shine"])
    for o in (iris, pupil):   # turn iris and pupil to face along the head surface
        o.data.transform(Matrix.Translation(c) @ rot @ Matrix.Translation(-c))
    eye = join([iris, pupil, shine, shine2], "eyeL" if side < 0 else "eyeR")
    bpy.ops.object.shade_smooth()
    set_origin(eye, c)
    parent(eye, head)
    return eye


eyeL = make_eye(-1)   # "L" and "R" are HER left and right: she faces -Z in
eyeR = make_eye(1)    # SceneKit, so her left is -X (same X in Blender).

# ---------------------------------------------------------------- ears
# Small, rounded, set wide and tipped outward.


def make_ear(side):
    base = Vector(h(side * 0.19, 0.0, 0.18))
    bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=0.112, radius2=0.016, depth=0.18,
                                    location=(0, 0, 0.09))
    outer = bpy.context.active_object
    outer.scale = (1.0, 0.55, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    m = outer.modifiers.new("sub", "SUBSURF")
    m.levels = 2
    apply_mods(outer)
    bpy.ops.object.shade_smooth()
    outer.data.materials.append(MAT["coat"])
    bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=0.078, radius2=0.01, depth=0.13,
                                    location=(0, 0.024, 0.07))
    inner = bpy.context.active_object
    inner.scale = (1.0, 0.35, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    m = inner.modifiers.new("sub", "SUBSURF")
    m.levels = 2
    apply_mods(inner)
    bpy.ops.object.shade_smooth()
    inner.data.materials.append(MAT["earInner"])
    ear = join([outer, inner], "earL" if side < 0 else "earR")
    # tilt outward and a little back, then place on the skull
    rot = (Matrix.Rotation(side * math.radians(-26), 4, "Y")
           @ Matrix.Rotation(math.radians(-12), 4, "X")
           @ Matrix.Rotation(side * math.radians(-12), 4, "Z"))
    ear.data.transform(rot)
    ear.location = base
    bpy.context.view_layer.update()
    parent(ear, head)
    return ear


earL = make_ear(-1)
earR = make_ear(1)

# ---------------------------------------------------------------- tail
# Thick plush tail from the back of her bottom, up over the back rim of the box
# (rim top at Z 0.42, back wall at Y ~ -0.46), tip hanging outside.
# Split at the rim so the tip can swing on its own.

JOINT = (0.13, -0.49, 0.5)
tail_path = [(0.0, -0.24, 0.08), (0.05, -0.36, 0.2), (0.1, -0.45, 0.38), JOINT]
tip_path = [JOINT, (0.15, -0.54, 0.46), (0.165, -0.575, 0.36), (0.19, -0.59, 0.29)]

tail = fuse(tube(tail_path, 0.082, 0.077), "tail", voxel=0.01, smooth=8, tris=1800)
set_origin(tail, tail_path[0])
parent(tail, body)
tip = fuse(tube(tip_path, 0.077, 0.07), "tailTip", voxel=0.01, smooth=8, tris=1400)
set_origin(tip, JOINT)
parent(tip, tail)

# ---------------------------------------------------------------- head size
# Chibi proportions: grow the whole head (with ears and eyes) about the neck.

HEAD_SCALE = 1.08


def scale_group(top, pivot, k):
    objs = [top] + list(top.children_recursive)
    world = {o.name: o.matrix_world.translation.copy() for o in objs}
    for o in objs:
        o.data.transform(Matrix.Scale(k, 4))
    for o in objs:   # parents first (children_recursive is breadth ordered)
        target = pivot + (world[o.name] - pivot) * k
        o.matrix_world = Matrix.Translation(target)
        bpy.context.view_layer.update()


scale_group(head, NECK, HEAD_SCALE)

# ---------------------------------------------------------------- root + export

root = bpy.data.objects.new("kitten", None)
scene.collection.objects.link(root)
parent(body, root)

tri_total = 0
bpy.context.view_layer.update()
for o in scene.objects:
    if o.type == "MESH":
        o.data.calc_loop_triangles()
        n = len(o.data.loop_triangles)
        tri_total += n
        print(f"  {o.name:8s} {n:6d} tris  pivot {tuple(round(v, 3) for v in o.matrix_world.translation)}")
print("TOTAL TRIS", tri_total)

bpy.ops.wm.usd_export(filepath=OUT, selected_objects_only=False, export_materials=True,
                      export_animation=False, export_uvmaps=False, export_normals=True)
print("wrote", OUT)
