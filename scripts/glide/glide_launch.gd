class_name GlideLaunch
extends Area3D
## Forward center-plane crossings only. Reverse travel and standing overlap never relaunch.
var _inside: Dictionary = {}

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_entered)
	body_exited.connect(_exited)

func _side(body: Node3D) -> float:
	return (body.global_position - global_position).dot(-global_basis.z)

func _entered(body: Node3D) -> void:
	if body is ArcadeKart:
		_inside[body.get_instance_id()] = {"body": body, "side": _side(body)}

func _exited(body: Node3D) -> void:
	_inside.erase(body.get_instance_id())

func _physics_process(_delta: float) -> void:
	for key: int in _inside.keys():
		var record: Dictionary = _inside[key]
		if not is_instance_valid(record.body):
			_inside.erase(key)
			continue
		var side: float = _side(record.body)
		if RaceManager.phase == RaceManager.Phase.RACING and float(record.side) < 0.0 and side >= 0.0 and side - float(record.side) < 5.0:
			record.body.glide.try_launch()
		record.side = side
