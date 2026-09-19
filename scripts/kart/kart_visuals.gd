extends Node3D
## Imported modular art and feedback. Read-only observer of movement and glide telemetry.

const TIER_COLORS: Array[Color] = [Color("9ba8b6"), Color("37d8ff"), Color("ffb73d"), Color("ee74ff")]
@onready var kart: ArcadeKart = get_parent() as ArcadeKart
@onready var drift: KartDrift = $"../DriftBoost"
const PAINT_SHADER: Shader = preload("res://assets/karts/kart_paint.gdshader")
@export var paint_color: Color = Color("36b4ce")
@onready var assembly: Node3D = $Model/kart_01
@onready var body: MeshInstance3D = $Model/kart_01/socket_chassis/kart_chassis_01
@onready var spoiler: MeshInstance3D = $Model/kart_01/socket_spoiler/kart_spoiler_01
@onready var booster: MeshInstance3D = $BoostTrail
var glider_socket: Node3D
var _material: ShaderMaterial
var _spoiler_material: ShaderMaterial
var _trail_material: StandardMaterial3D

func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = PAINT_SHADER
	body.material_override = _material
	_spoiler_material = ShaderMaterial.new()
	_spoiler_material.shader = PAINT_SHADER
	spoiler.material_override = _spoiler_material
	set_livery(paint_color)
	# Preserve the authored rear-top offset under the existing deployment/bank parent.
	# This only attaches art; KartGlide continues to own visibility and flight behavior.
	glider_socket = assembly.get_node("socket_glider")
	glider_socket.reparent(get_node("../Glide/Canopy"), false)
	glider_socket.show()
	_trail_material = StandardMaterial3D.new()
	_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	booster.material_override = _trail_material

func set_livery(color: Color) -> void:
	paint_color = color
	if _material != null:
		_material.set_shader_parameter("paint_color", color)
		_spoiler_material.set_shader_parameter("paint_color", color)

func _physics_process(delta: float) -> void:
	var index: int = drift.boost_tier if drift.is_boosting() else drift.tier
	var color: Color = TIER_COLORS[index]
	if drift.drifting and index == 0:
		color = TIER_COLORS[0].lerp(TIER_COLORS[1], drift.charge_time / kart.stats.mini_turbo_thresholds[0] * 0.6)
	_material.set_shader_parameter("feedback_color", color)
	_material.set_shader_parameter("feedback_mix", 1.0 if index > 0 or drift.drifting else 0.0)
	_material.set_shader_parameter("feedback_energy", 0.6 if index > 0 else 0.0)
	var target_yaw: float = -drift.direction * deg_to_rad(kart.stats.drift_visual_yaw) if drift.drifting else 0.0
	if kart.controls.suppression_remaining > 0.0:
		rotation.y += TAU * 1.8 * delta
		_material.set_shader_parameter("feedback_color", Color("ff6375"))
		_material.set_shader_parameter("feedback_mix", 1.0)
		_material.set_shader_parameter("feedback_energy", 0.5)
	else:
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-10.0 * delta))
	rotation.z = lerpf(rotation.z, -kart.controls.steering * 0.04 * minf(kart.speed / kart.stats.top_speed, 1.0), 1.0 - exp(-10.0 * delta))
	booster.visible = drift.is_boosting()
	_trail_material.albedo_color = color
	if booster.visible:
		booster.scale.z = 0.9 + 0.12 * sin(Time.get_ticks_msec() * 0.04)
