extends Node
## Full physical race first; isolated setups below never substitute for race evidence.
const OUTPUT: String = "res://artifacts/phase_4/"
@onready var track: Node3D = $Track
@onready var player: ArcadeKart = $Track/Player
var pilot: KartAI
var events: Array[Dictionary] = []
var hits_pending: Array[Dictionary] = []
var effects_measured: Array[Dictionary] = []
var gate_counts: Dictionary = {"player": 0, "cpu_1": 0, "cpu_2": 0, "cpu_3": 0}
var checks: int = 0
var failures: PackedStringArray = []
var full_race: bool = true
var hud_captured: bool = false
var actor_captured: bool = false
var report: Dictionary = {}
var rank_error: bool = false
var snapshots: Array[Dictionary] = []
var _next_snapshot: float = 15.0

func _ready() -> void:
	process_physics_priority = 80
	pilot = KartAI.new()
	pilot.name = "QAPlayerPilot"
	pilot.racer_id = &"player"
	pilot.tuning = preload("res://resources/ai/default_ai.tres")
	pilot.lane_offset = -1.5
	pilot.apply_rubber_band = false
	player.add_child(pilot)
	track.items.inventories[&"player"].cpu_controlled = true
	track.items.item_event.connect(_event)
	RaceManager.checkpoint_passed.connect(_gate)
	_run.call_deferred()

func _physics_process(_delta: float) -> void:
	if not full_race:
		return
	var standings: Array[Dictionary] = RaceManager.get_standings()
	for index in range(standings.size()):
		if int(standings[index].position) != index + 1:
			rank_error = true
		if index > 0 and not standings[index - 1].finished and float(standings[index].distance_progress) > float(standings[index - 1].distance_progress) + 0.002:
			rank_error = true
	if RaceManager.elapsed >= _next_snapshot:
		_next_snapshot += 15.0
		snapshots.append({"time": RaceManager.elapsed, "standings": standings})
		print("[Phase 4 standings] " + JSON.stringify(snapshots[-1]))
	for measurement: Dictionary in hits_pending.duplicate():
		if RaceManager.elapsed >= float(measurement.time) + 0.55:
			var inventory: KartInventory = track.items.inventories[StringName(measurement.subject)]
			measurement["speed_after"] = inventory.kart.speed
			measurement["suppression_remaining"] = inventory.kart.controls.suppression_remaining
			effects_measured.append(measurement)
			hits_pending.erase(measurement)
			print("[Phase 4 measured effect] " + JSON.stringify(measurement))

func _event(event: Dictionary) -> void:
	var copy: Dictionary = event.duplicate()
	copy["full_race"] = full_race
	events.append(copy)
	if full_race and event.kind in ["hit", "boost"]:
		var measurement: Dictionary = event.duplicate()
		measurement["subject"] = event.target if event.kind == "hit" else event.racer
		hits_pending.append(measurement)
	if full_race and event.kind == "pickup" and event.racer == "player" and not hud_captured:
		hud_captured = true
		_capture_hud.call_deferred()
	if full_race and event.kind == "deploy" and event.item == "banana" and not actor_captured:
		actor_captured = true
		_capture_actor.call_deferred()

func _gate(id: StringName, _checkpoint: int) -> void:
	if full_race:
		gate_counts[str(id)] = int(gate_counts[str(id)]) + 1

func _check(condition: bool, description: String) -> void:
	checks += 1
	print("[Phase 4 check] %s: %s" % ["PASS" if condition else "FAIL", description])
	if not condition:
		failures.append(description)

func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame
	await get_tree().process_frame

func _wait_until(condition: Callable, seconds: float) -> bool:
	for _tick in range(ceili(seconds * Engine.physics_ticks_per_second)):
		if condition.call():
			return true
		await get_tree().physics_frame
	return bool(condition.call())

func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + filename)) == OK, "Captured " + filename)

func _capture_hud() -> void:
	if DisplayServer.get_name() != "headless":
		await _capture("item-hud.png")

