extends AudioStreamPlayer
## Release the looping playback before scene teardown (including a direct window close).
func _exit_tree() -> void:
	stop()
	stream = null
