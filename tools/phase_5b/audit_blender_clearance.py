"""Blender MCP geometric clearance audit of authored seated poses, without editing source."""
import bpy, math, ast, json
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
GAME='/Users/shane/Gaming/Games/nodekins-racing'
scene=bpy.data.scenes['Nodekins_Characters']
bpy.context.window.scene=scene
B=lambda g:Vector((g[0],-g[2],g[1]))
G=lambda b:Vector((b[0],b[2],-b[1]))
rigs=[bpy.data.objects[n] for n in ['CharRigMale','CharRigFemale','CharRigParts']]
BONES={b.name:(G(b.head_local),G(b.tail_local),b.parent.name if b.parent else None) for b in rigs[0].data.bones}
source=ast.parse(open(GAME+'/tools/phase_5b/build_characters.py').read())
for node in source.body:
    if isinstance(node,ast.FunctionDef) and node.name in ['pose','ik_elbow']:
        exec(compile(ast.Module(body=[node],type_ignores=[]),'pose_functions','exec'))
saved={r.name:{p.name:p.matrix_basis.copy() for p in r.pose.bones} for r in rigs}

def geom(ob,evaluated=True):
    e=ob.evaluated_get(bpy.context.evaluated_depsgraph_get()) if evaluated else ob
    mesh=e.to_mesh() if evaluated else ob.data
    mesh.calc_loop_triangles()
    verts=[G(ob.matrix_world@v.co) for v in mesh.vertices]
    faces=[tuple(t.vertices) for t in mesh.loop_triangles]
    if evaluated:e.to_mesh_clear()
    return verts,faces,BVHTree.FromPolygons(verts,faces,all_triangles=True,epsilon=0.0001)

kart=[bpy.data.objects[n] for n in ['kart_chassis_01','kart_spoiler_01','kart_glider_01']]
kgeom={o.name:geom(o,False) for o in kart}
results=[]
cases=[(kind,0.0,0.0) for kind in ['Drive','SteerLeft','SteerRight','Hit']]
cases += [('GlideLeft' if sign<0 else 'GlideRight',amount,sign*amount) for sign in [-1,1] for amount in [.25,.5,.75,1.0]]
for kind,phase,steer in cases:
    for r in rigs:pose(r,kind,phase)
    bpy.context.view_layer.update()
    krot=Matrix.Rotation(-steer*.04,3,'Z');grot=Matrix.Rotation(-steer*.18,3,'Z')
    for ob in scene.objects:
        if ob.type!='MESH':continue
        verts,faces,bvh=geom(ob)
        verts=[krot@v for v in verts]
        bvh=BVHTree.FromPolygons(verts,faces,all_triangles=True,epsilon=.0001)
        for name,(kv,kf,kbvh) in kgeom.items():
            rot=grot if name=='kart_glider_01' else krot
            kbvh=BVHTree.FromPolygons([rot@v for v in kv],kf,all_triangles=True,epsilon=.0001)
            pairs=bvh.overlap(kbvh)
            if pairs:
                cv=[verts[i] for a,b in pairs for i in faces[a]]
                # Hand/rim contact is intentional. Everything outside this grip envelope is a fault.
                local_cv=[krot.inverted()@v for v in cv]
                grip=ob.name.startswith('char_body_') and name=='kart_chassis_01' and all(.63<v.y<.80 and -.25<v.z<-.035 and abs(v.x)<.235 for v in local_cv)
                results.append({'pose':kind,'amount':phase,'part':ob.name,'kart':name,'pairs':len(pairs),'intentional_grip':grip,'min':[min(v[a] for v in cv) for a in range(3)],'max':[max(v[a] for v in cv) for a in range(3)]})
for r in rigs:
    for p in r.pose.bones:p.matrix_basis=saved[r.name][p.name]
bpy.context.view_layer.update()
with open(GAME+'/artifacts/phase_5b/clearance-intersections.json','w') as f:json.dump(results,f,indent=2)
result={'pose_cases':len(cases),'non_grip_intersections':[r for r in results if not r['intentional_grip']],'intentional_grip_contacts':len(results)}
