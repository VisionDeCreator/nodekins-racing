extends "res://tools/phase_4_5/verify_glide.gd"
const ART_OUTPUT: String = "res://artifacts/phase_5c/"
var pad_events: Array[Dictionary] = []

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

func _ready() -> void:
	super._ready()
	track.items.item_event.connect(_pad_event)

func _pad_event(event: Dictionary) -> void:
	if event.kind == "pad_activate":
		var entry: Dictionary = event.duplicate()
		entry["full_race"] = full_race
		pad_events.append(entry)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ART_OUTPUT))
	_check(track.get_node("BoostPads").get_child_count() == 3, "Three shared-effect boost pads cover the west straight")
	var geometry: Dictionary = JSON.parse_string(JSON.stringify(preload("res://tools/phase_5c/track_snapshot.gd").capture(track)))
	_check(geometry.collisions.size() == 255 and geometry.areas.size() == 24, "Pads add exactly three trigger shapes and three areas")
	for category: String in ["collisions", "areas"]:
		for path: String in geometry[category].keys():
			if path.begins_with("BoostPads/"):
				geometry[category].erase(path)
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/phase_5c/physics_baseline.json"))
	_check(geometry == baseline, "Pads preserve every original collision, trigger, route point and checkpoint")
	get_tree().paused = true
	$Track/DrivingHUD.hide()
	$Track/RaceHUD.hide()
	track.get_node("ItemHUD").hide()
	await _static_shot("track-overhead-with-pads", Vector3(0,180,0), Vector3(0,4,0), true)
	await _static_shot("boost-pads-on-track", Vector3(-19,12,-43), Vector3(-32,4,-27))
	await _static_shot("connection-seam", Vector3(43,9,-37), Vector3(32,4,-36))
	await _static_shot("tunnel-and-props", Vector3(-13,18,-30), Vector3(-31,5,-12))
	player.get_node("ChaseCamera/SpringArm3D/Camera3D").make_current()
	$Track/DrivingHUD.show()
	$Track/RaceHUD.show()
	track.get_node("ItemHUD").show()
	get_tree().paused = false
	await super._run()
	for id: String in ["player", "cpu_1", "cpu_2", "cpu_3"]:
		_check(pad_events.any(func(event: Dictionary) -> bool: return event.full_race and event.racer == id), "%s receives a pad boost during the physical three-lap race" % id)
	_check(report.race_recoveries.is_empty(), "Boost pads cause no race recovery")
	await _isolated_pads()
	report["pad_events"] = pad_events
	report["checks"] = checks
	report["failures"] = failures
	var file := FileAccess.open(ART_OUTPUT + "boost-pad-race-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("[Phase 5c pad verification] %s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,failures])
	if OS.get_cmdline_user_args().has("--phase5c-pads-check"):
		get_tree().quit(0 if failures.is_empty() else 1)

func _isolated_pads() -> void:
	# A temporary pad on the original first straight tests locks without spoofing checkpoints.
	var fixture := preload("res://scenes/track/BoostPad.tscn").instantiate() as TrackBoostPad
	fixture.name = "QAFirstStraightPad"
	track.add_child(fixture)
	fixture.global_transform = RaceManager.route.sample(4.0)
	var centered: Transform3D = RaceManager.route.sample(7.0)
	centered.origin.y += 0.12
	RaceManager.start_race()
	player.respawn_at(centered)
	player.controls.set_command(0,0,0,false)
	var before: int = pad_events.size()
	await _frames(12)
	_check(player.controls.is_locked() and not player.drift.is_boosting() and pad_events.size() == before, "A grounded kart on a pad gets no boost during countdown")
	await _wait_until(func() -> bool: return RaceManager.phase == RaceManager.Phase.RACING, 4.0)
	var inventory: KartInventory = track.items.inventories[&"player"]
	var held_item: ItemDefinition = preload("res://resources/items/shell.tres")
	inventory.receive(held_item)
	await _frames(8)
	_check(pad_events.size() == before + 1 and is_equal_approx(player.drift.boost_multiplier, 1.5), "GO enables exactly one 1.5x pad boost for the waiting kart")
	_check(inventory.held == held_item, "Pad effect leaves the held item unchanged")
	await _frames(150)
	_check(pad_events.size() == before + 1 and not player.drift.is_boosting(), "Parking on a pad does not refresh its two-second boost forever")
	var outside: Transform3D = RaceManager.route.sample(14.0)
	outside.origin.y += 0.12
	player.respawn_at(outside)
	await _frames(5)
	var approach: Transform3D = RaceManager.route.sample(2.0)
	approach.origin.y += 0.12
	player.respawn_at(approach)
	player.controls.set_command(1,0,0,false)
	_check(await _wait_until(func() -> bool: return pad_events.size() > before + 1, 2.0), "Leaving and driving back across the pad activates it again")
	await _frames(24)
	_check(player.speed > 25.0 and player.drift.is_boosting(), "Pad accelerates through the existing kart boost pipeline")
	player.controls.set_command(0,0,0,false)
	player.respawn_at(outside)
	await _frames(5)
	player.respawn_at(centered)
	player.drift.activate_boost(1.6,1.5)
	await _frames(8)
	_check(is_equal_approx(player.drift.boost_multiplier,1.6) and player.drift.boost_remaining > 1.8, "An existing stronger turbo stays at 1.6x; pads extend duration without multiplying speed")
	fixture.queue_free()
	RaceManager.start_race()
	await _frames(2)
	_check(not player.drift.is_boosting() and player.controls.is_locked(), "Restart clears pad boosts and restores the locked countdown")
