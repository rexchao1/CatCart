"""Export saved coyote/food studies to compact SceneKit JSON, without saving over them.
Blender -b input.blend --python this_file -- coyote|food output.json
Geometry is grouped by moving part and material, dropping studio and strand fur.

The coyote's gallop lives here, not in the .blend: a rotary gallop (hind legs
lead, then the fronts, then a stretch of suspension) with the body rising and
pitching over the stride, the head steadying against it, ears pinned back, the
tail streaming in two links, and the jaw snapping shut once a stride.
"""
import ast
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
def pivot_of(name,default=None):
    # Newer source files place each joint with a "Pivot <part>" empty. Older
    # ones fall back to the positions the first game export used.
    o=bpy.data.objects.get('Pivot '+name)
    if o:return o.matrix_world.translation.copy()
    return None if default is None else Vector(default)
if kind=='coyote':
    part('body',pivot_of('body',(0,0,.70)),'coyote')
    part('head',pivot_of('head',(0,-.44,.90)),'body')
    part('jaw',bpy.data.objects['Snarl jaw pivot'].matrix_world.translation,'head')
    part('tail1',pivot_of('tail1',(0,.57,.69)),'body')
    if pivot_of('tail2') is not None:part('tail2',pivot_of('tail2'),'tail1')
    for side,sx in (('L',-1),('R',1)):
        if pivot_of('ear'+side) is not None:part('ear'+side,pivot_of('ear'+side),'head')
        y=-.30+(.025 if sx<0 else -.025)
        h=.45+(.06 if sx<0 else -.04)
        part('frontUpper'+side,pivot_of('frontUpper'+side,(sx*.132,y,.71)),'body')
        part('frontLower'+side,pivot_of('frontLower'+side,(sx*.147,y+.055,.405)),'frontUpper'+side)
        part('hindUpper'+side,pivot_of('hindUpper'+side,(sx*.13,h,.70)),'body')
        part('hindLower'+side,pivot_of('hindLower'+side,(sx*.16,h-.085,.37)),'hindUpper'+side)
# Lips and claws are curves with no color attribute; the source names their colors.
curve_colors={}
root_object=bpy.data.objects.get(root_name)
if root_object is not None and 'Curve colors' in root_object:
    curve_colors=ast.literal_eval(root_object['Curve colors'])

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
    strength=bsdf.inputs['Emission Strength'].default_value if 'Emission Strength' in bsdf.inputs else 0
    if strength>0:
        glow=bsdf.inputs['Emission Color'].default_value
        value['emission']=[min(1.0,c*strength) for c in glow[:3]]  # linear, like the base color
    materials[m.name]=value

LEGS={'Left foreleg','Right foreleg','Left hind leg','Right hind leg'}
def group_for(o,p):
    if kind=='food':return root_name
    name=o.name
    if name.endswith(' tufts'):name=name[:-len(' tufts')]
    if o.parent and o.parent.name=='Snarl jaw pivot':return 'jaw'
    if name=='Lean torso and neck':return 'body'
    if name=='Bushy low tail':
        return 'tail2' if 'tail2' in pivots and p.y>pivots['tail2'].y else 'tail1'
    if name in LEGS:
        side='L' if name.startswith('Left') else 'R'
        front='foreleg' in name
        limb='front' if front else 'hind'
        return limb+('Upper' if p.z>pivots[limb+'Lower'+side].z else 'Lower')+side
    if name.startswith('Short dark claw') or name.startswith('Paw toe'):
        return ('frontLower' if p.y<0 else 'hindLower')+('L' if p.x<0 else 'R')
    if name=='Left ear' and 'earL' in pivots:return 'earL'
    if name=='Right ear' and 'earR' in pivots:return 'earR'
    return 'head'

