"""Original Nodekins environment kit. Run only inside the connected Blender MCP."""
import bpy, bmesh, math, json, os, shutil
from mathutils import Vector, Matrix
GAME='/Users/shane/Gaming/Games/nodekins-racing'
SOURCE='/Users/shane/Gaming/Assets/nodekins-racing/phase_5c'
SCENE='Nodekins_Track_Kit'
TAG='phase5c'
old=bpy.data.scenes.get(SCENE)
if old:
    if old.get('nodekins_builder')!=TAG or any(o.get('nodekins_builder')!=TAG for o in old.objects):
        raise RuntimeError('Refusing to replace unowned Blender objects')
    for ob in list(old.objects):bpy.data.objects.remove(ob,do_unlink=True)
    bpy.data.scenes.remove(old)
    for group in [bpy.data.meshes,bpy.data.materials,bpy.data.cameras,bpy.data.lights,bpy.data.worlds]:
        for data in list(group):
            if data.get('nodekins_builder')==TAG and data.users==0:group.remove(data)
scene=bpy.data.scenes.new(SCENE);scene['nodekins_builder']=TAG;bpy.context.window.scene=scene
scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=1440;scene.render.resolution_y=1080;scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('TrackKit_Studio');scene.world['nodekins_builder']=TAG;scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.23,.35,.42,1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.6
B=lambda g:Vector((g[0],-g[2],g[1]))
C={'road':(.055,.085,.105,1),'edge':(.026,.07,.088,1),'teal':(.055,.43,.45,1),'deep':(.025,.21,.25,1),'cream':(.94,.88,.68,1),'orange':(.88,.26,.07,1),'gold':(.95,.59,.12,1),'green':(.19,.67,.14,1),'grass':(.16,.36,.22,1),'rock':(.13,.23,.29,1),'dark':(.025,.044,.058,1)}
def tag(d):d['nodekins_builder']=TAG;return d
def link(o):tag(o);scene.collection.objects.link(o);return o
def empty(name,parent=None,at=(0,0,0),yaw=0):
    o=link(bpy.data.objects.new(parent.name+'__'+name if parent else name,None));o.parent=parent;o.location=B(at);o.rotation_euler.z=yaw;o.empty_display_size=.6;return o
mat=tag(bpy.data.materials.new('TrackKit_FlatPalette'));mat.use_nodes=True
p=mat.node_tree.nodes.get('Principled BSDF');p.inputs['Roughness'].default_value=.95
v=mat.node_tree.nodes.new('ShaderNodeVertexColor');v.layer_name='Color';mat.node_tree.links.new(v.outputs['Color'],p.inputs['Base Color'])
class Shape:
    def __init__(self):self.v=[];self.f=[];self.c=[]
    def add(self,vs,fs,color):
        n=len(self.v);self.v.extend(vs);self.f.extend([tuple(n+i for i in f) for f in fs]);self.c.extend([color]*len(fs))
    def box(self,center,size,color,bevel=0,rotate_z=0,rotate_y=0):
        bm=bmesh.new();bmesh.ops.create_cube(bm,size=1)
        for v in bm.verts:v.co=Vector((v.co.x*size[0],v.co.y*size[1],v.co.z*size[2]))
        if bevel:bmesh.ops.bevel(bm,geom=list(bm.edges),offset=bevel,segments=1,affect='EDGES')
        bm.verts.ensure_lookup_table();bm.verts.index_update()
        rot=Matrix.Rotation(rotate_y,3,'Y')@Matrix.Rotation(rotate_z,3,'Z')
        self.add([tuple(rot@v.co+Vector(center)) for v in bm.verts],[tuple(v.index for v in f.verts) for f in bm.faces],color);bm.free()
    def beam(self,a,b,r,color,sides=6):
        a,b=Vector(a),Vector(b);axis=(b-a).normalized();ref=Vector((0,1,0)) if abs(axis.y)<.9 else Vector((1,0,0))
        u=axis.cross(ref).normalized()*r;v=axis.cross(u).normalized()*r
        vs=[tuple(t+u*math.cos(i*math.tau/sides)+v*math.sin(i*math.tau/sides)) for t in [a,b] for i in range(sides)]
        fs=[tuple(range(sides-1,-1,-1)),tuple(range(sides,2*sides))]+[(i,(i+1)%sides,(i+1)%sides+sides,i+sides) for i in range(sides)]
        self.add(vs,fs,color)
    def prism(self,outline,y0,y1,color):
        n=len(outline);vs=[(x,y,z) for y in [y0,y1] for x,z in outline]
        self.add(vs,[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],color)
    def rock(self,center,scale,color,seed=0):
        n=7;vs=[]
        for j,(y,r) in enumerate([(0,.8),(.35,1),(.78,.75),(1,.24)]):
            for i in range(n):
                a=math.tau*i/n+.13*j;rr=r*(1+.09*math.sin(i*7+seed))
                vs.append((center[0]+scale[0]*rr*math.cos(a),center[1]+scale[1]*y,center[2]+scale[2]*rr*math.sin(a)))
        fs=[tuple(range(n-1,-1,-1)),tuple(range(3*n,4*n))]+[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(3) for i in range(n)]
        self.add(vs,fs,color)
    def object(self,name,parent):
        name=parent.name+'__'+name
        mesh=tag(bpy.data.meshes.new(name+'_mesh'));mesh.from_pydata([B(v) for v in self.v],[],self.f);mesh.update()
        colors=mesh.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
        for face,color in zip(mesh.polygons,self.c):
            face.use_smooth=False
            for li in face.loop_indices:colors.data[li].color=color
        bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free();mesh.materials.append(mat)
        o=link(bpy.data.objects.new(name,mesh));o.parent=parent;return o

