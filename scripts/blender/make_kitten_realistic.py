"""Natural-proportion kitten study, built locally without embedding the photo.
Run: Blender --background --python-exit-code 1 --python this_file
"""
from pathlib import Path
import math
import random
import bpy
from mathutils import Vector

OUT = Path(__file__).resolve().parents[2] / 'art/options/kitten-realistic-v2'
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
rng = random.Random(73)

def lin(c):
    c /= 255
    return c/12.92 if c <= .04045 else ((c+.055)/1.055)**2.4

def material(name, rgb, rough=.7):
    mat = bpy.data.materials.new(name)
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*map(lin,rgb),1)
    shader.inputs['Roughness'].default_value = rough
    mat.diffuse_color = (*map(lin,rgb),1)
    return mat

coat = material('Warm dove gray coat',(112,108,111))
inner = material('Muted inner ear skin',(116,94,97))
nosemat = material('Charcoal rose nose leather',(69,59,63),.46)
lipmat = material('Dark eyelid and lip',(42,37,39),.5)
whiskermat = material('Fine gray ivory whiskers',(168,164,160),.6)
shader = coat.node_tree.nodes.get('Principled BSDF')
shader.inputs['Sheen Weight'].default_value = .15
noise = coat.node_tree.nodes.new('ShaderNodeTexNoise')
noise.inputs['Scale'].default_value = 115
bump = coat.node_tree.nodes.new('ShaderNodeBump')
bump.inputs['Strength'].default_value = .13
bump.inputs['Distance'].default_value = .003
coat.node_tree.links.new(noise.outputs['Fac'],bump.inputs['Height'])
coat.node_tree.links.new(bump.outputs['Normal'],shader.inputs['Normal'])

fur_objects = []
def smooth(obj):
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj

def ell(name, center, scale, mat=coat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48,ring_count=32,location=center)
    obj=bpy.context.object
    obj.name=name
    obj.scale=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    obj.data.materials.append(mat)
    return smooth(obj)

def fuse(name, parts, voxel=.005):
    bpy.ops.object.select_all(action='DESELECT')
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.object.join()
    obj=parts[0]
    obj.name=name
    mod=obj.modifiers.new('Continuous anatomy','REMESH')
    mod.mode='VOXEL'
    mod.voxel_size=voxel
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mod=obj.modifiers.new('Soften transitions','SMOOTH')
    mod.factor=.55
    mod.iterations=9
    bpy.ops.object.modifier_apply(modifier=mod.name)
    smooth(obj)
    fur_objects.append(obj)
    return obj

def curve(name, pts, radius, mat, taper=True):
    data=bpy.data.curves.new(name,'CURVE')
    data.dimensions='3D'
    data.resolution_u=10
    data.bevel_depth=radius
    data.bevel_resolution=3
    data.use_fill_caps=True
    spline=data.splines.new('BEZIER')
    spline.bezier_points.add(len(pts)-1)
    for i,(p,co) in enumerate(zip(spline.bezier_points,pts)):
        p.co=co
        p.handle_left_type=p.handle_right_type='AUTO'
        p.radius=(1-i/(len(pts)-1)*.85) if taper else 1
    obj=bpy.data.objects.new(name,data)
    scene.collection.objects.link(obj)
    data.materials.append(mat)
    return obj

# Seated anatomy: weight over the rear haunches, shoulders above the front feet.
body=fuse('Torso and haunches',[
    ell('Pelvis',(0,-.12,.25),(.245,.265,.255)),
    ell('Ribcage',(0,-.025,.43),(.196,.22,.29)),
    ell('Shoulders',(0,.025,.58),(.155,.165,.205)),
    ell('Neck',(0,.06,.67),(.132,.14,.18)),
    ell('Left folded thigh',(-.181,-.06,.19),(.135,.205,.18)),
    ell('Right folded thigh',(.181,-.06,.19),(.135,.205,.18)),
    ell('Left rear foot',(-.207,.085,.055),(.087,.15,.057)),
    ell('Right rear foot',(.207,.085,.055),(.087,.15,.057)),
])
for side in (-1,1):
    fuse('Left foreleg' if side < 0 else 'Right foreleg',[
        ell('Upper foreleg',(side*.094,.106,.36),(.067,.084,.19)),
        ell('Forearm',(side*.097,.17,.19),(.053,.060,.17)),
        ell('Front paw',(side*.101,.209,.048),(.068,.098,.051)),
    ],.0035)
    for dx in (-.022,.020):
        curve('Subtle toe crease',[(side*.101+dx,.293,.039),(side*.101+dx,.287,.06),(side*.101+dx,.27,.074)],.0012,coat)

