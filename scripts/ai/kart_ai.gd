class_name KartAI
extends Node
## A driver attached to the existing Kart.tscn. Never writes velocity, pose, or drift state.
## Route queries and normalized commands are the only path-following mechanisms.

@export var racer_id: StringName
@export var tuning: AITuning
@export var lane_offset: float = 0.0
@export var apply_rubber_band: bool = true
@export var use_drift: bool = true
var kart: ArcadeKart
var multiplier: float = 1.0
var target_multiplier: float = 1.0
var watchdog_recoveries: int = 0
var _base_stats: KartHandling
var _runtime_stats: KartHandling
var _lane: float = 0.0
var _drift_cooldown: float = 0.0
var _progress_anchor: float = 0.0
var _no_progress: float = 0.0
var _reset_progress_anchor: bool = true
var _log_remaining: float = 0.0

func _ready() -> void:
	kart = get_parent() as ArcadeKart
	process_physics_priority = -40
	_base_stats = kart.stats
	# Same source Resource; only the scalar speed budget is adjusted per instance.
	# Curves and all other handling defaults remain shared and unmodified.
	_runtime_stats = _base_stats.duplicate() as KartHandling
	kart.stats = _runtime_stats
	_lane = lane_offset
	kart.respawned.connect(_on_respawn)
	kart.controls.set_command(0.0, 1.0, 0.0, false)

func _exit_tree() -> void:
	if is_instance_valid(kart) and not kart.is_queued_for_deletion():
		kart.stats = _base_stats
		kart.controls.use_player_input()

func _on_respawn() -> void:
	_lane = lane_offset
	_no_progress = 0.0
	_reset_progress_anchor = true
	_drift_cooldown = tuning.drift_cooldown
	if RaceManager.phase == RaceManager.Phase.COUNTDOWN:
		multiplier = 1.0
		target_multiplier = 1.0
		_runtime_stats.top_speed = _base_stats.top_speed
		watchdog_recoveries = 0
		_log_remaining = 0.0

func _physics_process(delta: float) -> void:
	var state: Dictionary = RaceManager.get_racer_state(racer_id)
	if state.is_empty():
		kart.controls.set_command(0.0, 1.0, 0.0, false)
		return
	if RaceManager.phase != RaceManager.Phase.RACING or state.finished or state.respawning:
		_no_progress = 0.0
		_progress_anchor = float(state.distance_progress)
		kart.controls.set_command(0.0, 1.0, 0.0, false)
		return
	_update_band(delta, state)
	_watch_progress(delta, state)
	_drive(delta, state)

func _update_band(delta: float, state: Dictionary) -> void:
	var distances: Array[float] = []
	for other: Dictionary in RaceManager.get_standings():
		if other.id != str(racer_id):
			distances.append(float(other.distance_progress))
	distances.sort()
	target_multiplier = 1.0
	if apply_rubber_band and not distances.is_empty():
		var middle: int = floori(distances.size() / 2.0)
		var median: float = distances[middle]
		if distances.size() % 2 == 0:
			median = (distances[middle - 1] + median) * 0.5
		target_multiplier = tuning.band_target(float(state.distance_progress), distances[-1], median,
			RaceManager.route.length() / RaceManager.route.checkpoint_indices.size())
	multiplier = move_toward(multiplier, target_multiplier, tuning.multiplier_change_per_second * delta)
	_runtime_stats.top_speed = _base_stats.top_speed * multiplier
	_log_remaining -= delta
	if _log_remaining <= 0.0:
		_log_remaining = tuning.telemetry_interval
		print("[CPU band] %s time=%.2f active=%.4f target=%.4f progress=%.2f" % [racer_id, RaceManager.elapsed, multiplier, target_multiplier, state.distance_progress])

