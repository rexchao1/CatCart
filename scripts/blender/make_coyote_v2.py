"""Coyote source model, revision 2: lean, ragged, and mean. Builds
art/models/coyote/coyote.blend from scratch and renders previews into
art/options/coyote/v2/. Not a game export: scripts/build_art.sh runs
export_game_pickup.py on the saved file for that.

    python3 scripts/blender/run_bpy.py - scripts/blender/make_coyote_v2.py -- [--quick] [--fur] [--no-render] [--out DIR]

Blender coordinates: meters, Z up, the coyote faces -Y. The exporter turns that
into the game's Y-up, +Z-forward basis and scales by 0.88.

Why the object names below never change: export_game_pickup.py sorts geometry
into the moving parts (body, head, jaw, legs, tail, ears) by these names.
"<part> tufts" objects are the ragged fur silhouette; they ride with their
part and are never decimated. Objects ending in " fur" are render-only strands
and stay out of the game. "Pivot <part>" empties tell the exporter where each
part turns.
"""
from pathlib import Path
import math
import random
import sys
import bpy
from mathutils import Vector
import time
_t0 = time.time()


def note(msg):
    print(f'[{time.time() - _t0:6.1f}s] {msg}', flush=True)


argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
QUICK = '--quick' in argv
FUR = '--fur' in argv
RENDER = '--no-render' not in argv
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'art/models/coyote'
PREVIEW = Path(argv[argv.index('--out') + 1]) if '--out' in argv else ROOT / 'art/options/coyote/v2'
OUT.mkdir(parents=True, exist_ok=True)
PREVIEW.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
rng = random.Random(1209)
model = bpy.data.collections.new('Coyote model')
scene.collection.children.link(model)
studio = bpy.data.collections.new('Preview studio')
scene.collection.children.link(studio)


def move(obj, col=model):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    col.objects.link(obj)
    return obj


def lin(v):
    v /= 255
    return v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4


def mat(name, rgb, rough=.65, vertex=False, emission=None):
    m = bpy.data.materials.new(name)
    s = m.node_tree.nodes.get('Principled BSDF')
    s.inputs['Base Color'].default_value = (*map(lin, rgb), 1)
    s.inputs['Roughness'].default_value = rough
    m.diffuse_color = (*map(lin, rgb), 1)
    if vertex:
        node = m.node_tree.nodes.new('ShaderNodeVertexColor')
        node.layer_name = 'Coat color'
        m.node_tree.links.new(node.outputs['Color'], s.inputs['Base Color'])
    if emission:
        s.inputs['Emission Color'].default_value = (*map(lin, emission[0]), 1)
        s.inputs['Emission Strength'].default_value = emission[1]
    return m


# One vertex-colored coat material carries the whole hide, the nose, lips, claws,
# pads, brows and ear skin, so the game draws each moving part in one call.
coat = mat('Grizzled warm tan coat', (150, 119, 82), .72, vertex=True)
coat.node_tree.nodes.get('Principled BSDF').inputs['Sheen Weight'].default_value = .2
tooth = mat('Warm ivory teeth', (240, 228, 200), .28)
mouth = mat('Dark mouth interior', (60, 20, 22), .45, vertex=True)
amber = mat('Amber iris', (214, 140, 28), .2, emission=((214, 140, 28), .35))

# sRGB palette. Tan and gray-brown back, cream underneath, rust on the legs and ears.
TAN = Vector((148, 116, 78))
GRIZZLE = Vector((92, 84, 72))
DARK = Vector((48, 40, 34))
CREAM = Vector((222, 206, 176))
RUST = Vector((160, 104, 58))
BLACK = Vector((22, 18, 16))
EAR_SKIN = Vector((84, 58, 50))
TONGUE = Vector((190, 86, 96))
GUM = Vector((110, 48, 50))
PAD = Vector((40, 30, 28))


def clamp(v, lo=0.0, hi=1.0):
    return max(lo, min(hi, v))


def smooth(o):
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def ell(name, c, r, material=coat, rot=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=36, ring_count=20, location=c)
    o = bpy.context.object
    o.name = name
    o.scale = r
    if rot:
        o.rotation_euler = rot
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    o.data.materials.append(material)
    move(o)
    return smooth(o)


def fuse(name, parts, voxel=.006):
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    o = parts[0]
    o.name = name
    mod = o.modifiers.new('Fused anatomy', 'REMESH')
    mod.mode = 'VOXEL'
    mod.voxel_size = voxel
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mod = o.modifiers.new('Soft transitions', 'SMOOTH')
    mod.factor = .6
    mod.iterations = 10
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return smooth(o)