head=fuse('Head cheeks and short muzzle',[
    ell('Skull',(0,.071,.783),(.209,.18,.187)),
    ell('Left cheek',(-.126,.114,.710),(.102,.119,.108)),
    ell('Right cheek',(.126,.114,.710),(.102,.119,.108)),
    ell('Jaw',(0,.137,.669),(.124,.105,.062)),
    ell('Nose bridge',(0,.223,.749),(.052,.052,.089)),
    ell('Left whisker pad',(-.042,.255,.679),(.061,.046,.041)),
    ell('Right whisker pad',(.042,.255,.679),(.061,.046,.041)),
    ell('Chin',(0,.226,.643),(.063,.047,.028)),
],.003)

# Lower the skull dome to match the reference's less exaggerated forehead.
for vertex in head.data.vertices:
    world_z=(head.matrix_world@vertex.co).z
    if world_z>.81:
        vertex.co.z-=(world_z-.81)*.21

# Cupped ears have a thick rim and a recessed, darker inner bowl.
for side in (-1,1):
    base=Vector((side*.149,.064,.865))
    outline=[(-.078,0,0),(-.069,-.014,.065),(-.045,-.027,.147),
             (-.028,-.023,.164),(-.010,-.015,.157),(.067,.005,.038),(.079,.012,0)]
    if side < 0:
        outline=[(-x,y,z) for x,y,z in outline[::-1]]
    verts=[]
    center=Vector((side*.009,.017,.066))
    for r in (1,.79,.52,.24):
        for x,y,z in outline:
            p=Vector((x,y,z))*r+center*(1-r)
            p.z *= .83
            p.y += (1-r)*-.032
            p.x += side*p.z*.24
            verts.append(base+p)
    verts.append(base+center+Vector((side*.016,-.027,0)))
    n=len(outline)
    faces=[]
    mats=[]
    for ring in range(3):
        for j in range(n):
            faces.append((ring*n+j,ring*n+(j+1)%n,(ring+1)*n+(j+1)%n,(ring+1)*n+j))
            mats.append(0 if ring==0 else 1)
    for j in range(n):
        faces.append((3*n+j,3*n+(j+1)%n,4*n))
        mats.append(1)
    mesh=bpy.data.meshes.new('Cupped ear mesh')
    mesh.from_pydata(verts,[],faces)
    mesh.materials.append(coat)
    mesh.materials.append(inner)
    obj=bpy.data.objects.new('Left ear' if side<0 else 'Right ear',mesh)
    scene.collection.objects.link(obj)
    for p,m in zip(mesh.polygons,mats): p.material_index=m
    mod=obj.modifiers.new('Rounded ear contour','SUBSURF'); mod.levels=2
    bpy.context.view_layer.objects.active=obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mod=obj.modifiers.new('Ear thickness','SOLIDIFY'); mod.thickness=.013; mod.material_offset=-1
    bpy.ops.object.modifier_apply(modifier=mod.name)
    smooth(obj)
    fur_objects.append(obj)

