class_name BoostItemEffect
extends ItemEffect
@export var speed_multiplier: float = 1.5

func activate(inventory: KartInventory, definition: ItemDefinition) -> bool:
	inventory.kart.drift.activate_boost(speed_multiplier, definition.duration)
	inventory.system.record("boost", {"racer": str(inventory.racer_id), "item": str(definition.id), "multiplier": speed_multiplier, "duration": definition.duration, "speed_before": inventory.kart.speed})
	return true

func cpu_should_use(inventory: KartInventory, definition: ItemDefinition) -> bool:
	# Prefer a clear exit, but don't hoard forever. KartInput still enforces every lock.
	return inventory.held_seconds >= definition.cpu_delay and (absf(inventory.kart.controls.steering) < 0.28 or inventory.held_seconds > 4.0)
