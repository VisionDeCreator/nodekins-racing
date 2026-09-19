"""Original Nodekins characters. Execute only through Blender MCP, in the connected file."""
import bpy, bmesh, math, json, os, shutil
from mathutils import Vector, Matrix

GAME='/Users/shane/Gaming/Games/nodekins-racing'
SOURCE='/Users/shane/Gaming/Assets/nodekins-racing/phase_5b'
SCENE='Nodekins_Characters'
# Rebuild only this tool's tagged output; never remove the user's kart or other scenes.
old=bpy.data.scenes.get(SCENE)
if old:
    if old.get('nodekins_builder') != 'phase5b': raise RuntimeError('Unowned character scene exists')
    for ob in list(old.objects):
        if ob.get('nodekins_builder') != 'phase5b': raise RuntimeError('Unowned object in character scene: '+ob.name)
    for ob in list(old.objects): bpy.data.objects.remove(ob,do_unlink=True)
    bpy.data.scenes.remove(old)
    for group in [bpy.data.meshes,bpy.data.armatures,bpy.data.materials,bpy.data.actions,bpy.data.cameras,bpy.data.lights,bpy.data.worlds]:
        for data in list(group):
            if data.get('nodekins_builder')=='phase5b' and data.users==0: group.remove(data)
scene=bpy.data.scenes.new(SCENE); scene['nodekins_builder']='phase5b'
bpy.context.window.scene=scene
scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
scene.render.engine='BLENDER_EEVEE'; scene.render.fps=30
scene.frame_start=1; scene.frame_end=61
scene.render.resolution_x=1200; scene.render.resolution_y=900; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.world=bpy.data.worlds.new('Character_Studio_World'); scene.world['nodekins_builder']='phase5b'; scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.12,.16,.22,1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.6

def B(g): return Vector((g[0],-g[2],g[1]))
def tag(data): data['nodekins_builder']='phase5b'; return data
def link(ob): tag(ob); scene.collection.objects.link(ob); return ob

BONES={}
def bone(name,head,tail,parent=None): BONES[name]=(Vector(head),Vector(tail),parent)
bone('root',(0,0,0),(0,.1,0))
bone('hips',(0,.60,0),(0,.72,0),'root')
bone('spine',(0,.72,0),(0,.85,0),'hips')
bone('chest',(0,.85,0),(0,.96,0),'spine')
bone('neck',(0,.96,0),(0,1.04,0),'chest')
bone('head',(0,1.04,0),(0,1.40,0),'neck')
for side,s in [('L',-1),('R',1)]:
    bone('upper_arm.'+side,(s*.18,.91,0),(s*.385,.91,0),'chest')
    bone('forearm.'+side,(s*.385,.91,0),(s*.57,.91,0),'upper_arm.'+side)
    bone('hand.'+side,(s*.57,.91,0),(s*.67,.91,0),'forearm.'+side)
    bone('thigh.'+side,(s*.1,.60,0),(s*.1,.32,0),'hips')
    bone('shin.'+side,(s*.1,.32,0),(s*.1,.09,0),'thigh.'+side)
    bone('foot.'+side,(s*.1,.09,0),(s*.1,.05,-.12),'shin.'+side)
bone('socket_hair',(0,1.43,0),(0,1.48,0),'head')
bone('socket_eyes',(0,1.23,-.21),(0,1.28,-.21),'head')
bone('socket_shirt',(0,.83,0),(0,.88,0),'chest')
bone('socket_pants',(0,.60,0),(0,.65,0),'hips')
for side,s in [('L',-1),('R',1)]: bone('socket_shoes.'+side,(s*.1,.09,0),(s*.1,.14,0),'foot.'+side)

def armature(name):
    data=tag(bpy.data.armatures.new(name+'_skeleton'))
    ob=link(bpy.data.objects.new(name,data)); ob.show_in_front=True
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); bpy.context.view_layer.objects.active=ob
    bpy.ops.object.mode_set(mode='EDIT')
    for name,(head,tail,parent) in BONES.items():
        eb=data.edit_bones.new(name); eb.head=B(head); eb.tail=B(tail)
        if parent: eb.parent=data.edit_bones[parent]
        eb.use_deform=not name.startswith('socket_')
    bpy.ops.object.mode_set(mode='OBJECT')
    ob['rig_id']='nodekins_humanoid_01'; ob['forward']='Blender +Y / Godot -Z'; ob['units']='metres'
    return ob
