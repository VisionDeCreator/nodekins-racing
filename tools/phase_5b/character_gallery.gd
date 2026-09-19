extends Node3D
const CHARACTER: PackedScene = preload("res://scenes/characters/Character.tscn")
const OUT: String = "res://artifacts/phase_5b/"
var people: Array[CharacterAppearance] = []
var heading: Label

func _ready() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("182638")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("b9d7ee")
	world.environment.ambient_light_energy = 0.65
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_energy = 1.7
	light.shadow_enabled = true
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 150, 0)
	fill.light_energy = 0.55
	add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("29394c")
	material.roughness = 1.0
	floor_mesh.material_override = material
	add_child(floor_mesh)
	for index in range(2):
		var person := CHARACTER.instantiate() as CharacterAppearance
		person.look = load("res://resources/characters/default_%s.tres" % ("male" if index == 0 else "female"))
		person.position.x = 0.75 if index == 0 else -0.75
		person.rotation.y = -0.12 if index == 0 else 0.12
		add_child(person)
		people.append(person)
	var camera := Camera3D.new()
	camera.position = Vector3(0.1, 1.65, -4.7)
	add_child(camera)
	camera.look_at(Vector3(0, 0.78, 0))
	camera.fov = 38
	camera.make_current()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	heading = Label.new()
	heading.position = Vector2(42, 24)
	heading.add_theme_font_size_override("font_size", 30)
	heading.text = "NODEKINS  /  CHARACTER STARTER SET"
	canvas.add_child(heading)
	var caption := Label.new()
	caption.position = Vector2(42, 665)
	caption.add_theme_font_size_override("font_size", 19)
	caption.text = "MALE · Outfit 01                       Shared rig · swappable parts                       FEMALE · Outfit 02"
	canvas.add_child(caption)
	_run.call_deferred()

func _shot(filename: String) -> void:
	for tick in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + filename + ".png"))

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	preload("res://tools/phase_5b/character_asset_audit.gd").new().run(self)
	for person: CharacterAppearance in people:
		person.sample_pose(&"Idle", 0.4)
		print("[Character import] ", person.look.body_id, " bones=", person.skeleton.get_bone_count(), " clips=", person.animator.get_animation_list(), " parts=", person.equipped.keys())
	await _shot("default-outfits-idle")
	heading.text = "NODEKINS  /  IDLE + VICTORY"
	people[1].sample_pose(&"Victory", 0.4)
	await _shot("idle-and-victory")
	print("[Character gallery] captured")
