"""Export saved coyote/food studies to compact SceneKit JSON, without saving over them.
Blender -b input.blend --python this_file -- coyote|food output.json
Geometry is grouped by moving part and material, dropping studio and strand fur.
"""
import bpy
import json
import math
import sys
from pathlib import Path
from mathutils import Vector, Quaternion

kind, output = sys.argv[sys.argv.index('--')+1:]
output=Path(output)
scene=bpy.context.scene
scene.frame_set(1)
bpy.context.view_layer.update()
collection=bpy.data.collections['Coyote model' if kind=='coyote' else 'Wet food pickup']
root_name='coyote' if kind=='coyote' else 'wet_food'
SCALE=.88 if kind=='coyote' else 1.0

def game(v):return [round(v[0]*SCALE,6),round(v[2]*SCALE,6),round(-v[1]*SCALE,6)]
def normal(v):return [round(v[0],5),round(v[2],5),round(-v[1],5)]
pivots={root_name:Vector((0,0,0))}
parents={root_name:None}
def part(name,pivot,parent):
    pivots[name]=Vector(pivot);parents[name]=parent
if kind=='coyote':
    part('body',(0,0,.70),'coyote')
    part('head',(0,-.44,.90),'body')
    part('jaw',bpy.data.objects['Snarl jaw pivot'].matrix_world.translation,'head')
    part('tail1',(0,.57,.69),'body')
    for side,sx in (('L',-1),('R',1)):
        y=-.30+(.025 if sx<0 else -.025)
        h=.45+(.06 if sx<0 else -.04)
        part('frontUpper'+side,(sx*.132,y,.71),'body')
        part('frontLower'+side,(sx*.147,y+.055,.405),'frontUpper'+side)
        part('hindUpper'+side,(sx*.13,h,.70),'body')
        part('hindLower'+side,(sx*.16,h-.085,.37),'hindUpper'+side)

materials={};groups={}
def describe_material(m):
    if m.name in materials:return
    bsdf=m.node_tree.nodes.get('Principled BSDF')
    value={'name':m.name,'color':list(bsdf.inputs['Base Color'].default_value),
           'roughness':bsdf.inputs['Roughness'].default_value,
           'metallic':bsdf.inputs['Metallic'].default_value}
    link=next((l for l in m.node_tree.links if l.to_node==bsdf and l.to_socket.name=='Base Color'),None)
    if link and link.from_node.type=='TEX_IMAGE':
        image=link.from_node.image
        path=output.with_name(kind+'-label.png')
        image.filepath_raw=str(path)
        image.file_format='PNG'
        image.save()
        value['texture']=str(path)
    value['vertexColor']=bool(link and link.from_node.type in {'VERTEX_COLOR','ATTRIBUTE'})
    materials[m.name]=value

def group_for(o,p):
    if kind=='food':return root_name
    if o.parent and o.parent.name=='Snarl jaw pivot':return 'jaw'
    if o.name=='Lean torso and neck':return 'body'
    if o.name=='Bushy low tail':return 'tail1'
    if o.name in {'Left foreleg','Right foreleg','Left hind leg','Right hind leg'}:
        side='L' if o.name.startswith('Left') else 'R'
        front='foreleg' in o.name
        return ('front' if front else 'hind')+('Upper' if p.z>(.405 if front else .37) else 'Lower')+side
    if o.name.startswith('Short dark claw'):
        return ('frontLower' if p.y<0 else 'hindLower')+('L' if p.x<0 else 'R')
    return 'head'

def budget(o):
    if kind=='food':
        return 40 if o.name.startswith('Salmon chunk') else (400 if 'wall' in o.name else 200)
    if o.name=='Lean torso and neck':return 4400
    if o.name=='Narrow head and raised upper muzzle':return 3800
    if o.name=='Bushy low tail':return 1600
    if 'leg' in o.name:return 1500
    if o.name=='Lower jaw':return 800
    if 'ear' in o.name:return 500
    if 'lip' in o.name:return 180
    if 'canine' in o.name or o.name.startswith('Tooth'):return 100
    return 180