male_rig=armature('CharRigMale'); female_rig=armature('CharRigFemale')
parts_rig=armature('CharRigParts')

def material(name):
    m=tag(bpy.data.materials.new(name)); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Roughness'].default_value=.9
    v=m.node_tree.nodes.new('ShaderNodeVertexColor'); v.layer_name='Color'
    m.node_tree.links.new(v.outputs['Color'],p.inputs['Base Color'])
    return m
skin=material('Character_Skin_Neutral'); cloth=material('Character_Clothing'); hairmat=material('Character_Hair'); eyesmat=material('Character_Eyes')

class Shape:
    def __init__(self): self.v=[];self.f=[];self.c=[];self.w=[]
    def add(self,vertices,faces,color,weights):
        n=len(self.v); self.v.extend(vertices); self.f.extend([tuple(n+i for i in f) for f in faces]); self.c.extend([color]*len(faces))
        self.w.extend([weights(v) if callable(weights) else weights.copy() for v in vertices])
    def ellipsoid(self,center,radii,weight,segments=12,rings=8,color=(.8,.8,.8,1)):
        vs=[]
        for j in range(1,rings):
            a=math.pi*j/rings
            for i in range(segments):
                t=math.tau*i/segments
                vs.append((center[0]+radii[0]*math.sin(a)*math.cos(t),center[1]+radii[1]*math.cos(a),center[2]+radii[2]*math.sin(a)*math.sin(t)))
        vs.extend([(center[0],center[1]+radii[1],center[2]),(center[0],center[1]-radii[1],center[2])])
        top=len(vs)-2; bot=len(vs)-1
        fs=[(top,i,(i+1)%segments) for i in range(segments)]
        fs += [(j*segments+i,(j+1)*segments+i,(j+1)*segments+(i+1)%segments,j*segments+(i+1)%segments) for j in range(rings-2) for i in range(segments)]
        fs += [(bot,(rings-2)*segments+(i+1)%segments,(rings-2)*segments+i) for i in range(segments)]
        self.add(vs,fs,color,weight)
    def loft(self,sections,weight,color,axis='y',sides=10,caps=True):
        vs=[]
        for center,r1,r2 in sections:
            for i in range(sides):
                a=math.tau*(i+.5)/sides
                q=(r1*math.cos(a),0,r2*math.sin(a)) if axis=='y' else (0,r1*math.cos(a),r2*math.sin(a))
                vs.append(tuple(Vector(center)+Vector(q)))
        fs=[(j*sides+i,(j+1)*sides+i,(j+1)*sides+(i+1)%sides,j*sides+(i+1)%sides) for j in range(len(sections)-1) for i in range(sides)]
        if caps: fs += [tuple(range(sides-1,-1,-1)),tuple(range((len(sections)-1)*sides,len(sections)*sides))]
        self.add(vs,fs,color,weight)
    def box(self,center,size,weight,color,bevel=0):
        bm=bmesh.new(); bmesh.ops.create_cube(bm,size=1)
        for v in bm.verts: v.co=Vector((v.co.x*size[0],v.co.y*size[1],v.co.z*size[2]))
        if bevel: bmesh.ops.bevel(bm,geom=list(bm.edges),offset=bevel,segments=1,affect='EDGES')
        bm.verts.ensure_lookup_table();bm.verts.index_update()
        self.add([tuple(v.co+Vector(center)) for v in bm.verts],[tuple(v.index for v in f.verts) for f in bm.faces],color,weight); bm.free()
    def object(self,name,rig,mat):
        mesh=tag(bpy.data.meshes.new(name+'_mesh'));mesh.from_pydata([B(v) for v in self.v],[],self.f);mesh.update()
        attr=mesh.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
        for f,c in zip(mesh.polygons,self.c):
            f.use_smooth=False
            for i in f.loop_indices:attr.data[i].color=c
        bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
        mesh.materials.append(mat); ob=link(bpy.data.objects.new(name,mesh));ob.parent=rig
        for bone_name in BONES: ob.vertex_groups.new(name=bone_name)
        for i,ws in enumerate(self.w):
            total=sum(ws.values())
            for bone_name,w in ws.items():
                if w>0: ob.vertex_groups[bone_name].add([i],w/total,'REPLACE')
        mod=ob.modifiers.new('SharedArmature','ARMATURE');mod.object=rig
        ob['part_id']=name;ob['rig_id']='nodekins_humanoid_01'
        return ob

