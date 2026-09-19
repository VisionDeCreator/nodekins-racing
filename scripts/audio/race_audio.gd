extends Node
func _ready() -> void:
	RaceManager.countdown_changed.connect(_countdown)
	RaceManager.lap_completed.connect(_lap)
	RaceManager.race_finished.connect(_finished)

func _countdown(text: String) -> void:
	if text == "3":
		$Music.play()
	if text in ["3","2","1"]:
		$Countdown.trigger(StringName("countdown_"+text),preload("res://assets/audio/countdown.wav"),1.0 + (3-int(text))*.12)
	elif text == "GO!":
		$Countdown.trigger(&"go",preload("res://assets/audio/go.wav"))

func _lap(id: StringName, completed: int, _time: float) -> void:
	if id == &"player" and completed < RaceManager.total_laps:
		$Lap.trigger(&"lap",preload("res://assets/audio/lap.wav"),1.0 if completed == 1 else 1.12)

func _finished() -> void:
	$Music.stop()
