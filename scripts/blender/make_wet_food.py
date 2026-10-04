"""Build the turquoise wet-food pickup as an editable, self-contained Blender file.
Run make_food_label.py first, then run this with Blender --background --python.
The model collection is separate from the studio and thumbnail cameras.
"""
from pathlib import Path
import bpy
import math
import random
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'art/models/food'
PREVIEW=ROOT/'art/options/food/wet-food-3d'
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
model=bpy.data.collections.new('Wet food pickup'); scene.collection.children.link(model)
studio=bpy.data.collections.new('Preview studio'); scene.collection.children.link(studio)
rng=random.Random(12)
def move(obj,collection=model):
    for old in list(obj.users_collection): old.objects.unlink(obj)
    collection.objects.link(obj)
    return obj

def linear(c):
    c/=255
    return c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4

def material(name,rgb,metal=0,rough=.45):
    mat=bpy.data.materials.new(name)
    s=mat.node_tree.nodes.get('Principled BSDF')
    s.inputs['Base Color'].default_value=(*map(linear,rgb),1)
    s.inputs['Metallic'].default_value=metal
    s.inputs['Roughness'].default_value=rough
    mat.diffuse_color=(*map(linear,rgb),1)
    return mat
metal=material('Brushed aluminum',(190,211,219),.8,.26)
edge=material('Polished rolled rims',(219,237,241),.82,.2)
gravy=material('Glossy salmon gravy',(120,64,34),0,.23)
gravy.node_tree.nodes.get('Principled BSDF').inputs['Coat Weight'].default_value=.38
salmon=[material('Salmon morsel '+str(i),rgb,0,.4) for i,rgb in enumerate(((202,132,100),(175,103,73),(220,150,111),(156,88,62)))]
label=material('Turquoise label',(0,184,208),0,.43)
tex=label.node_tree.nodes.new('ShaderNodeTexImage')
tex.image=bpy.data.images.load(str(OUT/'label.png')); tex.image.pack()
label.node_tree.links.new(tex.outputs['Color'],label.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])

def finish(obj,name,mat):
    obj.name=name; obj.data.materials.append(mat); move(obj)
    for p in obj.data.polygons: p.use_smooth=True
    return obj

def cylinder(name,radius,depth,loc,mat,bevel=0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=96,radius=radius,depth=depth,location=loc)
    obj=finish(bpy.context.object,name,mat)
    if bevel:
        m=obj.modifiers.new('Rounded metal edge','BEVEL'); m.width=bevel; m.segments=3
        m=obj.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    return obj

def torus(name,radius,tube,z,mat):
    bpy.ops.mesh.primitive_torus_add(major_radius=radius,minor_radius=tube,major_segments=96,minor_segments=12,location=(0,0,z))
    return finish(bpy.context.object,name,mat)

# One hollow wall, including the interior: lathed section keeps the top open.
profile=[(.434,.027),(.454,.041),(.457,.078),(.457,.401),(.449,.427),(.428,.427),(.428,.074),(.416,.052)]
verts=[]; faces=[]; n=96
for radius,z in profile:
    for j in range(n):
        a=2*math.pi*j/n; verts.append((radius*math.sin(a),-radius*math.cos(a),z))
for i in range(len(profile)-1):
    for j in range(n): faces.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
mesh=bpy.data.meshes.new('Hollow aluminum can'); mesh.from_pydata(verts,[],faces)
obj=bpy.data.objects.new('Can wall and inner liner',mesh); model.objects.link(obj); mesh.materials.append(metal)
for p in mesh.polygons:p.use_smooth=True
cylinder('Can bottom',.435,.023,(0,0,.035),metal,.005)
torus('Bottom rolled rim',.441,.015,.043,edge)
torus('Top rolled rim',.443,.018,.425,edge)
torus('Inner open edge',.424,.007,.417,metal)

# Explicit UV strip: the main label panel faces -Y, toward the game camera.
verts=[]; faces=[]
for z in (.083,.397):
    for j in range(n+1):
        a=-math.pi+2*math.pi*j/n
        verts.append((.459*math.sin(a),-.459*math.cos(a),z))
for j in range(n):faces.append((j,j+1,n+2+j,n+1+j))
mesh=bpy.data.meshes.new('Wrapped label mesh'); mesh.from_pydata(verts,[],faces)
mesh.materials.append(label)
uv=mesh.uv_layers.new(name='Label UV')
for poly in mesh.polygons:
    poly.use_smooth=True
    for li in poly.loop_indices:
        vi=mesh.loops[li].vertex_index
        uv.data[li].uv=(vi%(n+1)/n,0 if vi<n+1 else 1)
obj=bpy.data.objects.new('Printed turquoise wrap',mesh); model.objects.link(obj)

