extends ObjectSound3D
func _ready() -> void:
	get_parent().picked_up.connect(func() -> void: trigger(&"pickup",preload("res://assets/audio/pickup.wav")))
