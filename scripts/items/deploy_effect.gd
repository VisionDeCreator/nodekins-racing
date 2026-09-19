class_name DeployItemEffect
extends ItemEffect
@export var actor_scene: PackedScene
@export var forward_offset: float = 2.0
@export var travel_speed: float = 0.0
@export var homing_degrees_per_second: float = 0.0
@export var target_range: float = 38.0
@export var target_cone_degrees: float = 35.0
@export var hit_duration: float = 0.95
@export var immunity_duration: float = 2.0
@export var arming_delay: float = 0.45
@export var wait_for_target: bool = false
@export var maximum_hold: float = 5.0

func activate(inventory: KartInventory, definition: ItemDefinition) -> bool:
	if travel_speed <= 0.0 and inventory.kart.glide.active:
		return false # Keep a trap in the slot until landing; never leave a floating obstacle.
	var actor: Node3D = actor_scene.instantiate() as Node3D
	actor.configure(inventory, definition, self)
	inventory.system.add_child(actor)
	actor.global_transform = inventory.kart.global_transform
	actor.global_position += -inventory.kart.global_basis.z * forward_offset + Vector3.UP * 0.65
	inventory.system.record("deploy", {"racer": str(inventory.racer_id), "item": str(definition.id), "position": [actor.global_position.x, actor.global_position.y, actor.global_position.z]})
	return true

func cpu_should_use(inventory: KartInventory, definition: ItemDefinition) -> bool:
	if (travel_speed <= 0.0 and inventory.kart.glide.active) or inventory.held_seconds < definition.cpu_delay:
		return false
	return not wait_for_target or inventory.find_target(target_range, target_cone_degrees) != null or inventory.held_seconds >= maximum_hold
