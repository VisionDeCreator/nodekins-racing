extends Node
## QA-only player pilot. Production Track always leaves the player under human control.
## All four racers traverse the full race using physical movement and real gate crossings.

const OUTPUT: String = "res://artifacts/phase_3/"
@onready var track: Node3D = $Track
@onready var player: ArcadeKart = $Track/Player
var output_directory: String = OUTPUT
var pilot: KartAI
var failures: PackedStringArray = []
var checks: int = 0
var recording: bool = true
var gate_counts: Dictionary = {}
var boosts: Dictionary = {}
var band_ranges: Dictionary = {}
var recoveries: Array[Dictionary] = []
var snapshots: Array[Dictionary] = []
var _next_snapshot: float = 10.0
var _previous_multipliers: Dictionary = {}
var _band_spike: bool = false
var _rank_error: bool = false
var report: Dictionary = {}

func _ready() -> void:
	process_physics_priority = 80
	if OS.get_cmdline_user_args().has("--no-band"):
		output_directory = OUTPUT + "no-band/"
		for ai: KartAI in track.cpu_drivers:
			ai.apply_rubber_band = false
	pilot = KartAI.new()
	pilot.name = "QAPlayerPilot"
	pilot.racer_id = &"player"
	pilot.tuning = preload("res://resources/ai/default_ai.tres")
	pilot.lane_offset = -1.5
	pilot.apply_rubber_band = false
	player.add_child(pilot)
	for kart: Node in get_tree().get_nodes_in_group("race_karts"):
		var id: String = "player" if kart == player else "cpu_%s" % str(kart.name).trim_prefix("CPU")
		gate_counts[id] = 0
		boosts[id] = 0
		kart.drift.boost_started.connect(_boost.bind(id))
	RaceManager.checkpoint_passed.connect(_gate)
	RaceManager.recovery_started.connect(_recovery)
	_run.call_deferred()

func _physics_process(delta: float) -> void:
	if not recording:
		return
	var standings: Array[Dictionary] = RaceManager.get_standings()
	for index in range(standings.size()):
		if int(standings[index].position) != index + 1:
			_rank_error = true
		if index > 0 and not standings[index - 1].finished and float(standings[index].distance_progress) > float(standings[index - 1].distance_progress) + 0.002:
			_rank_error = true
	for ai: KartAI in track.cpu_drivers:
		var id: String = str(ai.racer_id)
		if not band_ranges.has(id):
			band_ranges[id] = {"min": 1.0, "max": 1.0, "max_step": 0.0}
		var difference: float = absf(ai.multiplier - float(_previous_multipliers.get(id, 1.0)))
		band_ranges[id].min = minf(float(band_ranges[id].min), ai.multiplier)
		band_ranges[id].max = maxf(float(band_ranges[id].max), ai.multiplier)
		band_ranges[id].max_step = maxf(float(band_ranges[id].max_step), difference)
		if difference > ai.tuning.multiplier_change_per_second * delta + 0.00001 or ai.multiplier < 0.96 - 0.00001 or ai.multiplier > 1.06 + 0.00001:
			_band_spike = true
		_previous_multipliers[id] = ai.multiplier
	if RaceManager.elapsed >= _next_snapshot:
		_next_snapshot += 10.0
		snapshots.append({"time": RaceManager.elapsed, "standings": standings})
		print("[Phase 3 standings] " + JSON.stringify(snapshots[-1]))

func _boost(_tier: int, _multiplier: float, _duration: float, id: String) -> void:
	if recording:
		boosts[id] = int(boosts[id]) + 1

func _gate(id: StringName, _checkpoint: int) -> void:
	if recording:
		gate_counts[str(id)] = int(gate_counts[str(id)]) + 1

func _recovery(id: StringName, checkpoint: int, reason: String) -> void:
	var event: Dictionary = {"id": str(id), "time": RaceManager.elapsed, "checkpoint": checkpoint, "reason": reason, "full_race": recording}
	recoveries.append(event)
	print("[Phase 3 recovery] " + JSON.stringify(event))

func _check(condition: bool, description: String) -> void:
	checks += 1
	print("[Phase 3 check] %s: %s" % ["PASS" if condition else "FAIL", description])
	if not condition:
		failures.append(description)

func _wait_until(condition: Callable, seconds: float) -> bool:
	for _tick in range(ceili(seconds * Engine.physics_ticks_per_second)):
		if condition.call():
			return true
		await get_tree().physics_frame
	return bool(condition.call())

func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame
	await get_tree().process_frame

