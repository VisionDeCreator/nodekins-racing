class_name CustomizationProfile
extends Resource
## Wire contract v1: exactly thirteen unsigned byte IDs. No paths, names, colors or stats.
const WIRE_VERSION: int = 1
const FIELDS: Array[StringName] = [&"chassis_id", &"wheel_id", &"spoiler_id", &"glider_id", &"primary_color", &"secondary_color", &"body_type_id", &"hair_id", &"eye_id", &"shirt_id", &"pants_id", &"shoe_id", &"skin_tone_id"]
@export_range(0,255) var chassis_id: int = 0
@export_range(0,255) var wheel_id: int = 0
@export_range(0,255) var spoiler_id: int = 0
@export_range(0,255) var glider_id: int = 0
@export_range(0,255) var primary_color: int = 0
@export_range(0,255) var secondary_color: int = 4
@export_range(0,255) var body_type_id: int = 0
@export_range(0,255) var hair_id: int = 0
@export_range(0,255) var eye_id: int = 0
@export_range(0,255) var shirt_id: int = 0
@export_range(0,255) var pants_id: int = 0
@export_range(0,255) var shoe_id: int = 0
@export_range(0,255) var skin_tone_id: int = 1

func to_values() -> Array[int]:
	var values: Array[int] = []
	for field: StringName in FIELDS:
		values.append(int(get(field)))
	return values

func to_wire() -> PackedByteArray:
	for value: int in to_values():
		if value < 0 or value > 255:
			return PackedByteArray()
	return PackedByteArray(to_values())

func to_dictionary() -> Dictionary:
	var result: Dictionary = {}
	for field: StringName in FIELDS:
		result[String(field)] = int(get(field))
	return result

static func from_values(values: Variant) -> CustomizationProfile:
	if not values is Array and not values is PackedByteArray:
		return null
	if values.size() != FIELDS.size():
		return null
	var result := CustomizationProfile.new()
	for index in range(FIELDS.size()):
		var value: Variant = values[index]
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			return null
		if not is_finite(float(value)) or float(value) != floorf(float(value)) or value < 0 or value > 255:
			return null
		result.set(FIELDS[index],int(value))
	return result
