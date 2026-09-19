extends Node
## End-to-end UI navigation via real key, joypad and mouse events; AI only drives the race.
const OUTPUT: String = "res://artifacts/phase_6/"
@onready var flow: RacingMenuFlow = $App
var checks: int = 0
var failures: PackedStringArray = []
var transitions: Array[String] = []
var hud_samples: Array[Dictionary] = []
var races: Array[Dictionary] = []
var comparison_frames: int = 0
var hud_mismatch: bool = false
var last_sample: float = -10
var captured_hud: bool = false
var race_number: int = 0
var gate_counts: Dictionary = {}
var glide_counts: Dictionary = {}
var recoveries: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	flow.screen_changed.connect(func(screen: StringName) -> void: transitions.append(String(screen)))
	flow.race_loaded.connect(_race_loaded)
	RaceManager.checkpoint_passed.connect(func(id: StringName, _gate: int) -> void: gate_counts[id] = int(gate_counts.get(id,0)) + 1)
	RaceManager.recovery_started.connect(func(id: StringName, cp: int, reason: String) -> void: recoveries.append({"id":str(id),"checkpoint":cp,"reason":reason}))
	_run.call_deferred()

func _race_loaded(track: Node3D) -> void:
	race_number += 1
	gate_counts.clear()
	glide_counts.clear()
	recoveries.clear()
	last_sample = -10
	var pilot := KartAI.new()
	pilot.name = "QAPlayerPilot"
	pilot.racer_id = &"player"
	pilot.tuning = preload("res://resources/ai/default_ai.tres")
	pilot.lane_offset = -1.5
	pilot.apply_rubber_band = false
	track.player.add_child(pilot)
	track.items.inventories[&"player"].cpu_controlled = true
	for id: StringName in track.items.inventories:
		var inventory: KartInventory = track.items.inventories[id]
		inventory.kart.glide.ended.connect(func(flight: Dictionary) -> void:
			if flight.reason == "landed":
				glide_counts[id] = int(glide_counts.get(id,0)) + 1)

func _process(_delta: float) -> void:
	if flow.current_screen != &"race" or not is_instance_valid(flow.hud):
		return
	var state: Dictionary = RaceManager.get_racer_state(&"player")
	if state.is_empty():
		return
	var inventory: KartInventory = flow.track.items.inventories[&"player"]
	var expected_item: String = "EMPTY" if inventory.held == null else inventory.held.display_name
	var expected_position: String = RacingUISkin.ordinal(int(state.position)) + " / " + str(state.racer_count)
	comparison_frames += 1
	if flow.hud.lap_label.text != "LAP %d / %d" % [state.lap,state.total_laps] or flow.hud.position_label.text != expected_position or flow.hud.item_label.text != expected_item:
		hud_mismatch = true
	if RaceManager.phase != RaceManager.Phase.RACING:
		return
	if RaceManager.elapsed - last_sample > 10:
		last_sample = RaceManager.elapsed
		var sample: Dictionary = {"race":race_number,"time":RaceManager.elapsed,"lap":state.lap,"position":state.position,"item":expected_item,"last_checkpoint":state.last_checkpoint,"progress":state.distance_progress,"map_markers":flow.hud.minimap.marker_positions.size()}
		hud_samples.append(sample)
		print("[UI HUD sample] " + JSON.stringify(sample))
	if not captured_hud and inventory.held != null and RaceManager.elapsed > 8.0:
		captured_hud = true
		_capture.call_deferred("race-hud")

func _check(ok: bool, detail: String) -> void:
	checks += 1
	print("[Phase 6 check] %s: %s" % ["PASS" if ok else "FAIL",detail])
	if not ok:
		failures.append(detail)

func _frames(count: int = 4) -> void:
	for _i in range(count):
		await get_tree().process_frame

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(3)

