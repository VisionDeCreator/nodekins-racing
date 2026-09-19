class_name CustomizationSlot
extends Resource
@export var field: StringName
@export var display_name: String
@export var is_palette: bool = false
@export var sockets: PackedStringArray
@export var entries: Array[CustomizationPart] = []

func entry(id: int) -> CustomizationPart:
	for part: CustomizationPart in entries:
		if part.id == id:
			return part
	return null

func legacy_id(key: StringName) -> int:
	for part: CustomizationPart in entries:
		if part.legacy_key == key:
			return part.id
	return -1
