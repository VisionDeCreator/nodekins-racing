extends CanvasLayer

@export var racer_id: StringName = &"player"
@onready var summary: Label = $Summary/Margin/Rows/Summary
@onready var timing: Label = $Summary/Margin/Rows/Timing
@onready var progress: Label = $Summary/Margin/Rows/Progress
@onready var countdown: Label = $Center/Rows/Countdown
@onready var message: Label = $Center/Rows/Message
@onready var banner: PanelContainer = $Center

func _process(_delta: float) -> void:
	var state: Dictionary = RaceManager.get_racer_state(racer_id)
	if state.is_empty():
		return
	summary.text = "LAP %d / %d    ·    POS %d / %d" % [state.lap, state.total_laps, state.position, state.racer_count]
	timing.text = "TIME  " + _time(float(state.finish_time) if state.finished else float(state.elapsed))
	progress.text = "CP %d → %d    ·    %.0f m progressed" % [state.last_checkpoint, state.next_checkpoint, state.distance_progress]
	countdown.text = RaceManager.countdown_text
	if state.finished:
		countdown.text = "FINISHED"
		message.text = "%s    ·    POSITION %d\nENTER / START TO RACE AGAIN" % [_time(float(state.finish_time)), state.finish_order]
	elif state.respawning:
		countdown.text = "RETURNING"
		message.text = "Checkpoint %d  ·  %.1f s\n%s" % [state.last_checkpoint, state.recovery_remaining, str(state.recovery_reason).to_upper()]
	elif RaceManager.phase == RaceManager.Phase.COUNTDOWN:
		message.text = "GET READY  ·  INPUT LOCKED"
	elif not RaceManager.countdown_text.is_empty():
		message.text = "3 LAPS  ·  PASS EVERY CHECKPOINT"
	elif state.wrong_way:
		message.text = "WRONG WAY  ·  TURN AROUND"
	elif not str(state.notice).is_empty():
		message.text = state.notice
	else:
		message.text = ""
	banner.visible = not countdown.text.is_empty() or not message.text.is_empty()

func _time(seconds: float) -> String:
	return "%02d:%05.2f" % [int(seconds / 60.0), fmod(seconds, 60.0)]
