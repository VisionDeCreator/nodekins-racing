extends Node3D
## Visual observer only. It never writes kart input, velocity, camera, or glide state.
@export var look: CharacterLook = preload("res://resources/characters/default_male.tres")
@onready var character: CharacterAppearance = $Character
@onready var kart: ArcadeKart = get_parent().get_parent() as ArcadeKart

func _enter_tree() -> void:
	$Character.look = look

func _ready() -> void:
	character.play_pose(&"Drive", 0.0)

func _process(_delta: float) -> void:
	if kart.glide.active:
		# Authored bank poses clear the wing supports while keeping both hands on the rim.
		# Observe the already-smoothed wing angle; never write to the glide component.
		var bank: float = kart.glide.canopy.rotation.z - get_parent().rotation.z
		character.sample_pose(&"GlideLeft" if bank >= 0.0 else &"GlideRight", clampf(absf(bank) / 0.14, 0.0, 1.0))
	elif kart.controls.suppression_remaining > 0.0:
		character.play_pose(&"Hit")
	elif kart.controls.steering < -0.2:
		character.play_pose(&"SteerLeft")
	elif kart.controls.steering > 0.2:
		character.play_pose(&"SteerRight")
	else:
		character.play_pose(&"Drive")

func set_look(value: CharacterLook) -> void:
	look = value
	if is_node_ready():
		character.set_look(value)
		character.play_pose(&"Drive", 0.0)