def curve(name, pts, r, material=coat, taper=False):
    d = bpy.data.curves.new(name, 'CURVE')
    d.dimensions = '3D'
    d.bevel_depth = r
    d.bevel_resolution = 3
    d.resolution_u = 10
    d.use_fill_caps = True
    sp = d.splines.new('BEZIER')
    sp.bezier_points.add(len(pts) - 1)
    for i, (p, co) in enumerate(zip(sp.bezier_points, pts)):
        p.co = co
        p.handle_left_type = p.handle_right_type = 'AUTO'
        p.radius = 1 - .9 * i / (len(pts) - 1) if taper else 1
    o = bpy.data.objects.new(name, d)
    model.objects.link(o)
    d.materials.append(material)
    return o


def capsule(name, a, b, r1, r2, n=19):
    a, b = Vector(a), Vector(b)
    out = []
    for i in range(n):
        t = i / (n - 1)
        r = r1 * (1 - t) + r2 * t
        out.append(ell(name, a.lerp(b, t), (r, r, r)))
    return out


def cone(name, base, tip, r, material=tooth, verts=8):
    base, tip = Vector(base), Vector(tip)
    length = (tip - base).length
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=.0008, depth=length, location=(base + tip) / 2)
    o = bpy.context.object
    o.name = name
    o.rotation_euler = (tip - base).to_track_quat('Z', 'Y').to_euler()
    o.data.materials.append(material)
    move(o)
    return smooth(o)


# Solid-colored coat pieces (nose, lips, claws, pads, brows): name -> sRGB color.
solid_color = {}


def solid(o, color):
    solid_color[o.name] = color
    return o


# -- torso and neck ------------------------------------------------------------
# Deep ribcage, pinched waist, bony shoulders and hips, and a thick neck ruff.
body = fuse('Lean torso and neck', [
    ell('Ribcage', (0, -.14, .675), (.168, .30, .245)),
    ell('Keel', (0, -.22, .56), (.09, .22, .12)),
    ell('Loin', (0, .05, .73), (.14, .20, .165)),
    ell('Waist', (0, .20, .745), (.118, .28, .13)),
    ell('Flank', (0, .32, .735), (.13, .16, .145)),
    ell('Pelvis', (0, .43, .725), (.138, .185, .16)),
    ell('Left hip bone', (-.085, .40, .775), (.045, .085, .045)),
    ell('Right hip bone', (.085, .40, .775), (.045, .085, .045)),
    ell('Shoulders', (0, -.33, .755), (.172, .17, .21)),
    ell('Left shoulder blade', (-.112, -.29, .815), (.062, .12, .085)),
    ell('Right shoulder blade', (.112, -.29, .815), (.062, .12, .085)),
    ell('Withers', (0, -.33, .86), (.085, .14, .07)),
    ell('Lower neck', (0, -.41, .835), (.14, .17, .20)),
    ell('Ruff', (0, -.40, .80), (.165, .16, .195)),
    ell('Upper neck', (0, -.49, .93), (.115, .15, .145)),
])

note('torso fused')