func _pad(code: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = code
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(3)

func _activate(id: StringName, device: String = "keyboard") -> void:
	await _frames()
	if not flow.buttons.has(id):
		_check(false,"Missing UI target " + String(id))
		return
	var target: Button = flow.buttons[id]
	if device == "mouse":
		var motion := InputEventMouseMotion.new()
		motion.position = target.get_global_rect().get_center()
		motion.global_position = motion.position
		# Control rectangles are viewport-local, already adjusted for window stretching.
		get_viewport().push_input(motion, true)
		for down: bool in [true,false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = down
			event.position = motion.position
			event.global_position = motion.position
			get_viewport().push_input(event, true)
			await _frames(2)
	else:
		for _step in range(24):
			if get_viewport().gui_get_focus_owner() == target:
				break
			if device == "gamepad":
				await _pad(JOY_BUTTON_DPAD_DOWN)
			else:
				await _key(KEY_TAB)
		_check(get_viewport().gui_get_focus_owner() == target,"Focus reaches " + String(id) + " via " + device)
		if device == "gamepad":
			await _pad(JOY_BUTTON_A)
		else:
			await _key(KEY_ENTER)
	await _frames(5)

func _screen(expected: StringName) -> bool:
	var ok: bool = flow.current_screen == expected
	_check(ok,"UI transition to " + String(expected))
	if not ok:
		_finish()
	return ok

func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + filename + ".png")) == OK,"Captured " + filename)

func _wait_results() -> bool:
	for _tick in range(150 * 60):
		if flow.current_screen == &"results":
			await _frames(4)
			return true
		await get_tree().physics_frame
	return false

func _validate_results() -> void:
	var authoritative: Array[Dictionary] = RaceManager.get_standings()
	_check(flow.results == authoritative and authoritative.size() == 4,"Results use all four authoritative RaceManager standings")
	for state: Dictionary in authoritative:
		var row: Dictionary = flow.result_rows[state.id]
		_check(row.place.text == RacingUISkin.ordinal(int(state.position)) and row.time.text == RacingUISkin.clock_text(float(state.finish_time)) and state.finished and state.completed_laps == 3,"Correct final position/time for " + str(state.name))
		_check(int(gate_counts.get(state.id,0)) == 24 and int(glide_counts.get(state.id,0)) == 3,"Three physical laps and glide landings for " + str(state.name))
	_check(recoveries.is_empty(),"Full UI race requires no recovery")
	races.append({"character_id":str(GameSession.selected_character_id),"results":authoritative,"gate_counts":gate_counts.duplicate(),"glide_counts":glide_counts.duplicate(),"recoveries":recoveries.duplicate()})

