class_name ItemBox
extends Area3D
var system: RaceItems
var cooldown: float = 0.0
@onready var visual: Node3D = $Visual

func _physics_process(delta: float) -> void:
	visual.rotation.y += delta * 1.8
	if cooldown > 0.0:
		cooldown = maxf(0.0, cooldown - delta)
		visual.visible = cooldown <= 0.0
		return
	if RaceManager.phase != RaceManager.Phase.RACING:
		return
	for body: Node3D in get_overlapping_bodies():
		var inventory: KartInventory = system.inventory_for(body)
		if inventory == null or inventory.held != null or not inventory.can_act():
			continue
		var state: Dictionary = RaceManager.get_racer_state(inventory.racer_id)
		var item: ItemDefinition = system.roll(int(state.position), int(state.racer_count))
		if inventory.receive(item):
			cooldown = system.box_respawn_seconds
			visual.hide()
			system.record("pickup", {"racer": str(inventory.racer_id), "item": str(item.id), "position": state.position, "box": str(name)})
			break

func reset() -> void:
	cooldown = 0.0
	visual.show()
