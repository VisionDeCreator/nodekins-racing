extends Node3D
## Visual-only cover for the proven collision/trigger layout. No physics is created here.
func _ready() -> void:
	var track: Node3D = get_parent()
	track.get_node("GrayboxRoadAndWalls").hide()
	for label: Label3D in track.find_children("*", "Label3D", true, false):
		if label.get_parent() == track or String(label.get_parent().name).begins_with("Checkpoint"):
			label.hide()
	for piece: Node in get_children():
		if piece.get_meta("external_rails", false):
			piece.find_child("RailLeft", true, false).hide()
			piece.find_child("RailRight", true, false).hide()
