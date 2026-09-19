class_name CharacterAppearance
extends Node3D
## Shared rest skeleton and named skin bindings fit every registered body and part.
const LIBRARY: CustomizationLibrary = preload("res://resources/customization/library.tres")
@export var look: CharacterLook = preload("res://resources/characters/default_male.tres")
var profile: CustomizationProfile
var skeleton: Skeleton3D
var animator: AnimationPlayer
var body: MeshInstance3D
var equipped: Dictionary = {}
var model: Node3D

func _ready() -> void:
	set_profile(profile if profile != null else LIBRARY.from_legacy(look))
	play_pose(&"Idle")

func set_look(value: CharacterLook) -> void:
	# Compatibility for existing track defaults and art tools, through the same registry.
	look = value
	set_profile(LIBRARY.from_legacy(value))

func set_profile(value: CustomizationProfile) -> void:
	if not LIBRARY.accepts(value):
		return
	profile = value.duplicate() as CustomizationProfile
	look = LIBRARY.legacy_look(profile)
	if not is_inside_tree():
		return
	if is_instance_valid(model):
		remove_child(model)
		model.queue_free()
	equipped.clear()
	var body_definition: CustomizationPart = LIBRARY.part(&"body_type_id",profile.body_type_id)
	model = body_definition.asset.instantiate() as Node3D
	add_child(model)
	skeleton = model.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	animator = model.find_children("*","AnimationPlayer",true,false)[0] as AnimationPlayer
	body = model.find_child(String(body_definition.mesh_name),true,false) as MeshInstance3D
	body.material_override = LIBRARY.make_material(body_definition,profile)
	for slot: CustomizationSlot in LIBRARY.character.slots:
		if slot.is_palette or slot.field == &"body_type_id":
			continue
		var definition: CustomizationPart = slot.entry(int(profile.get(slot.field)))
		var source_root: Node = definition.asset.instantiate()
		var source: MeshInstance3D = source_root.find_child(String(definition.mesh_name),true,false) as MeshInstance3D
		var part := MeshInstance3D.new()
		part.name = definition.mesh_name
		part.mesh = source.mesh
		part.skin = source.skin
		part.transform = source.transform
		part.material_override = LIBRARY.make_material(definition,profile)
		part.skeleton = NodePath("..")
		# Skinned meshes bind to the shared skeleton, not a second bone transform.
		skeleton.add_child(part)
		equipped[definition.legacy_key] = part
		source_root.free()
	for index in range(skeleton.get_bone_count()):
		var bone_name: String = skeleton.get_bone_name(index)
		if bone_name.begins_with("socket_"):
			var socket := BoneAttachment3D.new()
			socket.name = bone_name
			socket.bone_name = bone_name
			skeleton.add_child(socket)

func play_pose(pose_name: StringName, blend: float = 0.12) -> void:
	if animator != null and animator.has_animation(pose_name) and animator.current_animation != String(pose_name):
		animator.play(pose_name,blend)

func sample_pose(pose_name: StringName, seconds: float = 0.0) -> void:
	if animator.assigned_animation != String(pose_name):
		animator.play(pose_name,0.0)
	animator.seek(seconds,true)
	animator.pause()
	skeleton.force_update_all_bone_transforms()
