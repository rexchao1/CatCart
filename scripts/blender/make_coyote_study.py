"""Natural-proportion coyote art study. Source model, not a game export.
Run with Blender --background --python-exit-code 1 --python this_file.
"""
from pathlib import Path
import math
import random
import bpy
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'art/models/coyote'; OUT.mkdir(parents=True,exist_ok=True)
PREVIEW=ROOT/'art/options/coyote/blender-study'; PREVIEW.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
rng=random.Random(83)
model=bpy.data.collections.new('Coyote model');scene.collection.children.link(model)
studio=bpy.data.collections.new('Preview studio');scene.collection.children.link(studio)
def move(obj,col=model):
    for c in list(obj.users_collection):c.objects.unlink(obj)
    col.objects.link(obj)
    return obj

def lin(v):
    v/=255
    return v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4

def mat(name,rgb,rough=.65):
    m=bpy.data.materials.new(name); s=m.node_tree.nodes.get('Principled BSDF')
    s.inputs['Base Color'].default_value=(*map(lin,rgb),1);s.inputs['Roughness'].default_value=rough
    m.diffuse_color=(*map(lin,rgb),1)
    return m
coat=mat('Grizzled warm tan coat',(150,119,82))
node=coat.node_tree.nodes.new('ShaderNodeVertexColor');node.layer_name='Coat color'
coat.node_tree.links.new(node.outputs['Color'],coat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
coat.node_tree.nodes.get('Principled BSDF').inputs['Sheen Weight'].default_value=.16
cream=mat('Cream muzzle and throat',(194,175,146))
black=mat('Nose lips and claws',(33,28,25),.36)
mouth=mat('Dark mouth interior',(56,22,22),.5)
gum=mat('Muted gums',(108,56,54),.48)
tooth=mat('Warm ivory teeth',(237,222,195),.3)
ear_skin=mat('Muted ear interior',(123,91,75))
amber=mat('Amber iris',(192,131,35),.23)
pupil=mat('Dark pupil',(13,12,9),.17)
whisker=mat('Sparse dark whiskers',(80,68,55))
fur_objects=[]
def smooth(o):
    for p in o.data.polygons:p.use_smooth=True
    return o

def ell(name,c,r,material=coat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=40,ring_count=24,location=c)
    o=bpy.context.object;o.name=name;o.scale=r
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(material);move(o);return smooth(o)

def fuse(name,parts,voxel=.005,fur=True):
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:o.select_set(True)
    bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();o=parts[0];o.name=name
    mod=o.modifiers.new('Fused anatomy','REMESH');mod.mode='VOXEL';mod.voxel_size=voxel;bpy.ops.object.modifier_apply(modifier=mod.name)
    mod=o.modifiers.new('Soft anatomical transitions','SMOOTH');mod.factor=.6;mod.iterations=8;bpy.ops.object.modifier_apply(modifier=mod.name)
    smooth(o)
    if fur:fur_objects.append(o)
    return o

def curve(name,pts,r,material=coat,taper=False):
    d=bpy.data.curves.new(name,'CURVE');d.dimensions='3D';d.bevel_depth=r;d.bevel_resolution=3;d.resolution_u=10;d.use_fill_caps=True
    sp=d.splines.new('BEZIER');sp.bezier_points.add(len(pts)-1)
    for i,(p,co) in enumerate(zip(sp.bezier_points,pts)):
        p.co=co;p.handle_left_type=p.handle_right_type='AUTO';p.radius=1-.9*i/(len(pts)-1) if taper else 1
    o=bpy.data.objects.new(name,d);model.objects.link(o);d.materials.append(material);return o

def capsule(name,a,b,r1,r2):
    a,b=Vector(a),Vector(b)
    parts=[]
    for i in range(23):
        t=i/22;p=a.lerp(b,t);r=r1*(1-t)+r2*t
        parts.append(ell(name,p,(r,r,r)))
    return parts

# Front faces -Y. A deep ribcage, narrow waist, and long legs distinguish it
# from the round seated kitten and from a broad-chested wolf.
body=fuse('Lean torso and neck',[
    ell('Ribcage',(0,-.13,.70),(.184,.33,.235)),
    ell('Waist',(0,.20,.735),(.126,.29,.135)),
    ell('Pelvis',(0,.44,.71),(.153,.195,.168)),
    ell('Shoulders',(0,-.32,.745),(.176,.172,.223)),
    ell('Lower neck',(0,-.39,.837),(.142,.162,.207)),
    ell('Upper neck',(0,-.465,.929),(.125,.145,.16)),
])
for side in (-1,1):
    x=side*.132
    y=-.30+(.025 if side<0 else -.025)
    parts=capsule('Foreleg',(x,y,.71),(side*.147,y+.055,.405),.071,.041)
    parts+=capsule('Forearm',(side*.147,y+.055,.405),(side*.158,y-.015,.09),.041,.028)
    parts+=[ell('Front paw',(side*.159,y-.047,.052),(.055,.092,.049))]
    fuse('Left foreleg' if side<0 else 'Right foreleg',parts,.004)
    h=.45+(.06 if side<0 else -.04)
    parts=[ell('Haunch',(side*.13,h,.625),(.10,.142,.179))]
    parts+=capsule('Thigh',(side*.139,h,.60),(side*.16,h-.085,.37),.074,.047)
    parts+=capsule('Hock',(side*.16,h-.085,.37),(side*.162,h+.09,.19),.043,.028)
    parts+=capsule('Rear ankle',(side*.162,h+.09,.19),(side*.163,h+.02,.069),.028,.026)
    parts+=[ell('Rear paw',(side*.163,h-.025,.047),(.05,.085,.043))]
    fuse('Left hind leg' if side<0 else 'Right hind leg',parts,.004)
    for py,px in ((y-.12,side*.159),(h-.095,side*.163)):
        for dx in (-.028,0,.028):
            curve('Short dark claw',[(px+dx,py+.02,.04),(px+dx,py-.015,.031),(px+dx,py-.026,.02)],.0055,black,True)

head=fuse('Narrow head and raised upper muzzle',[
    ell('Skull',(0,-.54,1.00),(.147,.166,.141)),
    ell('Left cheek',(-.102,-.529,.924),(.085,.112,.099)),
    ell('Right cheek',(.102,-.529,.924),(.085,.112,.099)),
    ell('Muzzle bridge',(0,-.679,.955),(.09,.16,.067)),
    ell('Tapered muzzle',(0,-.783,.932),(.062,.108,.047)),
    ell('Nose base',(0,-.852,.935),(.047,.039,.033)),
],.0035)
ell('Black canine nose',(0,-.881,.945),(.052,.030,.034),black)
for side in (-1,1):ell('Nostril',(side*.026,-.905,.951),(.010,.005,.007),black)
ell('Dark throat',(0,-.654,.874),(.073,.093,.048),mouth)

# Separate lower jaw and its contents, pivoted near the jaw joint.
jaw=fuse('Lower jaw',[
    ell('Jaw hinge',(0,-.581,.872),(.084,.063,.053),cream),
    ell('Lower muzzle',(0,-.710,.839),(.061,.155,.029),cream),
    ell('Chin',(0,-.810,.840),(.043,.068,.027),cream),
],.003,fur=False)
jaw_parts=[jaw,ell('Lower mouth lining',(0,-.715,.856),(.053,.132,.015),gum),
           ell('Tongue',(0,-.702,.868),(.033,.081,.012),gum)]
for side in (-1,1):
    curve('Upper black lip',[(side*.055,-.85,.914),(side*.065,-.775,.897),(side*.087,-.69,.901),(side*.097,-.625,.910)],.0045,black)
    lower=curve('Lower black lip',[(side*.034,-.86,.850),(side*.050,-.77,.856),(side*.064,-.68,.864)],.0035,black);jaw_parts.append(lower)
    # Canines dominate the silhouette; the other teeth stay restrained.
    for upper in (True,False):
        for i in range(6):
            y=-.821+i*.033;x=side*(.039+i*.006)
            long=i==1
            length=(.065 if long else .022) if upper else (.046 if long else .018)
            z=.904 if upper else .862
            tip=Vector((x*.95,y-.006,z-length if upper else z+length))
            base=Vector((x,y,z))
            bpy.ops.mesh.primitive_cone_add(vertices=16,radius1=.013 if long else .007,radius2=.001,depth=length,location=(base+tip)/2)
            o=bpy.context.object;o.name='Upper canine' if upper and long else 'Tooth'
            o.rotation_euler=(tip-base).to_track_quat('Z','Y').to_euler();o.data.materials.append(tooth);move(o);smooth(o)
            if not upper:jaw_parts.append(o)
    # Small amber eyes beneath sloping brows, without an oversized cute pupil.
    ell('Dark eye socket',(side*.105,-.652,1.023),(.038,.024,.028),black)
    ell('Amber eye',(side*.108,-.668,1.024),(.025,.014,.021),amber)
    ell('Round canine pupil',(side*.108,-.680,1.024),(.010,.004,.017),pupil)
    brow=ell('Angled brow',(side*.108,-.660,1.056),(.051,.026,.016),coat)
    brow.rotation_euler.y=-side*.30
    fur_objects.append(brow)
    for i in range(3):
        curve('Muzzle whisker',[(side*.051,-.798,.934+i*.009),(side*.100,-.825,.942+i*.015),(side*.178,-.806,.943+i*.020)],.00065,whisker,True)

# Tall cupped ears lean outward. Gray-brown backs and muted inner skin.
for side in (-1,1):
    base=Vector((side*.105,-.50,1.079))
    shape=[(-.060,0,0),(-.058,.016,.11),(-.026,.028,.25),(0,.018,.267),(.025,.007,.242),(.071,0,.04)]
    if side<0:shape=[(-x,y,z) for x,y,z in shape[::-1]]
    verts=[];center=Vector((side*.020,.015,.102));n=len(shape)
    for r in (1,.78,.45,.12):
        for x,y,z in shape:
            p=Vector((x,y,z))*r+center*(1-r);p.z*=.82;p.x+=side*p.z*.38;p.y+=(1-r)*.030
            verts.append(base+p)
    verts.append(base+center+Vector((side*.03,.04,0)))
    faces=[];materials=[]
    for k in range(3):
        for j in range(n):faces.append((k*n+j,k*n+(j+1)%n,(k+1)*n+(j+1)%n,(k+1)*n+j));materials.append(0 if k==0 else 1)
    for j in range(n):faces.append((3*n+j,3*n+(j+1)%n,4*n));materials.append(1)
    mesh=bpy.data.meshes.new('Cupped coyote ear');mesh.from_pydata(verts,[],[tuple(reversed(f)) for f in faces]);mesh.materials.append(coat);mesh.materials.append(ear_skin)
    o=bpy.data.objects.new('Left ear' if side<0 else 'Right ear',mesh);model.objects.link(o)
    for p,m in zip(mesh.polygons,materials):p.material_index=m
    bpy.context.view_layer.objects.active=o
    mod=o.modifiers.new('Round ear contour','SUBSURF');mod.levels=2;bpy.ops.object.modifier_apply(modifier=mod.name)
    mod=o.modifiers.new('Ear thickness','SOLIDIFY');mod.thickness=.012;mod.material_offset=-1;bpy.ops.object.modifier_apply(modifier=mod.name)
    smooth(o);fur_objects.append(o)

# A bushy, low tail with a dark tip rather than a curled domestic-dog tail.
parts=[]
for i in range(18):
    t=i/17
    p=Vector((.025+.10*math.sin(t*math.pi),.57+.66*t,.69-.37*t))
    r=.047+.051*math.sin(math.pi*t)**.8
    r*=1-.55*t**5
    parts.append(ell('Tail section',p,(r,r*1.18,r)))
tail=fuse('Bushy low tail',parts,.0045)

# A restrained grizzled saddle, rusty lower legs, and pale throat.
def tint(p,n):
    tan=Vector((157,127,89));dark=Vector((75,67,56));pale=Vector((201,183,155));rust=Vector((151,103,65))
    if p.z<.48:col=rust.lerp(tan,max(0,min(1,(p.z-.27)/.21)))
    else:
        saddle=max(0,min(1,(p.z-.70)/.16))*max(0,min(1,(p.y+.40)/.3))
        if p.y>.65:saddle=max(saddle,max(0,min(1,(p.y-.65)/.5))*.75)
        col=tan.lerp(dark,saddle*.88)
        chest=max(0,min(1,(-p.y-.24)/.22))*max(0,min(1,(.91-p.z)/.17))
        if p.z>.47:col=col.lerp(pale,chest*.85)
        if p.y<-.63 and p.z<.97:col=col.lerp(pale,.83)
    if p.y>.65:
        tailshade=max(0,min(1,(p.y-.65)/.55))
        col=tan.lerp(dark,tailshade**1.5)
    if p.z>1.15:col=col.lerp(dark,.25)
    return col

# Short fur on legs and muzzle; longer guard hairs on cheeks, neck, and tail.
fur_material=mat('Directional guard hairs',(150,122,86))
attr=fur_material.node_tree.nodes.new('ShaderNodeVertexColor');attr.layer_name='Coat color'
fur_material.node_tree.links.new(attr.outputs['Color'],fur_material.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
bpy.context.view_layer.update()
for obj in fur_objects:
    mesh=obj.data
    ca=mesh.color_attributes.new(name='Coat color',type='FLOAT_COLOR',domain='POINT')
    for v,c in zip(mesh.vertices,ca.data):
        p=obj.matrix_world@v.co;col=tint(p,v.normal)
        if 'brow' in obj.name:col*=.58
        c.color=(*[lin(x) for x in col],1)
    mesh.calc_loop_triangles();verts=[];faces=[];cols=[]
    for tri in mesh.loop_triangles:
        if mesh.materials[tri.material_index]!=coat:continue
        a,b,c=[obj.matrix_world@mesh.vertices[i].co for i in tri.vertices]
        count=int((b-a).cross(c-a).length*.5*23500+rng.random())
        ns=[(obj.matrix_world.to_3x3()@mesh.vertices[i].normal).normalized() for i in tri.vertices]
        for _ in range(count):
            u,v=rng.random(),rng.random()
            if u+v>1:u,v=1-u,1-v
            p=a+u*(b-a)+v*(c-a);n=(ns[0]*(1-u-v)+ns[1]*u+ns[2]*v).normalized()
            flow=Vector((p.x*.4,.9,-.35))
            if p.z<.5:flow=Vector((0,.1,-1))
            if p.y<-.5:flow=Vector((p.x*2,.3,-.35))
            tangent=(flow-n*flow.dot(n)).normalized();direction=(n*.46+tangent*.88).normalized()
            length=rng.uniform(.009,.025)
            if p.z<.5 or p.y<-.66:length*=.38
            if p.y>.70:length*=1.5
            width=rng.uniform(.00025,.00050);across=direction.cross(Vector((.21,.35,.91))).normalized()
            idx=len(verts);verts.extend((p-across*width,p+across*width,p+direction*length))
            faces.append((idx,idx+1,idx+2))
            col=tint(p,n)*rng.uniform(.73,1.18);cols.extend([(*[lin(min(255,x)) for x in col],1)]*3)
    fm=bpy.data.meshes.new(obj.name+' fur mesh');fm.from_pydata(verts,[],faces);fm.materials.append(fur_material)
    ca=fm.color_attributes.new(name='Coat color',type='FLOAT_COLOR',domain='POINT')
    for v,c in zip(ca.data,cols):v.color=c
    fo=bpy.data.objects.new(obj.name+' fur',fm);model.objects.link(fo)

pivot=bpy.data.objects.new('Snarl jaw pivot',None);model.objects.link(pivot);pivot.location=(0,-.58,.875)
bpy.context.view_layer.update()
for o in jaw_parts:
    wm=o.matrix_world.copy();o.parent=pivot;o.matrix_world=wm
for frame,angle in ((1,.04),(10,.13),(18,.025),(30,.04)):
    pivot.rotation_euler.x=angle;pivot.keyframe_insert(data_path='rotation_euler',frame=frame)
scene.frame_start=1;scene.frame_end=30;scene.render.fps=30;scene.frame_set(1)
root=bpy.data.objects.new('coyote',None);model.objects.link(root)
for o in list(model.objects):
    if o!=root and o.parent is None:o.parent=root
root['Notes']='Natural-proportion art study, front -Y, Z up. Frames 1-30 preview a snarl. Walking/running rig and game export are not included.'

floor=mat('Warm neutral studio',(157,151,140),.9)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.007));o=bpy.context.object;o.name='Studio ground';o.data.materials.append(floor);move(o,studio)
def aim(o,p):o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
def camera(name,loc,target,scale):
    d=bpy.data.cameras.new(name);o=bpy.data.objects.new(name,d);studio.objects.link(o);o.location=loc;aim(o,target);d.type='ORTHO';d.ortho_scale=scale;return o
