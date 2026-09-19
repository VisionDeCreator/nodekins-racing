class_name KartInventory
extends Node
signal changed
var system: RaceItems
var racer_id: StringName
var cpu_controlled: bool = false
var kart: ArcadeKart
var held: ItemDefinition
var held_seconds: float = 0.0
var immunity_remaining: float = 0.0

func _ready() -> void:
	kart = get_parent() as ArcadeKart
	process_physics_priority = -20
	kart.controls.item_use_requested.connect(use_item)
	kart.respawned.connect(reset)
	RaceManager.racer_finished.connect(_finished)

func _physics_process(delta: float) -> void:
	immunity_remaining = maxf(0.0, immunity_remaining - delta)
	if held != null and can_act():
		held_seconds += delta
		if cpu_controlled and held.effect.cpu_should_use(self, held):
			kart.controls.request_item_use()

func can_act() -> bool:
	var state: Dictionary = RaceManager.get_racer_state(racer_id)
	return not state.is_empty() and RaceManager.phase == RaceManager.Phase.RACING and not state.finished and not state.respawning and not kart.controls.is_locked()

func receive(item: ItemDefinition) -> bool:
	if held != null or item == null or not can_act():
		return false
	held = item
	held_seconds = 0.0
	changed.emit()
	return true

func use_item() -> void:
	if held == null or not can_act():
		return
	var item: ItemDefinition = held
	if item.effect.activate(self, item):
		held = null
		held_seconds = 0.0
		changed.emit()
		system.record("use", {"racer": str(racer_id), "item": str(item.id), "speed": kart.speed})

func take_hit(source: StringName, item: ItemDefinition, effect: DeployItemEffect) -> bool:
	if not can_act() or immunity_remaining > 0.0:
		return false
	var before: float = kart.speed
	kart.drift.reset()
	kart.controls.suppress_for(effect.hit_duration)
	immunity_remaining = effect.hit_duration + effect.immunity_duration
	system.record("hit", {"racer": str(source), "target": str(racer_id), "item": str(item.id), "speed_before": before, "spin_seconds": effect.hit_duration})
	changed.emit()
	return true

func find_target(max_distance: float, cone_degrees: float) -> KartInventory:
	var result: KartInventory
	var nearest: float = max_distance
	for other: KartInventory in system.inventories.values():
		if other == self or not other.can_act():
			continue
		var offset: Vector3 = other.kart.global_position - kart.global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance > 0.1 and distance < nearest and (-kart.global_basis.z).dot(offset / distance) >= cos(deg_to_rad(cone_degrees)):
			nearest = distance
			result = other
	return result

func reset() -> void:
	held = null
	held_seconds = 0.0
	immunity_remaining = 0.0
	kart.controls.clear_suppression()
	changed.emit()

func _finished(id: StringName, _position: int, _time: float) -> void:
	if id == racer_id:
		reset()