func _capture_actor() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var actors: Array[Node] = get_tree().get_nodes_in_group("item_actors")
	var trap: Node3D
	for actor: Node in actors:
		if actor.definition.id == &"banana":
			trap = actor
	if trap == null:
		return
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = trap.global_position + Vector3(7, 8, 9)
	camera.look_at(trap.global_position)
	camera.make_current()
	$Track/DrivingHUD.hide()
	$Track/RaceHUD.hide()
	track.get_node("ItemHUD").hide()
	await _capture("banana-on-track.png")
	player.get_node("ChaseCamera/SpringArm3D/Camera3D").make_current()
	$Track/DrivingHUD.show()
	$Track/RaceHUD.show()
	track.get_node("ItemHUD").show()
	camera.queue_free()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	await _frames(30)
	_check(track.items.catalog.size() == 3 and track.items.boxes.size() == 12, "Three Resources discovered and twelve physical boxes placed")
	_check(await _wait_until(func() -> bool: return RaceManager.phase == RaceManager.Phase.FINISHED, 120.0), "All four racers complete a three-lap race with items")
	report["results"] = RaceManager.get_standings()
	for result: Dictionary in report.results:
		_check(result.finished and int(result.completed_laps) == 3 and int(gate_counts[result.id]) == 24, "%s completes 24 valid gates" % result.id)
		_check(events.any(func(event: Dictionary) -> bool: return event.full_race and event.kind == "pickup" and event.racer == result.id), "%s collects from real item boxes" % result.id)
		_check(events.any(func(event: Dictionary) -> bool: return event.full_race and event.kind == "use" and event.racer == result.id), "%s uses held items" % result.id)
	for id: String in ["boost", "shell", "banana"]:
		_check(events.any(func(event: Dictionary) -> bool: return event.full_race and event.kind == "use" and event.item == id), "Full race uses " + id)
	_check(effects_measured.any(func(event: Dictionary) -> bool: return event.kind == "hit" and event.speed_after < event.speed_before and event.suppression_remaining > 0.0), "A real item hit visibly spins and slows a moving racer")
	_check(effects_measured.any(func(event: Dictionary) -> bool: return event.kind == "boost" and event.speed_after > event.speed_before + 3.0), "A real Boost pickup produces a measured speed burst")
	_check(not rank_error, "Race positions remain ordered throughout item chaos")
	full_race = false
	report["full_race_events"] = events.duplicate(true)
	report["effect_measurements"] = effects_measured
	report["standings_snapshots"] = snapshots
	await _isolated_checks()
	report["checks"] = checks
	report["failures"] = failures
	report["all_events"] = events
	var file := FileAccess.open(OUTPUT + "race-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("[Phase 4 verification] %s — %d checks; failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, failures])
	if OS.get_cmdline_user_args().has("--phase4-check"):
		get_tree().quit(0 if failures.is_empty() else 1)

func _isolated_checks() -> void:
	# Statistical rolls do not alter the race or its recorded item moments.
	var front: Dictionary = {"boost": 0, "shell": 0, "banana": 0}
	var back: Dictionary = front.duplicate()
	for _trial in range(6000):
		var first: String = str(track.items.roll(1, 4).id)
		var last: String = str(track.items.roll(4, 4).id)
		front[first] += 1
		back[last] += 1
	_check(front.banana > back.banana and back.boost > front.boost and back.shell > front.shell, "Position-weighted rolls favor defense ahead and comeback items behind")
	_check(front.values().all(func(count: int) -> bool: return count > 0) and back.values().all(func(count: int) -> bool: return count > 0), "Every item remains possible at the front and back")
	report["roll_distribution_6000"] = {"first": front, "last": back}
	# Keep fixture setup separate from the actual full race. Both input owners exercise each effect.
	pilot.set_physics_process(false)
	for ai: KartAI in track.cpu_drivers:
		ai.set_physics_process(false)
	for inventory: KartInventory in track.items.inventories.values():
		inventory.cpu_controlled = false
	RaceManager.start_race()
	await _wait_until(func() -> bool: return RaceManager.phase == RaceManager.Phase.RACING, 4.0)
	for box: ItemBox in track.items.boxes:
		box.set_physics_process(false)
	for source_id: StringName in [&"player", &"cpu_1"]:
		await _effect_checks(source_id)
	await _lifecycle_checks()
	await _device_input_checks()

func _park() -> void:
	RaceManager.start_race()
	await _wait_until(func() -> bool: return RaceManager.phase == RaceManager.Phase.RACING, 4.0)
	track.items.clear_actors()
	var index: int = 0
	for inventory: KartInventory in track.items.inventories.values():
		var pose: Transform3D = RaceManager.route.sample(3.0 + index * 3.0)
		pose.origin += pose.basis.x * 4.5 + Vector3.UP * 0.12
		inventory.kart.respawn_at(pose)
		inventory.kart.controls.set_command(0, 1, 0, false)
		index += 1
	await _frames(2)

func _place(inventory: KartInventory, distance: float) -> void:
	var pose: Transform3D = RaceManager.route.sample(distance)
	pose.origin.y += 0.12
	inventory.kart.respawn_at(pose)
	inventory.kart.controls.set_command(0, 0, 0, false)

