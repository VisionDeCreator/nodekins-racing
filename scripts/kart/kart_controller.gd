class_name ArcadeKart
extends CharacterBody3D
## Arcade translation/yaw only. Devices, drift state, visuals, and camera live in components.

signal respawned
signal stats_changed(value: KartHandling)

@export var stats: KartHandling:
	set(value):
		stats = value
		if is_node_ready():
			_configure_stats()
@onready var controls: KartInput = $Input
@onready var drift: KartDrift = $DriftBoost

var speed: float = 0.0
var turn_rate_degrees: float = 0.0
var _travel_direction: Vector3 = Vector3.FORWARD
var _spawn: Transform3D

func _ready() -> void:
	_spawn = global_transform
	_travel_direction = -global_basis.z
	_configure_stats()

func _configure_stats() -> void:
	if stats == null:
		push_error("Kart requires a KartHandling Resource.")
		set_physics_process(false)
		return
	var errors: PackedStringArray = stats.validation_errors()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		set_physics_process(false)
		return
	drift.stats = stats
	set_physics_process(true)
	stats_changed.emit(stats)

func _physics_process(delta: float) -> void:
	controls.sample(delta)
	if controls.reset_pressed or global_position.y < -8.0:
		_reset_to_spawn()
		return
	drift.step(delta, controls, is_on_floor(), speed)
	_update_speed(delta)
	var speed_fraction: float = clampf(speed / stats.top_speed, 0.0, 1.0)
	var steering_scale: float = stats.steering_speed_curve.sample_baked(speed_fraction)
	turn_rate_degrees = stats.low_speed_turn_rate * steering_scale * minf(speed / stats.full_steering_speed, 1.0)
	if is_on_floor():
		rotation.y -= deg_to_rad(turn_rate_degrees) * drift.steering_for(controls.steering) * delta
		var grip: float = stats.drift_grip if drift.drifting else stats.normal_grip
		_travel_direction = _travel_direction.slerp(-global_basis.z, 1.0 - exp(-grip * delta)).normalized()
		velocity.y = -1.0
	else:
		velocity.y -= stats.gravity * delta
	velocity.x = _travel_direction.x * speed
	velocity.z = _travel_direction.z * speed
	move_and_slide()
	# Feed collision-clipped velocity back into the next tick; no stored wall-speed boost.
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	speed = horizontal_velocity.length()
	if speed > 0.01:
		_travel_direction = horizontal_velocity / speed

func _update_speed(delta: float) -> void:
	if controls.brake > 0.0:
		speed = move_toward(speed, 0.0, stats.brake_deceleration * controls.brake * delta)
		return
	if controls.throttle <= 0.001:
		speed = move_toward(speed, 0.0, stats.coast_deceleration * delta)
		return
	var target_speed: float = stats.top_speed * controls.throttle
	if drift.is_boosting():
		target_speed *= drift.boost_multiplier
		speed = move_toward(speed, target_speed, stats.boost_acceleration * delta)
	elif speed > target_speed:
		speed = move_toward(speed, target_speed, stats.boost_decay * delta)
	else:
		# Invert the time->speed curve so reapplying throttle resumes from actual speed.
		var low: float = 0.0
		var high: float = 1.0
		var fraction: float = speed / target_speed
		for _iteration in range(12):
			var midpoint: float = (low + high) * 0.5
			if stats.acceleration_curve.sample_baked(midpoint) < fraction:
				low = midpoint
			else:
				high = midpoint
		var next_time: float = minf((low + high) * 0.5 + delta / stats.time_to_top_speed, 1.0)
		speed = minf(target_speed, target_speed * stats.acceleration_curve.sample_baked(next_time))

func _reset_to_spawn() -> void:
	global_transform = _spawn
	velocity = Vector3.ZERO
	speed = 0.0
	turn_rate_degrees = 0.0
	_travel_direction = -global_basis.z
	drift.reset()
	controls.reset_smoothing()
	reset_physics_interpolation()
	respawned.emit()
