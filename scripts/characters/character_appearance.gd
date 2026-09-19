class_name CharacterAppearance
extends Node3D
## One skeleton drives either body and every interchangeable appearance mesh.
const BODY_PATHS: Dictionary = {
	&"char_body_male": "res://assets/characters/char_body_male.glb",
	&"char_body_female": "res://assets/characters/char_body_female.glb",
}
const SKIN_TONES: Dictionary = {&"warm_01": Color("b97851"), &"warm_02": Color("e4af82"), &"deep_01": Color("784b38")}
const PARTS_PATH: String = "res://assets/characters/char_appearance_parts.glb"
const SKIN_SHADER: Shader = preload("res://assets/characters/skin_tint.gdshader")
@export var look: CharacterLook = preload("res://resources/characters/default_male.tres")
var skeleton: Skeleton3D
var animator: AnimationPlayer
var body: MeshInstance3D
var equipped: Dictionary = {}
var model: Node3D

func _ready() -> void:
	set_look(look)
	play_pose(&"Idle")

func set_look(value: CharacterLook) -> void:
	look = value
	if not is_inside_tree():
		return
	if not BODY_PATHS.has(look.body_id) or not SKIN_TONES.has(look.skin_tone_id):
		push_error("Unknown character body or skin-tone ID")
		return
	if is_instance_valid(model):
		remove_child(model)
		model.queue_free()
	equipped.clear()
	model = (load(BODY_PATHS[look.body_id]) as PackedScene).instantiate() as Node3D
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	animator = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	body = model.find_child(String(look.body_id), true, false) as MeshInstance3D
	var skin_material := ShaderMaterial.new()
	skin_material.shader = SKIN_SHADER
	skin_material.set_shader_parameter("skin_tone", SKIN_TONES[look.skin_tone_id])
	body.material_override = skin_material
	var library: Node = (load(PARTS_PATH) as PackedScene).instantiate()
	for id: StringName in look.part_ids():
		var source: MeshInstance3D = library.find_child(String(id), true, false) as MeshInstance3D
		if source == null:
			push_error("Unknown character appearance part: " + String(id))
			continue
		var part := MeshInstance3D.new()
		part.name = id
		part.mesh = source.mesh
		part.skin = source.skin
		part.skeleton = NodePath("..")
		skeleton.add_child(part)
		equipped[id] = part
	library.free()
	# Explicit bone attachments remain available for future rigid accessories.
	for index in range(skeleton.get_bone_count()):
		var bone_name: String = skeleton.get_bone_name(index)
		if bone_name.begins_with("socket_"):
			var socket := BoneAttachment3D.new()
			socket.name = bone_name
			socket.bone_name = bone_name
			skeleton.add_child(socket)

func play_pose(pose_name: StringName, blend: float = 0.12) -> void:
	if animator != null and animator.has_animation(pose_name) and animator.current_animation != String(pose_name):
		animator.play(pose_name, blend)

func sample_pose(pose_name: StringName, seconds: float = 0.0) -> void:
	if animator.assigned_animation != String(pose_name):
		animator.play(pose_name, 0.0)
	animator.seek(seconds, true)
	animator.pause()
	skeleton.force_update_all_bone_transforms()
