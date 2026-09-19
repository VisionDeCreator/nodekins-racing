class_name CharacterLook
extends Resource
## Compact appearance IDs; paths are resolved locally by the visual catalog.
@export var version: int = 1
@export var body_id: StringName = &"char_body_male"
@export var hair_id: StringName = &"char_hair_01"
@export var shirt_id: StringName = &"char_shirt_01"
@export var pants_id: StringName = &"char_pants_01"
@export var shoes_id: StringName = &"char_shoes_01"
@export var eyes_id: StringName = &"char_eyes_01"
@export var skin_tone_id: StringName = &"warm_02"

func part_ids() -> Array[StringName]:
	return [hair_id, shirt_id, pants_id, shoes_id, eyes_id]
