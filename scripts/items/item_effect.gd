class_name ItemEffect
extends Resource
## Extend an effect strategy for new behavior; inventory, rolls, and HUD stay generic.
func activate(_inventory: KartInventory, _definition: ItemDefinition) -> bool:
	return false

func cpu_should_use(inventory: KartInventory, definition: ItemDefinition) -> bool:
	return inventory.held_seconds >= definition.cpu_delay
