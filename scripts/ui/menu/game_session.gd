extends Node
## Menu choices only. RaceManager and inventories remain the sole live race state.
var catalog: MenuCatalog = preload("res://resources/ui/default_catalog.tres")
var selected_character_id: StringName = &"char_body_male"
var selected_track_id: StringName = &"loop_01"
var library: CustomizationLibrary = preload("res://resources/customization/library.tres")
var profile: CustomizationProfile
var profile_store := CustomizationProfileStore.new()
signal profile_changed(profile: CustomizationProfile)

func _ready() -> void:
	reload_profile()

func reload_profile() -> void:
	profile = profile_store.load_profile(library)
	selected_character_id = library.part(&"body_type_id",profile.body_type_id).legacy_key
	profile_changed.emit(profile)

func change_part(field: StringName, id: int) -> bool:
	if library.part(field,id) == null:
		return false
	var candidate := profile.duplicate() as CustomizationProfile
	candidate.set(field,id)
	if not profile_store.save_profile(candidate,library):
		return false
	profile = candidate
	selected_character_id = library.part(&"body_type_id",profile.body_type_id).legacy_key
	profile_changed.emit(profile)
	return true

func driver_name() -> String:
	return library.part(&"body_type_id",profile.body_type_id).display_name

func select_character(id: StringName) -> bool:
	var body_id: int = library.slot(&"body_type_id").legacy_id(id)
	return change_part(&"body_type_id",body_id)

func select_track(id: StringName) -> bool:
	if catalog.track(id) == null:
		return false
	selected_track_id = id
	return true

func character() -> DriverEntry:
	return catalog.driver(selected_character_id)

func track() -> RaceTrackEntry:
	return catalog.track(selected_track_id)
