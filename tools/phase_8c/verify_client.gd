extends Node
## Persistent QA driver: real menu buttons, then 8b's ordinary-input race pilot.
var transitions: Array[Dictionary] = []
var failures: Array[String] = []
var captured_search: bool = false
var captured_race: bool = false
var written: bool = false
var began: float = 0.0
var queued_at: float = -1.0
var canceled_once: bool = false
var previous: String = ""
var finished_at: float = -1.0
var assigned: Dictionary = {}
var completed_rounds: Array[Dictionary] = []
var rejoining: bool = false

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(Matchmaking.output+"/clients")
	GameSession.profile = CustomizationProfile.from_values([1,1,1,1,1,7,1,2,1,1,1,1,4] if Matchmaking.test_tag == "A" else [0,1,0,1,0,4,0,0,2,0,0,0,2])
	get_window().title = "Nodekins Matchmaking — Client "+Matchmaking.test_tag
	get_window().size = Vector2i(800,500)
	get_window().position = Vector2i(10 if Matchmaking.test_tag == "A" else 820,60)
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(.4+Matchmaking.test_delay).timeout
	var flow: RacingMenuFlow = get_tree().current_scene as RacingMenuFlow
	if flow == null:
		failures.append("Main menu missing")
		_report()
		return
	await _press(flow,&"online")
	await _press(flow,&"find_match")

func _press(flow: RacingMenuFlow, id: StringName) -> void:
	flow.buttons[id].grab_focus()
	await get_tree().process_frame
	var event := InputEventAction.new()
	event.action = &"ui_accept"
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = InputEventAction.new()
	event.action = &"ui_accept"
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame

func _process(delta: float) -> void:
	began += delta
	if previous != Matchmaking.state:
		previous = Matchmaking.state
		transitions.append({"state":previous,"seconds":began,"message":Matchmaking.message})
		print("MATCH_QA ",Matchmaking.test_tag," ",previous)
		if previous == "queued":
			queued_at = began
		if not Matchmaking.assignment.is_empty():
			assigned = {"match":Matchmaking.assignment.match,"track":Matchmaking.assignment.track,"port":Matchmaking.assignment.port}
	if Matchmaking.state == "queued" and began-queued_at > .6 and not captured_search:
		captured_search = true
		var flow: RacingMenuFlow = get_tree().current_scene as RacingMenuFlow
		if flow == null or flow.current_screen != &"online" or flow.buttons.has(&"start") or flow.buttons.has(&"loop_01") or not flow.buttons[&"cancel_match"].visible:
			failures.append("Searching UI is missing, cannot cancel, or contains track selection")
		_capture("searching")
	if Matchmaking.state == "queued" and began-queued_at > 1.0 and not canceled_once:
		if Matchmaking.test_scenario in ["cancel","cancel_retry"]:
			canceled_once = true
			_cancel_test()
		elif Matchmaking.test_scenario == "queue_drop":
			canceled_once = true
			Matchmaking.peer.close()
			_report()
			get_tree().current_scene.get_node("MenuAudio").request_quit()
	if Matchmaking.state == "error" and not written:
		var flow: RacingMenuFlow = get_tree().current_scene as RacingMenuFlow
		if flow != null and flow.current_screen == &"online":
			if not flow.buttons[&"find_match"].visible:
				failures.append("Error did not restore retry action")
			_capture("error")
			_report()
	if Matchmaking.state == "in_race":
		if not captured_race and RaceManager.phase == RaceManager.Phase.COUNTDOWN:
			captured_race = true
			_capture("matched")
		if RaceManager.phase == RaceManager.Phase.FINISHED:
			if finished_at < 0:
				finished_at = began
			elif began-finished_at > 4.5 and not written and not rejoining:
				if Matchmaking.test_scenario == "repeat" and completed_rounds.is_empty():
					rejoining = true
					completed_rounds.append({"assignment":assigned.duplicate(),"race":RaceManager.online_snapshot()})
					_repeat.call_deferred()
				else:
					_report()
	if began > 210 and not written:
		failures.append("Timed out")
		_report()

func _repeat() -> void:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().create_timer(.4).timeout
	finished_at = -1
	rejoining = false
	await _run()

func _cancel_test() -> void:
	var flow: RacingMenuFlow = get_tree().current_scene as RacingMenuFlow
	await _press(flow,&"cancel_match")
	if Matchmaking.state != "idle":
		failures.append("Cancel did not reset search")
	if Matchmaking.test_scenario == "cancel_retry":
		await get_tree().create_timer(.6).timeout
		await _press(flow,&"find_match")
	else:
		_report()

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(Matchmaking.output+"/clients/"+Matchmaking.test_tag+"_"+label+".png")

func _report() -> void:
	written = true
	Matchmaking._write_json(Matchmaking.output+"/clients/qa_"+Matchmaking.test_tag+".json",{"failures":failures,"completed_rounds":completed_rounds,"transitions":transitions,"assignment":assigned,"searching":captured_search,"matched":captured_race,"state":Matchmaking.state,"message":Matchmaking.message,"race":RaceManager.online_snapshot()})
	print("MATCH_QA_REPORT ",Matchmaking.test_tag," failures=",failures)
