extends "res://tools/phase_4_5/verify_glide.gd"
const ART_OUTPUT: String = "res://artifacts/phase_5c/"
var seam_max: float = 0.0
var seam_count: int = 0

func _static_shot(filename: String, eye: Vector3, target: Vector3, ortho: bool = false) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = eye
	camera.far = 700
	if ortho:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 94
		camera.look_at(target, Vector3.RIGHT)
	else:
		camera.fov = 58
		camera.look_at(target)
	camera.make_current()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(ART_OUTPUT + filename + ".png")) == OK, "Captured " + filename)
	camera.queue_free()

func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(ART_OUTPUT + filename + ".png")) == OK, "Captured " + filename)
	if filename == "after-landing":
		_capture_active = false
		player.get_node("ChaseCamera/SpringArm3D/Camera3D").make_current()
		$Track/DrivingHUD.show()
		$Track/RaceHUD.show()
		track.get_node("ItemHUD").show()
		_camera.queue_free()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ART_OUTPUT))
	var raw_snapshot: Dictionary = preload("res://tools/phase_5c/track_snapshot.gd").capture(track)
	# Normalize JSON numeric types before comparing to the on-disk baseline.
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(raw_snapshot))
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/phase_5c/physics_baseline.json"))
	_check(snapshot == baseline, "All 252 collision shapes, 21 areas, route points and checkpoint indices match the pre-art baseline")
	var physics_file := FileAccess.open(ART_OUTPUT + "physics-after.json", FileAccess.WRITE)
	physics_file.store_string(JSON.stringify(snapshot, "\t"))
	var art: Node3D = track.get_node("EnvironmentKit")
	_check(art.find_children("*", "CollisionObject3D", true, false).is_empty(), "Imported art creates no additional collision bodies or triggers")
	_check(not track.get_node("GrayboxRoadAndWalls").visible, "Gray-box visuals are hidden while their collision shapes remain active")
	var pieces: Array[Node3D] = []
	for child: Node3D in art.get_children():
		if child.get_meta("road_piece", false):
			pieces.append(child)
	for index in range(pieces.size()):
		var piece: Node3D = pieces[index]
		var next: Node3D = pieces[(index + 1) % pieces.size()]
		var exit_socket: Node3D = piece.find_child("socket_out", true, false)
		var entry_socket: Node3D = next.find_child("socket_in", true, false)
		if piece.name == "LaunchRamp":
			var gap: Vector3 = entry_socket.global_position - exit_socket.global_position
			_check(absf(Vector2(gap.x, gap.z).length() - 16.0) < 0.0001 and absf(gap.y + 1.4) < 0.0001, "Authored launch lip and landing preserve the exact 16 m / 1.4 m gap")
			continue
		seam_max = maxf(seam_max, exit_socket.global_position.distance_to(entry_socket.global_position))
		seam_count += 1
	_check(pieces.size() == 34 and seam_count == 33 and seam_max < 0.0001, "Every ordinary kit connection closes within 0.1 mm, including the loop seam")
	var edge_vertices_match: bool = true
	for piece: Node3D in pieces:
		var surface: MeshInstance3D = piece.find_child("Surface", true, false)
		for socket_name: String in ["socket_in", "socket_out"]:
			var socket: Node3D = piece.find_child(socket_name, true, false)
			for side: float in [-1.0, 1.0]:
				var expected_corner: Vector3 = socket.global_position + socket.global_basis.x * side * 7.0
				var found_corner: bool = false
				for vertex: Vector3 in surface.mesh.get_faces():
					if (surface.global_transform * vertex).distance_to(expected_corner) < 0.0001:
						found_corner = true
						break
				edge_vertices_match = edge_vertices_match and found_corner
	_check(edge_vertices_match, "Imported road surface corners meet the socket edges at the full 14 m width")
	var ramp: Node3D = art.get_node("LaunchRamp")
	_check(ramp.find_child("socket_in", true, false).global_position.distance_to(Vector3(32,4,16)) < 0.0001 and ramp.find_child("socket_out", true, false).global_position.distance_to(Vector3(32,5.4,4)) < 0.0001, "Blender ramp matches the existing launch geometry without scaling")
	var meshes: Array[Mesh] = []
	for box: ItemBox in track.items.boxes:
		meshes.append(box.visual.find_child("Crystal", true, false).mesh)
	_check(meshes.size() == 12 and meshes.all(func(mesh: Mesh) -> bool: return mesh == meshes[0]), "All twelve rotating item boxes instance one imported mesh")
	# Pausing only for overview evidence keeps countdown and race timing deterministic.
	get_tree().paused = true
	$Track/DrivingHUD.hide()
	$Track/RaceHUD.hide()
	track.get_node("ItemHUD").hide()
	await _static_shot("track-overhead", Vector3(0,180,0), Vector3(0,4,0), true)
	await _static_shot("connection-seam", Vector3(43,9,-37), Vector3(32,4,-36))
	await _static_shot("glide-ramp-gap", Vector3(58,30,15), Vector3(32,4,1))
	await _static_shot("item-box-on-track", Vector3(28,6.4,-22.0), Vector3(32,5.1,-28))
	await _static_shot("tunnel-and-props", Vector3(-13,18,-30), Vector3(-31,5,-12))
	player.get_node("ChaseCamera/SpringArm3D/Camera3D").make_current()
	$Track/DrivingHUD.show()
	$Track/RaceHUD.show()
	track.get_node("ItemHUD").show()
	get_tree().paused = false
	await super._run()
	var expected: Dictionary = {"cpu_2":45.3166666666654, "player":47.9666666666652, "cpu_3":48.5333333333319, "cpu_1":54.6833333333315}
	_check(report.race_recoveries.is_empty(), "The art-covered track needs no full-race recovery")
	for racer: Dictionary in report.results:
		_check(absf(racer.finish_time - float(expected[racer.id])) < 0.018, "%s finish time matches the pre-art race within one physics tick" % racer.id)
	report["checks"] = checks
	report["failures"] = failures
	report["art"] = {"road_modules":pieces.size(), "seams":seam_count, "maximum_seam_error_metres":seam_max, "physics_matches_baseline":snapshot==baseline, "boost_pads_disabled_for_baseline":true}
	var file := FileAccess.open(ART_OUTPUT + "track-art-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("[Phase 5c verification] %s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,failures])
	if OS.get_cmdline_user_args().has("--phase5c-check"):
		get_tree().quit(0 if failures.is_empty() else 1)
