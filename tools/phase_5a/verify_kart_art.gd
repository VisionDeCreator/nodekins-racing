extends "res://tools/phase_4_5/verify_glide.gd"
## Art checks and closer evidence cameras layered on the existing physical glide race.
const ART_OUTPUT: String = "res://artifacts/phase_5a/"
var _drift_captured: bool = false
var _boost_captured: bool = false
var _detail_camera: Camera3D
var _detail_offset := Vector3(3.1, 1.75, -3.3)
var _capture_busy: bool = false

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _capture_active:
		_camera.fov = 52
		_camera.global_position = player.global_position + Vector3(-2.2, 2.4, -4.3)
		_camera.look_at(player.global_position + Vector3(0, 0.8, 0))
	if is_instance_valid(_detail_camera):
		_detail_camera.global_position = player.global_position + player.global_basis * _detail_offset
		_detail_camera.look_at(player.global_position + Vector3(0, 0.48, 0))
	if not full_race or _capture_active or _capture_busy:
		return
	if not _drift_captured and player.drift.drifting and player.drift.tier >= 1:
		_drift_captured = true
		_detail_shot.call_deferred("mid-drift", Vector3(3.0, 1.8, -3.2))
	elif _drift_captured and not _boost_captured and player.drift.is_boosting():
		_boost_captured = true
		_detail_shot.call_deferred("mid-boost", Vector3(3.0, 1.65, 3.2))

func _hud(visible_now: bool) -> void:
	$Track/DrivingHUD.visible = visible_now
	$Track/RaceHUD.visible = visible_now
	track.get_node("ItemHUD").visible = visible_now
	for label: Label3D in track.find_children("*", "Label3D", true, false):
		label.visible = visible_now

func _launch(id: StringName) -> void:
	super._launch(id)
	if _capture_active:
		_hud(false)

func _detail_shot(filename: String, offset: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_capture_busy = true
	_detail_offset = offset
	_detail_camera = Camera3D.new()
	_detail_camera.fov = 48
	add_child(_detail_camera)
	_detail_camera.global_position = player.global_position + player.global_basis * offset
	_detail_camera.look_at(player.global_position + Vector3(0, 0.48, 0))
	_detail_camera.make_current()
	_hud(false)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(ART_OUTPUT + filename + ".png")) == OK, "Captured new art: " + filename)
	player.get_node("ChaseCamera/SpringArm3D/Camera3D").make_current()
	_hud(true)
	_detail_camera.queue_free()
	_detail_camera = null
	_capture_busy = false

func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(ART_OUTPUT + filename + ".png")) == OK, "Captured new art: " + filename)
	if filename == "after-landing":
		_capture_active = false
		player.get_node("ChaseCamera/SpringArm3D/Camera3D").make_current()
		_hud(true)
		_camera.queue_free()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ART_OUTPUT))
	await _frames(15)
	var visuals: Node3D = player.get_node("Visuals")
	var body: MeshInstance3D = visuals.body
	var wheel_meshes: Array[Mesh] = []
	for socket_name: String in ["fl", "fr", "rl", "rr"]:
		var socket: Node = visuals.assembly.get_node("socket_wheel_" + socket_name)
		_check(socket.get_child_count() == 1 and socket.get_child(0) is MeshInstance3D, "Wheel socket %s contains only a modular mesh" % socket_name)
		wheel_meshes.append(socket.get_child(0).mesh)
	_check(wheel_meshes.all(func(mesh: Mesh) -> bool: return mesh == wheel_meshes[0]), "All four wheels share one imported mesh")
	_check(wheel_meshes[0].surface_get_material(0).vertex_color_use_as_albedo and visuals.glider_socket.get_child(0).mesh.surface_get_material(0).vertex_color_use_as_albedo, "Wheel and glider materials display authored vertex colors")
	_check(int(body.mesh.get_faces().size() / 3.0) == 980 and int(wheel_meshes[0].get_faces().size() / 3.0) == 96, "Chassis and wheel triangle budgets survive import")
	_check(body.mesh.get_surface_count() == 1 and body.material_override is ShaderMaterial, "One chassis material supports shader tint")
	var colors: PackedColorArray = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var paint_vertices: int = 0
	var trim_vertices: int = 0
	var grayscale: bool = true
	for color: Color in colors:
		paint_vertices += int(color.a > 0.99)
		trim_vertices += int(color.a < 0.01)
		grayscale = grayscale and absf(color.r - color.g) < 0.002 and absf(color.r - color.b) < 0.002
	_check(grayscale and paint_vertices > 0 and trim_vertices > 0, "Neutral grayscale and paint/trim masks survive GLB import")
	_check(body.mesh.get_aabb().position.is_equal_approx(Vector3(-0.58, 0.17, -0.93)), "Ground origin and -Z front import at metre scale")
	_check(player.get_node("CollisionShape3D").shape.size.is_equal_approx(Vector3(1.2, 0.7, 1.9)) and player.find_children("*", "CollisionShape3D", true, false).size() == 1 and player.find_children("*", "PhysicsBody3D", true, false).is_empty(), "Original collider stays unchanged; art adds no physics bodies")
	_check(visuals.glider_socket.get_parent() == player.glide.canopy and visuals.glider_socket.position.is_equal_approx(Vector3(0, 0.78, 0.4)), "Imported glider uses the existing canopy parent and authored rear-top mount")
	_check(not visuals.glider_socket.is_visible_in_tree(), "Driving pose hides the deployed glider")
	_check(visuals.glider_socket.get_child_count() == 1 and int(visuals.glider_socket.get_child(0).mesh.get_faces().size() / 3.0) == 244 and int(visuals.spoiler.mesh.get_faces().size() / 3.0) == 156, "Glider and spoiler remain separate meshes within budget")
	var default_color: Color = visuals.paint_color
	visuals.set_livery(Color("a864de"))
	_check(visuals.body.material_override.get_shader_parameter("paint_color") == Color("a864de") and track.cpu_drivers[0].kart.get_node("Visuals").paint_color != Color("a864de"), "Paint tint is per kart and needs no texture rebake")
	visuals.set_livery(default_color)
	await _detail_shot("track-front", Vector3(3.1, 1.75, -3.3))
	await _detail_shot("track-rear", Vector3(-3.0, 1.9, 3.2))
	await super._run()
	_check(_drift_captured and _boost_captured, "New model drove, drifted, and boosted during the full race")
	report["checks"] = checks
	report["failures"] = failures
	report["art"] = {"chassis_triangles": 980, "wheel_triangles_each": 96, "spoiler_triangles": 156, "glider_triangles": 244, "shared_wheel_mesh": true, "collider_unchanged": true, "paint_vertices": paint_vertices, "trim_vertices": trim_vertices}
	var file := FileAccess.open(ART_OUTPUT + "kart-art-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("[Phase 5a verification] %s — %d checks; failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, failures])
	if OS.get_cmdline_user_args().has("--phase5a-check"):
		get_tree().quit(0 if failures.is_empty() else 1)
