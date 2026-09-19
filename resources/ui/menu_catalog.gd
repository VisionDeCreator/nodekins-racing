class_name MenuCatalog
extends Resource
@export var drivers: Array[DriverEntry] = []
@export var tracks: Array[RaceTrackEntry] = []

func driver(id: StringName) -> DriverEntry:
	for entry: DriverEntry in drivers:
		if entry.id == id:
			return entry
	return null

func track(id: StringName) -> RaceTrackEntry:
	for entry: RaceTrackEntry in tracks:
		if entry.id == id:
			return entry
	return null