# -- legs ------------------------------------------------------------------------
# Thin legs, a real elbow and hock, narrow paws with toes. The exporter cuts
# each leg at its "Pivot ...Lower" empty into an upper and a lower piece.
pivots = {'body': (0, 0, .70), 'head': (0, -.46, .915), 'tail1': (0, .57, .70), 'tail2': (0, .93, .555)}
for side, L in ((-1, 'L'), (1, 'R')):
    y = -.30 + (.02 if side < 0 else -.02)
    shoulder = (side * .128, y, .72)
    elbow = (side * .146, y + .04, .415)
    wrist = (side * .156, y - .03, .13)
    parts = capsule('Upper arm', shoulder, elbow, .066, .040)
    parts += capsule('Forearm', elbow, wrist, .040, .027)
    parts += capsule('Pastern', wrist, (side * .157, y - .07, .06), .027, .026, 6)
    parts += [ell('Elbow', elbow, (.046, .05, .046)),
              ell('Front paw', (side * .158, y - .085, .045), (.048, .075, .042))]
    for k in (-1, 0, 1):
        parts.append(ell('Front toe', (side * .158 + k * .028, y - .135, .036), (.018, .034, .024)))
    fuse('Left foreleg' if side < 0 else 'Right foreleg', parts, .0045)
    pivots['frontUpper' + L] = shoulder
    pivots['frontLower' + L] = elbow

    h = .45 + (.05 if side < 0 else -.03)
    hip = (side * .122, h, .70)
    stifle = (side * .152, h - .09, .375)
    hock = (side * .160, h + .11, .20)
    parts = [ell('Haunch', (side * .122, h - .02, .62), (.092, .135, .165)),
             ell('Thigh muscle', (side * .138, h - .04, .50), (.075, .105, .11))]
    parts += capsule('Thigh', (side * .135, h - .03, .58), stifle, .068, .042)
    parts += capsule('Hock', stifle, hock, .040, .026)
    parts += capsule('Rear pastern', hock, (side * .162, h + .03, .06), .026, .025)
    parts += [ell('Stifle', stifle, (.046, .05, .046)),
              ell('Rear paw', (side * .162, h - .01, .045), (.045, .072, .040))]
    for k in (-1, 0, 1):
        parts.append(ell('Rear toe', (side * .162 + k * .026, h - .06, .035), (.017, .032, .023)))
    fuse('Left hind leg' if side < 0 else 'Right hind leg', parts, .0045)
    pivots['hindUpper' + L] = hip
    pivots['hindLower' + L] = stifle
    for py, px in ((y - .15, side * .158), (h - .075, side * .162)):
        for dx in (-.028, 0, .028):
            solid(curve('Short dark claw', [(px + dx, py + .012, .036), (px + dx, py - .016, .026), (px + dx, py - .03, .012)],
                        .006, coat, True), BLACK)

note('legs fused')

# -- head --------------------------------------------------------------------------
# Long narrow muzzle, heavy brow, cheeks, snarl wrinkles on the bridge, and the
# upper lips pulled up off the fangs.
head = fuse('Narrow head and raised upper muzzle', [
    ell('Skull', (0, -.565, 1.00), (.138, .16, .13)),
    ell('Occiput', (0, -.50, 1.01), (.10, .09, .095)),
    ell('Left cheek', (-.098, -.555, .925), (.078, .11, .09)),
    ell('Right cheek', (.098, -.555, .925), (.078, .11, .09)),
    ell('Left brow', (-.064, -.665, 1.048), (.052, .05, .036)),
    ell('Right brow', (.064, -.665, 1.048), (.052, .05, .036)),
    ell('Muzzle bridge', (0, -.715, .955), (.082, .16, .062)),
    ell('Tapered muzzle', (0, -.815, .935), (.056, .10, .044)),
    ell('Nose base', (0, -.885, .937), (.043, .035, .031)),
    ell('Left lip flare', (-.058, -.79, .905), (.025, .05, .02)),
    ell('Right lip flare', (.058, -.79, .905), (.025, .05, .02)),
    ell('Snarl wrinkle', (0, -.745, .992), (.052, .012, .014)),
    ell('Snarl wrinkle', (0, -.785, .977), (.046, .011, .013)),
    ell('Snarl wrinkle', (0, -.825, .965), (.040, .010, .012)),
], .0035)
solid(ell('Black canine nose', (0, -.905, .947), (.047, .030, .032)), BLACK)
for side in (-1, 1):
    solid(ell('Nostril', (side * .024, -.93, .95), (.011, .006, .008)), BLACK)
ell('Dark throat', (0, -.66, .875), (.072, .095, .05), mouth)
ell('Upper mouth lining', (0, -.745, .886), (.050, .12, .010), mouth)

# Lower jaw, pivoted at the hinge. Cream chin, dark gums, a tongue.
jaw = fuse('Lower jaw', [
    ell('Jaw hinge', (0, -.60, .872), (.080, .062, .050)),
    ell('Lower muzzle', (0, -.73, .842), (.056, .15, .028)),
    ell('Chin', (0, -.835, .845), (.040, .062, .026)),
], .003)
jaw_parts = [jaw,
             ell('Lower mouth lining', (0, -.735, .858), (.050, .13, .013), mouth),
             ell('Tongue', (0, -.715, .870), (.032, .085, .013), mouth)]
