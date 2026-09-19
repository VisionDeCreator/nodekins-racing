"""Write data-only local registries. This script does not model or modify assets."""
from pathlib import Path
root=Path('/Users/shane/Gaming/Games/nodekins-racing')
def rgba(h):return 'Color('+', '.join(str(int(h[i:i+2],16)/255) for i in [0,2,4])+', 1)'
assets={'kart':'res://assets/karts/kart_01.glb','variants':'res://assets/customization/kart_variants.glb','male':'res://assets/characters/char_body_male.glb','female':'res://assets/characters/char_body_female.glb','clothes':'res://assets/characters/char_appearance_parts.glb','hair':'res://assets/customization/character_variants.glb'}
colors=[('Lagoon','36b4ce'),('Cherry','e43e45'),('Midnight','293752'),('Citrus','ebd34e'),('Sunset','e3a13e'),('Lime','71cc58'),('Violet','9455d5'),('Cloud','e8ebe2'),('Ocean','3672d4'),('Rose','e976ad')]
skins=[('Amber','b97851','warm_01'),('Warm','e4af82','warm_02'),('Porcelain','f2d1b5','light_01'),('Bronze','965c3d','brown_01'),('Umber','784b38','deep_01'),('Deep','493029','deep_02')]
def part(id,label,asset=None,mesh=None,material=None,tint=None,legacy=None,color=None):return dict(id=id,label=label,asset=asset,mesh=mesh,material=material,tint=tint,legacy=legacy,color=color)
def slot(field,label,entries,sockets=[],palette=False):return dict(field=field,label=label,entries=entries,sockets=sockets,palette=palette)
kart=[]
for field,label,base,labels,sockets in [('chassis_id','Chassis','chassis',['Classic','Sprint'],['socket_chassis']),('wheel_id','Wheels','wheel',['Faceted','Six-spoke'],['socket_wheel_fl','socket_wheel_fr','socket_wheel_rl','socket_wheel_rr']),('spoiler_id','Spoiler','spoiler',['Touring','Split fin'],['socket_spoiler']),('glider_id','Glider','glider',['Cloudwing','Arrowwing'],['socket_glider'])]:
 kart.append(slot(field,label,[part(i,title,'kart' if i==0 else 'variants','kart_'+base+'_%02d'%(i+1),'wing' if base=='glider' else 'paint','primary_color' if base=='chassis' else 'secondary_color') for i,title in enumerate(labels)],sockets))
for field,label in [('primary_color','Primary paint'),('secondary_color','Accent paint')]:kart.append(slot(field,label,[part(i,n,color=c) for i,(n,c) in enumerate(colors)],palette=True))
character=[slot('body_type_id','Body type',[part(0,'Male','male','char_body_male','skin','skin_tone_id','char_body_male'),part(1,'Female','female','char_body_female','skin','skin_tone_id','char_body_female')]),slot('hair_id','Hair',[part(i,n,'hair' if i==2 else 'clothes','char_hair_%02d'%(i+1),legacy='char_hair_%02d'%(i+1)) for i,n in enumerate(['Quiff','Bob','Mohawk'])]),slot('eye_id','Eyes',[part(i,n,'clothes','char_eyes_01','eye'+str(i),legacy='char_eyes_%02d'%(i+1),color=c) for i,(n,c) in enumerate([('Sapphire','1589b8'),('Emerald','46965a'),('Hazel','955c29')])])]
for field,base,label,names in [('shirt_id','shirt','Shirt',['Striped tee','Zip jacket']),('pants_id','pants','Pants',['Shorts','Trousers']),('shoe_id','shoes','Shoes',['Trainers','Boots'])]:character.append(slot(field,label,[part(i,n,'clothes','char_'+base+'_%02d'%(i+1),legacy='char_'+base+'_%02d'%(i+1)) for i,n in enumerate(names)]))
character.append(slot('skin_tone_id','Skin tone',[part(i,n,legacy=key,color=c) for i,(n,c,key) in enumerate(skins)],palette=True))
def write_registry(name,slots):
 lines=['[gd_resource type="Resource" script_class="PartsRegistry" format=3]','[ext_resource type="Script" path="res://scripts/customization/parts_registry.gd" id="registry"]','[ext_resource type="Script" path="res://scripts/customization/slot_definition.gd" id="slot"]','[ext_resource type="Script" path="res://scripts/customization/part_definition.gd" id="part"]']
 for key,path in assets.items():lines.append(f'[ext_resource type="PackedScene" path="{path}" id="{key}"]')
 for key,path in [('paint','res://assets/karts/kart_paint.gdshader'),('skin','res://assets/characters/skin_tint.gdshader'),('eye','res://assets/customization/eye_tint.gdshader')]:lines.append(f'[ext_resource type="Shader" path="{path}" id="shader_{key}"]')
 for mat in ['paint','wing','skin','eye0','eye1','eye2']:
  sh='paint' if mat=='wing' else ('eye' if mat.startswith('eye') else mat)
  lines+= [f'[sub_resource type="ShaderMaterial" id="mat_{mat}"]',f'shader = ExtResource("shader_{sh}")']
  if mat=='wing':lines+=['shader_parameter/neutralize_base = true']
  if mat.startswith('eye'):lines+=[f'shader_parameter/eye_color = {rgba(["1589b8","46965a","955c29"][int(mat[-1])])}']
 for s in slots:
  for p in s['entries']:
   key=s['field']+'_'+str(p['id']);lines+=[f'[sub_resource type="Resource" id="{key}"]','script = ExtResource("part")',f'id = {p["id"]}',f'display_name = "{p["label"]}"']
   for field,kind in [('asset','ExtResource'),('material','SubResource')]:
    if p[field]:lines.append(f'{field} = {kind}("'+('mat_' if field=='material' else '')+p[field]+'")')
   if p['mesh']:lines.append(f'mesh_name = &"{p["mesh"]}"')
   if p['tint']:lines.append(f'tint_source = &"{p["tint"]}"')
   if p['material']=='skin':lines.append('tint_uniform = &"skin_tone"')
   if p['legacy']:lines.append(f'legacy_key = &"{p["legacy"]}"')
   if p['color']:lines.append('color = '+rgba(p['color']))
  lines+=[f'[sub_resource type="Resource" id="slot_{s["field"]}"]','script = ExtResource("slot")',f'field = &"{s["field"]}"',f'display_name = "{s["label"]}"','is_palette = '+str(s['palette']).lower()]
  if s['sockets']:lines.append('sockets = PackedStringArray('+', '.join('"'+x+'"' for x in s['sockets'])+')')
  lines.append('entries = Array[ExtResource("part")](['+', '.join('SubResource("'+s['field']+'_'+str(p['id'])+'")' for p in s['entries'])+'])')
 lines+=['[resource]','script = ExtResource("registry")',f'display_name = "{name.title()}"','slots = Array[ExtResource("slot")](['+', '.join('SubResource("slot_'+s['field']+'")' for s in slots)+'])']
 (root/f'resources/customization/{name}_registry.tres').write_text('\n'.join(lines)+'\n')
write_registry('kart',kart);write_registry('character',character)
(root/'resources/customization/library.tres').write_text('''[gd_resource type="Resource" script_class="CustomizationLibrary" format=3]
[ext_resource type="Script" path="res://scripts/customization/customization_library.gd" id="1"]
[ext_resource type="Resource" path="res://resources/customization/kart_registry.tres" id="2"]
[ext_resource type="Resource" path="res://resources/customization/character_registry.tres" id="3"]
[resource]
script = ExtResource("1")
kart = ExtResource("2")
character = ExtResource("3")
''')
