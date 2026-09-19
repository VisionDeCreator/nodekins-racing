extends Node3D
## Placeholder feedback only. Read-only observer of kart telemetry and drift/boost state.

const TIER_COLORS: Array[Color] = [Color("9ba8b6"), Color("37d8ff"), Color("ffb73d"), Color("ee74ff")]
@onready var kart: ArcadeKart = get_parent() as ArcadeKart
@onready var drift: KartDrift = $"../DriftBoost"
@onready var body: MeshInstance3D = $Body
@onready var booster: MeshInstance3D = $BoostTrail
var _material: StandardMaterial3D
var _trail_material: StandardMaterial3D

func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.roughness = 0.65
	_material.emission_enabled = true
	body.material_override = _material
	_trail_material = StandardMaterial3D.new()
	_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	booster.material_override = _trail_material

func _physics_process(delta: float) -> void:
	var index: int = drift.boost_tier if drift.is_boosting() else drift.tier
	var color: Color = TIER_COLORS[index]
	if drift.drifting and index == 0:
		color = TIER_COLORS[0].lerp(TIER_COLORS[1], drift.charge_time / kart.stats.mini_turbo_thresholds[0] * 0.6)
	_material.albedo_color = color
	_material.emission = color
	_material.emission_energy_multiplier = 0.6 if index > 0 else 0.0
	var target_yaw: float = -drift.direction * deg_to_rad(kart.stats.drift_visual_yaw) if drift.drifting else 0.0
	if kart.controls.suppression_remaining > 0.0:
		rotation.y += TAU * 1.8 * delta
		_material.albedo_color = Color("ff6375")
		_material.emission = Color("ff6375")
		_material.emission_energy_multiplier = 0.5
	else:
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-10.0 * delta))
	rotation.z = lerpf(rotation.z, -kart.controls.steering * 0.04 * minf(kart.speed / kart.stats.top_speed, 1.0), 1.0 - exp(-10.0 * delta))
	booster.visible = drift.is_boosting()
	_trail_material.albedo_color = color
	if booster.visible:
		booster.scale.z = 0.9 + 0.12 * sin(Time.get_ticks_msec() * 0.04)
