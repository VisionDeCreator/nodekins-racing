class_name KartGlide
extends Node3D
## Flight-only state. The kart retains its normal speed, boost, input and collision pipeline.
signal launched
signal ended(flight: Dictionary)
var active: bool = false
var flight_time: float = 0.0
var last_flight: Dictionary = {}
@onready var kart: ArcadeKart = get_parent() as ArcadeKart
@onready var canopy: Node3D = $Canopy
var _direction: Vector3
var _launch_yaw: float = 0.0
var _entry_speed: float = 0.0
var _entry_position: Vector3
var _peak_height: float = 0.0
var _floor_snap: float = 0.35

func _ready() -> void:
	_floor_snap = kart.floor_snap_length
	canopy.hide()
	kart.respawned.connect(reset)

func try_launch() -> bool:
	if active or kart.controls.is_locked() or not kart.is_on_floor() or kart.speed < kart.stats.glide_minimum_launch_speed:
		return false
	active = true
	flight_time = 0.0
	_entry_speed = kart.speed
	_entry_position = kart.global_position
	_peak_height = _entry_position.y
	_launch_yaw = kart.rotation.y
	_direction = Vector3(kart.velocity.x, 0.0, kart.velocity.z).normalized()
	if _direction.is_zero_approx():
		_direction = -kart.global_basis.z
	kart.velocity.y = kart.stats.glide_launch_velocity
	kart.floor_snap_length = 0.0
	canopy.show()
	print("[Glide launch] %s speed=%.2f height=%.2f" % [kart.name, kart.speed, kart.global_position.y])
	launched.emit()
	return true

func step(delta: float) -> void:
	flight_time += delta
	var yaw_change: float = -deg_to_rad(kart.turn_rate_degrees) * kart.stats.glide_air_steering_authority * kart.controls.steering * delta
	var relative_yaw: float = wrapf(kart.rotation.y + yaw_change - _launch_yaw, -PI, PI)
	var limit: float = deg_to_rad(kart.stats.glide_heading_limit_degrees)
	kart.rotation.y = _launch_yaw + clampf(relative_yaw, -limit, limit)
	if _direction.is_equal_approx(-kart.global_basis.z):
		_direction = -kart.global_basis.z
	_direction = _direction.slerp(-kart.global_basis.z, 1.0 - exp(-kart.stats.glide_air_grip * delta)).normalized()
	kart.velocity.x = _direction.x * kart.speed
	kart.velocity.z = _direction.z * kart.speed
	kart.velocity.y -= kart.stats.gravity * kart.stats.glide_gravity_multiplier * delta
	var descending: bool = kart.velocity.y <= 0.0
	var speed_before_contact: float = kart.speed
	kart.move_and_slide()
	_peak_height = maxf(_peak_height, kart.global_position.y)
	canopy.rotation.z = lerpf(canopy.rotation.z, -kart.controls.steering * 0.18, 1.0 - exp(-8.0 * delta))
	if descending and kart.is_on_floor():
		_finish("landed", speed_before_contact)
	elif flight_time >= kart.stats.glide_maximum_seconds:
		_finish("timeout", speed_before_contact)

func _finish(reason: String, speed_before_contact: float) -> void:
	active = false
	kart.floor_snap_length = _floor_snap
	canopy.hide()
	last_flight = {"reason": reason, "seconds": flight_time, "launch_speed": _entry_speed,
		"launch_height": _entry_position.y, "peak_height": _peak_height,
		"horizontal_distance": Vector2(kart.global_position.x - _entry_position.x, kart.global_position.z - _entry_position.z).length(),
		"speed_before_contact": speed_before_contact, "speed_after_contact": Vector2(kart.velocity.x, kart.velocity.z).length(),
		"landing_height": kart.global_position.y}
	print("[Glide end] %s %s" % [kart.name, JSON.stringify(last_flight)])
	ended.emit(last_flight.duplicate())

func reset() -> void:
	if active:
		_finish("respawn", kart.speed)
	active = false
	flight_time = 0.0
	kart.floor_snap_length = _floor_snap
	canopy.hide()
	canopy.rotation = Vector3.ZERO
