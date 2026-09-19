extends Node
## QA driver only. The full three-lap run uses normalized input and real Area3D crossings.
## Teleports and direct gate events are isolated to the explicitly labeled fault/unit cases.

@onready var track: Node3D = $Track
@onready var kart: ArcadeKart = $Track/Player
var _pilot: bool = false
var _record_race: bool = true
var _gate_count: int = 0
var _wrong_way_events: int = 0
var _failures: PackedStringArray = []
var _snapshots: Array[Dictionary] = []
var _checks: int = 0
var _report: Dictionary = {}
var _route: TrackRoute
var _initial_pose: Transform3D
const OUTPUT: String = "res://artifacts/phase_2/"

func _ready() -> void:
	process_physics_priority = -50
	_route = RaceManager.route
	_initial_pose = kart.global_transform
	RaceManager.checkpoint_passed.connect(_checkpoint)
	RaceManager.route_violation.connect(_violation)
	_run.call_deferred()

func _physics_process(_delta: float) -> void:
	if not _pilot:
		return
	var state: Dictionary = RaceManager.get_racer_state(&"player")
	if state.is_empty() or state.finished:
		return
	var target: Vector3 = _route.sample(float(state.lap_distance) + 9.0).origin
	var to_target: Vector3 = target - kart.global_position
	to_target.y = 0.0
	var forward: Vector3 = -kart.global_basis.z
	var error: float = forward.signed_angle_to(to_target.normalized(), Vector3.UP)
	var yaw_rate: float = 2.0 * maxf(kart.speed, 4.0) * sin(error) / maxf(to_target.length(), 1.0)
	var steering: float = -yaw_rate / deg_to_rad(maxf(kart.turn_rate_degrees, 30.0))
	kart.controls.set_command(1.0, 0.0, clampf(steering, -1.0, 1.0), false)

func _checkpoint(racer_id: StringName, checkpoint: int) -> void:
	if not _record_race or racer_id != &"player":
		return
	_gate_count += 1
	var state: Dictionary = RaceManager.get_racer_state(racer_id)
	if (int(state.completed_laps) == 0 and checkpoint == 4) or (int(state.completed_laps) == 1 and checkpoint == 3) or state.finished:
		_snapshots.append(state)
		print("[Phase 2 race snapshot] " + JSON.stringify(state))

func _violation(_racer_id: StringName, reason: String) -> void:
	if reason.begins_with("WRONG WAY"):
		_wrong_way_events += 1
	print("[Phase 2 route notice] " + reason)

func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame
	await get_tree().process_frame

func _wait_until(condition: Callable, seconds: float) -> bool:
	for _index in range(ceili(seconds * Engine.physics_ticks_per_second)):
		if condition.call():
			return true
		await get_tree().physics_frame
	return bool(condition.call())

func _check(condition: bool, description: String) -> void:
	_checks += 1
	print("[Phase 2 check] %s: %s" % ["PASS" if condition else "FAIL", description])
	if not condition:
		_failures.append(description)

func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + filename)) == OK, "Captured " + filename)

func _state() -> Dictionary:
	return RaceManager.get_racer_state(&"player")

