"""Run inside Blender through execute_blender_code. No external art or textures."""
import bpy, bmesh, math, json, os, shutil
from mathutils import Vector, Matrix

GAME = '/Users/shane/Gaming/Games/nodekins-racing'
SOURCE = '/Users/shane/Gaming/Assets/nodekins-racing/phase_5a'
scene = bpy.data.scenes.new('Nodekins_Kart_01')
bpy.context.window.scene = scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x = 1200
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.world = bpy.data.worlds.new('Kart_Studio_World')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (.16,.19,.25,1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = .45
scene.view_settings.view_transform = 'AgX'

def blender(g):
    return Vector((g[0], -g[2], g[1]))

def empty(name, parent=None, at=(0,0,0)):
    obj = bpy.data.objects.new(name, None)
    scene.collection.objects.link(obj)
    obj.empty_display_type = 'PLAIN_AXES'
    obj.empty_display_size = .13
    obj.parent = parent
    obj.location = blender(at)
    return obj

root = empty('kart_01')
root['forward_axis'] = 'Blender +Y -> Godot -Z; Blender Z up -> Godot Y up'
root['origin'] = 'ground center, metres; socket translations are intentional attachment offsets'
root['asset_id'] = 'kart_01'
root['mask_contract'] = 'COLOR_0.rgb = neutral grayscale; COLOR_0.a = paint mask, NOT opacity'
chassis_socket = empty('socket_chassis', root)
spoiler_socket = empty('socket_spoiler', root, (0,.62,.73))
glider_socket = empty('socket_glider', root, (0,.78,.40))

def material(name, roughness=.8):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Roughness'].default_value = roughness
    p.inputs['Metallic'].default_value = 0
    v = m.node_tree.nodes.new('ShaderNodeVertexColor')
    v.layer_name = 'Color'
    m.node_tree.links.new(v.outputs['Color'], p.inputs['Base Color'])
    return m

paint = material('Kart_Paint_GrayscaleMask')
rubber = material('Kart_Wheel_Grayscale')
wing_mat = material('Kart_Glider_Amber', .9)

class Shape:
    def __init__(self):
        self.v, self.f, self.c = [], [], []

    def add(self, vertices, faces, color=(.65,.65,.65,1)):
        n = len(self.v)
        self.v.extend(vertices)
        self.f.extend([tuple(n+i for i in face) for face in faces])
        self.c.extend([color]*len(faces))

    def box(self, center, size, bevel=0, segments=1, gray=.6, mask=1, rotate_x=0):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1)
        for v in bm.verts:
            v.co = Vector((v.co.x*size[0], v.co.y*size[1], v.co.z*size[2]))
        if bevel:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segments, affect='EDGES', profile=.5)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.verts.ensure_lookup_table()
        bm.verts.index_update()
        rot = Matrix.Rotation(rotate_x, 3, 'X')
        self.add([tuple(rot@v.co + Vector(center)) for v in bm.verts],
                 [tuple(v.index for v in f.verts) for f in bm.faces], (gray,gray,gray,mask))
        bm.free()

    def beam(self, start, end, radius, sides=6, color=(.08,.08,.08,0)):
        a,b = Vector(start), Vector(end)
        axis = (b-a).normalized()
        ref = Vector((0,1,0)) if abs(axis.y)<.9 else Vector((1,0,0))
        u = axis.cross(ref).normalized()*radius
        v = axis.cross(u).normalized()*radius
        vertices = [tuple(p+u*math.cos(i*math.tau/sides)+v*math.sin(i*math.tau/sides)) for p in [a,b] for i in range(sides)]
        faces = [tuple(range(sides-1,-1,-1)), tuple(range(sides,2*sides))]
        faces += [(i,(i+1)%sides,(i+1)%sides+sides,i+sides) for i in range(sides)]
        self.add(vertices,faces,color)

    def object(self, name, parent, mat):
        mesh = bpy.data.meshes.new(name+'_mesh')
        mesh.from_pydata([blender(v) for v in self.v], [], self.f)
        mesh.update()
        colors=mesh.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
        for poly,color in zip(mesh.polygons,self.c):
            poly.use_smooth=False
            for li in poly.loop_indices:
                colors.data[li].color=color
        mesh.materials.append(mat)
        # Ensure consistent outward normals after coordinate conversion and composed pieces.
        bm=bmesh.new(); bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(mesh); bm.free()
        mesh.update()
        obj=bpy.data.objects.new(name,mesh)
        scene.collection.objects.link(obj)
        obj.parent=parent
        return obj