def torso_weights(v):
    y=v[1]
    if y<.72:
        t=max(0,min(1,(y-.63)/.09));return {'hips':1-t,'spine':t}
    t=max(0,min(1,(y-.72)/.13));return {'spine':1-t,'chest':t}
def arm_weights(side):
    def weights(v):
        x=abs(v[0]);t=max(0,min(1,(x-.35)/.07))
        return {'upper_arm.'+side:1-t,'forearm.'+side:t}
    return weights
def leg_weights(side):
    def weights(v):
        t=max(0,min(1,(.36-v[1])/.08))
        return {'thigh.'+side:1-t,'shin.'+side:t}
    return weights

bodies=[]
for gender,rig in [('male',male_rig),('female',female_rig)]:
    s=Shape(); feminine=gender=='female'
    s.loft([((0,.61,0),.15 if not feminine else .164,.098),((0,.7,0),.16 if not feminine else .145,.10),((0,.8,0),.183 if not feminine else .167,.104),((0,.9,0),.205 if not feminine else .191,.102),((0,.94,0),.16,.082)],torso_weights,(.8,.8,.8,1))
    s.ellipsoid((0,.595,0),(.157 if not feminine else .172,.075,.103),{'hips':1},12,6)
    s.loft([((0,.945,0),.063,.065),((0,1.055,0),.067,.067)],{'neck':1},(.76,.76,.76,1),sides=8)
    s.ellipsoid((0,1.215,0),(.224,.228,.199),{'head':1},16,10)
    # Subtle shared-fit jaw shaping, below the common eyes/hair envelope.
    for i,v in enumerate(s.v):
        if v[1]>1.0 and v[1]<1.17:
            factor=.94 if feminine else 1.02
            s.v[i]=(v[0]*factor,v[1],v[2])
    for sign in [-1,1]: s.ellipsoid((sign*.222,1.20,.012),(.034,.058,.039),{'head':1},8,6)
    s.box((0,1.19,-.2),(.066,.058,.065),{'head':1},(.81,.81,.81,1),.015)
    for side,sign in [('L',-1),('R',1)]:
        s.loft([((sign*x,.91,0),r,r*.92) for x,r in [(.18,.07),(.25,.068),(.34,.06),(.385,.057),(.43,.055),(.51,.047),(.57,.04)]],arm_weights(side),(.8,.8,.8,1),'x',8)
        s.ellipsoid((sign*.623,.91,0),(.065,.047,.044),{'hand.'+side:1},8,6)
        s.loft([((sign*.1,y,0),r,r*.94) for y,r in [(.60,.078),(.52,.081),(.40,.068),(.32,.061),(.26,.06),(.16,.05),(.09,.043)]],leg_weights(side),(.8,.8,.8,1),sides=8)
        s.ellipsoid((sign*.1,.072,-.039),(.062,.05,.108),{'foot.'+side:1},8,4)
    bodies.append(s.object('char_body_'+gender,rig,skin))

parts=[]
# Face patches follow the common head surface and are weighted to the head bone.
eyes=Shape()
def face_z(x,y,offset=.004):return -.199*math.sqrt(max(.03,1-(x/.224)**2-((y-1.215)/.228)**2))-offset
def eye_disc(cx,cy,rx,ry,color,offset):
    v=[(cx,cy,face_z(cx,cy,offset))]
    for i in range(12):
        a=math.tau*i/12;x=cx+rx*math.cos(a);y=cy+ry*math.sin(a);v.append((x,y,face_z(x,y,offset)))
    eyes.add(v,[(0,i+1,(i+1)%12+1) for i in range(12)],color,{'head':1})
for x in [-.087,.087]:
    eye_disc(x,1.245,.064,.076,(.98,.98,.95,1),.006)
    eye_disc(x,1.239,.027,.041,(.025,.18,.25,1),.009)
    eye_disc(x,1.239,.013,.027,(.009,.014,.02,1),.011)
    eye_disc(x-.009,1.258,.008,.011,(1,1,1,1),.013)
    eyes.box((x,1.327,face_z(x,1.327,.007)),(.09,.016,.008),{'head':1},(.09,.045,.025,1))
v=[]
for i in range(9):
    x=-.058+i*.0145;y=1.095+.017*(x/.058)**2
    v.extend([(x,y,face_z(x,y,.006)),(x,y+.008,face_z(x,y+.008,.006))])
eyes.add(v,[(i*2,i*2+1,i*2+3,i*2+2) for i in range(8)],(.14,.06,.035,1),{'head':1})
parts.append(eyes.object('char_eyes_01',parts_rig,eyesmat))

