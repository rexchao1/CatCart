"""Editable portrait study. Run with Blender --background --python this_file.

Reuses the game's kitten proportions, keeping this art option separate from
its live model. No reference photos are read, embedded, or exported.
"""
from pathlib import Path
import math
import random
import runpy
import sys
import tempfile
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'art/options/kitten-study'
OUT.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory() as tmp:
    sys.argv = ['make_cat.py', '--', str(Path(tmp) / 'base.usdc')]
    base = runpy.run_path(str(ROOT / 'scripts/blender/make_cat.py'))
scene = bpy.context.scene

# Muted warm gray, like the photograph. Colors are entered in sRGB.
def color(rgb):
    return tuple(base['srgb_to_lin'](v) for v in rgb) + (1,)

for name, rgb in {'kittenCoat': (122, 119, 122),
                  'kittenMuzzle': (140, 135, 136),
                  'kittenEarInner': (148, 122, 126),
                  'kittenIris': (151, 123, 68),
                  'kittenNose': (92, 83, 87),
                  'kittenWhisker': (190, 186, 183)}.items():
    mat = bpy.data.materials[name]
    mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value = color(rgb)

# Bring the face closer to the photo: less dome above the eyes, inset eyes,
# and a large dark pupil with a narrow muted amber iris.
head = bpy.data.objects['head']
for vertex in head.data.vertices:
    world_z = (head.matrix_world @ vertex.co).z
    if world_z > .66:
        vertex.co.z -= (world_z - .66) * .22
for name in ('earL', 'earR'):
    bpy.data.objects[name].location.z -= .049
for name in ('eyeL', 'eyeR'):
    bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)
for side in (-1, 1):
    center = Vector((side*.127, .296, .674))
    rotation = Matrix.Rotation(-side*math.radians(18), 4, 'Z')
    forward = rotation @ Vector((0,1,0))
    pieces = []
    for label, offset, scale, mat in (
        ('Eye rim', -.005, (.070,.020,.072), 'mouth'),
        ('Amber iris', .004, (.064,.018,.066), 'iris'),
        ('Dark pupil', .020, (.046,.009,.053), 'pupil')):
        obj = base['ellipsoid'](center+forward*offset, scale, segs=48, rings=32)
        obj.name = label
        obj.data.transform(Matrix.Translation(center) @ rotation @ Matrix.Translation(-center))
        obj.data.materials.append(base['MAT'][mat])
        bpy.ops.object.shade_smooth()
        pieces.append(obj)
    eye = base['join'](pieces, 'eyeL' if side < 0 else 'eyeR')
    base['set_origin'](eye,center)
    base['parent'](eye,head)

# Short dense plush coat, plus fine surface grain that stays visible close up.
coat = bpy.data.materials['kittenCoat']
bsdf = coat.node_tree.nodes.get('Principled BSDF')
bsdf.inputs['Roughness'].default_value = 0.86
bsdf.inputs['Sheen Weight'].default_value = 0.12
noise = coat.node_tree.nodes.new('ShaderNodeTexNoise')
noise.inputs['Scale'].default_value = 190
noise.inputs['Detail'].default_value = 2
bump = coat.node_tree.nodes.new('ShaderNodeBump')
bump.inputs['Strength'].default_value = 0.08
bump.inputs['Distance'].default_value = 0.007
coat.node_tree.links.new(noise.outputs['Fac'], bump.inputs['Height'])
coat.node_tree.links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
for name in ('kittenIris', 'kittenPupil'):
    shader = bpy.data.materials[name].node_tree.nodes.get('Principled BSDF')
    shader.inputs['Roughness'].default_value = 0.23
    shader.inputs['Coat Weight'].default_value = 0.32