for side in (-1, 1):
    # Lips: black, thicker than before, curling up over the fangs in the snarl.
    solid(curve('Upper black lip', [(side * .052, -.885, .918), (side * .062, -.80, .892), (side * .070, -.76, .882),
                                    (side * .088, -.69, .900), (side * .100, -.625, .912)], .0058), BLACK)
    jaw_parts.append(solid(curve('Lower black lip', [(side * .032, -.885, .848), (side * .050, -.78, .856),
                                                    (side * .066, -.68, .866)], .0045), BLACK))
    # Big fangs rule the mouth; the other teeth stay small.
    for upper in (True, False):
        for i in range(6):
            yy = -.845 + i * .034
            x = side * (.040 + i * .0062)
            fang = i == 1
            length = (.080 if fang else .024) if upper else (.055 if fang else .018)
            z = .902 if upper else .862
            base = Vector((x, yy, z))
            tip = Vector((x * .96, yy - .010, z - length if upper else z + length))
            o = cone('Upper canine' if upper and fang else 'Tooth', base, tip, .0135 if fang else .0068)
            if not upper:
                jaw_parts.append(o)
    # Eyes: amber, forward-set under a hard brow, with a dark mask and a glint.
    solid(ell('Dark eye socket', (side * .10, -.655, 1.022), (.042, .026, .032)), DARK)
    ell('Amber eye', (side * .103, -.672, 1.022), (.028, .016, .024), amber)
    solid(ell('Round canine pupil', (side * .104, -.687, 1.022), (.011, .004, .013)), BLACK)
    ell('Eye glint', (side * .112, -.690, 1.031), (.006, .003, .005), tooth)
    brow = ell('Angled brow', (side * .105, -.662, 1.058), (.055, .028, .017))
    brow.rotation_euler.y = -side * .38
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    solid(brow, DARK)
    # Dark tear line from the eye corner down the muzzle.
    solid(ell('Dark tear line', (side * .072, -.73, .985), (.011, .045, .009)), DARK)

pivots['Snarl jaw pivot'] = (0, -.59, .877)
pivot = bpy.data.objects.new('Snarl jaw pivot', None)
model.objects.link(pivot)
pivot.location = pivots['Snarl jaw pivot']
bpy.context.view_layer.update()
for o in jaw_parts:
    wm = o.matrix_world.copy()
    o.parent = pivot
    o.matrix_world = wm
for frame, angle in ((1, .18), (10, .02), (14, .30), (22, .12), (30, .18)):
    pivot.rotation_euler.x = angle
    pivot.keyframe_insert(data_path='rotation_euler', frame=frame)

note('head built')

# -- ears -----------------------------------------------------------------------------
# Big, tall, cupped, tipped back and out. Rust outside, dark skin inside with a
# pale rim. Each ear is its own moving part.
for side, L in ((-1, 'L'), (1, 'R')):
    base = Vector((side * .098, -.49, 1.085))
    shape = [(-.058, 0, 0), (-.054, .016, .09), (-.030, .030, .15), (.0, .026, .225), (.030, .012, .15), (.066, 0, .04)]
    if side < 0:
        shape = [(-x, y, z) for x, y, z in shape[::-1]]
    verts = []
    center = Vector((side * .02, .016, .12))
    n = len(shape)
    for r in (1, .78, .45, .12):
        for x, y, z in shape:
            p = Vector((x, y, z)) * r + center * (1 - r)
            p.z *= .92
            p.x += side * p.z * .28
            p.y += p.z * .34 + (1 - r) * .028
            verts.append(base + p)
    verts.append(base + center + Vector((side * .035, .05, 0)))
    faces = []
    for k in range(3):
        for j in range(n):
            faces.append((k * n + j, k * n + (j + 1) % n, (k + 1) * n + (j + 1) % n, (k + 1) * n + j))
    for j in range(n):
        faces.append((3 * n + j, 3 * n + (j + 1) % n, 4 * n))
    mesh = bpy.data.meshes.new('Cupped coyote ear')
    mesh.from_pydata(verts, [], [tuple(reversed(f)) for f in faces])
    mesh.materials.append(coat)
    o = bpy.data.objects.new('Left ear' if side < 0 else 'Right ear', mesh)
    model.objects.link(o)
    bpy.context.view_layer.objects.active = o
    mod = o.modifiers.new('Round ear contour', 'SUBSURF')
    mod.levels = 2
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mod = o.modifiers.new('Ear thickness', 'SOLIDIFY')
    mod.thickness = .011
    bpy.ops.object.modifier_apply(modifier=mod.name)
    smooth(o)
    pivots['ear' + L] = tuple(base)