def sweep(shape,sections,profile,color):
    # Section = road point, local right vector, local surface normal.
    vs=[tuple(Vector(p)+Vector(right)*x+Vector(up)*y) for p,right,up in sections for x,y in profile];n=len(profile)
    fs=[tuple(range(n-1,-1,-1)),tuple(range((len(sections)-1)*n,len(sections)*n))]
    fs += [(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(len(sections)-1) for i in range(n)]
    shape.add(vs,fs,color)

def straight(length,rise=0):
    up=Vector((0,length,rise)).normalized()
    return [((0,rise*t/length,-t),(1,0,0),(0,1,0) if t in [0,length] else tuple(up)) for t in range(0,int(length)+1,4)]
def curve(degrees):
    return [((-32+32*math.cos(a),0,-32*math.sin(a)),(math.cos(a),0,-math.sin(a)),(0,1,0)) for a in [math.radians(i*7.5) for i in range(int(degrees/7.5)+1)]]
def ribbon(shape,sections,x1,x2,y,color):sweep(shape,sections,[(x1,y-.006),(x2,y-.006),(x2,y),(x1,y)],color)

def road(root,sections,ramp=False):
    s=Shape();sweep(s,sections,[(-7,0),(7,0),(7,-.68),(6.75,-1),(-6.75,-1),(-7,-.68)],C['road'])
    for side in [-1,1]:
        ribbon(s,sections,side*6.40,side*6.54,.007,C['cream'])
        ribbon(s,sections,side*6.62,side*7,.007,C['teal'])
        for j in range(len(sections)-1):
            if j%2==0:ribbon(s,sections[j:j+2],side*6.66,side*6.96,.011,C['cream'])
        # Visible deck fascias have the same endpoints as the road.
        sweep(s,sections,[(side*7,-.68),(side*7,-.50),(side*7.018,-.50),(side*7.018,-.68)],C['deep'])
    if not ramp:
        for j in range(len(sections)-1):
            p0,r0,u0=sections[j];p1,r1,u1=sections[j+1]
            center=(Vector(p0)+Vector(p1))*.5;direction=(Vector(p1)-Vector(p0)).normalized();right=(Vector(r0)+Vector(r1)).normalized();up=(Vector(u0)+Vector(u1)).normalized()
            vs=[tuple(center+right*x+direction*z+up*.01) for x,z in [(-.08,-.8),(.08,-.8),(.08,.8),(-.08,.8)]]
            s.add(vs,[(0,1,2,3)],C['cream'])
    s.object('Surface',root)

def rail(root,sections,side,name):
    s=Shape();x=side*7.2
    sweep(s,sections,[(x-.25,0),(x+.25,0),(x+.25,.94),(x+.18,1.1),(x-.18,1.1),(x-.25,.94)],C['teal'])
    for sign in [-1,1]:
        sweep(s,sections,[(x+sign*.251,.23),(x+sign*.251,.32),(x+sign*.254,.32),(x+sign*.254,.23)],C['cream'])
        sweep(s,sections,[(x+sign*.251,.76),(x+sign*.251,.84),(x+sign*.254,.84),(x+sign*.254,.76)],C['deep'])
    for index in range(1,len(sections),2):
        p,right,up=sections[index];c=Vector(p)+Vector(right)*x+Vector(up)*.6
        # Reflectors are shallow plaques, away from the driving surface.
        for sign in [-1,1]:
            center=c+Vector(right)*sign*.26
            s.box(tuple(center),(.035,.22,.60),C['gold'],.008,rotate_y=math.atan2(-right[2],right[0]))
    s.object(name,root)

assets=[];contracts={}
def module(name,end=None,yaw=0):
    root=empty(name);root['asset_id']=name;root['units']='metres';root['forward']='Blender +Y / Godot -Z';root['origin']='ground-level entrance connection'
    empty('socket_in',root)
    if end is not None:empty('socket_out',root,end,yaw)
    assets.append(root);contracts[name]={'width':.5 if name=='track_barrier_01' else 14 if name.startswith('track_') else None,'exit':end,'exit_yaw_degrees':math.degrees(yaw)}
    return root
root=module('track_straight_01',(0,0,-4));secs=straight(4);road(root,secs)
for side,name in [(-1,'RailLeft'),(1,'RailRight')]:rail(root,secs,side,name)
for deg in [45,90]:
    a=math.radians(deg);root=module('track_curve_%d_01'%deg,(-32+32*math.cos(a),0,-32*math.sin(a)),a);secs=curve(deg);road(root,secs)
    for side,name in [(-1,'RailLeft'),(1,'RailRight')]:rail(root,secs,side,name)
root=module('track_hill_01',(0,1.4,-12));road(root,straight(12,1.4))
root=module('track_ramp_01',(0,1.4,-12));secs=straight(12,1.4);road(root,secs,True)
s=Shape()
for z in [-3,-6,-9]:
    for x in [-3.8,0,3.8]:
        # White swept wing marks distinguish launch from the lime boost pad.
        poly=[(x-1.15,z+.5),(x,z-.6),(x+1.15,z+.5),(x+.58,z+.5),(x,z-.05),(x-.58,z+.5)]
        vs=[(px,-pz*(1.4/12)+.017,pz) for px,pz in poly];s.add(vs,[tuple(range(len(vs)))],C['cream'])
for z0,z1 in [(-.7,0),(-12,-11.4)]:
    s.add([(-7,-z0*1.4/12+.014,z0),(7,-z0*1.4/12+.014,z0),(7,-z1*1.4/12+.014,z1),(-7,-z1*1.4/12+.014,z1)],[(0,1,2,3)],C['gold'])
s.object('LaunchMarkings',root)
root=module('track_barrier_01',(0,0,-4));secs=straight(4)
# Centered wall connector, unlike road modules' edge rails.
shift=[((p[0]-7.2,p[1],p[2]),r,u) for p,r,u in secs];rail(root,shift,1,'Barrier')
root=module('track_tunnel_01',(0,0,-12));secs=straight(12);road(root,secs)
for side,name in [(-1,'RailLeft'),(1,'RailRight')]:rail(root,secs,side,name)
s=Shape()
profile=[(-7.6,0),(-7.6,4.4),(-5.9,6.1),(5.9,6.1),(7.6,4.4),(7.6,0)]
for z in [0,-4,-8,-12]:
    for a,b in zip(profile,profile[1:]):s.beam((a[0],a[1],z),(b[0],b[1],z),.20,C['orange'])
for index,(a,b) in enumerate(zip(profile[1:4],profile[2:5])):
    # Closed thin panels retain both exterior and interior faces after normal recalculation.
    vs=[(x,y+thickness,z) for thickness in [0,.06] for z in [-.08,-11.92] for x,y in [a,b]]
    s.add(vs,[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)],C['deep'] if index%2 else C['teal'])