# Editable tapered fur ribbons. Sample only the gray coat faces, keeping the
# eyes, nose, and mouth clear. Seed makes a rebuild reproducible.
rng = random.Random(31)
verts, faces = [], []
for name in ('body', 'head', 'tail', 'tailTip', 'earL', 'earR'):
    obj = bpy.data.objects[name]
    obj.data.calc_loop_triangles()
    matrix = obj.matrix_world
    normal_matrix = matrix.to_3x3().inverted().transposed()
    for tri in obj.data.loop_triangles:
        if obj.data.materials[tri.material_index] != coat:
            continue
        a, b, c = [matrix @ obj.data.vertices[i].co for i in tri.vertices]
        area = (b-a).cross(c-a).length / 2
        count = int(area * 22000 + rng.random())
        normals = [(normal_matrix @ obj.data.vertices[i].normal).normalized() for i in tri.vertices]
        for _ in range(count):
            u, v = rng.random(), rng.random()
            if u + v > 1:
                u, v = 1-u, 1-v
            p = a + u*(b-a) + v*(c-a)
            n = (normals[0]*(1-u-v) + normals[1]*u + normals[2]*v).normalized()
            tangent = n.cross(Vector((0.31, 0.17, 1))).normalized()
            length = rng.uniform(0.004, 0.010)
            width = rng.uniform(0.00035, 0.00065)
            drift = Vector((rng.uniform(-.2,.2), rng.uniform(-.2,.2), -.23))
            index = len(verts)
            verts.extend((p-tangent*width, p+tangent*width, p+(n+drift)*length))
            faces.append((index,index+1,index+2))
mesh = bpy.data.meshes.new('Short plush coat mesh')
mesh.from_pydata(verts, [], faces)
mesh.materials.append(coat)
fur = bpy.data.objects.new('Short plush coat', mesh)
scene.collection.objects.link(fur)

# A quiet mint studio gives the gray silhouette a readable edge.
stage = base['material']('Studio mint', (185, 211, 207))
bpy.ops.mesh.primitive_plane_add(size=200, location=(0,0,-0.012))
floor = bpy.context.object
floor.name = 'Studio floor'
floor.data.materials.append(stage)

def aim(obj, point):
    obj.rotation_euler = (Vector(point)-obj.location).to_track_quat('-Z','Y').to_euler()

def camera(name, location, target, scale):
    data = bpy.data.cameras.new(name)
    obj = bpy.data.objects.new(name,data)
    scene.collection.objects.link(obj)
    obj.location = location
    aim(obj,target)
    data.type = 'ORTHO'
    data.ortho_scale = scale
    data.lens = 70
    return obj

hero = camera('Portrait camera', (1.25, 2.8, 1.34), (0,0,0.46), 1.47)
rear = camera('Rear silhouette camera', (-1.45,-2.8,1.5), (0,-.06,.46), 1.47)
front = camera('Face camera', (0,3,1.04), (0,.02,.47), 1.38)

def light(name, position, power, size, rgb):
    data = bpy.data.lights.new(name,'AREA')
    data.energy = power
    data.shape = 'DISK'
    data.size = size
    data.color = rgb
    obj = bpy.data.objects.new(name,data)
    scene.collection.objects.link(obj)
    obj.location = position
    aim(obj,(0,0,.5))

light('Large warm key',(-2,3,3.7),220,3,(1,.91,.83))
light('Soft face fill',(2,1.4,2),85,2.5,(.83,.91,1))
light('Ear and tail rim',(.5,-2,2.8),260,2,(1,.96,.9))
scene.world = bpy.data.worlds.new('Studio world')
scene.world.color = (.22,.22,.22)
scene.render.engine = 'CYCLES'
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.resolution_x = 1100
scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'AgX'
scene.camera = hero
scene['Art note'] = 'First photo-based study: warm dove-gray coat, copper-olive eyes, compact sitting pose. Review before game integration.'
for obj in scene.objects:
    obj.select_set(False)
bpy.context.view_layer.objects.active = bpy.data.objects['head']
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == 'VIEW_3D':
            area.spaces.active.region_3d.view_perspective = 'CAMERA'
            area.spaces.active.shading.type = 'MATERIAL'
            area.spaces.active.overlay.show_overlays = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'kitten-study-v1.blend'))
for cam, filename in ((hero,'portrait.png'), (front,'front.png'), (rear,'rear.png')):
    scene.camera = cam
    scene.render.filepath = str(OUT / filename)
    bpy.ops.render.render(write_still=True)
print('Saved kitten study and three views:', OUT)
