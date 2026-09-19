extends SceneTree
func _initialize() -> void:
	for clip_name: String in ["engine_loop","drift_loop","menu_loop","race_loop"]:
		var clip: AudioStreamWAV = load("res://assets/audio/"+clip_name+".wav")
		print(clip_name," mode=",clip.loop_mode," begin=",clip.loop_begin," end=",clip.loop_end," length=",clip.get_length()," format=",clip.format)
	quit()
