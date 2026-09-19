extends Node
func _ready() -> void:
	await get_tree().create_timer(.3).timeout
	$App.get_node("MenuAudio").request_quit()
