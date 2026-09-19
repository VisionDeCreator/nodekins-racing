extends Node
## Volume persistence only. This singleton never owns players or triggers sounds.
const BUSES: Array[StringName] = [&"Music",&"SFX",&"Engine"]
const DEFAULTS: Array[float] = [.70,.90,.70]
var path: String = "user://audio.cfg"
var values: Dictionary = {}
var status: String = ""
var _save_timer: Timer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = .35
	_save_timer.timeout.connect(save)
	add_child(_save_timer)
	reload_settings()

func reload_settings() -> void:
	var config := ConfigFile.new()
	config.load(path)
	for index in range(BUSES.size()):
		var value: Variant = config.get_value("volume",String(BUSES[index]),DEFAULTS[index])
		var valid: bool = (value is float or value is int) and is_finite(float(value))
		set_volume(BUSES[index],clampf(float(value),0,1) if valid else DEFAULTS[index],false)

func set_volume(bus: StringName, value: float, persist: bool = true) -> void:
	if not BUSES.has(bus) or not is_finite(value):
		return
	values[bus] = clampf(value,0,1)
	var index: int = AudioServer.get_bus_index(bus)
	AudioServer.set_bus_mute(index,value <= 0)
	AudioServer.set_bus_volume_db(index,linear_to_db(maxf(value,.0001)))
	if persist:
		_save_timer.start()

func save() -> void:
	_save_timer.stop()
	var config := ConfigFile.new()
	for bus: StringName in BUSES:
		config.set_value("volume",String(bus),values[bus])
	status = "Volumes saved" if config.save(path) == OK else "Could not save volumes"
