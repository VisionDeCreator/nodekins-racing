class_name KartInput
extends Node
## Sole command boundary. Human input and future drivers submit identical normalized values.
## Injection replaces input sampling, never the movement or drift simulation.

signal item_use_requested

@export_range(1.0, 30.0, 0.5) var steering_response: float = 10.0

var throttle: float = 0.0
var brake: float = 0.0
var steering: float = 0.0
var drift_held: bool = false
var reset_pressed: bool = false
var _override_enabled: bool = false
var _command: Vector3 = Vector3.ZERO
var _command_drift: bool = false
var _command_reset: bool = false
var _locked: bool = false
var suppression_remaining: float = 0.0
var _item_queued: bool = false

## Composes with the race lock; an item cannot unlock countdown/recovery/finish.
func suppress_for(seconds: float) -> void:
	suppression_remaining = maxf(suppression_remaining, seconds)

func clear_suppression() -> void:
	suppression_remaining = 0.0
	_item_queued = false

func request_item_use() -> void:
	_item_queued = true

## An authoritative race lock, applied after either human or injected commands are sampled.
func set_locked(value: bool) -> void:
	_locked = value
	if value:
		throttle = 0.0
		brake = 1.0
		steering = 0.0
		drift_held = false
		reset_pressed = false

func is_locked() -> bool:
	return _locked or suppression_remaining > 0.0

func set_command(accelerate: float, braking: float, steer: float, drift: bool, reset: bool = false) -> void:
	_override_enabled = true
	_command = Vector3(clampf(accelerate, 0.0, 1.0), clampf(braking, 0.0, 1.0), clampf(steer, -1.0, 1.0))
	_command_drift = drift
	_command_reset = reset

func use_player_input() -> void:
	_override_enabled = false

func sample(delta: float) -> void:
	suppression_remaining = maxf(0.0, suppression_remaining - delta)
	var target_steering: float
	if _override_enabled:
		throttle = _command.x
		brake = _command.y
		target_steering = _command.z
		drift_held = _command_drift
		reset_pressed = _command_reset
		_command_reset = false
	else:
		throttle = Input.get_action_strength("kart_accelerate")
		brake = Input.get_action_strength("kart_brake")
		target_steering = Input.get_axis("kart_left", "kart_right")
		drift_held = Input.is_action_pressed("kart_drift")
		reset_pressed = Input.is_action_just_pressed("kart_reset")
	if is_locked():
		throttle = 0.0
		brake = 1.0
		steering = 0.0
		drift_held = false
		reset_pressed = false
		_item_queued = false
		return
	if _item_queued or (not _override_enabled and Input.is_action_just_pressed("kart_item")):
		_item_queued = false
		item_use_requested.emit()
	steering = lerpf(steering, target_steering, 1.0 - exp(-steering_response * delta))
	if absf(steering) < 0.001:
		steering = 0.0

func reset_smoothing() -> void:
	steering = 0.0
