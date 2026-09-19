extends RefCounted
## Tests the imported contract that Phase 6.5 will rely on: interchangeable named skins.
var checks: int = 0
var failures: Array[String] = []
var min_triangles: int = 100000
var max_triangles: int = 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		print("[Character asset failure] " + description)

func run(parent: Node) -> Dictionary:
	var rest_signature: Array[Dictionary] = []
	var probe := preload("res://scenes/characters/Character.tscn").instantiate() as CharacterAppearance
	parent.add_child(probe)
	for body_id: StringName in [&"char_body_male", &"char_body_female"]:
		for combo in range(16):
			var profile := CharacterLook.new()
			profile.body_id = body_id
			profile.hair_id = StringName("char_hair_0%d" % (1 + (combo & 1)))
			profile.shirt_id = StringName("char_shirt_0%d" % (1 + ((combo >> 1) & 1)))
			profile.pants_id = StringName("char_pants_0%d" % (1 + ((combo >> 2) & 1)))
			profile.shoes_id = StringName("char_shoes_0%d" % (1 + ((combo >> 3) & 1)))
			probe.set_look(profile)
			var rig: Skeleton3D = probe.skeleton
			if rest_signature.is_empty():
				for index in range(rig.get_bone_count()):
					rest_signature.append({"name": rig.get_bone_name(index), "parent": rig.get_bone_parent(index), "rest": rig.get_bone_rest(index)})
			var matching_rig: bool = rest_signature.size() == rig.get_bone_count()
			var sockets: int = 0
			for index in range(rig.get_bone_count()):
				matching_rig = matching_rig and rest_signature[index].name == rig.get_bone_name(index) and rest_signature[index].parent == rig.get_bone_parent(index) and rest_signature[index].rest.is_equal_approx(rig.get_bone_rest(index))
				if String(rig.get_bone_name(index)).begins_with("socket_"):
					sockets += 1
			check(matching_rig and sockets == 6, "%s/%d: identical joints and six sockets" % [body_id, combo])
			var meshes: Array[MeshInstance3D] = [probe.body]
			for part: MeshInstance3D in probe.equipped.values():
				meshes.append(part)
			var bindings_valid: bool = true
			var triangles: int = 0
			for mesh: MeshInstance3D in meshes:
				triangles += int(mesh.mesh.get_faces().size() / 3.0)
				bindings_valid = bindings_valid and mesh.transform.is_equal_approx(Transform3D.IDENTITY)
				for bind in range(mesh.skin.get_bind_count()):
					var index: int = rig.find_bone(mesh.skin.get_bind_name(bind))
					bindings_valid = bindings_valid and index >= 0
					if index >= 0:
						bindings_valid = bindings_valid and mesh.skin.get_bind_pose(bind).is_equal_approx(rig.get_bone_global_rest(index).affine_inverse())
			check(bindings_valid and probe.equipped.size() == 5, "%s/%d: all parts bind to the same named skeleton" % [body_id, combo])
			check(triangles >= 1500 and triangles <= 3000, "%s/%d: dressed triangle budget" % [body_id, combo])
			min_triangles = mini(min_triangles, triangles)
			max_triangles = maxi(max_triangles, triangles)
			for clip: StringName in [&"Idle", &"Drive", &"SteerLeft", &"SteerRight", &"Hit", &"Victory", &"GlideLeft", &"GlideRight"]:
				check(probe.animator.has_animation(clip), "%s: animation %s" % [body_id, clip])
			probe.sample_pose(&"Drive")
			var hand: Vector3 = rig.get_bone_global_pose(rig.find_bone("hand.L")).origin
			var foot: Vector3 = rig.get_bone_global_pose(rig.find_bone("foot.L")).origin
			check(hand.distance_to(Vector3(-0.145, 0.714, -0.105)) < 0.001 and absf(foot.y - 0.528) < 0.001, "%s/%d: seated pose survives GLB animation import" % [body_id, combo])
			check(probe.body.material_override is ShaderMaterial, "%s/%d: skin uses independent shader tint" % [body_id, combo])
	parent.remove_child(probe)
	probe.queue_free()
	var result: Dictionary = {"checks": checks, "failures": failures, "outfits_checked": 32, "bones": rest_signature.size(), "triangle_range": [min_triangles, max_triangles]}
	var file := FileAccess.open("res://artifacts/phase_5b/character-assets-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("[Character assets] " + JSON.stringify(result))
	return result