# Visible wet food. Broad gravy pools separate irregular salmon chunks.
cylinder('Gravy surface',.416,.026,(0,0,.378),gravy,.007)
for i in range(53):
    a=rng.random()*math.tau; r=.375*math.sqrt(rng.random())
    x,y=r*math.cos(a),r*math.sin(a)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=(x,y,.394+rng.uniform(-.004,.015)))
    obj=finish(bpy.context.object,'Salmon chunk %02d'%i,salmon[i%4])
    obj.scale=(rng.uniform(.031,.070),rng.uniform(.028,.06),rng.uniform(.017,.030))
    obj.rotation_euler=(rng.uniform(-.2,.2),rng.uniform(-.2,.2),rng.random()*math.tau)
    for v in obj.data.vertices:v.co*=rng.uniform(.90,1.10)
    m=obj.modifiers.new('Soft food edges','BEVEL'); m.width=.065; m.segments=2

# A hinged, lifted lid gives the pickup a distinctive outline at small sizes.
hinge=Vector((0,.419,.429)); rot=Matrix.Rotation(math.radians(-140),4,'X')
def lift(obj):
    obj.location=hinge+rot@(obj.location-hinge)
    obj.rotation_euler=rot.to_euler()
    return obj
lift(cylinder('Peeled lid',.427,.012,(0,0,.429),metal,.006))
lift(torus('Lid rolled edge',.418,.010,.435,edge))
for radius in (.29,.345,.382):
    lift(torus('Lid embossed ring',radius,.003,.438,metal))
    lift(torus('Lid underside ring',radius,.002,.420,metal))
# An actual opening through the pull tab, not a painted oval.
bpy.ops.mesh.primitive_torus_add(major_radius=.078,minor_radius=.012,major_segments=40,minor_segments=10,location=(0,-.12,.452))
obj=finish(bpy.context.object,'Oval pull ring',edge)
obj.scale=(.68,1.0,.4); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
lift(obj)
lift(cylinder('Pull tab rivet',.023,.013,(0,-.025,.451),edge,.005))

root=bpy.data.objects.new('wet_food',None); model.objects.link(root)
for obj in list(model.objects):
    if obj!=root:obj.parent=root
root['Description']='Turquoise open salmon wet-food can; front faces -Y, Z up, base at zero.'
root['Game integration']='Source model only. Export collection Wet food pickup; exclude Preview studio.'

# Studio is deliberately separate so it cannot accidentally ship as pickup geometry.
floor=material('Studio slate',(35,48,65),0,.85)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,.012))
obj=bpy.context.object; obj.name='Preview ground'; obj.data.materials.append(floor); move(obj,studio)
def aim(obj,point):obj.rotation_euler=(Vector(point)-obj.location).to_track_quat('-Z','Y').to_euler()
def camera(name,loc,target,scale):
    data=bpy.data.cameras.new(name); obj=bpy.data.objects.new(name,data); studio.objects.link(obj)
    obj.location=loc; aim(obj,target); data.type='ORTHO'; data.ortho_scale=scale; return obj
hero=camera('Product camera',(1.15,-2.8,1.8),(0,.22,.47),1.80)
pickup=camera('Pickup readability camera',(.18,-3,1.75),(0,.20,.47),1.78)
for name,loc,power,size in (('Large softbox',(-2,-3,4),260,3),('Turquoise fill',(2,-1,2.3),140,2),('Lid rim light',(0,3,3),350,2)):
    data=bpy.data.lights.new(name,'AREA'); data.energy=power; data.shape='DISK'; data.size=size
    obj=bpy.data.objects.new(name,data); studio.objects.link(obj); obj.location=loc; aim(obj,(0,0,.4))
scene.world=bpy.data.worlds.new('Neutral studio world');scene.world.color=(.17,.17,.17)
scene.render.engine='CYCLES';scene.cycles.samples=64;scene.cycles.use_denoising=True
scene.view_settings.view_transform='AgX'
scene.render.resolution_x=1200;scene.render.resolution_y=1200;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.camera=hero
bpy.ops.object.select_all(action='DESELECT'); root.select_set(True); bpy.context.view_layer.objects.active=root
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA'
            area.spaces.active.overlay.show_overlays=False
            area.spaces.active.shading.type='MATERIAL'
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'wet-food.blend'))
scene.render.filepath=str(PREVIEW/'portrait.png');bpy.ops.render.render(write_still=True)
scene.camera=pickup;scene.render.film_transparent=True
bpy.data.objects['Preview ground'].hide_render=True
scene.render.resolution_x=512;scene.render.resolution_y=512
scene.render.filepath=str(PREVIEW/'pickup.png');bpy.ops.render.render(write_still=True)
print('Saved',OUT/'wet-food.blend')