body=Shape()
# Tapered perimeter tub: broad rear haunches, chamfered nose, three silhouette rings.
outline=[(-.38,-.93),(.38,-.93),(.54,-.76),(.58,-.28),(.58,.66),(.44,.91),(-.44,.91),(-.58,.66),(-.58,-.28),(-.54,-.76)]
verts=[]
for y,s in [(.17,.85),(.25,1),(.37,.94)]:
    verts.extend([(x*s,y,z*s) for x,z in outline])
n=len(outline)
faces=[tuple(range(n-1,-1,-1)),tuple(range(2*n,3*n))]
faces += [(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(2) for i in range(n)]
body.add(verts,faces,(.28,.28,.28,1))
body.box((0,.425,-.55),(.90,.31,.70),.075,2,.8)
for x in [-.46,.46]:
    body.box((x,.43,.13),(.23,.32,1.15),.055,2,.62)
body.box((0,.47,.68),(.92,.25,.39),.055,2,.6)
body.box((0,.24,-.82),(1.1,.13,.20),.04,1,.07,0)
body.box((0,.24,.83),(1.1,.13,.16),.035,1,.08,0)
body.box((0,.375,.13),(.54,.1,.50),.025,1,.04,0)
body.box((0,.62,.43),(.54,.47,.13),.035,1,.055,0,math.radians(-10))
body.box((0,.56,-.22),(.58,.12,.16),.035,1,.09,0)
body.box((0,.3,-.1),(.53,.06,.52),0,1,.12,0)
body.beam((0,.43,-.25),(0,.65,-.15),.033,8)
# Visible steering rim, 12-sided with a diamond tube section.
v=[]
for i in range(12):
    a=i*math.tau/12
    for j in range(4):
        b=j*math.tau/4
        r=.145+.025*math.cos(b)
        v.append((r*math.cos(a),.70+r*math.sin(a)*.75,-.17+r*math.sin(a)*.66+.025*math.sin(b)))
f=[(i*4+j,((i+1)%12)*4+j,((i+1)%12)*4+(j+1)%4,i*4+(j+1)%4) for i in range(12) for j in range(4)]
body.add(v,f,(.055,.055,.055,0))
body.beam((-.12,.7,-.17),(.12,.7,-.17),.016,4,(.3,.3,.3,0))
for x in [-.3,.3]:
    body.box((x,.44,-.886),(.20,.075,.045),.018,1,.95,0)
for z in [.58,.68,.78]:
    body.box((0,.604,z),(.38,.014,.035),0,1,.06,0)
chassis=body.object('kart_chassis_01',chassis_socket,paint)

wheel=Shape()
v=[]
for x,r in [(-.13,.23),(-.10,.29),(.10,.29),(.13,.23)]:
    for i in range(12):
        a=i*math.tau/12
        v.append((x,r*math.cos(a),r*math.sin(a)))
v += [(-.13,0,0),(.13,0,0)]
f=[(j*12+i,j*12+(i+1)%12,(j+1)*12+(i+1)%12,(j+1)*12+i) for j in range(3) for i in range(12)]
wheel.add(v,f,(.027,.027,.027,1))
for side,base in [(0,0),(1,36)]:
    for i in range(12):
        ids=(48+side,base+i,base+(i+1)%12)
        wheel.f.append(ids)
        g=.22 if i%2==0 else .09
        wheel.c.append((g,g,g,1))
wheels=[]
for i,(tag,x,z) in enumerate([('fl',-.68,-.57),('fr',.68,-.57),('rl',-.68,.60),('rr',.68,.60)]):
    socket=empty('socket_wheel_'+tag,root,(x,.29,z))
    if i==0:
        obj=wheel.object('kart_wheel_01',socket,rubber)
        shared=obj.data
    else:
        obj=bpy.data.objects.new('kart_wheel_01_'+tag,shared)
        scene.collection.objects.link(obj); obj.parent=socket
    wheels.append(obj)

spoiler=Shape()
spoiler.box((0,.19,.01),(1.16,.09,.24),.035,1,.6)
for x in [-.53,.53]:
    spoiler.box((x,.2,.01),(.075,.20,.30),.025,1,.34)
for x in [-.33,.33]:
    spoiler.box((x,.08,0),(.055,.19,.08),0,1,.08,0)
spoiler_obj=spoiler.object('kart_spoiler_01',spoiler_socket,paint)

glider=Shape()
# Closed, faceted swept canopy. Vertex colors are a simple amber/cream panel livery.
xs=[-1.9,-1.65,-1.15,-.55,0,.55,1.15,1.65,1.9]
zs=[-.6,-.32,-.04,.25,.50]
v=[]
for underside in [False,True]:
    for x in xs:
        t=abs(x)/1.9
        for z in zs:
            sweep=.22*t*t
            chord=1-.35*t
            arch=.92+.12*(1-t*t)+.08*math.cos((z+.2)*math.pi)
            v.append((x,arch-(.055 if underside else 0),z*chord+sweep-.4))
f=[]; colors=[]
for side in range(2):
    off=side*45
    for i in range(8):
        for j in range(4):
            ids=(off+i*5+j,off+(i+1)*5+j,off+(i+1)*5+j+1,off+i*5+j+1)
            f.append(ids if side==0 else ids[::-1])
            cream=(i in [2,5] or j==0)
            colors.append((.96,.81,.47,1) if cream else (.98,.46,.035,1))
edge=list(range(5))+[i*5+4 for i in range(1,9)]+[40+j for j in range(3,-1,-1)]+[i*5 for i in range(7,0,-1)]
for i in range(len(edge)):
    a,b=edge[i],edge[(i+1)%len(edge)]
    f.append((a,b,b+45,a+45)); colors.append((.32,.15,.025,1))
glider.add(v,f); glider.c=colors
for x in [-.46,.46]:
    glider.beam((x*.35,0,0),(x,.95,-.4),.026,4,(.10,.11,.14,1))
glider.box((0,.06,0),(.27,.16,.19),.025,1,.13,1)
glider_obj=glider.object('kart_glider_01',glider_socket,wing_mat)

parts=[chassis,*wheels,spoiler_obj,glider_obj]
for obj in parts:
    obj['part_id']=obj.name
    obj['socket']=obj.parent.name
    obj['shading']='flat'
bpy.context.view_layer.update()
audit={'forward_axis':root['forward_axis'],'unit_scale':scene.unit_settings.scale_length,'parts':[]}
for obj in parts:
    obj.data.calc_loop_triangles()
    coords=[obj.matrix_world@v.co for v in obj.data.vertices]
    bounds=[[min(v[i] for v in coords) for i in range(3)],[max(v[i] for v in coords) for i in range(3)]]
    audit['parts'].append({'name':obj.name,'triangles':len(obj.data.loop_triangles),'mesh':obj.data.name,'socket':obj.parent.name,'bounds_blender':bounds,'scale':list(obj.scale),'rotation':list(obj.rotation_euler),'location':list(obj.location),'material_count':len(obj.data.materials)})

# Delivery camera and studio lighting are source-only, excluded from selected-object GLB.
cam_data=bpy.data.cameras.new('Kart_Studio_Camera')
cam=bpy.data.objects.new('Kart_Studio_Camera',cam_data); scene.collection.objects.link(cam)
cam.location=blender((3.5,2.8,-4.0))
target=blender((0,.8,0)); cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
cam_data.type='ORTHO'; cam_data.ortho_scale=4.7; scene.camera=cam
for name,pos,power,size in [('Key',(3,5,-3),550,5),('Fill',(-3,3,-1),350,4),('Rim',(0,4,4),650,3)]:
    data=bpy.data.lights.new('Kart_'+name,'AREA'); data.energy=power; data.shape='DISK'; data.size=size
    ob=bpy.data.objects.new('Kart_'+name,data); scene.collection.objects.link(ob); ob.location=blender(pos)
    ob.rotation_euler=(target-ob.location).to_track_quat('-Z','Y').to_euler()
scene.render.film_transparent=True

bpy.ops.object.select_all(action='DESELECT')
for obj in [root,*root.children_recursive]: obj.select_set(True)
bpy.context.view_layer.objects.active=root
os.makedirs(SOURCE,exist_ok=True)
export_path=GAME+'/assets/karts/kart_01.glb'
bpy.ops.export_scene.gltf(filepath=export_path,export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_animations=False,export_cameras=False,export_lights=False,export_extras=True,export_apply=True,export_vertex_color='NAME',export_vertex_color_name='Color',export_all_vertex_colors=False)
bpy.ops.wm.save_as_mainfile(filepath=SOURCE+'/kart_01.blend')
shutil.copy2(SOURCE+'/kart_01.blend', GAME+'/source_assets/phase_5a/kart_01.blend')
with open(GAME+'/artifacts/phase_5a/blender-audit.json','w') as file: json.dump(audit,file,indent=2)
result={'export':export_path,'source':SOURCE+'/kart_01.blend','audit':audit}
