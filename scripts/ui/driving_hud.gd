extends CanvasLayer
## Test instrumentation. Observes gameplay; it does not drive the kart.

@export var kart: ArcadeKart
@onready var speed_label: Label = $SpeedPanel/Margin/Rows/Speed
@onready var state_label: Label = $SpeedPanel/Margin/Rows/State
@onready var detail_label: Label = $SpeedPanel/Margin/Rows/Detail
@onready var meter: ProgressBar = $ChargePanel/Margin/Rows/Meter
@onready var charge_label: Label = $ChargePanel/Margin/Rows/Charge
@onready var tiers_label: Label = $ChargePanel/Margin/Rows/Tiers
var _fill: StyleBoxFlat

func _ready() -> void:
	_fill = StyleBoxFlat.new()
	_fill.bg_color = Color("37d8ff")
	_fill.corner_radius_top_left = 4
	_fill.corner_radius_top_right = 4
	_fill.corner_radius_bottom_left = 4
	_fill.corner_radius_bottom_right = 4
	meter.add_theme_stylebox_override("fill", _fill)
	print("[Phase 1] Test plane ready. Keyboard/gamepad -> shared KartInput. CharacterBody3D + independent drift and chase camera.")

func _process(_delta: float) -> void:
	var drift: KartDrift = kart.drift
	meter.max_value = kart.stats.mini_turbo_thresholds[2]
	speed_label.text = "%04.1f" % kart.speed
	detail_label.text = "%d km/h  ·  %.0f°/s steering ceiling" % [roundi(kart.speed * 3.6), kart.turn_rate_degrees]
	var colors: Array[Color] = [Color("9ba8b6"), Color("37d8ff"), Color("ffb73d"), Color("ee74ff")]
	if drift.is_boosting():
		state_label.text = "BOOST  /  TIER %d  ×%.2f" % [drift.boost_tier, drift.boost_multiplier]
		charge_label.text = "MINI-TURBO  ·  %.2f s remaining" % drift.boost_remaining
		meter.value = drift.boost_remaining / drift.boost_duration * meter.max_value
		_fill.bg_color = colors[drift.boost_tier]
	elif drift.drifting:
		state_label.text = "DRIFT  /  %s" % ("RIGHT" if drift.direction > 0.0 else "LEFT")
		charge_label.text = "CHARGING  %.2f s  /  %s" % [drift.charge_time, "RELEASE FOR BOOST" if drift.tier > 0 else "HOLD TO CHARGE"]
		meter.value = drift.charge_time
		_fill.bg_color = colors[maxi(1, drift.tier)]
	else:
		state_label.text = "BRAKING" if kart.controls.brake > 0.0 else ("DRIVING" if kart.speed > 0.1 else "READY")
		charge_label.text = "MINI-TURBO  /  HOLD DRIFT + STEER"
		meter.value = 0.0
		_fill.bg_color = colors[0]
	state_label.modulate = _fill.bg_color if drift.drifting or drift.is_boosting() else Color.WHITE
	var times: PackedFloat32Array = kart.stats.mini_turbo_thresholds
	var multipliers: PackedFloat32Array = kart.stats.mini_turbo_speed_multipliers
	tiers_label.text = "%.1f s  ×%.2f          %.1f s  ×%.2f          %.1f s  ×%.2f" % [times[0], multipliers[0], times[1], multipliers[1], times[2], multipliers[2]]