# -- tail --------------------------------------------------------------------------------
# Bushy, carried low, streaming back, dark along the top and black at the tip.
parts = []
for i in range(20):
    t = i / 19
    p = Vector((.015 + .05 * math.sin(t * math.pi), .57 + .70 * t, .70 - .40 * t + .14 * t * t))
    r = .042 + .055 * math.sin(math.pi * t) ** .75
    r *= 1 - .6 * t ** 5
    parts.append(ell('Tail section', p, (r, r * 1.15, r * 1.05)))
tail = fuse('Bushy low tail', parts, .0045)

note('ears and tail built')

# -- coat colors ----------------------------------------------------------------------
# One rule for the whole hide, by position. Vertex colors survive the game's
# decimation as soft blends; the speckle below keeps the back grizzled.
def tint(p, n, rnd):
    if p.z < .50:
        col = RUST.lerp(TAN, clamp((p.z - .30) / .18))
        if p.z < .09:
            col = col.lerp(DARK, .35)
    else:
        saddle = clamp((p.z - .63) / .19) * clamp((p.y + .45) / .25)
        if p.y > .62:
            saddle = max(saddle, clamp((p.y - .62) / .5) * .8)
        col = TAN.lerp(GRIZZLE, saddle)
        if n.z > .2 and saddle > .3 and rnd < .3:
            col = col.lerp(DARK, .6)  # dark guard-hair tips
        belly = clamp((.62 - p.z) / .14) * clamp(1 - abs(p.x) / .2)
        col = col.lerp(CREAM, belly * .9)
        chest = clamp((-p.y - .26) / .2) * clamp((.92 - p.z) / .2)
        col = col.lerp(CREAM, chest * .9)
        if p.y < -.60 and p.z < .945 and abs(p.x) > .045:
            col = col.lerp(CREAM, .8)  # cheeks and lower muzzle sides
        if p.y < -.70 and p.z > .94 and abs(p.x) < .055:
            col = col.lerp(DARK, clamp((-p.y - .70) / .2) * .7)  # dark stripe up the nose
        if p.z > 1.03 and p.y < -.56:
            col = col.lerp(GRIZZLE, .45)  # darker crown
    if p.y > .62:
        tail_t = clamp((p.y - .62) / .62)
        col = (TAN.lerp(GRIZZLE, .5) if n.z > 0 else CREAM.lerp(TAN, .5)).lerp(BLACK, tail_t ** 4)
    return col * (1 + (rnd - .5) * .16)


# Reading one vertex normal from Python after writing a color makes Blender
# rebuild the whole mesh's normals, so every mesh is read in bulk first and its
# colors written in one call.
def positions_and_normals(obj):
    mesh = obj.data
    M = obj.matrix_world
    R = M.to_3x3()
    co = [0.0] * (len(mesh.vertices) * 3)
    mesh.vertices.foreach_get('co', co)
    no = [0.0] * (len(mesh.vertices) * 3)
    mesh.vertex_normals.foreach_get('vector', no)
    pts = [M @ Vector(co[i:i + 3]) for i in range(0, len(co), 3)]
    nrm = [(R @ Vector(no[i:i + 3])).normalized() for i in range(0, len(no), 3)]
    return pts, nrm


def write_colors(ca, cols):
    flat = []
    for col in cols:
        flat.extend((lin(clamp(col.x, 0, 255)), lin(clamp(col.y, 0, 255)), lin(clamp(col.z, 0, 255)), 1.0))
    ca.data.foreach_set('color', flat)


def color_object(obj):
    mesh = obj.data
    if mesh.color_attributes.get('Coat color'):
        return
    fixed = solid_color.get(obj.name)
    if fixed is not None:
        cols = [fixed * (1 + (rng.random() - .5) * .08) for _ in mesh.vertices]
    else:
        pts, nrm = positions_and_normals(obj)
        cols = [tint(p, nn, rng.random()) for p, nn in zip(pts, nrm)]
    ca = mesh.color_attributes.new(name='Coat color', type='FLOAT_COLOR', domain='POINT')
    write_colors(ca, cols)


