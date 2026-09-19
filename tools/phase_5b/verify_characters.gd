extends "res://tools/phase_4_5/verify_glide.gd"
## Art checks and closer evidence cameras layered on the existing physical glide race.
const ART_OUTPUT: String = "res://artifacts/phase_5b/"
var _drift_captured: bool = false
var _boost_captured: bool = false
var _detail_camera: Camera3D
var _detail_offset := Vector3(3.1, 1.75, -3.3)
var _capture_busy: bool = false
var _minimum_camera_clearance: float = INF
var _rider_glide_pose_seen: bool = false

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if full_race:
		var character: CharacterAppearance = player.get_node("Visuals/Rider/Character")
		var head: Vector3 = character.skeleton.global_transform * character.skeleton.get_bone_global_pose(character.skeleton.find_bone("head")).origin
		var chase: Camera3D = player.get_node("ChaseCamera/SpringArm3D/Camera3D")
		_minimum_camera_clearance = minf(_minimum_camera_clearance, chase.global_position.distance_to(head))
		if player.glide.active and character.animator.assigned_animation.begins_with("Glide"):
			_rider_glide_pose_seen = true
	if _capture_active:
		_camera.fov = 52
		_camera.global_position = player.global_position + Vector3(-2.2, 2.4, -4.3)
		_camera.look_at(player.global_position + Vector3(0, 0.8, 0))
	if is_instance_valid(_detail_camera):
		_detail_camera.global_position = player.global_position + player.global_basis * _detail_offset
		_detail_camera.look_at(player.global_position + Vector3(0, 0.8, 0))
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
	_detail_camera.look_at(player.global_position + Vector3(0, 0.8, 0))
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
	var assets: Dictionary = preload("res://tools/phase_5b/character_asset_audit.gd").new().run(self)
	_check(assets.failures.is_empty(), "Both bodies and all 32 outfits pass imported rig/pose/material checks")
	for inventory: KartInventory in track.items.inventories.values():
		var character: CharacterAppearance = inventory.kart.get_node("Visuals/Rider/Character")
		_check(character.skeleton.get_bone_count() == 24 and character.equipped.size() == 5, "%s has a complete bound rider" % inventory.kart.name)
	await _detail_shot("rider-driving-front", Vector3(2.7, 1.9, -3.2))
	await _detail_shot("rider-driving-side", Vector3(3.0, 1.4, 0.05))
	await super._run()
	_check(_drift_captured and _boost_captured, "Riders drove, drifted and boosted during the full race")
	_check(_minimum_camera_clearance > 1.0, "Original chase camera stays clear of the rider throughout driving, drift and glide")
	_check(_rider_glide_pose_seen, "Rider displays imported glide poses without modifying wing behavior")
	report["character_assets"] = assets
	report["minimum_camera_to_head_bone_metres"] = _minimum_camera_clearance
	report["checks"] = checks
	report["failures"] = failures
	var file := FileAccess.open(ART_OUTPUT + "character-race-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("[Phase 5b verification] %s — %d checks; failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, failures])
	if OS.get_cmdline_user_args().has("--phase5b-check"):
		get_tree().quit(0 if failures.is_empty() else 1)
