class_name DriverPreview
extends SubViewportContainer
## Isolated display world: original art and animation, no kart controller or race registration.
var viewport: SubViewport
var pivot: Node3D
var character: CharacterAppearance
var camera: Camera3D
var kart_assembly: Node3D
var fitted_parts: Dictionary = {}
var profile: CustomizationProfile
var _time: float = 0.0
var _base_yaw: float = -0.25

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport = SubViewport.new()
	viewport.size = Vector2i(600, 520)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d9efff")
	environment.ambient_light_energy = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	world.add_child(environment_node)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40,-30,0)
	key.light_energy = 1.3
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20,140,0)
	fill.light_color = Color("78d7ff")
	fill.light_energy = 0.7
	world.add_child(fill)
	pivot = Node3D.new()
	world.add_child(pivot)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true

func show_driver(look: CharacterLook, seated: bool = false, pose: StringName = &"Idle") -> void:
	show_profile(CharacterAppearance.LIBRARY.from_legacy(look),seated,pose)

func show_profile(value: CustomizationProfile, seated: bool = false, pose: StringName = &"Idle", deployed: bool = false) -> void:
	profile = value.duplicate() as CustomizationProfile
	kart_assembly = null
	fitted_parts.clear()
	for child: Node in pivot.get_children():
		pivot.remove_child(child)
		child.queue_free()
	character = preload("res://scenes/characters/Character.tscn").instantiate() as CharacterAppearance
	character.profile = profile
	pivot.add_child(character)
	character.play_pose(&"Drive" if seated else pose, 0.0)
	if seated:
		var kart: Node3D = preload("res://assets/karts/kart_01.glb").instantiate()
		pivot.add_child(kart)
		kart_assembly = kart.get_node("kart_01")
		fitted_parts = KartPartsAssembler.apply(kart_assembly,profile)
		kart_assembly.get_node("socket_glider").visible = deployed
		camera.size = 4.2 if deployed else 3.5
		camera.position = Vector3(2.7,2.3 if deployed else 1.8,-4)
		camera.look_at(Vector3(0,1.0 if deployed else 0.6,0))
	else:
		camera.size = 2.15
		camera.position = Vector3(0.9,1.12,-4)
		camera.look_at(Vector3(0,0.77,0))
	_time = 0.0

func _process(delta: float) -> void:
	_time += delta
	if pivot != null:
		pivot.rotation.y = _base_yaw + sin(_time * 0.5) * 0.22
