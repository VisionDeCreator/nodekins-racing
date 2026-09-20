extends Node3D
## Independent render-frame camera. Follows interpolated physics position, not kart visuals.

@export var target: CharacterBody3D
@export var boost_source: KartDrift
@onready var arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D
var _stats: KartHandling
var _yaw: float = 0.0

func _ready() -> void:
	set_as_top_level(true)
	arm.add_excluded_object(target.get_rid())
	target.connect("respawned", snap_to_target)
	target.connect("stats_changed", _apply_stats)
	_apply_stats(target.get("stats") as KartHandling)
	snap_to_target()

func _apply_stats(value: KartHandling) -> void:
	_stats = value
	if _stats == null:
		set_process(false)
		return
	set_process(true)
	var reach: float = _stats.camera_distance + _stats.camera_look_ahead
	var rise: float = _stats.camera_height - 0.6
	arm.spring_length = Vector2(reach, rise).length()
	arm.rotation.x = -atan2(rise, reach)

func snap_to_target() -> void:
	if _stats == null:
		return
	_yaw = target.global_rotation.y
	global_position = target.global_position - target.global_basis.z * _stats.camera_look_ahead + Vector3.UP * 0.6
	global_rotation = Vector3(0.0, _yaw, 0.0)
	camera.fov = _stats.camera_base_fov

func _process(delta: float) -> void:
	var pose: Transform3D = target.get_global_transform_interpolated()
	if target.has_meta(&"online_render_pose"):
		pose = target.get_meta(&"online_render_pose")
	var desired_position: Vector3 = pose.origin - pose.basis.z * _stats.camera_look_ahead + Vector3.UP * 0.6
	# Compensate steady travel lag so damping does not stretch a 4.5 m chase to 7 m on boost.
	var horizontal_velocity := Vector3(target.velocity.x, 0.0, target.velocity.z)
	desired_position += horizontal_velocity / _stats.camera_position_damping
	global_position = global_position.lerp(desired_position, 1.0 - exp(-_stats.camera_position_damping * delta))
	_yaw = lerp_angle(_yaw, pose.basis.get_euler().y, 1.0 - exp(-_stats.camera_rotation_damping * delta))
	global_rotation = Vector3(0.0, _yaw, 0.0)
	var fov_target: float = _stats.camera_boost_fov if boost_source.is_boosting() else _stats.camera_base_fov
	camera.fov = lerpf(camera.fov, fov_target, 1.0 - exp(-_stats.camera_fov_damping * delta))
