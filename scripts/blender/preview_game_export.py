"""Render the game export itself: the decimated meshes, vertex colors, and baked
gallop from export_game_pickup.py's JSON, posed at chosen stride phases. This
is what SceneKit will draw, as near as Cycles can show it, so it is the check
to look at when there is no Mac for scripts/check_game_art.swift.

    python3 scripts/blender/run_bpy.py - scripts/blender/preview_game_export.py -- export.json OUT_DIR [phase ...]
"""
import json
import math
import sys
from pathlib import Path
import bpy
from mathutils import Vector, Quaternion

argv = sys.argv[sys.argv.index('--') + 1:]
asset = json.loads(Path(argv[0]).read_text())
out = Path(argv[1])
out.mkdir(parents=True, exist_ok=True)
phases = [float(p) for p in argv[2:]] or [0.0, 0.25, 0.5, 0.75]

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def to_blender(v):
    """Game (x, y up, z toward camera) -> Blender (x, -z, y)."""
    return Vector((v[0], -v[2], v[1]))


def srgb(c):
    return c / 12.92 if c <= .0031308 else 1.055 * c ** (1 / 2.4) - .055


materials = {}
for m in asset['materials']:
    mat = bpy.data.materials.new(m['name'])
    bsdf = mat.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Roughness'].default_value = m['roughness']
    if m['vertexColor']:
        node = mat.node_tree.nodes.new('ShaderNodeVertexColor')
        node.layer_name = 'Col'
        mat.node_tree.links.new(node.outputs['Color'], bsdf.inputs['Base Color'])
    else:
        bsdf.inputs['Base Color'].default_value = m['color']
    if m.get('emission'):
        bsdf.inputs['Emission Color'].default_value = (*m['emission'], 1)
        bsdf.inputs['Emission Strength'].default_value = 1
    materials[m['name']] = mat

nodes = {}
for p in asset['parts']:
    if p.get('vertices'):
        v = p['vertices']
        verts = [to_blender(v[i:i + 3]) for i in range(0, len(v), 3)]
        idx = p['indices']
        faces = [(idx[i], idx[i + 1], idx[i + 2]) for i in range(0, len(idx), 3)]
        mesh = bpy.data.meshes.new(p['name'])
        mesh.from_pydata(verts, [], faces)
        mesh.materials.append(materials[p['material']])
        ca = mesh.color_attributes.new(name='Col', type='FLOAT_COLOR', domain='POINT')
        ca.data.foreach_set('color', p['colors'])
        # Flat faces show the real game triangles; smooth would flatter the decimation.
        for poly in mesh.polygons:
            poly.use_smooth = True
        obj = bpy.data.objects.new(p['name'], mesh)
    else:
        obj = bpy.data.objects.new(p['name'], None)
    scene.collection.objects.link(obj)
    obj.rotation_mode = 'QUATERNION'
    obj.location = to_blender(p['position'])
    nodes[p['name']] = obj
for p in asset['parts']:
    if p['parent']:
        nodes[p['name']].parent = nodes[p['parent']]

frames = asset['frames']


def pose(phase):
    f = int(round(phase * frames)) % (frames + 1)
    for name, track in asset['anim'].items():
        obj = nodes[name]
        obj.location = to_blender(track['position'][f])
        qx, qy, qz, qw = track['orientation'][f]
        # Game quaternion (x, y up, z) -> Blender (x, -z, y) keeps the same handedness.
        obj.rotation_quaternion = Quaternion((qw, qx, -qz, qy))


# Studio: a floor, two lamps, and cameras for the player's view and the side.
floor_mat = bpy.data.materials.new('floor')
floor_mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (.35, .33, .30, 1)
bpy.ops.mesh.primitive_plane_add(size=50, location=(0, 0, -.005))
bpy.context.object.data.materials.append(floor_mat)


def aim(o, target):
    o.rotation_euler = (Vector(target) - o.location).to_track_quat('-Z', 'Y').to_euler()


def camera(name, loc, target, scale):
    cam = bpy.data.cameras.new(name)
    cam.type = 'ORTHO'
    cam.ortho_scale = scale
    o = bpy.data.objects.new(name, cam)
    scene.collection.objects.link(o)
    o.location = loc
    aim(o, target)
    return o


game_cam = camera('game', (.8, -3.0, 2.3), (0, -.1, .55), 1.9)
side_cam = camera('side', (4, 0, 1.0), (0, .1, .55), 2.3)
for name, loc, energy in (('key', (-2, -3, 4), 400), ('fill', (2.5, -2, 2), 150), ('rim', (1, 3, 3), 250)):
    light = bpy.data.lights.new(name, 'AREA')
    light.energy = energy
    light.size = 3
    o = bpy.data.objects.new(name, light)
    scene.collection.objects.link(o)
    o.location = loc
    aim(o, (0, 0, .6))
scene.world = bpy.data.worlds.new('w')
scene.world.color = (.2, .2, .2)
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 24
scene.cycles.use_denoising = True
scene.render.resolution_x = scene.render.resolution_y = 560
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'AgX'
for phase in phases:
    pose(phase)
    for cam, tag in ((game_cam, 'game'), (side_cam, 'side')):
        scene.camera = cam
        scene.render.filepath = str(out / f'{tag}-{int(phase * 100):02d}.png')
        bpy.ops.render.render(write_still=True)
print('rendered', out)
