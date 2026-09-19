extends Node
## End-to-end UI navigation via real key, joypad and mouse events; AI only drives the race.
const OUTPUT: String = "res://artifacts/phase_6_5/"
@onready var flow: RacingMenuFlow = $App
@export var restart_only: bool = false
var expected: Array[int] = [1,1,1,1,1,7,1,2,1,1,1,1,4]
var audit: Dictionary = {}
var captured_match: bool = false
var captured_glide: bool = false
var capture_busy: bool = false
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

func _enter_tree() -> void:
	GameSession.profile_store.path = "res://artifacts/phase_6_5/restart-profile.json"
	if not restart_only:
		for suffix: String in ["", ".bak", ".tmp"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSession.profile_store.path + suffix))
	GameSession.reload_profile()

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
	if not captured_match and RaceManager.elapsed > 4.0 and not flow.track.player.glide.active:
		captured_match = true
		_capture_kart.call_deferred("customized-on-track")
	if not captured_glide and not capture_busy and flow.track.player.glide.active and flow.track.player.glide.flight_time > 0.3:
		captured_glide = true
		_capture_kart.call_deferred("customized-mid-glide")
	if not captured_hud and inventory.held != null and RaceManager.elapsed > 8.0:
		captured_hud = true
		_capture.call_deferred("race-hud")

func _check(ok: bool, detail: String) -> void:
	checks += 1
	print("[Phase 6.5 check] %s: %s" % ["PASS" if ok else "FAIL",detail])
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
		for _step in range(90):
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

func _screen(expected_screen: StringName) -> bool:
	var ok: bool = flow.current_screen == expected_screen
	_check(ok,"UI transition to " + String(expected_screen))
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

func _capture_kart(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	capture_busy = true
	var previous: Camera3D = get_viewport().get_camera_3d()
	var camera := Camera3D.new()
	flow.track.player.add_child(camera)
	camera.position = Vector3(3.0,2.1,-4.2)
	camera.look_at(flow.track.player.to_global(Vector3(0,.9,0)))
	camera.fov = 46
	camera.current = true
	await _capture(filename)
	previous.current = true
	camera.queue_free()
	capture_busy = false

func _matches(where: String) -> void:
	_check(GameSession.profile.to_values() == expected,where + ": active thirteen IDs match choices")
	if is_instance_valid(flow.preview):
		_check(flow.preview.profile.to_values() == expected and flow.preview.character.profile.to_values() == expected,where + ": preview uses same profile")
	if is_instance_valid(flow.track):
		var visual: Node3D = flow.track.player.get_node("Visuals")
		_check(visual.customization_profile.to_values() == expected and visual.get_node("Rider/Character").profile.to_values() == expected,where + ": kart and rider match")
		_check(visual.body.name == &"kart_chassis_02" and visual.glider_socket.get_child(0).name == &"kart_glider_02",where + ": actual meshes swapped at sockets")
		_check(visual.body.material_override.get_shader_parameter("paint_color") == GameSession.library.tint(GameSession.profile,&"primary_color"),where + ": actual paint shader matches")

func _run() -> void:
	await _frames(12)
	if restart_only:
		_matches("Fresh process title")
		_check(GameSession.profile_store.status == "Saved profile loaded","Startup loads saved disk profile")
		await _capture("restart-title")
		await _activate(&"play","gamepad")
		await _activate(&"continue")
		await _activate(&"start","mouse")
		_matches("Fresh process countdown")
		await _key(KEY_ESCAPE)
		await _activate(&"main_menu","gamepad")
		_finish()
		return
	audit = preload("res://tools/phase_6_5/customization_audit.gd").new().run(self)
	_check(audit.failures.is_empty(),"Registry, wire, save recovery and all-part assembly audit (%d checks)" % audit.checks)
	await _activate(&"play","gamepad")
	await _activate(&"customize_character","mouse")
	if not _screen(&"customize_character"): return
	await _activate(&"body_type_id_next","gamepad")
	await _activate(&"hair_id_next")
	await _activate(&"hair_id_next","mouse")
	await _activate(&"eye_id_next")
	await _activate(&"shirt_id_next","gamepad")
	await _activate(&"pants_id_next")
	await _activate(&"shoe_id_next","mouse")
	await _activate(&"palette_skin_tone_id_4","mouse")
	_check(GameSession.profile.body_type_id == 1 and GameSession.profile.hair_id == 2 and GameSession.profile.skin_tone_id == 4,"Female, mohawk and skin palette selected through UI")
	await _capture("character-customization")
	await _activate(&"switch_customization","gamepad")
	if not _screen(&"customize_kart"): return
	for field: String in ["chassis_id","wheel_id","spoiler_id","glider_id"]:
		await _activate(StringName(field + "_next"),"mouse")
	await _activate(&"palette_primary_color_1","mouse")
	await _activate(&"palette_secondary_color_7","mouse")
	_matches("Kart customization")
	_check(flow.preview.kart_assembly.get_node("socket_glider").visible,"Glider swap automatically shows deployed preview")
	await _capture("kart-customization-glider")
	await _activate(&"toggle_glider","gamepad")
	_check(not flow.preview.kart_assembly.get_node("socket_glider").visible,"Glider hides in driving preview")
	await _capture("kart-customization")
	# Carousel wraps both ways; changing body retains the chosen clothes and hair.
	await _activate(&"chassis_id_next")
	_check(GameSession.profile.chassis_id == 0,"Carousel wraps forward")
	await _activate(&"chassis_id_prev")
	_matches("Carousel wraps backward")
	await _key(KEY_ESCAPE)
	if not _screen(&"characters"): return
	await _activate(&"char_body_male","mouse")
	_check(GameSession.profile.hair_id == 2 and GameSession.profile.shirt_id == 1,"Body selection preserves appearance")
	await _activate(&"char_body_female","gamepad")
	await _activate(&"customize_character")
	_matches("Character customization revisit")
	await _capture("character-customization-final")
	await _activate(&"continue","mouse")
	await _activate(&"start","gamepad")
	_matches("Race countdown")
	var cpu: Node3D = flow.track.get_node("CPU1/Visuals")
	_check(cpu.customization_profile == null,"Player changes leave CPU appearances independent")
	_check(await _wait_results(),"Full customized race reaches results")
	if not _screen(&"results"): return
	_validate_results()
	_matches("Results")
	await _capture("customized-results")
	_check(not hud_mismatch and comparison_frames > 300,"HUD remains synchronized with race and inventory")
	_check(captured_match and captured_glide,"Customized kart seen on road and gliding")
	await _activate(&"main_menu","gamepad")
	_matches("Return title")
	_finish()

func _finish() -> void:
	var file := FileAccess.open(OUTPUT + ("restart-report.json" if restart_only else "customization-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"audit":audit,"profile":GameSession.profile.to_values(),"transitions":transitions,"hud_frames":comparison_frames,"hud_samples":hud_samples,"races":races},"\t"))
	file.close()
	print("[Phase 6.5 verification] %s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,failures])
	if OS.get_cmdline_user_args().has("--phase65-check"):
		get_tree().quit(0 if failures.is_empty() else 1)
