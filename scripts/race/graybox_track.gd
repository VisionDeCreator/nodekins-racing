extends Node3D
## Builds placeholder boxes from the same centerline used by the race systems.
## Replace this builder with authored track geometry later; RaceManager does not depend on it.

const KART_SCENE: PackedScene = preload("res://scenes/kart/Kart.tscn")
const CPU_TUNING: AITuning = preload("res://resources/ai/default_ai.tres")
@export_range(0, 3) var cpu_count: int = 3
@export var route: TrackRoute
var cpu_drivers: Array[KartAI] = []
@onready var player: ArcadeKart = $Player
var _world: StaticBody3D
var _road_material: StandardMaterial3D
var _wall_material: StandardMaterial3D
var _gate_material: StandardMaterial3D
var _white: StandardMaterial3D
var _dark: StandardMaterial3D

func _ready() -> void:
	route.prepare()
	_build_graybox()
	RaceManager.configure(route, 3)
	if cpu_count > 0:
		player.global_position.x -= 2.7
		player.collision_mask = 3
		player.add_to_group("race_karts")
		_mark_kart(player, "PLAYER", Color("e8edf2"))
	RaceManager.register_kart(player, &"player", "Player")
	_spawn_cpus()
	player.get_node("ChaseCamera/SpringArm3D/Camera3D").make_current()
	RaceManager.start_race()
	$OverviewCamera.look_at(Vector3(0, 4, 0))
	print("[Race] Track ready: %.2f m loop, %d ordered gates, 3 laps, %d racers." % [route.length(), route.checkpoint_indices.size(), cpu_count + 1])

func _spawn_cpus() -> void:
	var lanes: Array[float] = [3.2, -3.2, 0.0]
	var colors: Array[Color] = [Color("ff805e"), Color("83e870"), Color("e3b455")]
	for index in range(cpu_count):
		var cpu: ArcadeKart = KART_SCENE.instantiate() as ArcadeKart
		cpu.name = "CPU%d" % (index + 1)
		var grid_distance: float = 0.0 if index == 0 else -5.0
		var pose: Transform3D = route.sample(grid_distance)
		pose.origin += pose.basis.x * lanes[index] + Vector3.UP * 0.12
		cpu.transform = pose
		cpu.collision_mask = 3
		add_child(cpu)
		cpu.add_to_group("race_karts")
		cpu.get_node("ChaseCamera").set_process(false)
		cpu.get_node("ChaseCamera/SpringArm3D/Camera3D").current = false
		var racer_id := StringName("cpu_%d" % (index + 1))
		RaceManager.register_kart(cpu, racer_id, "CPU %d" % (index + 1))
		var driver := KartAI.new()
		driver.name = "CPUDriver"
		driver.racer_id = racer_id
		driver.tuning = CPU_TUNING
		driver.lane_offset = lanes[index]
		cpu.add_child(driver)
		cpu.get_node("ChaseCamera").set_process(false)
		cpu_drivers.append(driver)
		_mark_kart(cpu, "CPU %d" % (index + 1), colors[index])

func _mark_kart(kart: ArcadeKart, label_text: String, color: Color) -> void:
	# Persistent identity remains readable when the body changes color for drift/boost.
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	kart.get_node("Visuals/Nose").material_override = material
	var label := Label3D.new()
	label.text = label_text
	label.position = Vector3(0, 1.8, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.font_size = 42
	label.outline_size = 10
	label.pixel_size = 0.009
	kart.add_child(label)

func _exit_tree() -> void:
	RaceManager.clear_race()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("race_restart"):
		RaceManager.start_race()
		get_viewport().set_input_as_handled()

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material

func _box(label: String, pose: Transform3D, size: Vector3, material: Material, solid: bool = true) -> void:
	var visual := MeshInstance3D.new()
	visual.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	visual.mesh = mesh
	_world.add_child(visual)
	visual.transform = pose
	if solid:
		var collision := CollisionShape3D.new()
		collision.name = label + "Collision"
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		_world.add_child(collision)
		collision.transform = pose

func _build_graybox() -> void:
	_world = StaticBody3D.new()
	_world.name = "GrayboxRoadAndWalls"
	_world.collision_layer = 1
	_world.collision_mask = 2
	add_child(_world)
	_road_material = _material(Color("4d5660"))
	_wall_material = _material(Color("a5aeb8"))
	_gate_material = _material(Color("55c8d1"))
	_white = _material(Color("e5e9eb"))
	_dark = _material(Color("202830"))
	for index in range(route.points.size()):
		var a: Vector3 = route.points[index]
		var b: Vector3 = route.points[(index + 1) % route.points.size()]
		var road_basis: Basis = Basis.looking_at((b - a).normalized(), Vector3.UP)
		var midpoint: Vector3 = (a + b) * 0.5
		var length: float = a.distance_to(b)
		_box("Road%02d" % index, Transform3D(road_basis, midpoint - Vector3.UP * 0.5), Vector3(route.road_width, 1, length + 0.4), _road_material)
		for side in [-1.0, 1.0]:
			# A short open outer edge on the first straight makes fall recovery testable.
			if side > 0.0 and index >= 4 and index <= 6:
				continue
			var wall_position: Vector3 = midpoint + road_basis.x * side * (route.road_width * 0.5 + 0.2) + Vector3.UP * 0.55
			_box("Wall%02d_%s" % [index, str(side)], Transform3D(road_basis, wall_position), Vector3(0.5, 1.1, length + 0.55), _wall_material)
		# Flat, non-colliding center dashes give a readable forward route and speed reference.
		if index % 2 == 0:
			_box("Dash%02d" % index, Transform3D(road_basis, midpoint + Vector3.UP * 0.015), Vector3(0.16, 0.025, 1.6), _white, false)
	for index in range(route.checkpoint_indices.size()):
		_build_gate(index)

func _build_gate(index: int) -> void:
	var pose: Transform3D = route.checkpoint_transform(index)
	var gate := RaceCheckpoint.new()
	gate.name = "Checkpoint%02d" % index
	gate.checkpoint_index = index
	gate.transform = pose
	var volume := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(route.road_width + 0.8, 4.0, 4.0)
	volume.shape = shape
	volume.position.y = 1.8
	gate.add_child(volume)
	add_child(gate)
	var material: Material = _white if index == 0 else _gate_material
	for side in [-1.0, 1.0]:
		var post: Vector3 = pose.origin + pose.basis.x * side * (route.road_width * 0.5 + 0.4) + Vector3.UP * 2.3
		_box("Gate%dPost%s" % [index, str(side)], Transform3D(pose.basis, post), Vector3(0.3, 4.6, 0.3), material, false)
	_box("Gate%dBeam" % index, Transform3D(pose.basis, pose.origin + Vector3.UP * 4.6), Vector3(route.road_width + 1, 0.25, 0.3), material, false)
	var label := Label3D.new()
	label.text = "START / FINISH" if index == 0 else "CP %02d" % index
	label.font_size = 72
	label.pixel_size = 0.015
	label.outline_size = 14
	label.modulate = Color.WHITE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	gate.add_child(label)
	label.position.y = 5.35
	for column in range(14):
		for row in range(2 if index == 0 else 1):
			var stripe_position: Vector3 = pose.origin + pose.basis.x * (column - 6.5) + pose.basis.z * (row - 0.5) * 0.7 + Vector3.UP * 0.025
			var stripe_material: Material = (_white if (column + row) % 2 == 0 else _dark) if index == 0 else _gate_material
			_box("Gate%dMark%d_%d" % [index, column, row], Transform3D(pose.basis, stripe_position), Vector3(1, 0.035, 0.7), stripe_material, false)
