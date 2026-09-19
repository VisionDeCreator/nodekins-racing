class_name AITuning
extends Resource
## Driving choices, never a second set of kart physics stats.

@export_group("Path and traffic")
@export var look_ahead: float = 8.0
@export var speed_look_ahead: float = 0.12
@export var lane_response: float = 2.0
@export var avoidance_distance: float = 9.0
@export var passing_clearance: float = 2.4
@export var road_edge_margin: float = 2.2

@export_group("Drift decisions")
@export var drift_curve_angle_degrees: float = 16.0
@export var drift_exit_angle_degrees: float = 7.0
@export var drift_probe_distance: float = 14.0
@export var drift_cooldown: float = 0.6
@export var drift_entry_margin: float = 0.06
@export var drift_max_heading_error_degrees: float = 38.0

@export_group("Rubber band")
@export var rubber_band_enabled: bool = true
## No adjustment inside one average checkpoint segment (~43 m on Loop 01).
@export var gap_segments: float = 1.0
@export var full_effect_segments: float = 2.5
@export_range(0.0, 0.15, 0.005) var catchup_cap: float = 0.06
@export_range(0.0, 0.15, 0.005) var leader_penalty_cap: float = 0.04
@export var multiplier_change_per_second: float = 0.02
@export var telemetry_interval: float = 2.0

@export_group("Progress watchdog")
@export var no_progress_seconds: float = 3.0
@export var minimum_progress: float = 1.0

func band_target(progress: float, leader: float, pack_median: float, segment_length: float) -> float:
	if not rubber_band_enabled:
		return 1.0
	var threshold: float = segment_length * gap_segments
	var ramp: float = maxf(segment_length * (full_effect_segments - gap_segments), 1.0)
	var behind: float = leader - progress
	if behind > threshold:
		return 1.0 + catchup_cap * clampf((behind - threshold) / ramp, 0.0, 1.0)
	var ahead: float = progress - pack_median
	if ahead > threshold:
		return 1.0 - leader_penalty_cap * clampf((ahead - threshold) / ramp, 0.0, 1.0)
	return 1.0
