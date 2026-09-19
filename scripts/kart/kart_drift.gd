class_name KartDrift
extends Node
## Owns drift charging and boost lifetime. It never moves the body or reads device input.

signal boost_started(tier: int, multiplier: float, duration: float)

var stats: KartHandling
var drifting: bool = false
var direction: float = 0.0
var charge_time: float = 0.0
var tier: int = 0
var boost_tier: int = 0
var boost_remaining: float = 0.0
var boost_duration: float = 0.0
var boost_multiplier: float = 1.0

func step(delta: float, controls: KartInput, grounded: bool, speed: float) -> void:
	boost_remaining = maxf(0.0, boost_remaining - delta)
	if not is_boosting():
		boost_multiplier = 1.0
		boost_tier = 0
	# Brake and lost ground cancel charge without rewarding an accidental release.
	if controls.brake > 0.0 or not grounded or speed < stats.drift_minimum_speed:
		_cancel_drift()
		if controls.brake > 0.0:
			boost_remaining = 0.0
			boost_multiplier = 1.0
			boost_tier = 0
		return
	if drifting and not controls.drift_held:
		if tier > 0:
			boost_tier = tier
			boost_multiplier = stats.mini_turbo_speed_multipliers[tier - 1]
			boost_duration = stats.mini_turbo_durations[tier - 1]
			boost_remaining = boost_duration
			boost_started.emit(tier, boost_multiplier, boost_duration)
		_cancel_drift()
		return
	if not drifting and not is_boosting() and controls.drift_held:
		var steer_angle: float = absf(controls.steering) * stats.maximum_steering_angle
		if steer_angle > stats.drift_steer_threshold_degrees:
			drifting = true
			direction = signf(controls.steering)
	if drifting:
		charge_time = minf(charge_time + delta, stats.mini_turbo_thresholds[2])
		tier = 0
		for index in range(3):
			if charge_time + 0.00001 >= stats.mini_turbo_thresholds[index]:
				tier = index + 1

func steering_for(input_steering: float) -> float:
	if not drifting:
		return input_steering
	# Latch drift side; countersteer opens the arc without instantly flipping it.
	return direction * clampf(0.55 + 0.45 * input_steering * direction, 0.1, 1.0) * stats.drift_turn_multiplier

func is_boosting() -> bool:
	return boost_remaining > 0.0

func reset() -> void:
	_cancel_drift()
	boost_tier = 0
	boost_remaining = 0.0
	boost_multiplier = 1.0
	boost_duration = 0.0

func _cancel_drift() -> void:
	drifting = false
	direction = 0.0
	charge_time = 0.0
	tier = 0