objects=[o for o in collection.objects if o.type in {'MESH','CURVE'} and not o.name.endswith(' fur')]
for o in objects:
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
    if o.type=='CURVE':
        o.data.resolution_u=3;o.data.bevel_resolution=1
        bpy.ops.object.convert(target='MESH');o=bpy.context.object
    for modifier in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=modifier.name)
    o.data.calc_loop_triangles()
    target=budget(o)
    if len(o.data.loop_triangles)>target:
        mod=o.modifiers.new('Game triangle budget','DECIMATE');mod.ratio=target/len(o.data.loop_triangles)
        bpy.ops.object.modifier_apply(modifier=mod.name)
    mesh=o.data;mesh.calc_loop_triangles()
    nm=o.matrix_world.to_3x3().inverted().transposed()
    for tri in mesh.loop_triangles:
        pts=[o.matrix_world@mesh.vertices[i].co for i in tri.vertices]
        moving=group_for(o,sum(pts,Vector())/3)
        m=mesh.materials[tri.material_index];describe_material(m)
        key=(moving,m.name)
        g=groups.setdefault(key,{'name':moving+'_'+str(len(groups)), 'parent':moving,'material':m.name,'position':[0,0,0],
                                'vertices':[],'normals':[],'colors':[],'uv':[],'indices':[]})
        ca=mesh.color_attributes.get('Coat color')
        for p,li,vi in zip(pts,tri.loops,tri.vertices):
            g['indices'].append(len(g['vertices'])//3)
            g['vertices']+=game(p-pivots[moving])
            g['normals']+=normal((nm@mesh.corner_normals[li].vector).normalized())
            if materials[m.name]['vertexColor'] and ca:
                g['colors']+=list(ca.data[vi if ca.domain=='POINT' else li].color)
            else:g['colors']+=[1,1,1,1]
            uv=mesh.uv_layers.active
            # SceneKit's embedded image origin is the top left; Blender's is bottom left.
            g['uv']+=[uv.data[li].uv.x,1-uv.data[li].uv.y] if uv else [0,0]

# Joint spheres hide the small opening between independently rotating limb pieces.
if kind=='coyote':
    joint_material='Game joint coat'
    materials[joint_material]={'name':joint_material,'color':[.30,.20,.11,1],'roughness':.8,'metallic':0,'vertexColor':False}
    for side in ('L','R'):
        for limb,r in (('front',.044),('hind',.047)):
            upper=limb+'Upper'+side;center=pivots[limb+'Lower'+side]
            bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=8,radius=r,location=center)
            o=bpy.context.object;me=o.data;me.calc_loop_triangles()
            g={'name':upper+'_joint','parent':upper,'material':joint_material,'position':[0,0,0],
               'vertices':[],'normals':[],'colors':[],'uv':[],'indices':[]}
            for tri in me.loop_triangles:
                for vi in tri.vertices:
                    v=me.vertices[vi];g['indices'].append(len(g['vertices'])//3)
                    g['vertices']+=game(v.co+center-pivots[upper]);g['normals']+=normal(v.normal)
                    g['colors']+=[1,1,1,1];g['uv']+=[0,0]
            groups[(upper,'joint')]=g

parts=[{'name':name,'parent':parents[name],'position':game(p-(pivots[parents[name]] if parents[name] else Vector()))}
       for name,p in pivots.items()]+list(groups.values())
anim={}
frames=27;duration=.45
if kind=='coyote':
    for name in pivots:
        if name==root_name:continue
        positions=[];orientations=[]
        for f in range(frames+1):
            phase=f/frames;angle=2*math.pi*phase
            offset=Vector();rx=ry=rz=0
            if name=='body':offset.z=.035*math.cos(angle);rx=.045*math.sin(angle)
            elif name=='head':rx=-.055*math.sin(angle)
            elif name=='jaw':rx=.10-.08*math.exp(-((phase-.5)/.1)**2)
            elif name=='tail1':rx=.07*math.sin(angle-.7);ry=.11*math.sin(angle-.9)
            else:
                q=angle+(.09*2*math.pi if name.endswith('R') else 0)
                if name.startswith('frontUpper'):rx=.52*math.sin(q)
                elif name.startswith('frontLower'):rx=.90*max(0,-math.cos(q))**1.5
                elif name.startswith('hindUpper'):rx=-.48*math.sin(q)
                elif name.startswith('hindLower'):rx=-.16+.75*max(0,math.cos(q))**1.5
            positions.append(game(pivots[name]-pivots[parents[name]]+offset))
            # Blender rotation axes converted into the game's Y-up basis.
            q=Quaternion((0,1,0),ry)@Quaternion((1,0,0),rx)@Quaternion((0,0,-1),rz)
            orientations.append([q.x,q.y,q.z,q.w])
        anim[name]={'position':positions,'orientation':orientations}
output.write_text(json.dumps({'name':root_name,'parts':parts,'materials':list(materials.values()),
                              'frames':frames,'duration':duration,'anim':anim}))
triangles=sum(len(g['indices'])//3 for g in groups.values())
assert triangles<(28000 if kind=='coyote' else 6500),triangles
assert all(math.isfinite(v) for g in groups.values() for v in g['vertices'])
print(f'{kind}: {triangles} triangles, {len(groups)} geometry groups -> {output}')
