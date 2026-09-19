extends RefCounted
const LIBRARY: CustomizationLibrary = preload("res://resources/customization/library.tres")
var checks: int = 0
var failures: Array[String] = []
func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
		print("[Customization audit FAIL] " + detail)

func run(parent: Node) -> Dictionary:
	var profile := CustomizationProfile.new()
	check(profile.to_wire().size() == 13 and CustomizationProfile.from_values(profile.to_wire()).to_values() == profile.to_values(),"13-byte wire round-trip")
	for bad: Variant in [[],[1,2],{},"path",null]:
		check(CustomizationProfile.from_values(bad) == null,"Reject malformed payload")
	for bad: Variant in [-1,256,1.5,"1",true,INF,NAN]:
		var values: Array = []
		values.assign(profile.to_values())
		values[0] = bad
		check(CustomizationProfile.from_values(values) == null,"Reject invalid ID type or range")
	var slots_seen: Array[StringName] = []
	for registry: PartsRegistry in [LIBRARY.kart,LIBRARY.character]:
		for slot: CustomizationSlot in registry.slots:
			check(not slots_seen.has(slot.field),"Unique slot " + str(slot.field))
			slots_seen.append(slot.field)
			check(slot.entries.size() >= 2,"Every slot has choices: " + str(slot.field))
			var ids: Array[int] = []
			for part: CustomizationPart in slot.entries:
				check(part.id >= 0 and part.id <= 255 and not ids.has(part.id),"Unique byte ID in " + str(slot.field))
				ids.append(part.id)
	check(slots_seen.size() == 13,"Registry covers all thirteen fields")
	profile.chassis_id = 255
	check(not LIBRARY.accepts(profile),"Unknown IDs rejected before assembly")
	profile.chassis_id = 0
	var store := CustomizationProfileStore.new()
	store.path = "res://artifacts/phase_6_5/store-audit.json"
	for suffix: String in ["",".bak",".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path + suffix))
	check(store.load_profile(LIBRARY).to_values() == profile.to_values(),"Missing file uses defaults")
	check(store.save_profile(profile,LIBRARY),"First save")
	profile.hair_id = 2
	profile.primary_color = 1
	check(store.save_profile(profile,LIBRARY) and store.load_profile(LIBRARY).to_values() == profile.to_values(),"Atomic update saves IDs")
	var serialized: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(store.path))
	check(serialized.size() == 2 and serialized["values"].size() == 13,"Disk envelope contains version and integer array only")
	_write(store.path,"{corrupt")
	check(store.load_profile(LIBRARY).hair_id == 0 and store.status.begins_with("Recovered"),"Corrupt file recovers previous valid backup")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path + ".bak"))
	var unknown: Array[int] = profile.to_values()
	unknown[0] = 255
	_write(store.path,JSON.stringify({"version":1,"values":unknown}))
	check(store.load_profile(LIBRARY).primary_color == 0,"Unknown registry ID falls back safely")
	_write(store.path,JSON.stringify({"version":999,"values":profile.to_values()}))
	check(store.load_profile(LIBRARY).primary_color == 0,"Unsupported schema version falls back")
	_write(store.path,"blocking file")
	store.path += "/cannot-save.json"
	check(not store.save_profile(profile,LIBRARY),"Write failure returns failure without replacing active profile")

	var probe := preload("res://scenes/characters/Character.tscn").instantiate() as CharacterAppearance
	parent.add_child(probe)
	var baseline: Array[Transform3D] = []
	for index in range(probe.skeleton.get_bone_count()):
		baseline.append(probe.skeleton.get_bone_global_rest(index))
	for body_id in range(2):
		profile.body_type_id = body_id
		for slot: CustomizationSlot in LIBRARY.character.slots:
			for part: CustomizationPart in slot.entries:
				var look := profile.duplicate() as CustomizationProfile
				look.set(slot.field,part.id)
				probe.set_profile(look)
				probe.sample_pose(&"Drive")
				var valid: bool = probe.equipped.size() == 5 and probe.skeleton.get_bone_count() == baseline.size()
				for mesh: MeshInstance3D in probe.equipped.values():
					valid = valid and mesh.transform.is_equal_approx(Transform3D.IDENTITY)
					for bind in range(mesh.skin.get_bind_count()):
						var index: int = probe.skeleton.find_bone(mesh.skin.get_bind_name(bind))
						valid = valid and index >= 0
						if index >= 0:
							valid = valid and mesh.skin.get_bind_pose(bind).is_equal_approx(baseline[index].affine_inverse())
				check(valid,"Named rest bindings body %d %s:%d" % [body_id,slot.field,part.id])
	var saved_material: ShaderMaterial = probe.body.material_override as ShaderMaterial
	var saved_tone: Color = saved_material.get_shader_parameter("skin_tone")
	profile.skin_tone_id = 0
	probe.set_profile(profile)
	check(saved_material != probe.body.material_override and saved_material.get_shader_parameter("skin_tone") == saved_tone,"Skin materials isolated per assembled look")
	parent.remove_child(probe)
	probe.queue_free()
	var kart: Node3D = preload("res://assets/karts/kart_01.glb").instantiate()
	parent.add_child(kart)
	var assembly: Node3D = kart.get_node("kart_01")
	var socket_transforms: Dictionary = {}
	for child: Node3D in assembly.get_children():
		socket_transforms[child.name] = child.transform
	for slot: CustomizationSlot in LIBRARY.kart.slots:
		for part: CustomizationPart in slot.entries:
			profile.set(slot.field,part.id)
			var fitted: Dictionary = KartPartsAssembler.apply(assembly,profile)
			check(fitted[&"wheel_id"].size() == 4 and fitted[&"wheel_id"][0].mesh == fitted[&"wheel_id"][3].mesh,"Wheel geometry shared across sockets")
			for child: Node3D in assembly.get_children():
				check(child.transform == socket_transforms[child.name] and child.get_child_count() == 1,"Socket preserved with one mesh: " + child.name)
			var material: ShaderMaterial = fitted[&"chassis_id"][0].material_override
			check(material.get_shader_parameter("paint_color") == LIBRARY.tint(profile,&"primary_color"),"Registry primary paint reaches chassis")
	parent.remove_child(kart)
	kart.queue_free()
	return {"checks":checks,"failures":failures}

func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(content)
	file.close()