for style in [1,2]:
    h=Shape();n=16;v=[];layers=5
    for j in range(layers):
        for i in range(n):
            a=math.tau*i/n
            front=max(0,-math.sin(a))
            # Polar angle: high hairline in front; bob extends to cheek height at back/sides.
            theta=(j/(layers-1))*(2.08-front*.93 if style==2 else 1.20-front*.22)
            if j==0:theta=.05
            x=.241*math.sin(theta)*math.cos(a)
            y=1.225+.252*math.cos(theta)
            z=.217*math.sin(theta)*math.sin(a)
            if style==1:y+=.04*max(0,math.cos(a))*(1-j/(layers-1))
            v.append((x,y,z))
    f=[(j*n+i,(j+1)*n+i,(j+1)*n+(i+1)%n,j*n+(i+1)%n) for j in range(layers-1) for i in range(n)]
    f+=[tuple(range(n-1,-1,-1))]
    h.add(v,f,(.052,.025,.016,1) if style==1 else (.16,.062,.029,1),{'head':1})
    # Sculpted asymmetric swept fringe, safely above the eye patches.
    fringe=[(-.105,1.407,-.12,(.16,.07,.18)),(.018,1.443,-.135,(.17,.08,.17)),(.125,1.407,-.1,(.115,.06,.12))] if style==1 else [(-.145,1.342,-.15,(.087,.095,.091)),(-.042,1.399,-.175,(.13,.071,.069)),(.148,1.329,-.135,(.076,.106,.08))]
    for x,y,z,scale in fringe:
        h.ellipsoid((x,y,z),scale,{'head':1},8,4,(.065,.032,.018,1) if style==1 else (.18,.074,.034,1))
    parts.append(h.object('char_hair_%02d'%style,parts_rig,hairmat))

for style in [1,2]:
    s=Shape();c=(.06,.35,.65,1) if style==1 else (.77,.20,.075,1)
    s.loft([((0,.632,0),.177,.119),((0,.72,0),.178,.12),((0,.82,0),.196,.123),((0,.91,0),.227,.125),((0,.951,0),.16,.091)],torso_weights,c,sides=10)
    for side,sign in [('L',-1),('R',1)]:
        xs=[(.18,.087),(.25,.086),(.31,.077)] if style==1 else [(.18,.087),(.29,.08),(.35,.075),(.385,.073),(.43,.071),(.51,.062),(.525,.06)]
        s.loft([((sign*x,.91,0),r,r*.97) for x,r in xs],arm_weights(side),c,'x',8)
    s.loft([((0,.936,0),.078,.077),((0,.963,0),.077,.075)],{'chest':1},(.92,.88,.73,1),sides=10,caps=False)
    if style==1:
        s.box((0,.807,-.125),(.27,.049,.01),{'chest':1},(.95,.84,.35,1))
    else:
        s.box((0,.79,-.128),(.025,.285,.012),torso_weights,(.96,.9,.75,1))
        for x in [-.106,.106]:s.box((x,.74,-.123),(.089,.009,.012),torso_weights,(.12,.045,.02,1))
    parts.append(s.object('char_shirt_%02d'%style,parts_rig,cloth))
    p=Shape();pc=(.095,.16,.23,1) if style==1 else (.15,.22,.13,1)
    p.ellipsoid((0,.595,0),(.184,.086,.121),{'hips':1},12,6,pc)
    for side,sign in [('L',-1),('R',1)]:
        ys=[(.595,.091),(.52,.096),(.42,.083),(.38,.079)] if style==1 else [(.595,.091),(.52,.096),(.40,.083),(.32,.078),(.26,.077),(.17,.066),(.105,.06)]
        p.loft([((sign*.1,y,0),r,r*1.02) for y,r in ys],leg_weights(side),pc,sides=8)
    p.loft([((0,.65,0),.173,.123),((0,.674,0),.173,.123)],{'hips':1},(.055,.065,.07,1),sides=10,caps=False)
    parts.append(p.object('char_pants_%02d'%style,parts_rig,cloth))
    sh=Shape();sc=(.83,.85,.81,1) if style==1 else (.115,.065,.045,1)
    for side,sign in [('L',-1),('R',1)]:
        sh.box((sign*.1,.074,-.045),(.14,.13,.244),{'foot.'+side:1},sc,.025)
        sh.box((sign*.1,.018,-.045),(.144,.036,.247),{'foot.'+side:1},(.07,.09,.115,1),.012)
        if style==1:
            sh.box((sign*.1,.14,-.043),(.085,.015,.081),{'foot.'+side:1},(.09,.41,.52,1))
        else:
            sh.loft([((sign*.1,.09,0),.069,.071),((sign*.1,.182,0),.065,.067)],{'foot.'+side:1},sc,sides=8)
    parts.append(sh.object('char_shoes_%02d'%style,parts_rig,cloth))

