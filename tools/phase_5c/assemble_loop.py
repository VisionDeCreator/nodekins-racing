"""Place exported modules at the existing Loop 01 route. No procedural game geometry."""
import json, math, pathlib
root=pathlib.Path('/Users/shane/Gaming/Games/nodekins-racing')
kit=json.loads((root/'assets/track_kit/catalog.json').read_text())['assets']
ids={name:str(i+1) for i,name in enumerate(kit)}
text=['[gd_scene format=3]']
for name,id in ids.items():text.append(f'[ext_resource type="PackedScene" path="res://assets/track_kit/{name}.glb" id="{id}"]')
text += ['[ext_resource type="Script" path="res://scripts/environment/track_art.gd" id="art"]','[node name="EnvironmentKit" type="Node3D"]','script = ExtResource("art")']
placements=[]
def place(name,asset,x,y,z,yaw=0,road=False,rails=False):
    text.extend([f'[node name="{name}" parent="." instance=ExtResource("{ids[asset]}")]',f'position = Vector3({x:.8f}, {y:.8f}, {z:.8f})',f'rotation_degrees = Vector3(0, {yaw}, 0)',f'metadata/kit_id = "{asset}"'])
    if road:text.append('metadata/road_piece = true')
    if rails:text.append('metadata/external_rails = true')
    placements.append({'name':name,'asset':asset,'position':[x,y,z],'yaw':yaw,'road':road})
def straight(index,x,z,yaw):
    place('Road%02d'%index,'track_straight_01',x,4,z,yaw,True,True)
    for side in [-1,1]:
        if index==4 and side==1:continue
        a=math.radians(yaw)
        place('Rail%02d%s'%(index,'L' if side<0 else 'R'),'track_barrier_01',x+math.cos(a)*side*7.2,4,z-math.sin(a)*side*7.2,yaw)
for i in range(5):straight(i,32,36-i*4,0)
place('LaunchRamp','track_ramp_01',32,4,16,0,True)
for i in range(12,18):straight(i,32,36-i*4,0)
place('NorthCurveA','track_curve_90_01',32,4,-36,0,True)
place('NorthCurveB','track_curve_90_01',0,4,-68,90,True)
for i in range(42,46):straight(i,-32,-36+(i-42)*4,180)
place('Tunnel','track_tunnel_01',-32,4,-20,180,True)
for i in range(49,60):straight(i,-32,-36+(i-42)*4,180)
for j in range(4):
    a=math.radians(j*45)
    place('SouthCurve%d'%j,'track_curve_45_01',-32*math.cos(a),4,36+32*math.sin(a),180+j*45,True)
place('StartFinish','track_arch_01',32,4,36)
place('Infield','environment_island_01',0,1,0)
for i,(x,z,yaw) in enumerate([(-10,-25,-20),(7,-31,65),(-6,2,130),(10,18,35),(-8,31,-30),(2,37,20)]):
    place('RockGarden%02d'%i,'prop_deco_01',x,1.015,z,yaw)
for i,(x,z,yaw) in enumerate([(10,-23,25),(-9,-13,-15),(4,-4,12),(-3,17,30),(9,30,-35)]):
    place('Crates%02d'%i,'prop_deco_02',x,1.01,z,yaw)
for i,(x,z,yaw) in enumerate([(-13,-24,180),(13,-16,0),(-12,20,180),(12,26,0),(0,-37,90),(0,39,-90)]):
    place('Banner%02d'%i,'prop_banner_01',x,1.0,z,yaw)
# Landing banners sit immediately outside the existing rail footprint.
for i,x in enumerate([24.8,39.2]):place('LandingBanner%d'%i,'prop_banner_01',x,5.1,-14,0)
(root/'scenes/track/Loop01Art.tscn').write_text('\n'.join(text)+'\n')
(root/'artifacts/phase_5c/placements.json').write_text(json.dumps(placements,indent=2))
