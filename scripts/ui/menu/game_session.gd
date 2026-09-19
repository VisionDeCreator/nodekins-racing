extends Node
## Menu choices only. RaceManager and inventories remain the sole live race state.
var catalog: MenuCatalog = preload("res://resources/ui/default_catalog.tres")
var selected_character_id: StringName = &"char_body_male"
var selected_track_id: StringName = &"loop_01"

func select_character(id: StringName) -> bool:
	if catalog.driver(id) == null:
		return false
	selected_character_id = id
	return true

func select_track(id: StringName) -> bool:
	if catalog.track(id) == null:
		return false
	selected_track_id = id
	return true

func character() -> DriverEntry:
	return catalog.driver(selected_character_id)

func track() -> RaceTrackEntry:
	return catalog.track(selected_track_id)
