class_name KartHandling
extends Resource
## Shared tuning for movement, drift, presentation, and the independent chase camera.
## World distance is metres; angles here are degrees; times are seconds.

@export_group("Speed")
@export_range(0.1, 100.0, 0.1, "suffix:m/s") var top_speed: float = 20.0
@export_range(0.1, 10.0, 0.05, "suffix:s") var time_to_top_speed: float = 1.5
## Normalized time -> normalized speed. Provisional ease-out shape for feel tuning.
@export var acceleration_curve: Curve
@export_range(1.0, 100.0, 0.5) var brake_deceleration: float = 42.0
@export_range(0.1, 50.0, 0.5) var coast_deceleration: float = 7.0
@export_range(1.0, 100.0, 0.5) var gravity: float = 24.0
@export_range(1.0, 40.0, 0.5) var normal_grip: float = 18.0

@export_group("Steering")
@export_range(1.0, 360.0, 1.0, "suffix:deg/s") var low_speed_turn_rate: float = 180.0
## Normalized speed -> turn-rate multiplier. End value is provisional, not final balance.
@export var steering_speed_curve: Curve
@export_range(16.0, 90.0, 1.0, "suffix:deg") var maximum_steering_angle: float = 35.0
@export_range(0.1, 10.0, 0.1) var full_steering_speed: float = 3.0

@export_group("Drift")
## abs(normalized steering) * maximum_steering_angle must exceed this angle.
@export_range(0.0, 90.0, 0.5, "suffix:deg") var drift_steer_threshold_degrees: float = 15.0
@export_range(0.1, 20.0, 0.1) var drift_minimum_speed: float = 6.0
@export_range(1.0, 30.0, 0.5) var drift_grip: float = 5.0
@export_range(0.1, 2.0, 0.05) var drift_turn_multiplier: float = 0.95
@export_range(0.0, 35.0, 1.0, "suffix:deg") var drift_visual_yaw: float = 12.0
@export var mini_turbo_thresholds: PackedFloat32Array = PackedFloat32Array([1.0, 2.0, 3.0])
@export var mini_turbo_speed_multipliers: PackedFloat32Array = PackedFloat32Array([1.3, 1.45, 1.6])
## Provisional tier durations within the specified 1–1.5 second range.
@export var mini_turbo_durations: PackedFloat32Array = PackedFloat32Array([1.0, 1.25, 1.5])
@export_range(1.0, 200.0, 1.0) var boost_acceleration: float = 90.0
@export_range(1.0, 100.0, 1.0) var boost_decay: float = 24.0

@export_group("Glide")
@export_range(0.05, 1.0, 0.01) var glide_gravity_multiplier: float = 0.3
@export_range(0.0, 1.0, 0.01) var glide_air_steering_authority: float = 0.22
@export_range(0.0, 10.0, 0.1, "suffix:m/s") var glide_launch_velocity: float = 3.5
@export_range(0.1, 20.0, 0.1, "suffix:m/s") var glide_minimum_launch_speed: float = 6.0
@export_range(1.0, 90.0, 1.0, "suffix:deg") var glide_heading_limit_degrees: float = 25.0
@export_range(0.1, 20.0, 0.1) var glide_air_grip: float = 3.0
@export_range(0.5, 10.0, 0.1, "suffix:s") var glide_maximum_seconds: float = 4.0

@export_group("Chase Camera")
@export_range(1.0, 10.0, 0.1) var camera_distance: float = 4.5
@export_range(0.5, 6.0, 0.1) var camera_height: float = 2.0
@export_range(0.0, 4.0, 0.1) var camera_look_ahead: float = 1.4
@export_range(1.0, 30.0, 0.5) var camera_position_damping: float = 12.0
@export_range(1.0, 30.0, 0.5) var camera_rotation_damping: float = 7.0
@export_range(40.0, 110.0, 1.0) var camera_base_fov: float = 70.0
@export_range(40.0, 110.0, 1.0) var camera_boost_fov: float = 79.0
@export_range(1.0, 30.0, 0.5) var camera_fov_damping: float = 12.0

func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	if top_speed <= 0.0 or time_to_top_speed <= 0.0:
		errors.append("Speed and acceleration duration must be positive.")
	if acceleration_curve == null or steering_speed_curve == null:
		errors.append("Acceleration and steering curves are required.")
	if maximum_steering_angle <= drift_steer_threshold_degrees:
		errors.append("Maximum steering angle must exceed the drift entry threshold.")
	if mini_turbo_thresholds.size() != 3 or mini_turbo_speed_multipliers.size() != 3 or mini_turbo_durations.size() != 3:
		errors.append("Define all three mini-turbo tiers.")
	else:
		var previous: float = 0.0
		for index in range(3):
			if mini_turbo_thresholds[index] <= previous or mini_turbo_speed_multipliers[index] <= 1.0 or mini_turbo_durations[index] <= 0.0:
				errors.append("Turbo thresholds must ascend; multipliers > 1; durations > 0.")
			previous = mini_turbo_thresholds[index]
	if glide_gravity_multiplier <= 0.0 or glide_gravity_multiplier > 1.0 or glide_air_steering_authority < 0.0 or glide_air_steering_authority > 1.0 or glide_maximum_seconds <= 0.0:
		errors.append("Glide needs positive reduced gravity/lifetime and air authority within 0–1.")
	return errors