func _effect_checks(source_id: StringName) -> void:
	var source: KartInventory = track.items.inventories[source_id]
	var victim: KartInventory = track.items.inventories[&"cpu_3"]
	await _park()
	_place(source, 5.0)
	source.kart.controls.set_command(1, 0, 0, false)
	await _frames(90)
	var before: float = source.kart.speed
	source.receive(preload("res://resources/items/boost.tres"))
	source.kart.controls.request_item_use()
	await _frames(30)
	_check(source.held == null and source.kart.speed > before + 4.0 and source.kart.drift.is_boosting(), "%s Boost uses shared acceleration and consumes inventory" % source_id)
	await _park()
	_place(source, 8.0)
	_place(victim, 20.0)
	var behind: KartInventory = track.items.inventories[&"cpu_2"]
	_place(behind, 24.0)
	source.receive(preload("res://resources/items/shell.tres"))
	source.kart.controls.request_item_use()
	_check(await _wait_until(func() -> bool: return victim.kart.controls.suppression_remaining > 0.0, 1.0), "%s Shell physically hits a target ahead" % source_id)
	_check(source.kart.controls.suppression_remaining == 0.0 and source.held == null, "Shell excludes its owner and consumes the slot once")
	var count: int = events.filter(func(event: Dictionary) -> bool: return not event.full_race and event.kind == "hit" and event.item == "shell" and event.racer == str(source_id)).size()
	await _frames(60)
	_check(events.filter(func(event: Dictionary) -> bool: return not event.full_race and event.kind == "hit" and event.item == "shell" and event.racer == str(source_id)).size() == count, "Shell applies only one hit")
	_check(behind.kart.controls.suppression_remaining == 0.0 and behind.immunity_remaining == 0.0, "The second kart behind the target is not hit")
	await _park()
	_place(source, 18.0)
	_place(victim, 6.0)
	source.receive(preload("res://resources/items/banana.tres"))
	source.kart.controls.request_item_use()
	await _frames(40)
	_check(get_tree().get_nodes_in_group("item_actors").size() == 1 and source.kart.controls.suppression_remaining == 0.0, "%s drops an armed trap behind without self-hitting on release" % source_id)
	victim.kart.controls.set_command(1, 0, 0, false)
	_check(await _wait_until(func() -> bool: return victim.kart.controls.suppression_remaining > 0.0, 2.0), "%s Banana physically catches a following kart" % source_id)
	var second_hit: bool = victim.take_hit(source_id, preload("res://resources/items/banana.tres"), preload("res://resources/items/banana.tres").effect)
	_check(not second_hit, "Hit immunity prevents repeated stun-locking")
	await _frames(80)
	_check(not victim.kart.controls.is_locked(), "Spin-out expires without leaving controls locked")

func _lifecycle_checks() -> void:
	await _park()
	var inventory: KartInventory = track.items.inventories[&"player"]
	_place(inventory, 15.0)
	_check(inventory.receive(preload("res://resources/items/banana.tres")) and not inventory.receive(preload("res://resources/items/shell.tres")), "Single inventory cannot be overwritten")
	inventory.kart.controls.request_item_use()
	await _frames(1)
	var actor: DeployedItem = get_tree().get_nodes_in_group("item_actors")[0]
	actor.age = actor.definition.duration - 0.05
	await _frames(10)
	_check(get_tree().get_nodes_in_group("item_actors").is_empty(), "Untriggered trap expires at its configured lifetime")
	inventory.receive(preload("res://resources/items/boost.tres"))
	inventory.kart.controls.set_locked(true)
	inventory.kart.controls.suppress_for(0.1)
	inventory.kart.controls.request_item_use()
	await _frames(15)
	_check(inventory.held != null and inventory.kart.controls.is_locked(), "Expired item suppression cannot release the race lock or consume an item")
	inventory.kart.controls.set_locked(false)
	inventory.reset()
	inventory.kart.drift.activate_boost(1.6, 1.5)
	inventory.kart.drift.activate_boost(1.5, 2.0)
	_check(is_equal_approx(inventory.kart.drift.boost_multiplier, 1.6) and is_equal_approx(inventory.kart.drift.boost_remaining, 2.0), "Boost overlap takes strongest/longest without multiplying")
	# Real box cooldown and reset, using stationary overlap (not a fake pickup call).
	await _park()
	var box: ItemBox = track.items.boxes[1]
	box.reset()
	box.set_physics_process(true)
	_place(inventory, 28.0)
	_check(await _wait_until(func() -> bool: return inventory.held != null, 0.5), "Real overlap awards an item")
	_check(box.cooldown > 0.0 and not box.visual.visible, "Picked-up box disappears immediately")
	_place(inventory, 32.0)
	_check(await _wait_until(func() -> bool: return box.cooldown == 0.0, 5.0), "Box respawns after its cooldown")
	RaceManager.start_race()
	await _frames(2)
	_check(track.items.inventories.values().all(func(entry: KartInventory) -> bool: return entry.held == null and entry.kart.controls.suppression_remaining == 0.0) and get_tree().get_nodes_in_group("item_actors").is_empty(), "Race restart clears held items, hits, and deployed actors")

func _device_input_checks() -> void:
	await _park()
	var inventory: KartInventory = track.items.inventories[&"player"]
	_place(inventory, 8.0)
	player.controls.use_player_input()
	Input.action_press("kart_accelerate")
	inventory.receive(preload("res://resources/items/boost.tres"))
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	Input.parse_input_event(key)
	await _frames(4)
	_check(inventory.held == null and player.drift.is_boosting(), "Keyboard E reaches the shared item-use input")
	key.pressed = false
	Input.parse_input_event(key)
	await _frames(4)
	inventory.receive(preload("res://resources/items/boost.tres"))
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_X
	button.pressed = true
	Input.parse_input_event(button)
	await _frames(4)
	_check(inventory.held == null and player.drift.is_boosting(), "Gamepad west button reaches the same item-use input")
	button.pressed = false
	Input.parse_input_event(button)
	Input.action_release("kart_accelerate")
	player.controls.set_command(0, 1, 0, false)