hero=camera('Portrait camera',(2.4,-3.7,2.0),(0,.03,.57),1.95)
front=camera('Front camera',(0,-4,1.58),(0,-.25,.69),1.73)
side=camera('Side camera',(4,-.1,1.3),(0,.14,.65),2.50)
for name,loc,energy,size in (('Soft key',(-2,-3,4),290,3),('Face fill',(2,-2,2.2),105,2.4),('Scruff rim',(1,3,3),330,2)):
    d=bpy.data.lights.new(name,'AREA');d.energy=energy;d.shape='DISK';d.size=size;o=bpy.data.objects.new(name,d);studio.objects.link(o);o.location=loc;aim(o,(0,0,.7))
scene.world=bpy.data.worlds.new('Neutral world');scene.world.color=(.13,.13,.13)
scene.render.engine='CYCLES';scene.cycles.samples=64;scene.cycles.use_denoising=True
scene.render.resolution_x=1200;scene.render.resolution_y=1200;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX';scene.camera=hero
bpy.ops.object.select_all(action='DESELECT');root.select_set(True);bpy.context.view_layer.objects.active=root
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.overlay.show_overlays=False;area.spaces.active.shading.type='MATERIAL'
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'coyote.blend'))
for cam,name in ((hero,'portrait'),(front,'front'),(side,'side')):
    scene.camera=cam;scene.render.filepath=str(PREVIEW/(name+'.png'));bpy.ops.render.render(write_still=True)
scene.camera=hero;scene.frame_set(10);scene.render.filepath=str(PREVIEW/'snarl.png');bpy.ops.render.render(write_still=True)
print('Saved coyote:',OUT/'coyote.blend')