for side in [-1,1]:
    s.box((side*7.62,2.75,-6),(.08,3.3,11.9),C['deep'])
    s.box((side*7.57,2.2,-6),(.035,.14,11.9),C['cream'])
for x in [-6.2,6.2]:s.box((x,5.73,-6),(.10,.10,11.9),C['cream'])
s.object('TunnelShell',root)
root=module('track_arch_01',(0,0,0));s=Shape()
for side in [-1,1]:
    s.box((side*7.65,2.7,0),(.85,5.4,.85),C['teal'],.12)
    s.box((side*7.65,.22,0),(1.2,.44,1.3),C['dark'],.08)
    for y in [.85,1.65,2.45,3.25,4.05]:s.box((side*7.65,y,-.45),(.66,.22,.05),C['cream'],.02)
s.box((0,5.3,0),(16.1,1.15,.9),C['orange'],.14)
for x in range(-7,8):
    for row in range(2):s.box((x,5.05+row*.36,-.463),(.90,.31,.04),C['cream'] if (x+row)%2 else C['dark'])
for column in range(14):
    for row in range(2):s.box((column-6.5,.018,(row-.5)*.7),(1,.015,.7),C['cream'] if (column+row)%2 else C['dark'])
s.object('Arch',root)
root=module('prop_itembox');s=Shape();s.box((0,.61,0),(.85,.85,.85),C['teal'],.07,rotate_z=math.pi/4)
for sign in [-1,1]:
    for x,y in [(0,1.14),(.53,.61),(0,.08),(-.53,.61)]:s.box((x,y,sign*.36),(.11,.11,.15),C['gold'],.024)
    poly=[(0,.34),(.07,.10),(.28,0),(.07,-.10),(0,-.34),(-.07,-.10),(-.28,0),(-.07,.10)]
    vs=[(x,.61+y,sign*.429) for x,y in poly];s.add(vs,[tuple(range(8))],C['cream'])