def ik_elbow(a,w,l1,l2,pole):
    direction=w-a;d=min(direction.length,l1+l2-.0001);u=direction.normalized()
    along=(l1*l1-l2*l2+d*d)/(2*d);h=math.sqrt(max(0,l1*l1-along*along))
    p=Vector(pole);p=(p-u*p.dot(u)).normalized()
    return a+u*along+p*h

def pose(rig,kind,phase=0):
    for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    drive=kind in ['Drive','SteerLeft','SteerRight','Hit','GlideLeft','GlideRight']
    offset=Vector((0,-.08,.19)) if drive else Vector((0,0,0))
    targets={n:(h+offset,t+offset) for n,(h,t,p) in BONES.items() if not n.startswith('socket_')}
    targets['root']=(offset,Vector((0,.1,0))+offset)
    if drive:
        # A slight forward torso lean clears the existing rear-top glider supports.
        for n in ['spine','chest','neck','head']:
            h,t=targets[n]
            h.z-=.07*max(0,min(1,(h.y-.64)/.18));t.z-=.07*max(0,min(1,(t.y-.64)/.18))
            targets[n]=(h,t)
    lean=(-.020 if kind=='SteerLeft' else .020 if kind=='SteerRight' else 0)
    if lean:
        for n in ['spine','chest','neck','head']:
            h,t=targets[n];h.x+=lean*max(0,(h.y-.5)/.5);t.x+=lean*max(0,(t.y-.5)/.5);targets[n]=(h,t)
    bank=(.14 if kind=='GlideLeft' else -.14 if kind=='GlideRight' else 0)*phase
    bank_rotation=Matrix.Rotation(bank,3,'Z')
    bank_lift=Vector((0,abs(bank)*.22,0))
    for side,sign in [('L',-1),('R',1)]:
        a=Vector((sign*.18,.91,0))+offset
        if drive:
            a.x+=lean*.7
            a.z-=.07
            if bank:a=bank_rotation@a+bank_lift
            w=Vector((sign*.145,.714,-.105));e=ik_elbow(a,w,.205,.185,(sign,0,0))
            ht=w+Vector((0,-.015,-.098))
            hip=Vector((sign*.1,.52,.19));k=hip+Vector((0,.14,-math.sqrt(.28**2-.14**2)))
            ankle_y=.528
            ankle=k+Vector((0,ankle_y-k.y,math.sqrt(.23**2-(ankle_y-k.y)**2)))
            targets['thigh.'+side]=(hip,k);targets['shin.'+side]=(k,ankle);targets['foot.'+side]=(ankle,ankle+Vector((0,-.04,-.12)))
        elif kind=='Victory':
            w=Vector((sign*(.37+.025*phase),1.225+.01*phase,-.035));e=ik_elbow(a,w,.205,.185,(sign,0,-.2));ht=w+Vector((0,.10,0))
        else:
            w=Vector((sign*.265,.54,-.035));e=ik_elbow(a,w,.205,.185,(sign,0,.15));ht=w+Vector((0,-.098,-.02))
        targets['upper_arm.'+side]=(a,e);targets['forearm.'+side]=(e,w);targets['hand.'+side]=(w,ht)
    if bank:
        for n,(h,t) in list(targets.items()):
            if not n.startswith(('upper_arm.','forearm.','hand.')):
                targets[n]=(bank_rotation@h+bank_lift,bank_rotation@t+bank_lift)
    if kind=='Hit':
        h,t=targets['head'];t+=Vector((0,-.024,.075));targets['head']=(h,t)
    if kind=='Idle':
        h,t=targets['head'];t+=Vector((.018*phase,0,0));targets['head']=(h,t)
    for name,(h,t) in targets.items():
        rest=rig.data.bones[name]
        q=(rest.tail_local-rest.head_local).rotation_difference(B(t-h))
        world=Matrix.Translation(B(h)) @ q.to_matrix().to_4x4() @ rest.matrix_local.to_3x3().to_4x4()
        rig.pose.bones[name].matrix=world
        bpy.context.view_layer.update()