func _capture_field() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var racers: Array[Node] = get_tree().get_nodes_in_group("race_karts")
	var center: Vector3 = Vector3.ZERO
	for kart: Node in racers:
		center += kart.global_position
	center /= racers.size()
	var radius: float = 0.0
	for kart: Node in racers:
		radius = maxf(radius, kart.global_position.distance_to(center))
	var camera := Camera3D.new()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(30.0, radius * 2.8 + 10.0)
	camera.global_position = center + Vector3(25, 36, 26)
	camera.look_at(center)
	camera.make_current()
	$Track/DrivingHUD.hide()
	$Track/RaceHUD.hide()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(output_directory + "four-karts-mid-race.png")) == OK, "Captured all-four mid-race view")
	var visible_count: int = 0
	for kart: Node in racers:
		var screen: Vector2 = camera.unproject_position(kart.global_position + Vector3.UP)
		if not camera.is_position_behind(kart.global_position) and get_viewport().get_visible_rect().has_point(screen):
			visible_count += 1
	_check(visible_count == 4, "All four moving karts project inside the screenshot")
	player.get_node("ChaseCamera/SpringArm3D/Camera3D").make_current()
	$Track/DrivingHUD.show()
	$Track/RaceHUD.show()
	camera.queue_free()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	await _frames(30)
	_check(RaceManager.get_standings().size() == 4, "Four independent racers registered")
	_check(player.controls.is_locked() and track.cpu_drivers.all(func(ai: KartAI) -> bool: return ai.kart.controls.is_locked() and ai.kart.speed < 0.01), "Countdown locks player and all CPUs")
	var source_stats: KartHandling = load("res://resources/handling/default_handling.tres")
	_check(track.cpu_drivers.all(func(ai: KartAI) -> bool: return ai.kart.scene_file_path == player.scene_file_path and ai.kart.stats.acceleration_curve == source_stats.acceleration_curve), "CPUs instantiate the same Kart scene and derive the same handling defaults")
	_check(await _wait_until(func() -> bool: return RaceManager.elapsed > 9.0, 15.0), "Four-kart race starts and advances")
	await _capture_field()
	_check(await _wait_until(func() -> bool: return RaceManager.phase == RaceManager.Phase.FINISHED, 110.0), "All four racers finish the physical three-lap race")
	report["results"] = RaceManager.get_standings()
	for result: Dictionary in report.results:
		var id: String = result.id
		_check(result.finished and int(result.completed_laps) == 3 and int(gate_counts[id]) == 24, "%s: three laps and 24 ordered physical crossings" % id)
		_check(int(result.invalid_crossings) == 0, "%s: no skipped gates" % id)
		if id != "player":
			_check(int(boosts[id]) > 0, "%s: earns real drift mini-turbos" % id)
	_check(not _rank_error, "RaceManager ranks all four correctly on every sampled physics tick")
	_check(not _band_spike, "Rubber band stays within 0.96–1.06 and its slew limit")
	_check(is_equal_approx(source_stats.top_speed, 20.0) and is_equal_approx(player.stats.top_speed, 20.0), "CPU rubber band never mutates source handling or player speed")
	report["full_race_boosts"] = boosts.duplicate()
	report["full_race_gate_counts"] = gate_counts.duplicate()
	report["band_ranges"] = band_ranges.duplicate(true)
	report["snapshots"] = snapshots.duplicate(true)
	print("[Phase 3 finish] " + JSON.stringify(report))
	recording = false
	_band_checks()
	await _recovery_check()
	report["recovery_events"] = recoveries
	report["checks"] = checks
	report["failures"] = failures
	var file := FileAccess.open(output_directory + "race-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("[Phase 3 verification] %s — %d checks; failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, failures])
	if OS.get_cmdline_user_args().has("--phase3-check"):
		get_tree().quit(0 if failures.is_empty() else 1)

func _band_checks() -> void:
	var tuning: AITuning = track.cpu_drivers[0].tuning
	var segment: float = RaceManager.route.length() / RaceManager.route.checkpoint_indices.size()
	_check(tuning.band_target(0.0, segment * 0.99, 0.0, segment) == 1.0, "No rubber band within one checkpoint segment")
	_check(is_equal_approx(tuning.band_target(0.0, segment * 10.0, 0.0, segment), 1.06), "Large trailing gap caps at +6 percent")
	_check(is_equal_approx(tuning.band_target(segment * 10.0, 0.0, 0.0, segment), 0.96), "Large lead over the pack caps at minus 4 percent")
	_check(tuning.band_target(segment * 2.0, segment * 2.0, segment * 2.0, segment) == 1.0, "An isolated straggler cannot penalize a grouped leader")

func _recovery_check() -> void:
	# Explicit fault injection after the valid race: suspend one body's physics at speed.
	# Its AI remains active. This models a stalled movement system with stale speed telemetry,
	# exercising the progress watchdog independently of RaceManager's zero-speed detector.
	RaceManager.start_race()
	_check(await _wait_until(func() -> bool: return RaceManager.elapsed > 1.5, 6.0), "Restart resets the full grid")
	var ai: KartAI = track.cpu_drivers[0]
	var cpu: ArcadeKart = ai.kart
	cpu.set_physics_process(false)
	var start_time: float = RaceManager.elapsed
	var recovery_before: int = int(RaceManager.get_racer_state(ai.racer_id).recovery_count)
	var requested: bool = await _wait_until(func() -> bool: return bool(RaceManager.get_racer_state(ai.racer_id).respawning), 4.0)
	var delay: float = RaceManager.elapsed - start_time
	_check(requested and delay <= ai.tuning.no_progress_seconds + 0.15, "No-progress watchdog requests recovery within three seconds")
	_check(str(RaceManager.get_racer_state(ai.racer_id).recovery_reason) == "CPU no forward progress", "Stale positive speed cannot hide a CPU stall")
	cpu.set_physics_process(true)
	_check(await _wait_until(func() -> bool: return int(RaceManager.get_racer_state(ai.racer_id).recovery_count) > recovery_before, 2.0), "CPU checkpoint recovery completes after its delay")
	_check(await _wait_until(func() -> bool: return int(RaceManager.get_racer_state(ai.racer_id).last_checkpoint) >= 1, 6.0), "Recovered CPU independently resumes and passes the next real checkpoint")
	report["injected_stall"] = {"request_delay": delay, "state_after_recovery": RaceManager.get_racer_state(ai.racer_id)}
