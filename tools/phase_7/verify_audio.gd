extends Node
## End-to-end UI navigation via real key, joypad and mouse events; AI only drives the race.
const OUTPUT: String = "res://artifacts/phase_7/"
@onready var flow: RacingMenuFlow = $App
var cues: Array[Dictionary] = []
var item_events: Array[Dictionary] = []
var engine_ranges: Dictionary = {}
var recording: AudioEffectRecord
var record_start_ms: int = 0
var race_cues: Array[Dictionary] = []
var phase_label: String = "flow"
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
	AudioPreferences.path = "res://artifacts/phase_7/audio-test.cfg"
	for index in range(AudioPreferences.BUSES.size()):
		AudioPreferences.set_volume(AudioPreferences.BUSES[index],AudioPreferences.DEFAULTS[index],false)
	get_tree().node_added.connect(_watch_sound)
	_start_recording()

func _start_recording() -> void:
	if DisplayServer.get_name() != "headless":
		record_start_ms = Time.get_ticks_msec()
		recording = AudioEffectRecord.new()
		recording.format = AudioStreamWAV.FORMAT_16_BITS
		AudioServer.add_bus_effect(0,recording)
		recording.set_recording_active(true)

func _watch_sound(node: Node) -> void:
	if node is ObjectSound3D or node is InterfaceSound:
		node.cue_played.connect(_heard.bind(node))

func _heard(cue: StringName, node: Node) -> void:
	var event: Dictionary = {"cue":str(cue),"node":str(node.get_path()),"time":snappedf(RaceManager.elapsed,.001),"stage":phase_label,"recording_seconds":(Time.get_ticks_msec()-record_start_ms)/1000.0,"bus":str(node.bus),"pitch":node.pitch_scale,"playing":node.playing}
	cues.append(event)
	if cue != &"ui_move":
		print("[Audio cue] " + JSON.stringify(event))

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
	track.items.item_event.connect(func(event: Dictionary) -> void: item_events.append(event))
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

	for id: StringName in track.items.inventories:
		var source: ArcadeKart = track.items.inventories[id].kart
		engine_ranges[id] = {"minimum":10.0,"maximum":0.0,"stopped_while_moving":false}
		source.motion_updated.connect(func(_speed: float, _throttle: float, _brake: float) -> void:
			var pitch: float = source.get_node("Audio/Engine").pitch_scale
			if RaceManager.phase == RaceManager.Phase.RACING and _speed > 1.0 and not source.get_node("Audio/Engine").playing:
				engine_ranges[id].stopped_while_moving = true
			engine_ranges[id].minimum = minf(engine_ranges[id].minimum,pitch)
			engine_ranges[id].maximum = maxf(engine_ranges[id].maximum,pitch))

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
	print("[Phase 7 check] %s: %s" % ["PASS" if ok else "FAIL",detail])
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
		for _step in range(80):
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

func _seconds(duration: float) -> void:
	await get_tree().create_timer(duration).timeout

func _slider(bus: StringName, percentage: float, device: String = "mouse") -> void:
	var slider: HSlider = flow.audio_options.sliders[bus]
	if device == "mouse":
		var rect: Rect2 = slider.get_global_rect()
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = Vector2(lerpf(rect.position.x+8,rect.end.x-8,percentage/100),rect.get_center().y)
		event.pressed = true
		get_viewport().push_input(event,true)
		event = event.duplicate()
		event.pressed = false
		get_viewport().push_input(event,true)
	else:
		slider.grab_focus()
		var steps: int = roundi(absf(slider.value-percentage))
		for _i in range(steps):
			if device == "gamepad":
				await _pad(JOY_BUTTON_DPAD_LEFT if slider.value > percentage else JOY_BUTTON_DPAD_RIGHT)
			else:
				await _key(KEY_LEFT if slider.value > percentage else KEY_RIGHT)
	await _frames(3)

