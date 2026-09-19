class_name PartsRegistry
extends Resource
@export var display_name: String
@export var slots: Array[CustomizationSlot] = []

func slot(field: StringName) -> CustomizationSlot:
	for category: CustomizationSlot in slots:
		if category.field == field:
			return category
	return null
