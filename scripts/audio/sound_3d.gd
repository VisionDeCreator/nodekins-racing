class_name ObjectSound3D
extends AudioStreamPlayer3D
## Object-owned sound source. Diagnostic signal reports playback, never routes gameplay.
signal cue_played(cue: StringName)
@export var base_db: float = -10.0
var last_cue: StringName
func trigger(cue: StringName, clip: AudioStream, pitch: float = 1.0, gain_db: float = 0.0) -> void:
	stream = clip
	pitch_scale = pitch
	volume_db = base_db + gain_db
	last_cue = cue
	play()
	cue_played.emit(cue)
