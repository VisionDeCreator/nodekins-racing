class_name DeployedItem
extends Node3D
## Swept projectile or stationary trap, configured entirely by its Item Resource strategy.
var inventory: KartInventory
var definition: ItemDefinition
var effect: DeployItemEffect
var age: float = 0.0
var target: KartInventory
var spent: bool = false
var _sweep: ShapeCast3D

func configure(source: KartInventory, item: ItemDefinition, parameters: DeployItemEffect) -> void:
	inventory = source
	definition = item
	effect = parameters
	target = source.find_target(effect.target_range, effect.target_cone_degrees)

func _ready() -> void:
	add_to_group("item_actors")
	_sweep = ShapeCast3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.48 if effect.travel_speed > 0.0 else 0.8
	_sweep.shape = shape
	_sweep.collision_mask = 3 if effect.travel_speed > 0.0 else 2
	_sweep.enabled = false
	add_child(_sweep)
	if effect.travel_speed > 0.0:
		_sweep.add_exception(inventory.kart)

func _physics_process(delta: float) -> void:
	if spent or RaceManager.phase != RaceManager.Phase.RACING:
		return
	age += delta
	if age >= definition.duration:
		_finish("timeout")
		return
	if age < effect.arming_delay:
		return
	if effect.travel_speed > 0.0 and is_instance_valid(target) and target.can_act():
		var direction: Vector3 = target.kart.global_position - global_position
		direction.y = 0.0
		var angle: float = (-global_basis.z).signed_angle_to(direction.normalized(), Vector3.UP)
		rotate_y(clampf(angle, -deg_to_rad(effect.homing_degrees_per_second) * delta, deg_to_rad(effect.homing_degrees_per_second) * delta))
	_sweep.target_position = Vector3(0, 0, -effect.travel_speed * delta)
	_sweep.force_shapecast_update()
	if _sweep.is_colliding():
		var victim: KartInventory = inventory.system.inventory_for(_sweep.get_collider(0))
		if victim != null:
			var accepted: bool = victim.take_hit(inventory.racer_id, definition, effect)
			if not accepted:
				inventory.system.record("hit_ignored", {"item": str(definition.id), "target": str(victim.racer_id)})
		_finish("impact")
		return
	global_position += -global_basis.z * effect.travel_speed * delta

func _finish(reason: String) -> void:
	spent = true
	inventory.system.record("despawn", {"racer": str(inventory.racer_id), "item": str(definition.id), "reason": reason})
	queue_free()