s.object('Crystal',root)
root=module('prop_boostpad',(0,0,-6));s=Shape();s.box((0,-.024,-3),(4,.05,6),C['dark'],.02)
for x in [-1.87,1.87]:s.box((x,.007,-3),(.15,.01,5.85),C['green'],.02)
for z in [-1,-3,-5]:
    poly=[(-1.6,z+.55),(0,z-.55),(1.6,z+.55),(1.6,z+.94),(0,z-.12),(-1.6,z+.94)]
    s.prism(poly,.001,.006,C['green'])
s.object('Pad',root)
root=module('prop_banner_01');s=Shape();s.box((0,.12,0),(.9,.24,.85),C['dark'],.06)
s.beam((0,.2,0),(0,4.6,0),.11,C['teal']);s.box((.88,3.25,0),(1.55,2.1,.08),C['orange'],.035)
# Directional geometric glyph, never a logo or real-world brand.
for z in [-.048,.048]:
    s.add([(.28,3.35,z),(.84,3.85,z),(1.40,3.35,z),(1.40,3.01,z),(.84,3.5,z),(.28,3.01,z)],[(0,1,2,3,4,5)],C['cream'])
s.object('Banner',root)
root=module('prop_deco_01');s=Shape();s.rock((0,0,0),(1.25,1.85,1.0),C['rock'],1);s.rock((1.1,0,.35),(.65,.72,.7),C['deep'],4)
for x,z in [(-1.0,-.5),(.5,-.9),(1.35,-.2)]:
    for angle in [0,2.1,4.2]:
        s.add([(x-.13,0,z),(x+.13,0,z),(x+.3*math.cos(angle),.65,z+.3*math.sin(angle)),(x-.13,0,z+.015),(x+.13,0,z+.015),(x+.3*math.cos(angle),.65,z+.3*math.sin(angle)+.015)],[(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)],C['green'])