func _wait_recovery(previous_count: int) -> bool:
	return await _wait_until(func() -> bool: return int(_state().recovery_count) > previous_count, 4.0)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	kart.controls.set_command(1.0, 0.0, 1.0, true)
	await _frames(15)
	var source_camera: Camera3D = get_viewport().get_camera_3d()
	$Track/DrivingHUD.hide()
	$Track/RaceHUD.hide()
	$Track/OverviewCamera.make_current()
	await _capture("track-layout.png")
	source_camera.make_current()
	$Track/DrivingHUD.show()
	$Track/RaceHUD.show()
	await _capture("countdown.png")
	_check(RaceManager.phase == RaceManager.Phase.COUNTDOWN and kart.controls.is_locked(), "Countdown locks the shared input boundary")
	_check(kart.speed < 0.01 and Vector2(kart.position.x - _initial_pose.origin.x, kart.position.z - _initial_pose.origin.z).length() < 0.01, "Held throttle/steer/drift cannot move the grid kart")
	_check(RaceManager.elapsed == 0.0 and int(_state().completed_laps) == 0, "Race timer and laps stay stopped during countdown")
	_pilot = true
	_check(await _wait_until(func() -> bool: return RaceManager.phase == RaceManager.Phase.RACING, 4.0), "Countdown transitions to GO")
	_check(not kart.controls.is_locked(), "GO unlocks input")
	_check(await _wait_until(func() -> bool: return RaceManager.phase == RaceManager.Phase.FINISHED, 100.0), "Real trigger crossings finish a full three-lap race")
	_pilot = false
	var result: Dictionary = _state()
	_report["full_race"] = result
	_report["race_snapshots"] = _snapshots
	_report["accepted_gate_count"] = _gate_count
	_check(int(result.completed_laps) == 3 and result.finished and _gate_count == 24, "Exactly 24 ordered crossings produce three laps")
	_check(int(result.invalid_crossings) == 0 and int(result.recovery_count) == 0, "Full race completes without skipped gates or recoveries")
	_check(int(result.position) == 1 and int(result.last_checkpoint) == 0 and result.lap_times.size() == 3, "Finish data has position, checkpoint, and three lap times")
	await _capture("race-finished.png")
	var finish_elapsed: float = RaceManager.elapsed
	kart.controls.set_command(1.0, 0.0, 1.0, true)
	await _frames(60)
	_check(kart.speed < 0.01 and RaceManager.elapsed == finish_elapsed, "Finish locks input and freezes the completed race timer")
	_record_race = false
	# Fault injection: physically cross CP2 while CP1 is still required.
	RaceManager.start_race()
	kart.controls.set_command(0.0, 0.0, 0.0, false)
	await _wait_until(func() -> bool: return RaceManager.phase == RaceManager.Phase.RACING, 4.0)
	var setup: Transform3D = _route.sample(_route.checkpoint_distance(2) - 5.0)
	setup.origin.y += 0.12
	kart.respawn_at(setup)
	kart.controls.set_command(1.0, 0.0, 0.0, false)
	_check(await _wait_until(func() -> bool: return bool(_state().respawning), 4.0), "Skipping CP1 and crossing CP2 visibly requests recovery")
	kart.controls.set_command(0.0, 0.0, 0.0, false)
	_report["missed_checkpoint"] = _state()
	_check(int(_state().last_checkpoint) == 0 and int(_state().next_checkpoint) == 1 and int(_state().invalid_crossings) == 1, "A skipped gate does not advance validated progress")
	_check(await _wait_recovery(0), "Skipped-gate recovery completes after a delay")
	_check(kart.global_position.distance_to(_route.recovery_transform(0).origin) < 0.3 and (-kart.global_basis.z).dot(-_route.recovery_transform(0).basis.z) > 0.99, "Respawn uses last checkpoint and correct forward direction")
	# Backward crossing is driven through the actual Area, not injected as a gate event.
	setup = _route.sample(_route.checkpoint_distance(1) + 5.0)
	setup.basis = setup.basis.rotated(Vector3.UP, PI)
	setup.origin.y += 0.12
	kart.respawn_at(setup)
	kart.controls.set_command(1.0, 0.0, 0.0, false)
	_check(await _wait_until(func() -> bool: return _wrong_way_events > 0, 4.0), "A backward gate crossing emits WRONG WAY")
	kart.controls.set_command(0.0, 1.0, 0.0, false)
	_check(int(_state().last_checkpoint) == 0 and int(_state().completed_laps) == 0, "Backward crossings cannot award checkpoints or laps")
	RaceManager.request_recovery(&"player", "verification reset")
	await _wait_recovery(1)
	kart.controls.set_command(1.0, 0.0, 0.0, false)
	_check(await _wait_until(func() -> bool: return int(_state().last_checkpoint) == 1, 5.0), "Reach a non-start checkpoint through its physical trigger")
	# Drive sideways through the open edge and let real gravity produce a fall.
	setup = _route.sample(22.0)
	setup.basis = Basis.looking_at(Vector3.RIGHT, Vector3.UP)
	setup.origin.y += 0.12
	kart.respawn_at(setup)
	kart.controls.set_command(1.0, 0.0, 0.0, false)
	_check(await _wait_until(func() -> bool: return bool(_state().respawning), 5.0), "Driving off the road triggers delayed recovery")
	_report["fall"] = {"state": _state(), "height_at_detection": kart.global_position.y}
	_check(str(_state().recovery_reason) == "fell off track" and kart.global_position.y < -2.0, "Fall recovery is triggered by an actual fall below the track")
	kart.controls.set_command(0.0, 0.0, 0.0, false)
	_check(await _wait_recovery(2), "Fall returns the kart to its last valid checkpoint")
	_check(int(_state().last_checkpoint) == 1 and int(_state().next_checkpoint) == 2 and kart.global_position.distance_to(_route.recovery_transform(1).origin) < 0.3, "Fall recovery preserves CP1 and returns there, not to the starting grid")
	# Idle is not stuck; sustained throttle against an inner wall is.
	await _frames(180)
	_check(int(_state().recovery_count) == 3, "An idle parked kart is not automatically respawned")
	setup = _route.sample(48.0)
	setup.basis = Basis.looking_at(Vector3.LEFT, Vector3.UP)
	setup.origin.y += 0.12
	kart.respawn_at(setup)
	kart.controls.set_command(1.0, 0.0, 0.0, false)
	_check(await _wait_until(func() -> bool: return bool(_state().respawning), 6.0), "Sustained throttle against a wall detects a stuck kart")
	_check(str(_state().recovery_reason) == "stuck", "Stuck recovery has an explicit reason")
	kart.controls.set_command(0.0, 0.0, 0.0, false)
	await _wait_recovery(3)
	kart.controls.set_command(0.0, 0.0, 0.0, false, true)
	_check(await _wait_until(func() -> bool: return bool(_state().respawning), 1.0), "Kart reset input requests recovery through the public signal")
	_check(await _wait_recovery(4), "Managed manual reset completes without leaving the kart locked")
	_check(not kart.controls.is_locked() and int(_state().last_checkpoint) == 1, "Manual reset retains the non-start checkpoint and unlocks input")
	await _ranking_checks()
	_report["checks"] = _checks
	_report["failures"] = _failures
	var file := FileAccess.open(OUTPUT + "race-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_report, "\t"))
	for failure in _failures:
		push_error("Phase 2 verification failed: " + failure)
	print("[Phase 2] VERIFICATION %s: %d checks; %d failures." % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	if "--phase2-check" in OS.get_cmdline_user_args():
		get_tree().quit(0 if _failures.is_empty() else 1)

func _ranking_checks() -> void:
	# Separate unit fixtures: no AI competitors are shipped in the playable race.
	RaceManager.configure(_route, 3)
	kart.respawn_at(_initial_pose)
	RaceManager.register_kart(kart, &"player", "Player")
	var fixtures: Array[ArcadeKart] = []
	var current_camera: Camera3D = get_viewport().get_camera_3d()
	for index in range(2):
		var fixture: ArcadeKart = preload("res://scenes/kart/Kart.tscn").instantiate()
		add_child(fixture)
		var pose: Transform3D = _route.sample(12.0 + index * 12.0)
		pose.origin.y += 0.12
		fixture.respawn_at(pose)
		fixture.controls.set_command(0.0, 0.0, 0.0, false)
		RaceManager.register_kart(fixture, StringName("fixture_%d" % index), "QA fixture %d" % index)
		fixtures.append(fixture)
	current_camera.make_current()
	RaceManager.start_race()
	var standings: Array[Dictionary] = RaceManager.get_standings()
	_check(standings.size() == 3 and standings[0].id == "fixture_1" and standings[1].id == "fixture_0" and standings[2].id == "player", "Three registered karts rank by distance within a checkpoint sector")
	await _wait_until(func() -> bool: return RaceManager.phase == RaceManager.Phase.RACING, 4.0)
	fixtures[1].respawn_at(fixtures[0].global_transform)
	await _frames(2)
	standings = RaceManager.get_standings()
	_check(standings[0].id == "fixture_0" and standings[1].id == "fixture_1", "Equal-distance positions use stable registration-order ties")
	var copied_state: Dictionary = RaceManager.get_racer_state(&"fixture_0")
	copied_state.completed_laps = 99
	_check(int(RaceManager.get_racer_state(&"fixture_0").completed_laps) == 0, "Race queries return independent snapshots")
	# Explicitly injected ordered gate events exercise lap precedence and partial finishes.
	for checkpoint in range(1, 8):
		RaceManager.report_checkpoint(fixtures[0], checkpoint, true)
	RaceManager.report_checkpoint(fixtures[0], 0, true)
	standings = RaceManager.get_standings()
	_check(standings[0].id == "fixture_0" and int(standings[0].completed_laps) == 1, "A completed lap outranks a physically farther kart on the previous lap")
	for _lap in range(2):
		for checkpoint in range(1, 8):
			RaceManager.report_checkpoint(fixtures[0], checkpoint, true)
		RaceManager.report_checkpoint(fixtures[0], 0, true)
	_check(RaceManager.phase == RaceManager.Phase.RACING and bool(RaceManager.get_racer_state(&"fixture_0").finished), "One finisher does not end a multi-kart race")
	_report["multi_kart_standings"] = RaceManager.get_standings()
	for fixture in fixtures:
		fixture.queue_free()
	await _frames(2)
	_check(RaceManager.get_standings().size() == 1, "Removed karts unregister cleanly from the autoload")
	RaceManager.configure(_route, 3)
	kart.respawn_at(_initial_pose)
	kart.controls.use_player_input()
	RaceManager.register_kart(kart, &"player", "Player")
	RaceManager.start_race()
