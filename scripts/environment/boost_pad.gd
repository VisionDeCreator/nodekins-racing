class_name TrackBoostPad
extends Area3D
## One shared Boost effect per grounded crossing; never writes kart velocity or consumes inventory.
signal activated(racer_id: StringName)
@export var boost_definition: ItemDefinition = preload("res://resources/items/boost.tres")
var _served: Dictionary = {}

func _ready() -> void:
	process_physics_priority = 10
	RaceManager.countdown_changed.connect(_countdown)

func _physics_process(_delta: float) -> void:
	var present: Dictionary = {}
	for body: Node3D in get_overlapping_bodies():
		present[body.get_instance_id()] = true
	for id: int in _served.keys():
		if not present.has(id):
			_served.erase(id)
	if RaceManager.phase != RaceManager.Phase.RACING:
		return
	for body: Node3D in get_overlapping_bodies():
		if not body is ArcadeKart or _served.has(body.get_instance_id()) or not body.is_on_floor():
			continue
		var inventory := body.get_node_or_null("Inventory") as KartInventory
		if inventory == null or not inventory.can_act():
			continue
		if boost_definition.effect.activate(inventory, boost_definition):
			_served[body.get_instance_id()] = true
			inventory.system.record("pad_activate", {"pad":str(name), "racer":str(inventory.racer_id), "duration":boost_definition.duration, "active_multiplier":inventory.kart.drift.boost_multiplier, "held_item":str(inventory.held.id) if inventory.held != null else ""})
			activated.emit(inventory.racer_id)

func _countdown(text: String) -> void:
	if text == "3":
		_served.clear()