def color_ear(obj, side):
    mesh = obj.data
    pts, _ = positions_and_normals(obj)
    pn = [0.0] * (len(mesh.polygons) * 3)
    mesh.polygon_normals.foreach_get('vector', pn)
    cols = [None] * len(mesh.loops)
    for poly in mesh.polygons:
        nrm = Vector(pn[poly.index * 3:poly.index * 3 + 3])
        inner = nrm.y < -.15 and nrm.x * side < .55
        for li in poly.loop_indices:
            p = pts[mesh.loops[li].vertex_index]
            if inner:
                col = EAR_SKIN.lerp(DARK, .25)
            else:
                col = RUST.lerp(GRIZZLE, clamp((p.z - 1.2) / .2) * .7)
                col = col.lerp(DARK, clamp((p.z - 1.33) / .07) * .8)
            cols[li] = col * (1 + (rng.random() - .5) * .1)
    ca = mesh.color_attributes.new(name='Coat color', type='FLOAT_COLOR', domain='CORNER')
    write_colors(ca, cols)


def color_mouth(obj):
    mesh = obj.data
    col = TONGUE if obj.name == 'Tongue' else (GUM if 'lining' in obj.name else Vector((60, 20, 22)))
    ca = mesh.color_attributes.new(name='Coat color', type='FLOAT_COLOR', domain='POINT')
    write_colors(ca, [col] * len(mesh.vertices))


bpy.context.view_layer.update()

# -- ragged tufts --------------------------------------------------------------------------
# Little four-sided spikes laid along the fur flow. They give the hackles, the
# neck ruff, the cheek ruff, the chest, belly fringe and the brush of the tail a
# ragged outline the game keeps (export never decimates them).
def tuft_rules(p, n):
    """Returns (tufts per m^2, length, flow direction, darken) or None."""
    if p.y > .60:  # tail
        t = clamp((p.y - .62) / .62)
        return 900, .05 + .025 * math.sin(math.pi * t), Vector((0, 1, -.35 + .5 * t)), .35 if t > .7 else .15
    if abs(p.x) < .07 and p.z > .80 and -.47 < p.y < .48 and n.z > .3:  # hackles
        return 1400, .06 + .025 * math.sin(clamp((p.y + .47) / .95) * math.pi), Vector((p.x * 2, 1, .35)), .45
    if -.56 < p.y < -.30 and p.z > .50:  # neck ruff
        return 850, .065 + .02 * rng.random(), Vector((p.x * 3, .8, -.2 if p.z < .78 else .4)), .2 if p.z > .8 else -.1
    if p.y < -.28 and .40 < p.z < .68 and abs(p.x) < .2:  # chest
        return 600, .055, Vector((p.x * 2, -.1, -1)), -.15
    if p.z < .58 and n.z < -.3 and -.3 < p.y < .5:  # belly fringe
        return 700, .045, Vector((p.x * 1.5, .5, -1)), -.05
    if p.y > .25 and p.z > .55 and abs(p.x) > .09:  # haunch
        return 550, .05, Vector((p.x, .9, -.4)), .15
    if abs(p.x) > .12 and .55 < p.z < .80 and -.3 < p.y < .3:  # flanks, sparse
        return 260, .04, Vector((p.x, 1, -.3)), .1
    return None


def head_rules(p, n):
    if abs(p.x) > .105 and -.62 < p.y < -.46 and .86 < p.z < 1.03:  # cheek ruff
        return 1500, .06, Vector((p.x * 3, 1.2, -.3)), -.1
    if p.z > 1.06 and -.62 < p.y < -.48 and abs(p.x) < .09:  # crown scruff
        return 900, .04, Vector((p.x, 1, .5)), .3
    if p.y > -.55 and p.z < .92 and abs(p.x) < .1:  # throat
        return 800, .045, Vector((p.x, .3, -1)), -.1
    return None


def leg_rules(p, n):
    if n.y > .4 and p.z > .42:  # feathering down the back of the upper legs
        return 800, .035, Vector((0, 1, -.6)), .1
    return None