func _watch_progress(delta: float, state: Dictionary) -> void:
	var progress: float = float(state.distance_progress)
	if _reset_progress_anchor:
		_progress_anchor = progress
		_no_progress = 0.0
		_reset_progress_anchor = false
	if progress >= _progress_anchor + tuning.minimum_progress:
		_progress_anchor = progress
		_no_progress = 0.0
	else:
		_no_progress += delta
	if _no_progress >= tuning.no_progress_seconds:
		watchdog_recoveries += 1
		print("[CPU recovery] %s no forward progress for %.2f s at CP%d" % [racer_id, _no_progress, state.last_checkpoint])
		RaceManager.request_recovery(racer_id, "CPU no forward progress")
		_no_progress = 0.0

func _drive(delta: float, state: Dictionary) -> void:
	var route: TrackRoute = RaceManager.route
	var distance: float = float(state.lap_distance)
	var desired_lane: float = lane_offset
	var traffic_throttle: float = 1.0
	var forward: Vector3 = -kart.global_basis.z
	for other: Node in get_tree().get_nodes_in_group("race_karts"):
		if other == kart:
			continue
		var separation: Vector3 = other.global_position - kart.global_position
		var ahead: float = separation.dot(forward)
		var side: float = separation.dot(kart.global_basis.x)
		if ahead > 0.0 and ahead < tuning.avoidance_distance and absf(side) < tuning.passing_clearance:
			var away: float = -signf(side) if absf(side) > 0.15 else signf(lane_offset + 0.1)
			desired_lane += away * tuning.passing_clearance
			if ahead < 3.5:
				traffic_throttle = 0.65
	var lane_limit: float = route.road_width * 0.5 - tuning.road_edge_margin
	desired_lane = clampf(desired_lane, -lane_limit, lane_limit)
	_lane = lerpf(_lane, desired_lane, 1.0 - exp(-tuning.lane_response * delta))
	var ahead_distance: float = tuning.look_ahead + kart.speed * tuning.speed_look_ahead
	var target_pose: Transform3D = route.sample(distance + ahead_distance)
	var to_target: Vector3 = target_pose.origin + target_pose.basis.x * _lane - kart.global_position
	to_target.y = 0.0
	var heading_error: float = forward.signed_angle_to(to_target.normalized(), Vector3.UP)
	var yaw_rate: float = 2.0 * maxf(kart.speed, 4.0) * sin(heading_error) / maxf(to_target.length(), 1.0)
	var desired_steering: float = clampf(-yaw_rate / deg_to_rad(maxf(kart.turn_rate_degrees, 30.0)), -1.0, 1.0)
	var near_forward: Vector3 = -route.sample(distance + 2.0).basis.z
	var far_forward: Vector3 = -route.sample(distance + tuning.drift_probe_distance).basis.z
	var bend: float = rad_to_deg(near_forward.signed_angle_to(far_forward, Vector3.UP))
	_drift_cooldown = maxf(0.0, _drift_cooldown - delta)
	var hold_drift: bool = false
	var steering: float = desired_steering
	if kart.drift.drifting:
		hold_drift = use_drift and absf(bend) > tuning.drift_exit_angle_degrees and absf(rad_to_deg(heading_error)) < tuning.drift_max_heading_error_degrees
		if kart.drift.charge_time >= kart.stats.mini_turbo_thresholds[2]:
			hold_drift = false
		if hold_drift:
			# Invert the existing drift steering response to countersteer along the line.
			var direction: float = kart.drift.direction
			steering = direction * (desired_steering * direction / kart.stats.drift_turn_multiplier - 0.55) / 0.45
		else:
			_drift_cooldown = tuning.drift_cooldown
	elif use_drift and _drift_cooldown <= 0.0 and not kart.drift.is_boosting() and kart.speed >= kart.stats.drift_minimum_speed:
		if absf(bend) >= tuning.drift_curve_angle_degrees and absf(rad_to_deg(heading_error)) < tuning.drift_max_heading_error_degrees and traffic_throttle == 1.0:
			hold_drift = true
			var entry: float = kart.stats.drift_steer_threshold_degrees / kart.stats.maximum_steering_angle + tuning.drift_entry_margin
			steering = -signf(bend) * maxf(absf(desired_steering), entry)
	kart.controls.set_command(traffic_throttle, 0.0, clampf(steering, -1.0, 1.0), hold_drift)
