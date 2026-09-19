class_name ItemDefinition
extends Resource
## Stable IDs and effect strategies, not item-name conditionals in inventory or HUD.
@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var duration: float = 2.0
@export var color: Color = Color.WHITE
@export var front_weight: float = 1.0
@export var back_weight: float = 1.0
@export var cpu_delay: float = 0.8
@export var effect: ItemEffect

func weight_for(position: int, racer_count: int) -> float:
	var fraction: float = float(maxi(0, position - 1)) / maxi(1, racer_count - 1)
	return maxf(0.0, lerpf(front_weight, back_weight, clampf(fraction, 0.0, 1.0)))
