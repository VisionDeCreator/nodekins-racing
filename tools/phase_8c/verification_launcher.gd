extends Node
@export var client_tag: String = "A"
func _ready() -> void:
	Matchmaking.verification = true
	Matchmaking.test_tag = client_tag
	Matchmaking.output = ProjectSettings.globalize_path("res://artifacts/phase8c/rendered")
	get_tree().change_scene_to_file.call_deferred("res://scenes/ui/Main.tscn")
	Matchmaking.start_test.call_deferred()
