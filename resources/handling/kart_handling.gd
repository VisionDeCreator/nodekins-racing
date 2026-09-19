class_name KartHandling
extends Resource
## Data only. Phase 1 will interpret these values in one device-independent controller.
## World distance is metres; angles here are degrees; times are seconds.

@export_group("Speed")
@export_range(0.1, 100.0, 0.1, "suffix:m/s") var top_speed: float = 20.0
@export_range(0.1, 10.0, 0.05, "suffix:s") var time_to_top_speed: float = 1.5
## Normalized time -> normalized speed. Provisional ease-out shape for feel tuning.
@export var acceleration_curve: Curve

@export_group("Steering")
@export_range(1.0, 360.0, 1.0, "suffix:deg/s") var low_speed_turn_rate: float = 180.0
## Normalized speed -> turn-rate multiplier. End value is provisional, not final balance.
@export var steering_speed_curve: Curve

@export_group("Drift")
## Hold-drift AND steering beyond this angle; analog-axis mapping is deferred to Phase 1.
@export_range(0.0, 90.0, 0.5, "suffix:deg") var drift_steer_threshold_degrees: float = 15.0
@export var mini_turbo_thresholds: PackedFloat32Array = PackedFloat32Array([1.0, 2.0, 3.0])
@export var mini_turbo_speed_multipliers: PackedFloat32Array = PackedFloat32Array([1.3, 1.45, 1.6])
## Provisional tier durations within the specified 1–1.5 second range.
@export var mini_turbo_durations: PackedFloat32Array = PackedFloat32Array([1.0, 1.25, 1.5])