func _run() -> void:
	await _frames(12)
	if not _screen(&"title"): return
	_check(RaceManager.phase == RaceManager.Phase.IDLE and RaceManager.get_standings().is_empty(),"Title preview creates no race or registered kart")
	await _capture("title-screen")
	await _activate(&"options","gamepad")
	if not _screen(&"options"): return
	await _capture("options")
	await _pad(JOY_BUTTON_B)
	if not _screen(&"title"): return
	await _activate(&"play")
	if not _screen(&"characters"): return
	await _activate(&"char_body_female","gamepad")
	_check(GameSession.selected_character_id == &"char_body_female" and flow.preview.character.look.body_id == &"char_body_female","Gamepad selects female and updates the live 3D model")
	var before: float = flow.preview.character.animator.current_animation_position
	await _frames(12)
	_check(flow.preview.character.animator.is_playing() and flow.preview.character.animator.current_animation_position != before,"Character preview runs live skeletal animation")
	await _capture("character-select-female")
	await _activate(&"continue")
	if not _screen(&"tracks"): return
	_check(flow.buttons.has(&"loop_01") and GameSession.selected_track_id == &"loop_01","Track list resolves the selected stable catalog ID")
	await _key(KEY_ESCAPE)
	if not _screen(&"characters"): return
	_check(GameSession.selected_character_id == &"char_body_female" and flow.buttons[&"char_body_female"].button_pressed,"Back navigation retains the selected driver")
	await _activate(&"continue")
	await _capture("track-select")
	await _activate(&"start","mouse")
	if not _screen(&"race"): return
	_check(RaceManager.phase == RaceManager.Phase.COUNTDOWN and flow.track.player.controls.is_locked(),"UI start enters the real input-locked countdown")
	_check(flow.track.player.get_node("Visuals/Rider").look.body_id == &"char_body_female","Selected female default is applied to the actual racer")
	await _capture("countdown")
	await _pad(JOY_BUTTON_START)
	if not _screen(&"paused"): return
	var paused_time: float = RaceManager.elapsed
	var paused_countdown: String = RaceManager.countdown_text
	var paused_position: Vector3 = flow.track.player.global_position
	await _frames(30)
	_check(get_tree().paused and RaceManager.elapsed == paused_time and RaceManager.countdown_text == paused_countdown and flow.track.player.global_position == paused_position,"Pause freezes countdown, timer and kart physics")
	await _capture("pause-menu")
	await _activate(&"resume","gamepad")
	if not _screen(&"race"): return
	_check(not get_tree().paused and flow.track.player.controls.is_locked(),"Resume preserves the countdown lock")
	_check(await _wait_results(),"First race reaches Results entirely through the UI")
	if not _screen(&"results"): return
	_validate_results()
	await _capture("results-screen")
	await _activate(&"race_again")
	if not _screen(&"tracks"): return
	_check(RaceManager.phase == RaceManager.Phase.IDLE and RaceManager.get_standings().is_empty() and not is_instance_valid(flow.track),"Race Again clears the completed race and returns to track select")
	await _activate(&"back")
	await _activate(&"char_body_male","mouse")
	_check(GameSession.selected_character_id == &"char_body_male","Mouse selects the other default driver")
	await _capture("character-select-male")
	await _activate(&"continue","gamepad")
	await _activate(&"start","gamepad")
	if not _screen(&"race"): return
	_check(RaceManager.elapsed == 0 and RaceManager.get_standings().size() == 4 and flow.track.items.inventories[&"player"].held == null,"Second race starts fresh with four racers and an empty inventory")
	_check(flow.track.player.get_node("Visuals/Rider").look.body_id == &"char_body_male","Selected male default reaches the second race")
	for _tick in range(12 * 60):
		if RaceManager.elapsed >= 5.0:
			break
		await get_tree().physics_frame
	await _key(KEY_ESCAPE)
	if not _screen(&"paused"): return
	var race_pause_time: float = RaceManager.elapsed
	var race_pause_position: Vector3 = flow.track.player.global_position
	await _frames(30)
	_check(race_pause_time > 0 and RaceManager.elapsed == race_pause_time and flow.track.player.global_position == race_pause_position,"Mid-race pause freezes the live timer and moving kart")
	await _pad(JOY_BUTTON_B)
	_check(flow.current_screen == &"race" and not get_tree().paused,"Gamepad Back resumes the in-progress race")
	_check(await _wait_results(),"Second complete race reaches Results without stale state")
	if not _screen(&"results"): return
	_validate_results()
	await _activate(&"main_menu","gamepad")
	if not _screen(&"title"): return
	_check(RaceManager.phase == RaceManager.Phase.IDLE and RaceManager.get_standings().is_empty(),"Results Main Menu releases the race and returns to Title")
	_check(comparison_frames > 300 and not hud_mismatch,"Visible lap/position/item labels match live state across %d frames" % comparison_frames)
	_check(captured_hud and hud_samples.any(func(sample: Dictionary) -> bool: return sample.map_markers == 4),"Mid-race item HUD is captured and all four minimap markers are live")
	# Also cover leaving an unfinished race and the title/selection back paths.
	await _activate(&"play")
	await _key(KEY_ESCAPE)
	_check(flow.current_screen == &"title","Character-select Back returns to Title")
	await _activate(&"play")
	await _activate(&"continue")
	await _activate(&"start")
	await _key(KEY_ESCAPE)
	await _activate(&"leave")
	_check(flow.current_screen == &"tracks" and RaceManager.get_standings().is_empty() and not get_tree().paused,"Leaving a paused race safely returns to track select")
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	_check(flow.current_screen == &"title","Final navigation returns to a stable title screen")
	_finish()

func _finish() -> void:
	var file := FileAccess.open(OUTPUT + "ui-flow-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"transitions":transitions,"hud_frames":comparison_frames,"hud_samples":hud_samples,"races":races},"\t"))
	print("[Phase 6 verification] %s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,failures])
	if OS.get_cmdline_user_args().has("--phase6-check"):
		get_tree().quit(0 if failures.is_empty() else 1)
