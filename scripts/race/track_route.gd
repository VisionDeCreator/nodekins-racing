class_name TrackRoute
extends Resource
## One closed centerline drives gate placement, respawn orientation, and sector ranking.
## Points and transforms are in world space. This Phase 2 track is rooted at identity.

@export var points: PackedVector3Array
@export var checkpoint_indices: PackedInt32Array
@export var road_width: float = 14.0
## Optional safe-ground anchors for checkpoints suspended over a gap.
@export var recovery_overrides: Dictionary = {}
var _distances: PackedFloat32Array = []
var _length: float = 0.0

func prepare() -> void:
	_distances.clear()
	_length = 0.0
	for index in range(points.size()):
		_distances.append(_length)
		_length += points[index].distance_to(points[(index + 1) % points.size()])

func length() -> float:
	return _length

func checkpoint_distance(index: int) -> float:
	return _distances[checkpoint_indices[index]]

func checkpoint_transform(index: int) -> Transform3D:
	return sample(checkpoint_distance(index))

func recovery_transform(index: int) -> Transform3D:
	if recovery_overrides.has(index):
		return recovery_overrides[index]
	# Spawn just beyond the accepted gate, never beyond the next required checkpoint.
	var pose: Transform3D = sample(checkpoint_distance(index) + 3.0)
	pose.origin.y += 0.12
	return pose

func sample(distance: float) -> Transform3D:
	var wrapped: float = fposmod(distance, _length)
	for index in range(points.size()):
		var end: float = _distances[index + 1] if index + 1 < points.size() else _length
		if wrapped <= end:
			var next_point: Vector3 = points[(index + 1) % points.size()]
			var forward: Vector3 = (next_point - points[index]).normalized()
			var position: Vector3 = points[index].lerp(next_point, (wrapped - _distances[index]) / (end - _distances[index]))
			return Transform3D(Basis.looking_at(forward, Vector3.UP), position)
	return Transform3D.IDENTITY

func project_sector(position: Vector3, checkpoint: int) -> Dictionary:
	var first: int = checkpoint_indices[checkpoint]
	var next_checkpoint: int = (checkpoint + 1) % checkpoint_indices.size()
	var end: int = checkpoint_indices[next_checkpoint]
	if end <= first:
		end += points.size()
	var best_squared: float = INF
	var best_distance: float = checkpoint_distance(checkpoint)
	var best_forward: Vector3 = Vector3.FORWARD
	for unwrapped_index in range(first, end):
		var index: int = unwrapped_index % points.size()
		var a: Vector3 = points[index]
		var edge: Vector3 = points[(index + 1) % points.size()] - a
		var fraction: float = clampf((position - a).dot(edge) / edge.length_squared(), 0.0, 1.0)
		var squared: float = position.distance_squared_to(a + edge * fraction)
		if squared < best_squared:
			best_squared = squared
			best_distance = _distances[index] + edge.length() * fraction
			best_forward = edge.normalized()
	return {"distance": best_distance, "offset": sqrt(best_squared), "forward": best_forward}