actions={}
for rig in [male_rig,female_rig]:
    rig.animation_data_create()
    for kind in ['Idle','Drive','SteerLeft','SteerRight','Hit','Victory','GlideLeft','GlideRight']:
        action=tag(bpy.data.actions.new(kind+'_'+rig.name));rig.animation_data.action=action
        for frame,phase in [(1,0),(16,1),(31,0),(46,-1),(61,0)]:
            scene.frame_set(frame);pose(rig,kind,(1-abs(frame-31)/30) if kind.startswith('Glide') else phase if kind in ['Idle','Victory'] else 0)
            for pb in rig.pose.bones:
                if pb.name.startswith('socket_'):continue
                pb.rotation_mode='QUATERNION'
                pb.keyframe_insert(data_path='location',frame=frame)
                pb.keyframe_insert(data_path='rotation_quaternion',frame=frame)
                pb.keyframe_insert(data_path='scale',frame=frame)
        track=rig.animation_data.nla_tracks.new();track.name=kind
        strip=track.strips.new(kind,1,action);strip.action_slot=action.slots[0]
        track.mute=True
        rig.animation_data.action=None
        actions[(rig.name,kind)]=action
    for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)

def export(path,rig,objects,animations):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in [rig,*objects]:ob.select_set(True)
    bpy.context.view_layer.objects.active=rig
    for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    scene.frame_set(1)
    for track in rig.animation_data.nla_tracks if rig.animation_data else []:track.mute=False
    bpy.ops.export_scene.gltf(filepath=GAME+'/assets/characters/'+path,export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_animations=animations,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_nla_strips=True,export_def_bones=False,export_skins=True,export_apply=False,export_extras=True,export_vertex_color='NAME',export_vertex_color_name='Color',export_all_vertex_colors=False)
    for track in rig.animation_data.nla_tracks if rig.animation_data else []:track.mute=True

export('char_body_male.glb',male_rig,[bodies[0]],True)
export('char_body_female.glb',female_rig,[bodies[1]],True)
export('char_appearance_parts.glb',parts_rig,parts,False)

audit={'rig_id':'nodekins_humanoid_01','bone_count':len(BONES),'bones':{n:{'head':list(h),'tail':list(t),'parent':p} for n,(h,t,p) in BONES.items()},'parts':[],'animations':['Idle','Drive','SteerLeft','SteerRight','Hit','Victory','GlideLeft','GlideRight']}
for ob in bodies+parts:
    ob.data.calc_loop_triangles()
    audit['parts'].append({'name':ob.name,'triangles':len(ob.data.loop_triangles),'identity_transform':ob.matrix_basis==Matrix.Identity(4),'unweighted_vertices':sum(not v.groups for v in ob.data.vertices)})
with open(GAME+'/artifacts/phase_5b/blender-audit.json','w') as f:json.dump(audit,f,indent=2)

# Source studio for inspecting the asset; not part of any exported GLB.
camdata=tag(bpy.data.cameras.new('CharacterStudioCamera'));cam=link(bpy.data.objects.new('CharacterStudioCamera',camdata))
cam.location=B((2.1,1.65,-3.6));cam.rotation_euler=(B((0,.8,0))-cam.location).to_track_quat('-Z','Y').to_euler();camdata.type='ORTHO';camdata.ortho_scale=2.05;scene.camera=cam
for name,pos,power,size in [('Key',(3,5,-3),450,4),('Fill',(-3,2,-2),220,3),('Rim',(0,4,3),500,3)]:
    data=tag(bpy.data.lights.new('Character'+name,'AREA'));data.energy=power;data.size=size
    ob=link(bpy.data.objects.new('Character'+name,data));ob.location=B(pos);ob.rotation_euler=(B((0,.8,0))-ob.location).to_track_quat('-Z','Y').to_euler()
scene.frame_set(1)
pose(male_rig,'Idle');pose(parts_rig,'Idle');pose(female_rig,'Idle')
bodies[1].hide_render=True;bodies[1].hide_set(True)
for ob in parts:
    if ob.name.endswith('_02'):ob.hide_render=True;ob.hide_set(True)
scene.render.film_transparent=True
bpy.ops.wm.save_as_mainfile(filepath=SOURCE+'/characters_01.blend')
shutil.copy2(SOURCE+'/characters_01.blend',GAME+'/source_assets/phase_5b/characters_01.blend')
result={'exports':['char_body_male.glb','char_body_female.glb','char_appearance_parts.glb'],'audit':audit}
