extends Node
## Real in-engine acceptance drive through the public KartInput boundary.
## Run this scene for measurements and drift/boost screenshots; normal main scene is manual.

@onready var kart: ArcadeKart = $DrivingLab/Kart
@onready var camera: Camera3D = $DrivingLab/Kart/ChaseCamera/SpringArm3D/Camera3D
var failures: PackedStringArray = []
var measurements: Dictionary = {}
var output_dir: String = "res://artifacts/phase_1"

func _ready() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame
	await get_tree().process_frame

func _drive(seconds: float, throttle: float, brake: float = 0.0, steer: float = 0.0, drift: bool = false) -> void:
	kart.controls.set_command(throttle, brake, steer, drift)
	await _frames(roundi(seconds * Engine.physics_ticks_per_second))

func _reset() -> void:
	kart.controls.set_command(0.0, 0.0, 0.0, false, true)
	await _frames(15)

func _check(condition: bool, label: String) -> void:
	print("[Phase 1 check] %s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		failures.append(label)

func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path: String = ProjectSettings.globalize_path(output_dir.path_join(filename))
	_check(get_viewport().get_texture().get_image().save_png(path) == OK, "Saved " + filename)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	await _reset()
	# Test actual keyboard/gamepad InputMap bindings before using normalized automation.
	kart.controls.use_player_input()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	kart.controls.sample(1.0 / Engine.physics_ticks_per_second)
	_check(kart.controls.throttle > 0.99, "Keyboard W reaches shared throttle")
	var key_release: InputEventKey = key.duplicate()
	key_release.pressed = false
	Input.parse_input_event(key_release)
	Input.flush_buffered_events()
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 0.65
	Input.parse_input_event(trigger)
	await _frames(3)
	_check(kart.controls.throttle > 0.4 and kart.controls.throttle < 0.8, "Gamepad trigger preserves analog throttle")
	trigger.axis_value = 0.0
	Input.parse_input_event(trigger)
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 0.08
	Input.parse_input_event(stick)
	await _frames(15)
	_check(absf(kart.controls.steering) < 0.01, "Gamepad stick deadzone rejects idle noise")
	stick.axis_value = 0.65
	Input.parse_input_event(stick)
	await _frames(15)
	_check(kart.controls.steering > 0.3 and kart.controls.steering < 0.8, "Gamepad steering stays analog")
	stick.axis_value = 0.0
	Input.parse_input_event(stick)
	await _reset()
	var initial_yaw: float = kart.rotation.y
	await _drive(0.5, 0.0, 0.0, 1.0, true)
	_check(is_equal_approx(kart.rotation.y, initial_yaw) and not kart.drift.drifting, "No stationary spin or free drift charge")
	await _reset()
	await _drive(0.25, 1.0)
	measurements["speed_at_0_25s"] = kart.speed
	await _drive(0.5, 1.0)
	measurements["speed_at_0_75s"] = kart.speed
	await _drive(0.75, 1.0)
	measurements["speed_at_1_5s"] = kart.speed
	measurements["steady_camera_distance_m"] = Vector2(camera.global_position.x - kart.global_position.x, camera.global_position.z - kart.global_position.z).length()
	_check(float(measurements["steady_camera_distance_m"]) > 4.0 and float(measurements["steady_camera_distance_m"]) < 5.2, "Damped camera maintains the intended chase distance at speed")
	_check(absf(kart.speed - 20.0) < 0.15, "Full throttle reaches 20 m/s in about 1.5 s")
	_check(float(measurements["speed_at_0_75s"]) > 12.0, "Acceleration is faster off the line than linear")
	await _drive(0.5, 0.0)
	measurements["coast_speed_after_0_5s"] = kart.speed
	_check(kart.speed > 15.5 and kart.speed < 17.2, "Coasting decelerates without an abrupt stop")
	await _drive(0.5, 0.0, 1.0)
	_check(kart.speed < 0.05, "Braking stops the kart without reversing")
	await _reset()
	await _drive(1.6, 0.2, 0.0, 1.0)
	measurements["low_speed_turn_rate_deg_s"] = kart.turn_rate_degrees
	await _reset()
	await _drive(1.6, 1.0)
	await _drive(0.5, 1.0, 0.0, 1.0)
	measurements["top_speed_turn_rate_deg_s"] = kart.turn_rate_degrees
	_check(float(measurements["low_speed_turn_rate_deg_s"]) > kart.turn_rate_degrees * 1.6, "Steering tapers as speed rises")
	await _drive(0.4, 1.0, 0.0, 0.25)
	await _drive(0.7, 1.0, 0.0, 0.25, true)
	_check(not kart.drift.drifting, "Steering below 15 degrees does not start drift")
	await _reset()
	await _drive(1.6, 1.0)
	await _drive(0.5, 1.0, 0.0, -0.65, true)
	_check(kart.drift.drifting and kart.drift.direction < 0.0, "Left drift enters and stays distinct from ordinary steering")
	await _drive(0.1, 1.0)
	_check(not kart.drift.is_boosting(), "Releasing an uncharged drift does not boost")
	for desired_tier in range(1, 4):
		await _reset()
		await _drive(1.6, 1.0)
		await _drive(float(desired_tier) + 0.2, 1.0, 0.0, 0.65, true)
		_check(kart.drift.tier == desired_tier, "Drift charge reaches tier %d" % desired_tier)
		if desired_tier == 2:
			var travel := Vector3(kart.velocity.x, 0.0, kart.velocity.z).normalized()
			measurements["drift_slip_degrees"] = absf(rad_to_deg((-kart.global_basis.z).signed_angle_to(travel, Vector3.UP)))
			measurements["visual_drift_yaw_degrees"] = rad_to_deg(kart.get_node("Visuals").rotation.y)
			await _capture("mid-drift.png")
		await _drive(0.25, 1.0)
		var expected: float = kart.stats.top_speed * kart.stats.mini_turbo_speed_multipliers[desired_tier - 1]
		measurements["tier_%d_speed" % desired_tier] = kart.speed
		_check(kart.drift.is_boosting() and absf(kart.speed - expected) < 0.15, "Tier %d boosts to %.1f m/s" % [desired_tier, expected])
		_check(camera.fov > 77.0 and camera.fov <= 79.05, "Boost camera eases toward 79-degree FOV")
		if desired_tier == 3:
			measurements["boost_fov"] = camera.fov
			await _capture("mid-boost.png")
		await _drive(kart.stats.mini_turbo_durations[desired_tier - 1] + 0.65, 1.0)
		_check(not kart.drift.is_boosting() and absf(kart.speed - 20.0) < 0.15, "Tier %d expires smoothly back to normal speed" % desired_tier)
		_check(absf(camera.fov - 70.0) < 0.1, "Camera returns to base FOV")
	await _reset()
	await _drive(1.6, 1.0)
	await _drive(1.25, 1.0, 0.0, 0.7, true)
	await _drive(0.4, 1.0, 0.0, -0.5, true)
	_check(kart.drift.drifting and kart.drift.direction > 0.0, "Countersteer opens drift arc without reversing drift side")
	await _drive(0.1, 0.0, 1.0)
	_check(not kart.drift.drifting and not kart.drift.is_boosting(), "Braking cancels charge without granting a boost")
	await _reset()
	await _drive(10.0, 1.0)
	_check(kart.global_position.z > -120.0 and kart.speed < 0.1, "Boundary collision clips speed and prevents tunneling")
	await _reset()
	_check(kart.speed < 0.05 and not kart.drift.is_boosting() and kart.global_position.distance_to(Vector3(0, 0, 45)) < 0.2, "Input reset restores spawn, speed, drift, and camera")
	var original_stats: KartHandling = kart.stats
	var replacement: KartHandling = original_stats.duplicate(true) as KartHandling
	replacement.top_speed = 10.0
	replacement.camera_base_fov = 65.0
	kart.stats = replacement
	await _drive(1.6, 1.0)
	_check(absf(kart.speed - 10.0) < 0.1 and kart.drift.stats == replacement and absf(camera.fov - 65.0) < 0.1, "Replacing only the stats Resource updates movement, drift, and camera")
	kart.stats = original_stats
	await _reset()
	measurements["failures"] = failures
	var report := FileAccess.open(output_dir.path_join("measurements.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify(measurements, "\t"))
	print("[Phase 1 measurements] " + JSON.stringify(measurements))
	for failure in failures:
		push_error("Phase 1 verification failed: " + failure)
	print("[Phase 1] VERIFICATION " + ("PASS" if failures.is_empty() else "FAIL"))
	if "--phase1-check" in OS.get_cmdline_user_args():
		get_tree().quit(0 if failures.is_empty() else 1)
	else:
		# Remain alive so Godot MCP can retrieve the complete output after the drive ends.
		kart.controls.use_player_input()