# Almond eye openings follow the round head. Iris fibers use radial vertex
# colors, so the amber ring is part of the eye surface rather than a button.
eye_mat=material('Copper olive eyes',(110,90,49),.26)
nt=eye_mat.node_tree
attr=nt.nodes.new('ShaderNodeVertexColor'); attr.layer_name='Iris color'
nt.links.new(attr.outputs['Color'],nt.nodes.get('Principled BSDF').inputs['Base Color'])
nt.nodes.get('Principled BSDF').inputs['Coat Weight'].default_value=.28
for side in (-1,1):
    center=Vector((side*.098,.236,.776))
    vertices=[center+Vector((0,.035,0))]
    colors=[(.004,.005,.004,1)]
    steps=128
    rings=24
    streak=[rng.uniform(.72,1.23) for _ in range(steps)]
    for k in range(1,rings+1):
        r=k/rings
        for j in range(steps):
            t=2*math.pi*j/steps
            x=.056*r*math.cos(t)
            z=.039*r*math.sin(t)*(abs(math.sin(t))**.18)+side*x*.10
            y=.035*(1-r*r)-side*x*.20
            vertices.append(center+Vector((x,y,z)))
            if r<.63:
                col=(.003,.004,.003,1)
            elif r>.94:
                col=(.022,.019,.012,1)
            else:
                strength=streak[j]*(.7+.3*math.sin((r-.63)/.31*math.pi))
                col=(.17*strength,.135*strength,.065*strength,1)
            colors.append(col)
    faces=[]
    for j in range(steps): faces.append((0,1+j,1+(j+1)%steps))
    for k in range(rings-1):
        for j in range(steps):
            a=1+k*steps+j; b=1+k*steps+(j+1)%steps
            faces.append((a,b,b+steps,a+steps))
    mesh=bpy.data.meshes.new('Inset eye surface')
    mesh.from_pydata(vertices,[],faces)
    mesh.materials.append(eye_mat)
    ca=mesh.color_attributes.new(name='Iris color',type='FLOAT_COLOR',domain='POINT')
    for v,c in zip(ca.data,colors): v.color=c
    obj=bpy.data.objects.new('Left eye' if side<0 else 'Right eye',mesh)
    scene.collection.objects.link(obj); smooth(obj)
    for upper in (False,True):
        pts=[]
        for j in range(17):
            t=(j/16*math.pi)+(0 if upper else math.pi)
            x=.056*math.cos(t)
            z=.039*math.sin(t)*abs(math.sin(t))**.18+side*x*.1
            pts.append(center+Vector((x,-side*x*.2+.0005,z)))
        curve('Fine eyelid edge',pts,.0025,lipmat,False)
        # Gray lid lies just outside the dark wet edge.
        pts=[p+Vector(((p.x-center.x)*.075,-.002,(p.z-center.z)*.11)) for p in pts]
        lid=curve('Furred upper lid' if upper else 'Furred lower lid',pts,.0045,coat,False)
        bpy.context.view_layer.objects.active=lid
        lid.select_set(True)
        bpy.ops.object.convert(target='MESH')
        fur_objects.append(bpy.context.object)
        bpy.context.object.select_set(False)

# Small broad triangular nose and a restrained feline mouth.
verts=[(-.032,.294,.710),(.032,.294,.710),(.018,.313,.699),(0,.319,.680),(-.018,.313,.699),
       (-.023,.284,.694),(.023,.284,.694),(0,.294,.677)]
faces=[(0,1,2,3,4),(0,5,6,1),(5,7,6),(0,4,3,7,5),(1,6,7,3,2)]
mesh=bpy.data.meshes.new('Triangular nose mesh'); mesh.from_pydata(verts,[],faces); mesh.materials.append(nosemat)
obj=bpy.data.objects.new('Nose',mesh); scene.collection.objects.link(obj)
mod=obj.modifiers.new('Soft nose edges','BEVEL'); mod.width=.006; mod.segments=3
smooth(obj)
for side in (-1,1):
    ell('Nostril',(side*.020,.310,.696),(.007,.003,.0035),lipmat)
    curve('Mouth line',[(0,.304,.681),(0,.303,.662),(side*.025,.293,.654),(side*.045,.277,.658)],.0018,lipmat)
    for i in range(6):
        z=.672+(i-2.5)*.006
        x=side*(.052+(i%2)*.009)
        curve('Whisker',[(x,.292,z),(side*.108,.308,z+.005),(side*.184,.300,z+(i-2.5)*.012),
                         (side*(.248+(.015 if i%2 else 0)),.274,z+(i-2.5)*.023)],.00065,whiskermat)
    for i in range(3):
        curve('Brow whisker',[(side*.115,.204,.855),(side*.16,.220,.887),(side*.20,.216,.921+i*.01)],.00038,whiskermat)

# Thick tail rests beside the feet, as in the reference photograph.
tail=curve('Resting tail',[(.08,-.30,.115),(.28,-.28,.072),(.355,-.08,.057),(.32,.16,.049),(.23,.295,.043),(.08,.34,.040)],.059,coat,False)
bpy.context.view_layer.objects.active=tail
bpy.ops.object.select_all(action='DESELECT'); tail.select_set(True)
bpy.ops.object.convert(target='MESH')
tail_mesh=bpy.context.object
fuse('Rounded resting tail',[tail_mesh,ell('Rounded tail tip',(.08,.34,.040),(.060,.060,.055))],.0035)