s.object('RockGarden',root)
root=module('prop_deco_02');s=Shape()
for center,size in [((0,.65,0),(1.3,1.3,1.3)),((.9,.4,.2),(.8,.8,.8))]:
    s.box(center,size,C['orange'],.055)
    for x in [-.38,.38]:s.box((center[0]+x*size[0],center[1],center[2]),(.065,size[1]+.02,size[2]+.02),C['cream'],.015)
    for z in [-.505,.505]:s.box((center[0],center[1],center[2]+z*size[2]),(size[0]*.63,.08,.03),C['dark'],.01,rotate_z=.60)
s.object('Crates',root)
# Non-colliding infield scenery remains separated from the driveable deck by open air.
root=module('environment_island_01');s=Shape();n=20;vs=[]
for y,rx,rz in [(0,17,43),(-1.2,18,44),(-5,15,40),(-11,8,31)]:
    for i in range(n):
        a=math.tau*i/n;vs.append((rx*math.cos(a),y,rz*math.sin(a)))
s.add(vs,[tuple(range(n))],C['grass'])
for j in range(3):
    for i in range(n):s.add(vs,[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i)],C['rock'] if (i+j)%3 else C['deep'])
s.add(vs,[tuple(range(3*n,4*n))],C['dark']);s.object('Infield',root)

# Asset catalog: all mesh transforms remain identity. Sockets carry intentional offsets.
audit={'units':'metres','forward':'Blender +Y -> Godot -Z','road_width':14,'straight_grid':4,'curve_radius':32,'curve_subdivision_degrees':7.5,'ramp_run':12,'ramp_rise':1.4,'assets':{}}
for root in assets:
    objects=[root]+list(root.children_recursive)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=GAME+'/assets/track_kit/'+root.name+'.glb',export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_animations=False,export_extras=True,export_vertex_color='NAME',export_vertex_color_name='Color',export_all_vertex_colors=False)
    tris=0;identity=True
    for ob in objects:
        if ob.type=='MESH':ob.data.calc_loop_triangles();tris+=len(ob.data.loop_triangles);identity=identity and ob.matrix_basis==Matrix.Identity(4)
    audit['assets'][root.name]={**contracts[root.name],'triangles':tris,'mesh_transforms_identity':identity}
with open(GAME+'/artifacts/phase_5c/blender-kit-audit.json','w') as f:json.dump(audit,f,indent=2)
with open(GAME+'/assets/track_kit/catalog.json','w') as f:json.dump(audit,f,indent=2)
# Save an uncluttered source: show the ramp; other modules remain at their authored origins.
for root in assets:
    for ob in [root]+list(root.children_recursive):ob.hide_set(root.name!='track_ramp_01');ob.hide_render=root.name!='track_ramp_01'
camdata=tag(bpy.data.cameras.new('TrackKitCamera'));cam=link(bpy.data.objects.new('TrackKitCamera',camdata));cam.location=B((17,16,15));cam.rotation_euler=(B((0,0,-5))-cam.location).to_track_quat('-Z','Y').to_euler();camdata.type='ORTHO';camdata.ortho_scale=23;scene.camera=cam
for name,at,power,size in [('Key',(8,15,-2),2200,12),('Fill',(-8,10,-10),1300,10)]:
    d=tag(bpy.data.lights.new('Kit'+name,'AREA'));d.energy=power;d.size=size;o=link(bpy.data.objects.new('Kit'+name,d));o.location=B(at);o.rotation_euler=(B((0,0,-5))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.wm.save_as_mainfile(filepath=SOURCE+'/track_kit_01.blend')
shutil.copy2(SOURCE+'/track_kit_01.blend',GAME+'/source_assets/phase_5c/track_kit_01.blend')
result={'exports':len(assets),'audit':audit}