func _run() -> void:
	await _frames(12)
	_check(flow.get_node("MenuAudio/Music").playing,"Title music playing on Music bus")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/manifest.json"))
	for clip_name: String in manifest.assets:
		if manifest.assets[clip_name].loop:
			var clip: AudioStreamWAV = load("res://assets/audio/"+clip_name+".wav")
			var stride: int = 4 if clip.stereo else 2
			_check(clip.data.size() == int(manifest.assets[clip_name].file_frames)*stride and clip.data.slice(0,stride) == clip.data.slice(clip.data.size()-stride),"PCM guard frame matches loop start: " + clip_name)
			_check(clip.loop_mode == AudioStreamWAV.LOOP_FORWARD and clip.loop_begin == 0 and clip.loop_end == int(manifest.assets[clip_name].frames),"Exact imported loop region: " + clip_name)
	var music: AudioStreamPlayer = flow.get_node("MenuAudio/Music")
	music.seek(music.stream.get_length()-.08)
	await _seconds(.2)
	_check(music.playing and music.get_playback_position() < .5,"Menu music crosses its loop boundary without stopping")
	await _seconds(.8)
	await _activate(&"options","gamepad")
	_check(flow.current_screen == &"options" and flow.audio_options.sliders.size() == 3,"Options exposes three independent bus sliders")
	await _slider(&"Music",0)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")) and not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")),"Music zero mutes only music")
	await _slider(&"Music",70)
	await _slider(&"SFX",88,"gamepad")
	_check(is_equal_approx(float(AudioPreferences.values[&"SFX"]),.88),"Gamepad adjusts SFX slider")
	await _slider(&"Engine",68,"keyboard")
	_check(is_equal_approx(float(AudioPreferences.values[&"Engine"]),.68),"Keyboard adjusts engine slider")
	await _seconds(.4)
	var saved: Dictionary = AudioPreferences.values.duplicate()
	AudioPreferences.reload_settings()
	_check(saved == AudioPreferences.values,"Volumes survive disk reload")
	await _capture("options-audio")
	await _key(KEY_ESCAPE)
	_check(flow.current_screen == &"title","Options Back returns to title")
	await _activate(&"play")
	await _activate(&"continue")
	await _activate(&"start","gamepad")
	_check(flow.get_node("MenuAudio/Music").playing == false and flow.track.get_node("RaceAudio/Music").playing,"Countdown swaps menu music for track-owned race loop")
	# Pause freezes race-owned audio along with the simulation; UI back still plays.
	await _seconds(.4)
	await _key(KEY_ESCAPE)
	_check(get_tree().paused and not flow.track.get_node("RaceAudio").can_process(),"Pause suspends race audio owners")
	await _seconds(.25)
	await _pad(JOY_BUTTON_B)
	_check(not get_tree().paused and flow.current_screen == &"race","Resume returns to the same race")
	_check(await _wait_results(),"Full audible race reaches results")
	if not _screen(&"results"): return
	_validate_results()
	race_cues.assign(cues.filter(func(e: Dictionary) -> bool: return e.node.contains("ActiveRace")))
	for cue: String in ["engine","drift_start","drift_charge","boost","glide_deploy","glide_land","pickup","item_boost","item_shell","item_banana","spinout","countdown_3","countdown_2","countdown_1","go","lap"]:
		_check(race_cues.any(func(e: Dictionary) -> bool: return e.cue == cue and e.playing),"Real race played " + cue)
	for id: StringName in engine_ranges:
		_check(float(engine_ranges[id].maximum)-float(engine_ranges[id].minimum) > .45 and not engine_ranges[id].stopped_while_moving,"Engine pitch follows speed and throttle for " + str(id))
	for item: String in ["boost","shell","banana"]:
		var uses: int = item_events.filter(func(e: Dictionary) -> bool: return e.kind == "use" and e.item == item).size()
		var sounds: int = race_cues.filter(func(e: Dictionary) -> bool: return e.cue == "item_" + item).size()
		_check(uses > 0 and uses == sounds,"Exactly one use cue per confirmed " + item)
	_check(race_cues.filter(func(e: Dictionary) -> bool: return e.cue == "lap").size() == 2,"Only player lap 1 and 2 chime; final lap uses result cue")
	_check(cues.any(func(e: Dictionary) -> bool: return e.cue == "results"),"Third-place finish selects neutral results jingle")
	_check(not flow.track.get_node("RaceAudio/Music").playing,"Race music stops at results")
	await _seconds(2.0)
	_check(flow.get_node("MenuAudio/Music").playing,"Menu music resumes after results jingle")
	await _activate(&"main_menu","gamepad")
	_stop_recording("full-flow-mix")
	phase_label = "supplementary_lab"
	_start_recording()
	await _lab()
	_stop_recording("mechanic-audition")
	_check(not hud_mismatch and comparison_frames > 300,"HUD and live gameplay data still match")
	for cue: String in ["ui_move","ui_select","ui_back"]:
		_check(cues.any(func(e: Dictionary) -> bool: return e.cue == cue),"UI cue " + cue)
	_finish()

