class_name RaceOverlay
extends Control
signal pause_requested
var kart: ArcadeKart
var inventory: KartInventory
var position_label: Label
var lap_label: Label
var time_label: Label
var item_label: Label
var item_detail: Label
var speed_label: Label
var charge_label: Label
var countdown_label: Label
var notice_label: Label
var minimap: RaceTrackMap
var meter: ProgressBar
var _fill: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_priority = 80

func _panel(at: Vector2, dimensions: Vector2, right: bool = false, bottom: bool = false) -> VBoxContainer:
	var panel := PanelContainer.new()
	add_child(panel)
	panel.add_theme_stylebox_override("panel", RacingUISkin.box(Color(0.035,0.10,0.15,0.94),14,Color("315263"),1))
	if right:
		panel.anchor_left = 1
		panel.anchor_right = 1
	if bottom:
		panel.anchor_top = 1
		panel.anchor_bottom = 1
	panel.offset_left = at.x
	panel.offset_right = at.x + dimensions.x
	panel.offset_top = at.y
	panel.offset_bottom = at.y + dimensions.y
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation",4)
	panel.add_child(rows)
	return rows

func setup(track: Node3D, entry: RaceTrackEntry) -> void:
	kart = track.player
	inventory = track.items.inventories[&"player"]
	var top: VBoxContainer = _panel(Vector2(28,26),Vector2(260,144))
	position_label = RacingUISkin.label("",48,RacingUISkin.CYAN)
	top.add_child(position_label)
	lap_label = RacingUISkin.label("",24)
	top.add_child(lap_label)
	time_label = RacingUISkin.label("",18,RacingUISkin.MUTED)
	top.add_child(time_label)
	var slot: VBoxContainer = _panel(Vector2(-288,26),Vector2(260,154),true)
	slot.add_child(RacingUISkin.label("ITEM   ·   E / X TO USE",14,RacingUISkin.MUTED))
	item_label = RacingUISkin.label("",30)
	slot.add_child(item_label)
	item_detail = RacingUISkin.paragraph("",16)
	item_detail.custom_minimum_size.y = 44
	slot.add_child(item_detail)
	var map_rows: VBoxContainer = _panel(Vector2(-308,-240),Vector2(280,210),true,true)
	map_rows.add_child(RacingUISkin.label(entry.display_name,15,RacingUISkin.MUTED))
	minimap = RaceTrackMap.new()
	minimap.custom_minimum_size = Vector2(234,146)
	minimap.live = true
	map_rows.add_child(minimap)
	minimap.set_route(RaceManager.route,track.glide_section)
	map_rows.add_child(RacingUISkin.label("● YOU     ● CPU RACERS",13,RacingUISkin.CYAN))
	var driving: VBoxContainer = _panel(Vector2(28,-166),Vector2(292,136),false,true)
	speed_label = RacingUISkin.label("",30)
	driving.add_child(speed_label)
	charge_label = RacingUISkin.label("",14,RacingUISkin.CYAN)
	driving.add_child(charge_label)
	meter = ProgressBar.new()
	meter.custom_minimum_size.y = 10
	meter.show_percentage = false
	meter.add_theme_stylebox_override("background",RacingUISkin.box(Color("264a56"),5))
	_fill = RacingUISkin.box(RacingUISkin.CYAN,5)
	meter.add_theme_stylebox_override("fill",_fill)
	driving.add_child(meter)
	var pause := Button.new()
	pause.text = "PAUSE  Ⅱ"
	pause.focus_mode = Control.FOCUS_NONE
	pause.custom_minimum_size = Vector2(140,48)
	add_child(pause)
	pause.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	pause.position = Vector2(size.x*.5-70,26)
	pause.pressed.connect(func() -> void: pause_requested.emit())
	countdown_label = RacingUISkin.label("",100)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(countdown_label)
	countdown_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	countdown_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	countdown_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	countdown_label.offset_left = -340
	countdown_label.offset_right = 340
	countdown_label.offset_top = -104
	countdown_label.offset_bottom = 24
	notice_label = RacingUISkin.label("",23,RacingUISkin.ORANGE)
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(notice_label)
	notice_label.anchor_left = .5
	notice_label.anchor_right = .5
	notice_label.anchor_top = .5
	notice_label.anchor_bottom = .5
	notice_label.offset_left = -470
	notice_label.offset_right = 470
	notice_label.offset_top = 35
	notice_label.offset_bottom = 80
	_process(0)

func _process(_delta: float) -> void:
	if not is_instance_valid(kart):
		return
	var state: Dictionary = RaceManager.get_racer_state(&"player")
	if state.is_empty():
		return
	position_label.text = RacingUISkin.ordinal(int(state.position)) + " / " + str(state.racer_count)
	lap_label.text = "LAP %d / %d" % [state.lap,state.total_laps]
	time_label.text = RacingUISkin.clock_text(float(state.finish_time) if state.finished else float(state.elapsed))
	var held: ItemDefinition = inventory.held
	item_label.text = "EMPTY" if held == null else held.display_name
	item_label.modulate = RacingUISkin.MUTED if held == null else held.color
	item_detail.text = "Collect a cyan item box" if held == null else held.description
	if kart.controls.suppression_remaining > 0:
		item_detail.text = "Spin out! Recovering…"
	speed_label.text = "%d km/h" % roundi(kart.speed * 3.6)
	meter.max_value = kart.stats.mini_turbo_thresholds[2]
	var drift: KartDrift = kart.drift
	if drift.is_boosting():
		charge_label.text = "BOOST ×%.2f   ·   %.1fs" % [drift.boost_multiplier,drift.boost_remaining]
		meter.value = drift.boost_remaining / drift.boost_duration * meter.max_value
		_fill.bg_color = RacingUISkin.CYAN
	elif drift.drifting:
		charge_label.text = "DRIFT   ·   " + ("RELEASE FOR TURBO" if drift.tier > 0 else "KEEP CHARGING")
		meter.value = drift.charge_time
		_fill.bg_color = [RacingUISkin.CYAN,RacingUISkin.CYAN,RacingUISkin.ORANGE,Color("ee74ff")][drift.tier]
	else:
		charge_label.text = "GLIDING" if kart.glide.active else "SPACE / A   ·   HOLD TO DRIFT"
		meter.value = 0
	countdown_label.text = RaceManager.countdown_text
	notice_label.text = ""
	if state.finished:
		countdown_label.text = "FINISHED!"
		notice_label.text = "Waiting for the rest of the field…"
	elif state.respawning:
		countdown_label.text = ""
		notice_label.text = "Returning to the track · %.1fs" % state.recovery_remaining
	elif RaceManager.phase == RaceManager.Phase.COUNTDOWN:
		notice_label.text = "Get ready · %d laps" % RaceManager.total_laps
	elif state.wrong_way:
		notice_label.text = "WRONG WAY · Turn around"
	elif not str(state.notice).is_empty():
		notice_label.text = state.notice
