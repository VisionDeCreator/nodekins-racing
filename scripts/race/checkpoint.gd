class_name RaceCheckpoint
extends Area3D
## Count an oriented center-plane crossing, not merely touching an Area boundary.

@export var checkpoint_index: int = 0
var _inside: Dictionary = {}

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_entered)
	body_exited.connect(_exited)

func _entered(body: Node3D) -> void:
	if body is ArcadeKart:
		_inside[body.get_instance_id()] = {"body": body, "side": _signed_distance(body.global_position)}

func _exited(body: Node3D) -> void:
	_inside.erase(body.get_instance_id())

func _signed_distance(world_position: Vector3) -> float:
	return (world_position - global_position).dot(-global_basis.z)

func _physics_process(_delta: float) -> void:
	for instance_id in _inside.keys():
		var record: Dictionary = _inside[instance_id]
		if not is_instance_valid(record.body):
			_inside.erase(instance_id)
			continue
		var kart: ArcadeKart = record.body
		var side: float = _signed_distance(kart.global_position)
		var previous: float = float(record.side)
		# Teleports do not count as physically traversing a gate.
		if absf(side - previous) < 5.0:
			if previous < 0.0 and side >= 0.0:
				RaceManager.report_checkpoint(kart, checkpoint_index, true)
			elif previous > 0.0 and side <= 0.0:
				RaceManager.report_checkpoint(kart, checkpoint_index, false)
		record.side = side
