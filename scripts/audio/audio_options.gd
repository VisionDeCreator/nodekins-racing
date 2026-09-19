class_name AudioOptions
extends VBoxContainer
var sliders: Dictionary = {}
var _labels: Dictionary = {}
var _status: Label

func _ready() -> void:
	for bus: StringName in AudioPreferences.BUSES:
		var row := HBoxContainer.new()
		add_child(row)
		var label: Label = RacingUISkin.label(String(bus),21)
		label.custom_minimum_size.x = 95
		row.add_child(label)
		var slider := HSlider.new()
		slider.name = String(bus) + "Volume"
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.custom_minimum_size = Vector2(210,44)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value = float(AudioPreferences.values[bus])*100
		slider.value_changed.connect(_volume_changed.bind(bus))
		row.add_child(slider)
		sliders[bus] = slider
		var value_label: Label = RacingUISkin.label("",19,RacingUISkin.CYAN)
		value_label.custom_minimum_size.x = 66
		row.add_child(value_label)
		_labels[bus] = value_label
		_update_label(bus,slider.value)
	_status = RacingUISkin.label("Changes save automatically · 0% mutes a bus",15,RacingUISkin.MUTED)
	add_child(_status)

func _volume_changed(value: float, bus: StringName) -> void:
	AudioPreferences.set_volume(bus,value/100)
	_update_label(bus,value)

func _update_label(bus: StringName, value: float) -> void:
	_labels[bus].text = "MUTE" if value <= 0 else "%d%%" % roundi(value)

func configure_focus(back: Button) -> void:
	var controls: Array[Control] = []
	for bus: StringName in AudioPreferences.BUSES:
		controls.append(sliders[bus])
	controls.append(back)
	for index in range(controls.size()):
		var control: Control = controls[index]
		control.focus_neighbor_top = control.get_path_to(controls[posmod(index-1,controls.size())])
		control.focus_previous = control.focus_neighbor_top
		control.focus_neighbor_bottom = control.get_path_to(controls[(index+1)%controls.size()])
		control.focus_next = control.focus_neighbor_bottom
	controls[0].grab_focus.call_deferred()

func _exit_tree() -> void:
	AudioPreferences.save()
