extends Node
## QA player pilot, complete race through physical ramp, gap, gates and item encounters.
const OUTPUT: String = "res://artifacts/phase_4_5/"
@onready var track: Node3D = $Track
@onready var player: ArcadeKart = $Track/Player
var pilot: KartAI
var flights: Array[Dictionary] = []
var airborne_gates: Array[Dictionary] = []
var item_events: Array[Dictionary] = []
var recoveries: Array[Dictionary] = []
var gate_counts: Dictionary = {"player": 0, "cpu_1": 0, "cpu_2": 0, "cpu_3": 0}
var checks: int = 0
var failures: PackedStringArray = []
var full_race: bool = true
var rank_error: bool = false
var visual_error: bool = false
var launches: Dictionary = {"player": 0, "cpu_1": 0, "cpu_2": 0, "cpu_3": 0}
var capture_counts: Dictionary = {}
var report: Dictionary = {}
var _camera: Camera3D
var _capture_active: bool = false

func _ready() -> void:
	process_physics_priority = 80
	pilot = KartAI.new()
	pilot.name = "QAPlayerPilot"
	pilot.racer_id = &"player"
	pilot.tuning = preload("res://resources/ai/default_ai.tres")
	pilot.lane_offset = -1.5
	pilot.apply_rubber_band = false
	player.add_child(pilot)
	track.items.inventories[&"player"].cpu_controlled = true
	for id: StringName in track.items.inventories:
		var kart: ArcadeKart = track.items.inventories[id].kart
		kart.glide.launched.connect(_launch.bind(id))
		kart.glide.ended.connect(_end.bind(id))
	RaceManager.checkpoint_passed.connect(_gate)
	RaceManager.recovery_started.connect(_recovery)
	track.items.item_event.connect(_item)
	_run.call_deferred()

func _physics_process(_delta: float) -> void:
	if _capture_active:
		_camera.global_position = player.global_position + Vector3(10, 6, 12)
		_camera.look_at(player.global_position + Vector3(0, 0.8, -1.5))
	if not full_race:
		return
	var standings: Array[Dictionary] = RaceManager.get_standings()
	for index in range(standings.size()):
		if int(standings[index].position) != index + 1:
			rank_error = true
		if index > 0 and not standings[index - 1].finished and float(standings[index].distance_progress) > float(standings[index - 1].distance_progress) + 0.002:
			rank_error = true
	for inventory: KartInventory in track.items.inventories.values():
		if inventory.kart.glide.active != inventory.kart.glide.canopy.visible:
			visual_error = true
	if player.glide.active and player.glide.flight_time > 0.5 and not capture_counts.has("mid-glide"):
		capture_counts["mid-glide"] = true
		_capture.call_deferred("mid-glide")

func _launch(id: StringName) -> void:
	if full_race:
		launches[str(id)] = int(launches[str(id)]) + 1
	if full_race and id == &"player" and not capture_counts.has("mid-launch"):
		capture_counts["mid-launch"] = true
		if DisplayServer.get_name() != "headless":
			_camera = Camera3D.new()
			add_child(_camera)
			_capture_active = true
			_camera.make_current()
			$Track/DrivingHUD.hide()
			$Track/RaceHUD.hide()
			track.get_node("ItemHUD").hide()
		_capture.call_deferred("mid-launch")

func _end(flight: Dictionary, id: StringName) -> void:
	var result: Dictionary = flight.duplicate()
	result["racer"] = str(id)
	result["time"] = RaceManager.elapsed
	result["full_race"] = full_race
	flights.append(result)
	if full_race and id == &"player" and flight.reason == "landed" and not capture_counts.has("after-landing"):
		capture_counts["after-landing"] = true
		_capture.call_deferred("after-landing")

func _gate(id: StringName, checkpoint: int) -> void:
	if not full_race:
		return
	gate_counts[str(id)] = int(gate_counts[str(id)]) + 1
	var kart: ArcadeKart = track.items.inventories[id].kart
	if checkpoint == track.glide_section.airborne_checkpoint:
		var state: Dictionary = RaceManager.get_racer_state(id)
		state["gliding"] = kart.glide.active
		state["grounded"] = kart.is_on_floor()
		state["height"] = kart.global_position.y
		airborne_gates.append(state)
		print("[Glide checkpoint] " + JSON.stringify(state))

func _recovery(id: StringName, checkpoint: int, reason: String) -> void:
	recoveries.append({"racer": str(id), "checkpoint": checkpoint, "reason": reason, "time": RaceManager.elapsed, "full_race": full_race})

func _item(event: Dictionary) -> void:
	if full_race:
		item_events.append(event)