def budget(o):
    if kind=='food':
        return 40 if o.name.startswith('Salmon chunk') else (400 if 'wall' in o.name else 200)
    n=o.name
    if n.endswith(' tufts'):return 10**9  # the ragged outline is already light; never decimate it
    if n=='Lean torso and neck':return 3800
    if n=='Narrow head and raised upper muzzle':return 3200
    if n=='Bushy low tail':return 1500
    if n in LEGS:return 1400
    if n=='Lower jaw':return 700
    if n in {'Left ear','Right ear'}:return 450
    if 'lip' in n:return 160
    if 'canine' in n or n.startswith('Tooth'):return 100
    if n.startswith('Amber eye'):return 220
    if n.startswith('Black canine nose'):return 200
    if n.startswith('Dark throat'):return 160
    if n.startswith('Dark eye socket'):return 160
    if n.startswith('Angled brow'):return 140
    if 'lining' in n or n.startswith('Tongue'):return 120
    if n.startswith('Eye glint') or n.startswith('Nostril') or n.startswith('Dark tear line'):return 50
    if n.startswith('Round canine pupil'):return 60
    if n.startswith('Short dark claw'):return 40
    return 180

objects=[o for o in collection.objects if o.type in {'MESH','CURVE'} and not o.name.endswith(' fur')
         and not o.name.startswith('Muzzle whisker')]  # whiskers are a millimeter thick: invisible in the game
