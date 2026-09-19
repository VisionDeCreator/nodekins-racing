"""Original modular variants, authored in the connected Blender MCP. Existing assets untouched."""
import bpy, bmesh, math, ast, json, shutil
from pathlib import Path
from mathutils import Vector, Matrix
GAME=Path('/Users/shane/Gaming/Games/nodekins-racing')
SOURCE=Path('/Users/shane/Gaming/Assets/nodekins-racing/phase_6_5')
TAG='phase6_5'; NAME='Nodekins_Customization'
old=bpy.data.scenes.get(NAME)
if old:
    if old.get('nodekins_builder')!=TAG or any(o.get('nodekins_builder')!=TAG for o in old.objects):raise RuntimeError('Unowned customization source')
    for ob in list(old.objects):bpy.data.objects.remove(ob,do_unlink=True)
    bpy.data.scenes.remove(old)
    for group in [bpy.data.meshes,bpy.data.armatures,bpy.data.materials]:
        for data in list(group):
            if data.get('nodekins_builder')==TAG and data.users==0:group.remove(data)
scene=bpy.data.scenes.new(NAME);scene['nodekins_builder']=TAG;bpy.context.window.scene=scene
scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
# Reuse our original primitive construction helper, without executing its asset build.
tree=ast.parse((GAME/'tools/phase_5a/build_kart.py').read_text())
exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in ['blender','material','Shape']],type_ignores=[]),'kart_geometry_helpers','exec'))
def tag(ob):ob['nodekins_builder']=TAG;return ob
def link(ob):tag(ob);scene.collection.objects.link(ob);return ob
root=link(bpy.data.objects.new('kart_variants',None))
paint=tag(material('Customization_Paint_Mask'))
def clone(source,name):
    ob=bpy.data.objects[source].copy();ob.data=tag(ob.data.copy());ob.name=name;ob.data.name=name+'_mesh';ob.parent=root;ob.matrix_basis=Matrix.Identity(4);link(ob);return ob
chassis=clone('kart_chassis_01','kart_chassis_02')
for v in chassis.data.vertices:
    # Preserve seat, steering wheel, floor and the full rider envelope.
    if v.co.y>.34 and v.co.z>.27:v.co.x*=.84
chassis.data.update()
wheel=Shape();n=16;vs=[]
for x,r in [(-.13,.23),(-.10,.29),(.10,.29),(.13,.23)]:
    for i in range(n):
        a=math.tau*i/n;vs.append((x,r*math.cos(a),r*math.sin(a)))
wheel.add(vs,[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(3) for i in range(n)],(.026,.026,.026,0))
for side in [-1,1]:
    vs=[(side*.13,0,0)]+[(side*.13,.23*math.cos(math.tau*i/n),.23*math.sin(math.tau*i/n)) for i in range(n)]
    wheel.add(vs,[(0,i+1,(i+1)%n+1) for i in range(n)],(.1,.1,.1,1))
    for i in range(6):
        a=math.tau*i/6
        wheel.beam((side*.135,.05*math.cos(a),.05*math.sin(a)),(side*.135,.195*math.cos(a),.195*math.sin(a)),.025,4,(.9,.9,.9,1))
wheel_ob=wheel.object('kart_wheel_02',root,paint);tag(wheel_ob);tag(wheel_ob.data)
spoiler=Shape();spoiler.box((0,.16,.01),(1.14,.07,.23),.025,1,.72)
for x in [-.51,.51]:spoiler.box((x,.22,.035),(.065,.25,.34),.018,1,.9)
for x in [-.33,.33]:spoiler.box((x,.07,0),(.055,.16,.08),0,1,.07,0)
spoiler_ob=spoiler.object('kart_spoiler_02',root,paint);tag(spoiler_ob);tag(spoiler_ob.data)
wing=clone('kart_glider_01','kart_glider_02')
for v in wing.data.vertices:
    if abs(v.co.x)>.5:
        t=(abs(v.co.x)-.5)/1.4
        v.co.x*=.94;v.co.y-=.35*t;v.co.z+=.10*t
wing.data.update()
rig_source=bpy.data.objects['CharRigParts']
rig=rig_source.copy();rig.data=tag(rig_source.data.copy());rig.name='CharRigCustomization';rig.animation_data_clear();rig.parent=None;rig.matrix_basis=Matrix.Identity(4);link(rig)
for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
hair=Shape();n=16;vs=[]
for j in range(5):
    for i in range(n):
        a=math.tau*i/n;theta=max(.04,j/4*(1.18-max(0,-math.sin(a))*.25))
        vs.append((.241*math.sin(theta)*math.cos(a),1.225+.253*math.cos(theta),.217*math.sin(theta)*math.sin(a)))
hair.add(vs,[(j*n+i,(j+1)*n+i,(j+1)*n+(i+1)%n,j*n+(i+1)%n) for j in range(4) for i in range(n)]+[tuple(range(n-1,-1,-1))],(.035,.019,.033,1))
# Five separate chunky tufts create a readable mohawk without exceeding the wing clearance.
for z,y in [(-.145,1.435),(-.072,1.482),(0,1.498),(.072,1.482),(.145,1.435)]:
    vs=[(-.045,y,z-.048),(.045,y,z-.048),(.045,y,z+.048),(-.045,y,z+.048),(-.022,y+.16,z-.025),(.022,y+.16,z-.025),(.022,y+.14,z+.04),(-.022,y+.14,z+.04)]
    hair.add(vs,[(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)],(.17,.035,.085,1))
hair_ob=hair.object('char_hair_03',rig,paint);tag(hair_ob);tag(hair_ob.data)
for bone in rig.data.bones:hair_ob.vertex_groups.new(name=bone.name)
hair_ob.vertex_groups['head'].add(list(range(len(hair_ob.data.vertices))),1,'REPLACE')
modifier=hair_ob.modifiers.new('SharedArmature','ARMATURE');modifier.object=rig
bpy.context.view_layer.update()
audit={'source':str(SOURCE/'customization_01.blend'),'units':'metres','forward':'Blender +Y -> Godot -Z','parts':[]}
for ob in [chassis,wheel_ob,spoiler_ob,wing,hair_ob]:
    ob.data.calc_loop_triangles()
    audit['parts'].append({'name':ob.name,'triangles':len(ob.data.loop_triangles),'identity':ob.matrix_basis==Matrix.Identity(4)})
for filename,objects in [('kart_variants.glb',[root,chassis,wheel_ob,spoiler_ob,wing]),('character_variants.glb',[rig,hair_ob])]:
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:ob.hide_set(False);ob.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.export_scene.gltf(filepath=str(GAME/'assets/customization'/filename),export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_animations=False,export_def_bones=False,export_skins=True,export_apply=False,export_extras=True,export_vertex_color='NAME',export_vertex_color_name='Color',export_all_vertex_colors=False)
for ob in [chassis,wheel_ob,spoiler_ob,wing]:ob.hide_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'customization_01.blend'))
shutil.copy2(SOURCE/'customization_01.blend',GAME/'source_assets/phase_6_5/customization_01.blend')
(GAME/'artifacts/phase_6_5/blender-audit.json').write_text(json.dumps(audit,indent=2))
result=audit