func _stop_recording(filename: String) -> void:
	if recording == null:
		return
	recording.set_recording_active(false)
	var stream: AudioStreamWAV = recording.get_recording()
	_check(stream != null and stream.data.size() > 44100,"Captured nonempty mixer PCM")
	if stream != null:
		stream.save_to_wav(ProjectSettings.globalize_path(OUTPUT+filename+".wav"))
	AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	recording = null

func _lab() -> void:
	# Physical edge cases supplement the untouched full race above.
	flow.get_node("MenuAudio/Music").stop()
	flow.get_node("InterfaceLayer").hide()
	var lab := Node3D.new()
	lab.name = "AudioLab"
	add_child(lab)
	var floor_body := StaticBody3D.new()
	lab.add_child(floor_body)
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200,1,200)
	floor_shape.shape = box
	floor_shape.position.y = -.5
	floor_body.add_child(floor_shape)
	var subject: ArcadeKart = preload("res://scenes/kart/Kart.tscn").instantiate()
	subject.name = "AuditionKart"
	subject.position.y = .2
	lab.add_child(subject)
	subject.controls.set_command(1,0,0,false)
	await _seconds(1.7)
	subject.controls.set_command(1,0,.65,true)
	await _seconds(3.5)
	for tier in range(1,4):
		_check(cues.any(func(e: Dictionary) -> bool: return e.stage == "supplementary_lab" and e.cue == "drift_tier_%d" % tier),"Physical drift reaches audible tier %d" % tier)
	subject.controls.set_command(1,0,0,false)
	await _frames(5)
	_check(not subject.get_node("Audio/Charge").playing and subject.get_node("Audio/Boost").playing,"Releasing charged drift stops loop and plays boost")
	subject.controls.set_command(0,1,0,false)
	var wall := StaticBody3D.new()
	lab.add_child(wall)
	var shape := CollisionShape3D.new()
	box = BoxShape3D.new()
	box.size = Vector3(8,3,1)
	shape.shape = box
	shape.position = Vector3(0,1.5,-9)
	wall.add_child(shape)
	subject.respawn_at(Transform3D(Basis.IDENTITY,Vector3(0,.2,0)))
	subject.controls.set_command(1,0,0,false)
	await _seconds(2.0)
	var impacts: int = cues.filter(func(e: Dictionary) -> bool: return e.stage == "supplementary_lab" and e.cue == "impact").size()
	_check(impacts == 1,"Physical wall hit sounds once; sustained wall push does not chatter")
	subject.controls.set_command(0,1,0,false)
	wall.queue_free()
	await _frames(3)
	var target: ArcadeKart = preload("res://scenes/kart/Kart.tscn").instantiate()
	target.name = "StationaryKart"
	target.position = Vector3(0,.2,-9)
	target.collision_mask = 3
	lab.add_child(target)
	target.controls.set_command(0,1,0,false)
	subject.get_node("ChaseCamera/SpringArm3D/Camera3D").make_current()
	subject.collision_mask = 3
	subject.respawn_at(Transform3D(Basis.IDENTITY,Vector3(0,.2,0)))
	subject.controls.set_command(1,0,0,false)
	await _seconds(1.7)
	_check(cues.filter(func(e: Dictionary) -> bool: return e.stage == "supplementary_lab" and e.cue == "impact" and e.node.contains("AuditionKart")).size() > impacts,"Physical kart-to-kart hit emits impact cue")
	lab.queue_free()
	await _frames(4)
	flow.get_node("MenuAudio").play_result(1)
	_check(flow.get_node("MenuAudio/Result").last_cue == &"victory" and flow.get_node("MenuAudio/Result").playing,"First-place branch plays victory stinger (supplementary audition)")
	await _seconds(2.5)
	flow.get_node("InterfaceLayer").show()
	flow.show_title()

func _finish() -> void:
	var report: Dictionary = {"checks":checks,"failures":failures,"cues":cues,"engine_ranges":engine_ranges,"races":races,"hud_frames":comparison_frames,"volumes":AudioPreferences.values,"item_events":item_events}
	var file := FileAccess.open(OUTPUT+"audio-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("[Phase 7 verification] %s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,failures])
	if OS.get_cmdline_user_args().has("--phase7-check"):
		flow.get_node("MenuAudio").request_quit(0 if failures.is_empty() else 1)
