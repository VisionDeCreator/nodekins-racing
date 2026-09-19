extends Node
func _ready() -> void:
	call_deferred("_capture")
func _capture() -> void:
	var snapshot: Dictionary = preload("res://tools/phase_5c/track_snapshot.gd").capture($Track)
	var file := FileAccess.open("res://artifacts/phase_5c/physics-baseline.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshot, "\t"))
	print("[Phase 5c baseline] shapes=%d areas=%d points=%d" % [snapshot.collisions.size(), snapshot.areas.size(), snapshot.route_points.size()])