# Fine tapered fibers comb downward on the chest and outward over cheeks.
fur_mats=[material('Fur shade '+str(i),(v,v-3,v-1),.84) for i,v in enumerate((100,110,120,130))]
vertices=[]; faces=[]; indices=[]
for obj in fur_objects:
    obj.data.calc_loop_triangles()
    mat_world=obj.matrix_world
    normals=mat_world.to_3x3().inverted().transposed()
    for tri in obj.data.loop_triangles:
        if obj.data.materials and obj.data.materials[tri.material_index] != coat: continue
        a,b,c=[mat_world@obj.data.vertices[i].co for i in tri.vertices]
        area=(b-a).cross(c-a).length*.5
        count=int(area*52000+rng.random())
        ns=[(normals@obj.data.vertices[i].normal).normalized() for i in tri.vertices]
        for _ in range(count):
            u,v=rng.random(),rng.random()
            if u+v>1: u,v=1-u,1-v
            p=a+u*(b-a)+v*(c-a)
            n=(ns[0]*(1-u-v)+ns[1]*u+ns[2]*v).normalized()
            direction=Vector((p.x*.3,0,-.8))
            if p.z>.63: direction=Vector((p.x*2,-.2,-.18))
            tangent=(direction-n*direction.dot(n)).normalized()
            length=rng.uniform(.006,.014) if p.z<.64 else rng.uniform(.003,.008)
            along=(n*.6+tangent*.8).normalized()
            across=along.cross(Vector((.13,.73,.31))).normalized()
            width=rng.uniform(.00016,.00030)
            idx=len(vertices)
            vertices.extend((p-across*width,p+across*width,p+along*length*.55+n*.001,p+along*length))
            faces.extend(((idx,idx+1,idx+2),(idx+1,idx+3,idx+2)))
            shade=rng.randrange(4); indices.extend((shade,shade))
mesh=bpy.data.meshes.new('Directional short fur mesh'); mesh.from_pydata(vertices,[],faces)
for mat in fur_mats: mesh.materials.append(mat)
for face,index in zip(mesh.polygons,indices): face.material_index=index
obj=bpy.data.objects.new('Directional short fur',mesh); scene.collection.objects.link(obj)

floor_mat=material('Warm studio floor',(178,176,166))
ell('Low display cushion',(0,0,-.035),(.63,.59,.047),floor_mat)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.061))
bpy.context.object.name='Studio floor'; bpy.context.object.data.materials.append(floor_mat)

def aim(obj,target): obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()
def camera(name,loc,target,scale):
    data=bpy.data.cameras.new(name); obj=bpy.data.objects.new(name,data); scene.collection.objects.link(obj)
    obj.location=loc; aim(obj,target); data.type='ORTHO'; data.ortho_scale=scale
    return obj
hero=camera('Portrait camera',(1.1,3,1.5),(0,.035,.49),1.43)
front=camera('Front camera',(0,3,1.2),(0,.04,.51),1.38)
rear=camera('Rear camera',(-1.6,-3,1.5),(0,0,.5),1.43)
for name,loc,power,size,rgb in (
    ('Window key',(-2,3,3),170,2.3,(1,.94,.88)),
    ('Soft fill',(2,1,1.7),55,2,(.85,.91,1)),
    ('Fur rim',(.7,-2,2.5),150,1.7,(1,.94,.87))):
    data=bpy.data.lights.new(name,'AREA'); data.energy=power; data.shape='DISK'; data.size=size; data.color=rgb
    obj=bpy.data.objects.new(name,data); scene.collection.objects.link(obj); obj.location=loc; aim(obj,(0,0,.5))
scene.world=bpy.data.worlds.new('Studio world'); scene.world.color=(.13,.13,.13)
scene.render.engine='CYCLES'; scene.cycles.samples=64; scene.cycles.use_denoising=True
scene.render.resolution_x=1200; scene.render.resolution_y=1200; scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
scene.render.image_settings.file_format='PNG'
scene.camera=hero
bpy.ops.object.select_all(action='DESELECT')
bpy.context.view_layer.objects.active=head
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA'
            area.spaces.active.overlay.show_overlays=False
            area.spaces.active.shading.type='MATERIAL'
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'kitten-realistic-v2.blend'))
for cam,name in ((hero,'portrait'),(front,'front'),(rear,'rear')):
    scene.camera=cam; scene.render.filepath=str(OUT/(name+'.png'))
    bpy.ops.render.render(write_still=True)
print('Study complete:',OUT)
