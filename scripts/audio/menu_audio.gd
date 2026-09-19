extends Node
## Persistent players owned by Main's UI, observing its existing screen/focus signals.
@onready var flow: RacingMenuFlow = get_parent() as RacingMenuFlow
var _quiet_focus_until: int = 0
var _last_move_ms: int = 0
var _previous_focus: Control
var _quitting: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	flow.screen_changed.connect(_screen)
	get_viewport().gui_focus_changed.connect(_focus_changed)
	$Result.finished.connect(_stinger_finished)

func _screen(screen: StringName) -> void:
	_quiet_focus_until = Time.get_ticks_msec() + 120
	_previous_focus = null
	for button: BaseButton in flow.get_node("InterfaceLayer/Interface").find_children("*","BaseButton",true,false) if flow.has_node("InterfaceLayer/Interface") else []:
		_wire_button(button)
	# UI containers are constructed by the existing menu, not owned by this adapter.
	for button: Button in flow.buttons.values():
		_wire_button(button)
	if screen in [&"race",&"paused"]:
		$Music.stop()
		$Result.stop()
	elif screen == &"results":
		$Music.stop()
		var position: int = 0
		for result: Dictionary in flow.results:
			if result.id == "player":
				position = int(result.position)
		play_result(position)
	else:
		$Result.stop()
		if not $Music.playing:
			$Music.play()

func _wire_button(button: BaseButton) -> void:
	var callback: Callable = _pressed.bind(StringName(button.name))
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)
	var hover: Callable = _hovered.bind(button)
	if not button.mouse_entered.is_connected(hover):
		button.mouse_entered.connect(hover)

func _pressed(id: StringName) -> void:
	var back: bool = id in [&"back",&"main_menu",&"leave"]
	$Navigation.trigger(&"ui_back" if back else &"ui_select",preload("res://assets/audio/ui_back.wav") if back else preload("res://assets/audio/ui_select.wav"))

func _focus_changed(control: Control) -> void:
	if control == _previous_focus:
		return
	_previous_focus = control
	_move()

func _hovered(button: BaseButton) -> void:
	if not button.disabled:
		_move()

func _move() -> void:
	var now: int = Time.get_ticks_msec()
	if now < _quiet_focus_until or now - _last_move_ms < 65:
		return
	_last_move_ms = now
	$Navigation.trigger(&"ui_move",preload("res://assets/audio/ui_move.wav"))

func _input(event: InputEvent) -> void:
	if not event.is_echo() and event.is_action_pressed("ui_cancel") and flow.current_screen != &"title":
		$Navigation.trigger(&"ui_back",preload("res://assets/audio/ui_back.wav"))

func play_result(position: int) -> void:
	$Result.trigger(&"victory" if position == 1 else &"results",preload("res://assets/audio/victory.wav") if position == 1 else preload("res://assets/audio/results.wav"))

func _stinger_finished() -> void:
	if flow.current_screen == &"results":
		$Music.play()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()

func request_quit(exit_code: int = 0) -> void:
	if _quitting:
		return
	_quitting = true
	AudioPreferences.save()
	for kind: String in ["AudioStreamPlayer","AudioStreamPlayer3D","AudioStreamPlayer2D"]:
		for player: Node in get_tree().root.find_children("*",kind,true,false):
			player.stop()
			player.stream = null
	# AudioServer releases stopped playback on its mixer thread, not the render frame.
	await get_tree().create_timer(.15,true).timeout
	get_tree().quit(exit_code)
