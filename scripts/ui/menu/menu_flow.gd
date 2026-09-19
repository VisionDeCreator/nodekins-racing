class_name RacingMenuFlow
extends Node
signal screen_changed(screen: StringName)
signal race_loaded(track: Node3D)
@export var race_random_seed: int = 0
var current_screen: StringName = &""
var track: Node3D
var hud: RaceOverlay
var preview: DriverPreview
var results: Array[Dictionary] = []
var buttons: Dictionary = {}
var result_rows: Dictionary = {}
var _button_order: Array[Button] = []
var _canvas: CanvasLayer
var _ui: Control
var _page: VBoxContainer
var _body: HBoxContainer
var _description: Label
var _preview_name: Label
var _features: Label
var _map: RaceTrackMap
var _changing: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = CanvasLayer.new()
	_canvas.layer = 20
	add_child(_canvas)
	_ui = Control.new()
	_ui.name = "Interface"
	_ui.theme = RacingUISkin.make_theme()
	_canvas.add_child(_ui)
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	RaceManager.race_finished.connect(_race_finished)
	show_title()

func _clear_ui() -> void:
	for child: Node in _ui.get_children():
		_ui.remove_child(child)
		child.queue_free()
	buttons.clear()
	_button_order.clear()
	result_rows.clear()
	preview = null
	hud = null

func _set_screen(value: StringName) -> void:
	current_screen = value
	print("[UI] screen=" + String(value) + " character=" + String(GameSession.selected_character_id) + " track=" + String(GameSession.selected_track_id))
	screen_changed.emit(value)

func _shell(kicker: String, heading: String, subtitle: String) -> void:
	_clear_ui()
	var backdrop := Control.new()
	backdrop.set_script(preload("res://scripts/ui/menu/menu_backdrop.gd"))
	_ui.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margins := MarginContainer.new()
	_ui.add_child(margins)
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left","right"]:
		margins.add_theme_constant_override("margin_"+edge,48)
	for edge: String in ["top","bottom"]:
		margins.add_theme_constant_override("margin_"+edge,34)
	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation",12)
	margins.add_child(_page)
	_page.add_child(RacingUISkin.label(kicker,15,RacingUISkin.CYAN))
	if not heading.is_empty():
		_page.add_child(RacingUISkin.label(heading,46))
	if not subtitle.is_empty():
		_page.add_child(RacingUISkin.label(subtitle,18,RacingUISkin.MUTED))
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation",46)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_child(_body)

func _column(parent: Node, ratio: float = 1.0) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_stretch_ratio = ratio
	parent.add_child(node)
	return node

func _spacer(parent: Node) -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)

