class_name OnlineRaceWorld
extends Node3D
## Reuses the actual Track scene, collision shapes, art, item boxes and boost-pad row.
var server: bool = false
var track: Node3D
var items: RaceItems
var launch: GlideLaunch
var karts: Dictionary = {}
var actor_views: Dictionary = {}

func _ready() -> void:
	track = preload("res://scenes/track/Track.tscn").instantiate()
	track.external_race_management = true
	add_child(track)
	for child_name: String in ["DrivingHUD","RaceHUD","RaceAudio","Player"]:
		track.get_node(child_name).free()
	track.set_process_unhandled_input(false)
	RaceManager.set_replica_mode(not server)
	if server:
		RaceManager.configure(track.route,3)
	else:
		RaceManager.route = track.route
	launch = track.get_node("GlideLaunch") as GlideLaunch
	launch.set_physics_process(false)
	# Replay uses a swept center-plane test against this exact authored launch volume.
	items = RaceItems.new()
	items.name = "OnlineItems"
	items.random_seed = 445
	items.row_distances = PackedFloat32Array([64.0,145.0,201.0,317.0])
	track.add_child(items)
	items.place_boxes(track.route)
	track.add_child(preload("res://scenes/track/BoostPadRow.tscn").instantiate())
	track.add_child(preload("res://scenes/track/Loop01Art.tscn").instantiate())
	if not server:
		for node: Node in track.find_children("*","Area3D",true,false):
			node.set_physics_process(false)
			node.set_deferred("monitoring",false)

func add_kart(id: String, slot: int, wire: PackedByteArray, cpu: bool) -> ArcadeKart:
	var kart: ArcadeKart = preload("res://scenes/kart/Kart.tscn").instantiate() as ArcadeKart
	kart.name = id
	kart.network_driven = true
	kart.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var lanes: Array[float] = [-2.7,3.2,-3.2,0.0]
	var pose: Transform3D = track.route.sample(0.0 if slot < 2 else -5.0)
	pose.origin += pose.basis.x*lanes[slot]+Vector3.UP*.12
	kart.transform = pose
	# Dynamic contacts are official on the server. Prediction replays static track contacts.
	kart.collision_mask = 3 if server else 1
	add_child(kart)
	kart.add_to_group("race_karts")
	kart.controls.set_command(0,1,0,false)
	kart.controls.set_locked(true)
	kart.get_node("ChaseCamera").set_process(false)
	kart.get_node("ChaseCamera/SpringArm3D/Camera3D").current = false
	var profile: CustomizationProfile = CustomizationProfile.from_values(wire)
	kart.get_node("Visuals").apply_profile(profile)
	items.attach(kart,StringName(id),cpu and server)
	items.inventories[StringName(id)].replica_mode = not server
	karts[id] = kart
	if server:
		RaceManager.register_kart(kart,StringName(id),id.replace("_"," ").capitalize())
	else:
		kart.recovery_requested.connect(func(_reason: String) -> void: pass)
		# Every one-shot online sound comes from a deduplicated authoritative event.
		kart.network_mute_signals(true)
	return kart

func simulate(kart: ArcadeKart, command: PackedFloat32Array, mute: bool = false) -> void:
	kart.network_mute_signals(mute)
	kart.controls.set_command(command[0],command[1],command[2],command[3] > .5,command[4] > .5)
	if server and command[5] > .5:
		kart.controls.request_item_use()
	var before: Vector3 = kart.global_position
	kart.simulate_step(1.0/60.0)
	if RaceManager.phase == RaceManager.Phase.RACING:
		var previous: Vector3 = launch.to_local(before)
		var current: Vector3 = launch.to_local(kart.global_position)
		var shape: BoxShape3D = launch.get_child(0).shape
		var center: Vector3 = launch.get_child(0).position
		if previous.z > 0 and current.z <= 0 and before.distance_to(kart.global_position) < 5.0 and absf(current.x-center.x) <= shape.size.x*.5 and absf(current.y-center.y) <= shape.size.y*.5:
			kart.glide.try_launch()

func remove_kart(id: String) -> void:
	if not karts.has(id):
		return
	var kart: ArcadeKart = karts[id]
	if server:
		for actor: Node in items.get_children():
			if actor is DeployedItem and actor.inventory == items.inventories.get(StringName(id)):
				actor.queue_free()
		RaceManager.unregister_kart(StringName(id))
	items.inventories.erase(StringName(id))
	kart.collision_layer = 0
	kart.collision_mask = 0
	kart.queue_free()
	karts.erase(id)

func item_definition(id: String) -> ItemDefinition:
	for item: ItemDefinition in items.catalog:
		if str(item.id) == id:
			return item
	return null

func item_snapshot() -> Dictionary:
	var inventories: Dictionary = {}
	for id: StringName in items.inventories:
		var inv: KartInventory = items.inventories[id]
		inventories[str(id)] = [str(inv.held.id) if inv.held != null else "",inv.held_seconds,inv.immunity_remaining]
	var boxes := PackedFloat32Array()
	for box: ItemBox in items.boxes:
		boxes.append(box.cooldown)
	var actors: Array[Dictionary] = []
	for actor: Node in items.get_children():
		if actor is DeployedItem and not actor.spent and not actor.is_queued_for_deletion():
			actors.append({"id":actor.get_instance_id(),"item":str(actor.definition.id),"pose":actor.global_transform})
	return {"inventories":inventories,"boxes":boxes,"actors":actors}

func apply_items(state: Dictionary) -> void:
	for id: String in state.inventories:
		if items.inventories.has(StringName(id)):
			var values: Array = state.inventories[id]
			items.inventories[StringName(id)].network_apply(item_definition(values[0]),values[1],values[2])
	for index in range(mini(items.boxes.size(),state.boxes.size())):
		items.boxes[index].cooldown = state.boxes[index]
		items.boxes[index].visual.visible = state.boxes[index] <= 0
	var present: Dictionary = {}
	for row: Dictionary in state.actors:
		present[row.id] = true
		if not actor_views.has(row.id):
			var definition: ItemDefinition = item_definition(row.item)
			var effect := definition.effect as DeployItemEffect
			var visual: Node3D = effect.actor_scene.instantiate()
			visual.set_script(null) # Mesh-only replica; no shapecast, hit logic or local lifetime.
			add_child(visual)
			actor_views[row.id] = visual
		actor_views[row.id].global_transform = row.pose
	for id: int in actor_views.keys():
		if not present.has(id):
			actor_views[id].queue_free()
			actor_views.erase(id)