part_triangles={}
for o in objects:
    source_name=o.name
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
    fixed=curve_colors.get(source_name)
    ca=mesh.color_attributes.get('Coat color')
    uv=mesh.uv_layers.active
    for tri in mesh.loop_triangles:
        pts=[o.matrix_world@mesh.vertices[i].co for i in tri.vertices]
        moving=group_for(o,sum(pts,Vector())/3)
        part_triangles[moving]=part_triangles.get(moving,0)+1
        m=mesh.materials[tri.material_index];describe_material(m)
        key=(moving,m.name)
        g=groups.setdefault(key,{'name':moving+'_'+str(len(groups)), 'parent':moving,'material':m.name,'position':[0,0,0],
                                'vertices':[],'normals':[],'colors':[],'uv':[],'indices':[]})
        for p,li,vi in zip(pts,tri.loops,tri.vertices):
            g['indices'].append(len(g['vertices'])//3)
            g['vertices']+=game(p-pivots[moving])
            g['normals']+=normal((nm@mesh.corner_normals[li].vector).normalized())
            if materials[m.name]['vertexColor'] and ca:
                g['colors']+=list(ca.data[vi if ca.domain=='POINT' else li].color)
            elif materials[m.name]['vertexColor'] and fixed:
                g['colors']+=list(fixed)+[1]
            else:g['colors']+=[1,1,1,1]
            # SceneKit's embedded image origin is the top left; Blender's is bottom left.
            g['uv']+=[uv.data[li].uv.x,1-uv.data[li].uv.y] if uv else [0,0]

# Joint spheres hide the small opening between independently rotating limb pieces.
# They join the upper leg's own coat geometry, so they cost no extra draw call.
if kind=='coyote':
    coat_name=next((n for n,v in materials.items() if v['vertexColor'] and 'coat' in n.lower()),None)
    if coat_name is None:
        coat_name='Game joint coat'
        materials[coat_name]={'name':coat_name,'color':[.30,.20,.11,1],'roughness':.8,'metallic':0,'vertexColor':False}
    rust=[.352,.141,.042,1]  # linear sRGB of the rusty lower legs
    for side in ('L','R'):
        for limb,r in (('front',.044),('hind',.047)):
            upper=limb+'Upper'+side;center=pivots[limb+'Lower'+side]
            bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=8,radius=r,location=center)
            o=bpy.context.object;me=o.data;me.calc_loop_triangles()
            g=groups.setdefault((upper,coat_name),{'name':upper+'_joint','parent':upper,'material':coat_name,'position':[0,0,0],
               'vertices':[],'normals':[],'colors':[],'uv':[],'indices':[]})
            for tri in me.loop_triangles:
                for vi in tri.vertices:
                    v=me.vertices[vi];g['indices'].append(len(g['vertices'])//3)
                    g['vertices']+=game(v.co+center-pivots[upper]);g['normals']+=normal(v.normal)
                    g['colors']+=rust if materials[coat_name]['vertexColor'] else [1,1,1,1];g['uv']+=[0,0]
            part_triangles[upper]=part_triangles.get(upper,0)+len(me.loop_triangles)

parts=[{'name':name,'parent':parents[name],'position':game(p-(pivots[parents[name]] if parents[name] else Vector()))}
       for name,p in pivots.items()]+list(groups.values())

# -- the gallop -------------------------------------------------------------------
TAU=2*math.pi
# Footfalls as a fraction of the stride: a rotary gallop on the left lead. The
# hind legs land a tenth of a stride apart, the fronts half a stride later, and
# the coyote is airborne, stretched out, before the hinds come down again.
CONTACT={'hindL':0.0,'hindR':0.10,'frontR':0.50,'frontL':0.60}
STANCE=.36
def gallop(name,phase):
    """Local offset (Blender axes: y back, z up) and rotations (rx ry rz, radians,
    game basis: +rx tips the front down, swings a leg back, lifts the tail)."""
    s=math.sin
    off=Vector();rx=ry=rz=0
    body_pitch=.08*s(TAU*(phase-.4))      # nose down as the fronts carry it, up as the hinds drive
    if name=='body':
        off.z=.04*math.cos(TAU*(phase-.9)) # highest stretched out in the air, lowest over the fronts
        off.y=.012*s(TAU*(phase-.4))
        rx=body_pitch;rz=.025*s(TAU*phase)
    elif name=='head':
        rx=-.6*body_pitch+.045*s(TAU*(phase+.1))   # eyes stay on the target, with a bob
        ry=.025*s(TAU*(phase-.2))
    elif name=='jaw':
        snap=sum(math.exp(-(((phase-.55+k)/.07)**2)) for k in (-1,0,1))
        rx=.26-.26*snap                     # hangs open, bites shut once a stride
    elif name=='tail1':
        rx=.12+.26*s(TAU*(phase-.2));ry=.08*s(TAU*(phase-.45))
    elif name=='tail2':
        rx=.30*s(TAU*(phase-.4));ry=.10*s(TAU*(phase-.65))
    elif name.startswith('ear'):
        sx=-1 if name.endswith('L') else 1
        rx=-.32+.09*s(TAU*(2*phase-.2));rz=sx*.12   # pinned back, fluttering out
    else:
        side=name[-1];limb='front' if name.startswith('front') else 'hind'
        q=(phase-CONTACT[limb+side])%1.0
        fwd,back=(.55,-.60) if limb=='front' else (.62,-.55)
        if q<STANCE:  # on the ground: the leg sweeps from reaching forward to pushing back
            t=q/STANCE;a=fwd+(back-fwd)*t;flex=.14*s(math.pi*t)
        else:         # in the air: it folds and swings forward again
            t=(q-STANCE)/(1-STANCE);a=back+(fwd-back)*(.5-.5*math.cos(math.pi*t))
            flex=(1.05 if limb=='front' else .95)*s(math.pi*t)**1.2
        if 'Upper' in name:rx=-a
        else:rx=flex if limb=='front' else -flex  # elbows fold back, hocks fold forward
    return off,(rx,ry,rz)

anim={}
frames=27;duration=.45
if kind=='coyote':
    for name in pivots:
        if name==root_name:continue
        positions=[];orientations=[]
        for f in range(frames+1):
            offset,(rx,ry,rz)=gallop(name,f/frames)
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
if kind=='coyote':
    print('  parts: '+', '.join(f'{n} {t}' for n,t in sorted(part_triangles.items())))
    print('  materials: '+', '.join(sorted(materials)))
