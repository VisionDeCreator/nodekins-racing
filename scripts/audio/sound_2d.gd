class_name InterfaceSound
extends AudioStreamPlayer
signal cue_played(cue: StringName)
var last_cue: StringName
func trigger(cue: StringName, clip: AudioStream, pitch: float = 1.0) -> void:
	stream = clip
	pitch_scale = pitch
	last_cue = cue
	play()
	cue_played.emit(cue)
