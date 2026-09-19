class_name RaceItems
extends Node3D
signal item_event(event: Dictionary)
@export var catalog: Array[ItemDefinition] = []
@export var box_respawn_seconds: float = 4.0
@export var random_seed: int = 0
@export var row_distances: PackedFloat32Array = PackedFloat32Array([28.0, 145.0, 201.0, 317.0])
var inventories: Dictionary = {}
var boxes: Array[ItemBox] = []
var _random := RandomNumberGenerator.new()
const BOX_SCENE: PackedScene = preload("res://scenes/items/ItemBox.tscn")

func _ready() -> void:
	if catalog.is_empty():
		var entries: PackedStringArray = DirAccess.get_files_at("res://resources/items")
		entries.sort()
		for entry: String in entries:
			var resource_path: String = "res://resources/items/" + entry.trim_suffix(".remap")
			if resource_path.ends_with(".tres"):
				var item := load(resource_path) as ItemDefinition
				if item != null and item.effect != null:
					catalog.append(item)
	if random_seed == 0:
		_random.randomize()
	else:
		_random.seed = random_seed
	RaceManager.countdown_changed.connect(_countdown)
	RaceManager.race_finished.connect(clear_actors)

func attach(kart: ArcadeKart, id: StringName, cpu: bool) -> void:
	var inventory := KartInventory.new()
	inventory.name = "Inventory"
	inventory.system = self
	inventory.racer_id = id
	inventory.cpu_controlled = cpu
	kart.add_child(inventory)
	inventories[id] = inventory

func place_boxes(route: TrackRoute) -> void:
	for distance: float in row_distances:
		for lane: float in [-3.2, 0.0, 3.2]:
			var box := BOX_SCENE.instantiate() as ItemBox
			box.system = self
			box.name = "ItemBox%d" % boxes.size()
			add_child(box)
			box.global_transform = route.sample(distance)
			box.global_position += box.global_basis.x * lane
			boxes.append(box)

func inventory_for(kart: Object) -> KartInventory:
	if kart is ArcadeKart:
		return kart.get_node_or_null("Inventory") as KartInventory
	return null

func roll(race_position: int, count: int) -> ItemDefinition:
	var total: float = 0.0
	for item: ItemDefinition in catalog:
		total += item.weight_for(race_position, count)
	var choice: float = _random.randf() * total
	for item: ItemDefinition in catalog:
		choice -= item.weight_for(race_position, count)
		if choice < 0.0:
			return item
	return catalog.back() if not catalog.is_empty() else null

func record(kind: String, details: Dictionary) -> void:
	var event: Dictionary = details.duplicate()
	event["kind"] = kind
	event["time"] = snappedf(RaceManager.elapsed, 0.001)
	print("[Items] " + JSON.stringify(event))
	item_event.emit(event)

func _countdown(text: String) -> void:
	if text == "3":
		clear_actors()
		for box: ItemBox in boxes:
			box.reset()

func clear_actors() -> void:
	for actor: Node in get_tree().get_nodes_in_group("item_actors"):
		if actor.get_parent() == self:
			actor.queue_free()