def make_tufts(obj, rules, name):
    mesh = obj.data
    mesh.calc_loop_triangles()
    verts, faces, cols = [], [], []
    pts, normals = positions_and_normals(obj)
    for tri in mesh.loop_triangles:
        a, b, c = [pts[i] for i in tri.vertices]
        centre = (a + b + c) / 3
        nrm = normals[tri.vertices[0]]
        rule = rules(centre, nrm)
        if not rule:
            continue
        density, length, flow, darken = rule
        count = int((b - a).cross(c - a).length * .5 * density + rng.random())
        for _ in range(count):
            u, v = rng.random(), rng.random()
            if u + v > 1:
                u, v = 1 - u, 1 - v
            p = a + u * (b - a) + v * (c - a)
            tangent = flow - nrm * flow.dot(nrm)
            if tangent.length < 1e-5:
                tangent = Vector((0, 1, 0))
            tangent.normalize()
            d = (nrm * .32 + tangent * 1.0 + Vector((rng.gauss(0, .16), rng.gauss(0, .16), rng.gauss(0, .16)))).normalized()
            ln = length * rng.uniform(.65, 1.25)
            w = ln * rng.uniform(.17, .27)
            s = d.cross(Vector((.31, .52, .80))).normalized()
            uu = d.cross(s).normalized()
            root = p - nrm * ln * .18
            tip = p + d * ln
            base_col = tint(p, nrm, rng.random())
            tip_col = base_col.lerp(DARK if darken > 0 else CREAM, abs(darken))
            idx = len(verts)
            # Ring counterclockwise when seen from the tip, so each side faces out.
            ring = [root + s * w, root + uu * w, root - s * w, root - uu * w]
            verts.extend(ring + [tip])
            cols.extend([base_col] * 4 + [tip_col])
            for k in range(4):
                faces.append((idx + k, idx + (k + 1) % 4, idx + 4))
    if not faces:
        return None
    fm = bpy.data.meshes.new(name)
    fm.from_pydata(verts, [], faces)
    fm.materials.append(coat)
    ca = fm.color_attributes.new(name='Coat color', type='FLOAT_COLOR', domain='POINT')
    write_colors(ca, cols)
    fo = bpy.data.objects.new(name, fm)
    model.objects.link(fo)
    return fo


for o in list(model.objects):
    if o.type != 'MESH':
        continue
    if o.data.materials and o.data.materials[0] == mouth:
        color_mouth(o)
    elif o.name == 'Left ear':
        color_ear(o, -1)
    elif o.name == 'Right ear':
        color_ear(o, 1)
    elif o.data.materials and o.data.materials[0] == coat:
        color_object(o)
note('colored')
make_tufts(body, tuft_rules, 'Lean torso and neck tufts')
make_tufts(head, head_rules, 'Narrow head and raised upper muzzle tufts')
make_tufts(tail, tuft_rules, 'Bushy low tail tufts')
for name in ('Left foreleg', 'Right foreleg', 'Left hind leg', 'Right hind leg'):
    make_tufts(bpy.data.objects[name], leg_rules, name + ' tufts')
for o in model.objects:
    if o.type == 'CURVE' and o.name in solid_color:
        pass  # curves carry their color through the exporter's solid table below

# Curves (lips, claws) become meshes only on export; give them a color attribute
# there by name. The exporter reads this table from the root's custom property.
curve_colors = {name: [lin(c) for c in col] for name, col in solid_color.items()
                if bpy.data.objects[name].type == 'CURVE'}

note('tufts done')

# -- pivots, root, snarl preview ------------------------------------------------------------------
for name, loc in pivots.items():
    if name == 'Snarl jaw pivot':
        continue
    e = bpy.data.objects.new('Pivot ' + name, None)
    e.empty_display_size = .04
    model.objects.link(e)
    e.location = loc
scene.frame_start = 1
scene.frame_end = 30
scene.render.fps = 30
scene.frame_set(1)
root = bpy.data.objects.new('coyote', None)
model.objects.link(root)
for o in list(model.objects):
    if o != root and o.parent is None:
        o.parent = root
root['Notes'] = ('Coyote revision 2: lean and ragged, front -Y, Z up. Frames 1-30 preview a jaw snap. '
                 '"Pivot <part>" empties place the game joints; "<part> tufts" are the ragged outline the game keeps. '
                 'The gallop is added by scripts/blender/export_game_pickup.py.')
root['Curve colors'] = str(curve_colors)