func _button(parent: Node, id: StringName, caption: String, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.name = String(id)
	button.text = caption
	button.custom_minimum_size.y = 58
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size",22)
	if primary:
		button.add_theme_stylebox_override("normal",RacingUISkin.box(RacingUISkin.CYAN,12))
		button.add_theme_color_override("font_color",RacingUISkin.INK)
		button.add_theme_color_override("font_focus_color",RacingUISkin.INK)
	button.pressed.connect(callback)
	parent.add_child(button)
	buttons[id] = button
	_button_order.append(button)
	return button

func _footer() -> void:
	_page.add_child(RacingUISkin.label("ARROWS / D-PAD  Navigate     ENTER / A  Select     ESC / B  Back",14,RacingUISkin.MUTED))

func _focus(id: StringName) -> void:
	for index in range(_button_order.size()):
		var button: Button = _button_order[index]
		var previous: NodePath = button.get_path_to(_button_order[posmod(index-1,_button_order.size())])
		var next: NodePath = button.get_path_to(_button_order[(index+1)%_button_order.size()])
		button.focus_neighbor_top = previous
		button.focus_neighbor_left = previous
		button.focus_previous = previous
		button.focus_neighbor_bottom = next
		button.focus_neighbor_right = next
		button.focus_next = next
	buttons[id].grab_focus.call_deferred()

func _add_preview(parent: Node, seated: bool = false, pose: StringName = &"Idle") -> void:
	preview = DriverPreview.new()
	parent.add_child(preview)
	preview.show_driver(GameSession.character().look,seated,pose)

func _dispose_race() -> void:
	get_tree().paused = false
	if is_instance_valid(track):
		remove_child(track)
		track.queue_free()
	track = null
	RaceManager.clear_race()

func show_title() -> void:
	_dispose_race()
	_shell("NODEKINS / ARCADE RACING", "", "")
	var left: VBoxContainer = _column(_body,.9)
	_spacer(left)
	left.add_child(RacingUISkin.label("NODEKINS",78))
	left.add_child(RacingUISkin.label("RACING",70,RacingUISkin.CYAN))
	left.add_child(RacingUISkin.paragraph("Find your line.\nMake a little chaos.",25))
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	left.add_child(gap)
	_button(left,&"play","PLAY   →",show_characters,true)
	var lower := HBoxContainer.new()
	left.add_child(lower)
	_button(lower,&"options","Options",show_options)
	_button(lower,&"quit","Quit",get_tree().quit)
	_spacer(left)
	var right: VBoxContainer = _column(_body,1.1)
	_add_preview(right,true)
	right.add_child(RacingUISkin.label("DRIFT. BOOST. TAKE FLIGHT.",17,RacingUISkin.CYAN))
	_footer()
	_set_screen(&"title")
	_focus(&"play")

func show_options() -> void:
	_shell("NODEKINS / OPTIONS","Options","A place for the settings to come.")
	var left: VBoxContainer = _column(_body)
	_spacer(left)
	left.add_child(RacingUISkin.label("You're ready to race.",34))
	left.add_child(RacingUISkin.paragraph("Audio, display and control settings will arrive in a later update.",23))
	left.add_child(RacingUISkin.paragraph("Keyboard: WASD / arrows to drive · Space to drift\nE to use an item · R to recover · Esc to pause\n\nGamepad: left stick · RT accelerate · LT brake\nA drift · X item · Y recover · Start pause",20))
	_spacer(left)
	_button(left,&"back","←  Main Menu",show_title,true)
	_add_preview(_column(_body),true)
	_footer()
	_set_screen(&"options")
	_focus(&"back")

func show_characters() -> void:
	_shell("01 / DRIVER     →     02 / TRACK     →     03 / RACE","Choose your driver","Pick a base character. Both use the same kart and handling.")
	var left: VBoxContainer = _column(_body,.9)
	_spacer(left)
	var group := ButtonGroup.new()
	for entry: DriverEntry in GameSession.catalog.drivers:
		var button: Button = _button(left,entry.id,entry.display_name + "   /   Default outfit",_select_character.bind(entry.id))
		button.toggle_mode = true
		button.button_group = group
		button.set_pressed_no_signal(entry.id == GameSession.selected_character_id)
	_description = RacingUISkin.paragraph(GameSession.character().description,19)
	left.add_child(_description)
	left.add_child(RacingUISkin.paragraph("More ways to make them yours are coming.",17))
	_spacer(left)
	_button(left,&"continue","Choose Track   →",show_tracks,true)
	_button(left,&"back","←  Main Menu",show_title)
	var right: VBoxContainer = _column(_body,1.1)
	_add_preview(right)
	_preview_name = RacingUISkin.label(GameSession.character().display_name.to_upper(),22,RacingUISkin.CYAN)
	_preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(_preview_name)
	_footer()
	_set_screen(&"characters")
	_focus(GameSession.selected_character_id)

func _select_character(id: StringName) -> void:
	if GameSession.select_character(id):
		_description.text = GameSession.character().description
		_preview_name.text = GameSession.character().display_name.to_upper()
		preview.show_driver(GameSession.character().look)

func show_tracks() -> void:
	_dispose_race()
	_shell("01 / DRIVER     →     02 / TRACK     →     03 / RACE","Choose a circuit","Driver: " + GameSession.character().display_name + "   ·   Three laps. Four racers. One finish line.")
	var left: VBoxContainer = _column(_body,.85)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var entries := VBoxContainer.new()
	entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(entries)
	var group := ButtonGroup.new()
	for entry: RaceTrackEntry in GameSession.catalog.tracks:
		var button: Button = _button(entries,entry.id,entry.display_name + "\n" + entry.subtitle,_select_track.bind(entry.id))
		button.custom_minimum_size.y = 104
		button.toggle_mode = true
		button.button_group = group
		button.set_pressed_no_signal(entry.id == GameSession.selected_track_id)
	_button(left,&"start","START RACE   →",start_race,true)
	_button(left,&"back","←  Change Driver",show_characters)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.15
	_body.add_child(panel)
	var details := VBoxContainer.new()
	panel.add_child(details)
	_preview_name = RacingUISkin.label("",28)
	details.add_child(_preview_name)
	_map = RaceTrackMap.new()
	_map.custom_minimum_size.y = 210
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(_map)
	_description = RacingUISkin.paragraph("",19)
	details.add_child(_description)
	_features = RacingUISkin.label("",13,RacingUISkin.CYAN)
	details.add_child(_features)
	_select_track(GameSession.selected_track_id)
	_footer()
	_set_screen(&"tracks")
	_focus(&"start")

func _select_track(id: StringName) -> void:
	if GameSession.select_track(id):
		var entry: RaceTrackEntry = GameSession.track()
		_preview_name.text = entry.display_name
		_description.text = entry.description
		_features.text = "    /    ".join(entry.features)
		_map.set_route(entry.route,entry.glide_section)

func start_race() -> void:
	if _changing or current_screen != &"tracks":
		return
	_changing = true
	_clear_ui()
	results.clear()
	get_tree().paused = false
	track = GameSession.track().scene.instantiate() as Node3D
	track.name = "ActiveRace"
	track.process_mode = Node.PROCESS_MODE_PAUSABLE
	track.item_random_seed = race_random_seed
	track.get_node("Player/Visuals/Rider").look = GameSession.character().look
	add_child(track)
	# Presentation adapter: the standalone track keeps its original instrumentation.
	track.set_process_unhandled_input(false)
	for label: Label3D in track.player.find_children("*", "Label3D", false, false):
		label.hide() # The local kart does not need the old debug name above the chase camera.
	for node_name: String in ["DrivingHUD","RaceHUD","ItemHUD"]:
		var layer: CanvasLayer = track.get_node(node_name)
		layer.hide()
		layer.process_mode = Node.PROCESS_MODE_DISABLED
	hud = RaceOverlay.new()
	_ui.add_child(hud)
	hud.setup(track,GameSession.track())
	hud.pause_requested.connect(show_pause)
	_set_screen(&"race")
	_changing = false
	race_loaded.emit(track)

func show_pause() -> void:
	if current_screen != &"race" or RaceManager.phase == RaceManager.Phase.FINISHED:
		return
	get_tree().paused = true
	_shell("NODEKINS / RACE PAUSED","Take a breather.","Your race will be right here.")
	var left: VBoxContainer = _column(_body)
	_spacer(left)
	_button(left,&"resume","RESUME   →",resume_race,true)
	_button(left,&"leave","Choose Track",show_tracks)
	_button(left,&"main_menu","Main Menu",show_title)
	_spacer(left)
	_add_preview(_column(_body),true)
	_footer()
	_set_screen(&"paused")
	_focus(&"resume")

func resume_race() -> void:
	if current_screen != &"paused":
		return
	_clear_ui()
	hud = RaceOverlay.new()
	_ui.add_child(hud)
	hud.setup(track,GameSession.track())
	hud.pause_requested.connect(show_pause)
	get_tree().paused = false
	_set_screen(&"race")

func _race_finished() -> void:
	if current_screen == &"race":
		# Take authoritative snapshots before any scene is removed.
		results = RaceManager.get_standings()
		show_results.call_deferred()

func show_results() -> void:
	if not is_instance_valid(track) or current_screen != &"race":
		return
	track.process_mode = Node.PROCESS_MODE_DISABLED
	_shell("NODEKINS / " + GameSession.track().display_name,"Race complete!","Every finish has another starting line.")
	var left: VBoxContainer = _column(_body,1.25)
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left",22)
	header_margin.add_theme_constant_override("margin_right",22)
	left.add_child(header_margin)
	var header := HBoxContainer.new()
	header_margin.add_child(header)
	var place_header: Label = RacingUISkin.label("PLACE",14,RacingUISkin.MUTED)
	place_header.custom_minimum_size.x = 78
	header.add_child(place_header)
	var name_header: Label = RacingUISkin.label("RACER",14,RacingUISkin.MUTED)
	name_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_header)
	header.add_child(RacingUISkin.label("TIME",14,RacingUISkin.MUTED))
	for state: Dictionary in results:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel",RacingUISkin.box(Color("205463") if state.id == "player" else RacingUISkin.PANEL,10))
		left.add_child(panel)
		var row := HBoxContainer.new()
		panel.add_child(row)
		var place: Label = RacingUISkin.label(RacingUISkin.ordinal(int(state.position)),26,RacingUISkin.CYAN if state.id == "player" else RacingUISkin.WHITE)
		place.custom_minimum_size.x = 78
		row.add_child(place)
		var racer_name: Label = RacingUISkin.label("YOU" if state.id == "player" else str(state.name),23)
		racer_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(racer_name)
		var time: Label = RacingUISkin.label(RacingUISkin.clock_text(float(state.finish_time)),24)
		row.add_child(time)
		result_rows[state.id] = {"place":place,"name":racer_name,"time":time}
	_spacer(left)
	var actions := HBoxContainer.new()
	left.add_child(actions)
	_button(actions,&"race_again","RACE AGAIN   →",show_tracks,true)
	_button(actions,&"main_menu","Main Menu",show_title)
	var right: VBoxContainer = _column(_body,.75)
	_add_preview(right,false,&"Victory")
	right.add_child(RacingUISkin.label("NICE RACING.",22,RacingUISkin.CYAN))
	_footer()
	_set_screen(&"results")
	_focus(&"race_again")

func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if current_screen == &"race":
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("race_restart"):
			get_viewport().set_input_as_handled()
			show_pause()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		match current_screen:
			&"characters", &"options", &"results": show_title()
			&"tracks": show_characters()
			&"paused": resume_race()

func _exit_tree() -> void:
	get_tree().paused = false