func _check(condition: bool, description: String) -> void:
	checks += 1
	print("[Phase 4.5 check] %s: %s" % ["PASS" if condition else "FAIL", description])
	if not condition:
		failures.append(description)

func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame
	await get_tree().process_frame

func _wait_until(condition: Callable, seconds: float) -> bool:
	for _tick in range(ceili(seconds * Engine.physics_ticks_per_second)):
		if condition.call():
			return true
		await get_tree().physics_frame
	return bool(condition.call())

func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + filename + ".png")) == OK, "Captured " + filename)
	if filename == "after-landing":
		_capture_active = false
		player.get_node("ChaseCamera/SpringArm3D/Camera3D").make_current()
		$Track/DrivingHUD.show()
		$Track/RaceHUD.show()
		track.get_node("ItemHUD").show()
		_camera.queue_free()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	await _frames(30)
	var at_gap: Vector3 = RaceManager.route.sample(40.0).origin
	var query := PhysicsRayQueryParameters3D.create(at_gap + Vector3.UP * 4, at_gap - Vector3.UP * 4, 1)
	_check(player.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "Gap has no hidden road collider")
	_check(player.controls.is_locked() and not player.glide.try_launch(), "Countdown prevents glide activation")
	_check(await _wait_until(func() -> bool: return RaceManager.phase == RaceManager.Phase.FINISHED, 125.0), "All four racers finish three laps across the gap with items enabled")
	report["results"] = RaceManager.get_standings()
	for result: Dictionary in report.results:
		var id: String = result.id
		var completed: Array = flights.filter(func(flight: Dictionary) -> bool: return flight.full_race and flight.racer == id and flight.reason == "landed")
		_check(result.finished and int(gate_counts[id]) == 24 and int(result.invalid_crossings) == 0, "%s finishes 24 ordered gates without shortcuts" % id)
		_check(int(launches[id]) >= 3 and completed.size() >= 3, "%s automatically launches and lands on every lap" % id)
		_check(airborne_gates.filter(func(state: Dictionary) -> bool: return state.id == id and state.gliding and not state.grounded).size() == 3, "%s passes CP1 in the air on all three laps" % id)
	_check(not rank_error, "Four-kart positions stay valid throughout airborne travel")
	_check(not visual_error, "Canopy appears only while gliding")
	_check(flights.filter(func(flight: Dictionary) -> bool: return flight.reason != "landed").is_empty(), "Every full-race glide returns to ordinary ground contact")
	_check(flights.all(func(flight: Dictionary) -> bool: return absf(flight.speed_before_contact - flight.speed_after_contact) < 0.75), "Landing preserves horizontal speed within 0.75 m/s")
	_check(item_events.any(func(event: Dictionary) -> bool: return event.kind == "use"), "Items remain active during the glide race")
	report["race_recoveries"] = recoveries.duplicate(true)
	report["full_race_flights"] = flights.duplicate(true)
	report["airborne_checkpoints"] = airborne_gates
	report["item_events"] = item_events
	full_race = false
	await _isolated_checks()
	for inventory: KartInventory in track.items.inventories.values():
		inventory.kart.controls.set_command(0, 1, 0, false)
	await _frames(240)
	_check(track.items.inventories.values().all(func(inventory: KartInventory) -> bool: return inventory.kart.speed < 0.01 and not inventory.kart.glide.active), "Completed verification leaves a stable parked grid")
	report["checks"] = checks
	report["failures"] = failures
	var file := FileAccess.open(OUTPUT + "glide-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("[Phase 4.5 verification] %s — %d checks; failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, failures])
	if OS.get_cmdline_user_args().has("--phase45-check"):
		get_tree().quit(0 if failures.is_empty() else 1)