# -- optional render-only strand fur ---------------------------------------------------------------------
if FUR:
    fur_material = mat('Directional guard hairs', (150, 122, 86), .7, vertex=True)
    for obj in (body, head, tail) + tuple(bpy.data.objects[n] for n in ('Left foreleg', 'Right foreleg', 'Left hind leg', 'Right hind leg')):
        mesh = obj.data
        mesh.calc_loop_triangles()
        verts, faces, cols = [], [], []
        pts, normals = positions_and_normals(obj)
        for tri in mesh.loop_triangles:
            a, b, c = [pts[i] for i in tri.vertices]
            count = int((b - a).cross(c - a).length * .5 * 14000 + rng.random())
            ns = [normals[i] for i in tri.vertices]
            for _ in range(count):
                u, v = rng.random(), rng.random()
                if u + v > 1:
                    u, v = 1 - u, 1 - v
                p = a + u * (b - a) + v * (c - a)
                nrm = (ns[0] * (1 - u - v) + ns[1] * u + ns[2] * v).normalized()
                flow = Vector((p.x * .4, .9, -.35))
                if p.z < .5:
                    flow = Vector((0, .1, -1))
                if p.y < -.5:
                    flow = Vector((p.x * 2, .3, -.35))
                tangent = (flow - nrm * flow.dot(nrm)).normalized()
                direction = (nrm * .46 + tangent * .88).normalized()
                length = rng.uniform(.01, .028)
                if p.z < .5 or p.y < -.66:
                    length *= .4
                if p.y > .70 or (-.56 < p.y < -.3 and p.z > .5):
                    length *= 1.5
                width = rng.uniform(.0003, .0005)
                across = direction.cross(Vector((.21, .35, .91))).normalized()
                idx = len(verts)
                verts.extend((p - across * width, p + across * width, p + direction * length))
                faces.append((idx, idx + 1, idx + 2))
                col = tint(p, nrm, rng.random()) * rng.uniform(.75, 1.15)
                cols.extend([(*[lin(clamp(x, 0, 255)) for x in col], 1)] * 3)
        fm = bpy.data.meshes.new(obj.name + ' fur mesh')
        fm.from_pydata(verts, [], faces)
        fm.materials.append(fur_material)
        ca = fm.color_attributes.new(name='Coat color', type='FLOAT_COLOR', domain='POINT')
        ca.data.foreach_set('color', [v for c in cols for v in c])
        fo = bpy.data.objects.new(obj.name + ' fur', fm)
        model.objects.link(fo)
        fo.parent = root

# -- studio ---------------------------------------------------------------------------------------------------
floor = mat('Warm neutral studio', (157, 151, 140), .9)
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.007))
o = bpy.context.object
o.name = 'Studio ground'
o.data.materials.append(floor)
move(o, studio)


def aim(o, p):
    o.rotation_euler = (Vector(p) - o.location).to_track_quat('-Z', 'Y').to_euler()


def camera(name, loc, target, scale):
    d = bpy.data.cameras.new(name)
    o = bpy.data.objects.new(name, d)
    studio.objects.link(o)
    o.location = loc
    aim(o, target)
    d.type = 'ORTHO'
    d.ortho_scale = scale
    return o


hero = camera('Portrait camera', (2.4, -3.7, 2.0), (0, .03, .57), 1.95)
front = camera('Front camera', (0, -4, 1.58), (0, -.25, .69), 1.73)
side = camera('Side camera', (4, -.1, 1.3), (0, .14, .65), 2.50)
# What the player sees: the coyote coming at the cart, from above and ahead of it.
game = camera('Game camera', (.9, -3.2, 2.6), (0, -.1, .62), 2.1)
for name, loc, energy, size in (('Soft key', (-2, -3, 4), 290, 3), ('Face fill', (2, -2, 2.2), 105, 2.4), ('Scruff rim', (1, 3, 3), 330, 2)):
    d = bpy.data.lights.new(name, 'AREA')
    d.energy = energy
    d.shape = 'DISK'
    d.size = size
    o = bpy.data.objects.new(name, d)
    studio.objects.link(o)
    o.location = loc
    aim(o, (0, 0, .7))
scene.world = bpy.data.worlds.new('Neutral world')
scene.world.color = (.13, .13, .13)
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 24 if QUICK else 64
scene.cycles.use_denoising = True
size = 640 if QUICK else 1100
scene.render.resolution_x = size
scene.render.resolution_y = size
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'AgX'
scene.camera = hero
bpy.ops.object.select_all(action='DESELECT')
root.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'coyote.blend'))
tris = sum(len(o.data.polygons) for o in model.objects if o.type == 'MESH' and not o.name.endswith(' fur'))
note('saved')
print('Saved coyote:', OUT / 'coyote.blend', 'source polygons', tris)
if RENDER:
    for cam, name in ((hero, 'portrait'), (front, 'front'), (side, 'side'), (game, 'game-view')):
        scene.camera = cam
        scene.render.filepath = str(PREVIEW / (name + '.png'))
        bpy.ops.render.render(write_still=True)
    scene.camera = hero
    scene.frame_set(14)
    scene.render.filepath = str(PREVIEW / 'snarl.png')
    bpy.ops.render.render(write_still=True)
    print('Rendered previews to', PREVIEW)