func _isolated_checks() -> void:
	pilot.set_physics_process(false)
	for ai: KartAI in track.cpu_drivers:
		ai.set_physics_process(false)
	for inventory: KartInventory in track.items.inventories.values():
		inventory.cpu_controlled = false
	RaceManager.start_race()
	await _wait_until(func() -> bool: return RaceManager.phase == RaceManager.Phase.RACING, 4.0)
	for box: ItemBox in track.items.boxes:
		box.set_physics_process(false)
	# Drive the actual ramp; steering stays straight until the launch.
	for id: StringName in track.items.inventories:
		var kart: ArcadeKart = track.items.inventories[id].kart
		if kart != player:
			var parked: Transform3D = RaceManager.route.sample(8.0)
			parked.origin += Vector3(5, 0.12, 0)
			kart.respawn_at(parked)
			kart.controls.set_command(0, 1, 0, false)
	player.controls.set_command(1, 0, 0, false)
	_check(await _wait_until(func() -> bool: return player.glide.active, 5.0), "Physical launch needs no glide button")
	var initial_speed: float = player.speed
	var vy: float = player.velocity.y
	var time_before_gravity: float = player.glide.flight_time
	await _frames(1)
	var gravity_step: float = (vy - player.velocity.y) / (player.glide.flight_time - time_before_gravity)
	_check(absf(gravity_step - player.stats.gravity * player.stats.glide_gravity_multiplier) < 0.02, "Airborne gravity matches the stats Resource multiplier")
	_check(absf(player.speed - initial_speed) < 1.0, "Launch carries speed instead of resetting it")
	player.controls.set_command(1, 0, 1, false)
	var yaw: float = player.rotation.y
	await _frames(20)
	var yaw_change: float = absf(rad_to_deg(wrapf(player.rotation.y - yaw, -PI, PI)))
	_check(yaw_change > 1.0 and yaw_change < 10.0, "Analog air steering changes heading with limited authority")
	report["air_control"] = {"gravity_metres_per_second_squared": gravity_step, "yaw_change_over_one_third_second": yaw_change, "launch_speed": initial_speed}
	player.controls.set_command(1, 0, 0, false)
	_check(await _wait_until(func() -> bool: return not player.glide.active, 3.0) and player.is_on_floor(), "Neutralizing air steer lands back on the track")
	var speed_at_landing: float = player.speed
	await _frames(10)
	_check(player.is_on_floor() and player.speed > speed_at_landing - 2.0 and not player.glide.canopy.visible, "Normal ground driving resumes immediately after landing")
	# A missed landing must recover onto real road, not repeatedly respawn over CP1's gap.
	var before: int = int(RaceManager.get_racer_state(&"player").recovery_count)
	RaceManager.request_recovery(&"player", "verification missed landing")
	player.controls.set_command(0, 0, 0, false)
	_check(await _wait_until(func() -> bool: return int(RaceManager.get_racer_state(&"player").recovery_count) > before, 2.0), "Recovery completes after an airborne checkpoint")
	await _frames(10)
	_check(player.is_on_floor() and player.global_position.distance_to(RaceManager.route.recovery_transform(1).origin) < 0.2 and not player.glide.active, "CP1 recovery is on the far bank with glider retracted")
	_check(preload("res://resources/tracks/oval.tres").recovery_overrides.is_empty(), "Gap recovery does not mutate the original route Resource")
	# Items still use the same boost/suppression paths while gliding.
	RaceManager.start_race()
	await _wait_until(func() -> bool: return RaceManager.phase == RaceManager.Phase.RACING, 4.0)
	player.controls.set_command(1, 0, 0, false)
	await _wait_until(func() -> bool: return player.glide.active, 5.0)
	var inventory: KartInventory = track.items.inventories[&"player"]
	inventory.receive(preload("res://resources/items/banana.tres"))
	player.controls.request_item_use()
	await _frames(3)
	_check(inventory.held != null and get_tree().get_nodes_in_group("item_actors").is_empty(), "Banana stays held during glide instead of spawning a floating trap")
	inventory.reset()
	inventory.receive(preload("res://resources/items/boost.tres"))
	player.controls.request_item_use()
	await _frames(12)
	_check(player.glide.active and player.speed > 27.0 and player.drift.is_boosting(), "Boost uses existing acceleration during a glide")
	var hit: bool = inventory.take_hit(&"cpu_1", preload("res://resources/items/shell.tres"), preload("res://resources/items/shell.tres").effect)
	await _frames(8)
	_check(hit and player.glide.active and player.speed < 27.0 and player.controls.is_locked(), "A midair hit brakes the kart while its glider remains deployed")
	RaceManager.request_recovery(&"player", "verification midair recovery")
	await _wait_until(func() -> bool: return not bool(RaceManager.get_racer_state(&"player").respawning), 2.0)
	_check(not player.glide.active and not player.glide.canopy.visible and is_equal_approx(player.floor_snap_length, 0.35), "Midair recovery clears glide state and restores ground snap")
	# Undesignated falling never deploys a glider.
	var off_edge: Transform3D = RaceManager.route.sample(55.0)
	off_edge.origin += Vector3(12, 2, 0)
	player.respawn_at(off_edge)
	await _frames(8)
	_check(not player.glide.active and player.velocity.y < -1.0, "Ordinary off-track falls retain normal gravity and no glider")
	RaceManager.start_race()
	await _frames(2)
	_check(not player.glide.active and is_equal_approx(player.floor_snap_length, 0.35) and player.controls.is_locked(), "Restart restores ground snap and keeps countdown input locked")
