extends RefCounted
## Geometry contract captured before the art swap; visibility is deliberately excluded.
static func capture(track: Node) -> Dictionary:
	var result: Dictionary = {"collisions": {}, "areas": {}, "route_points": [], "checkpoints": [], "road_width": track.route.road_width}
	for point: Vector3 in track.route.points:
		result.route_points.append([point.x, point.y, point.z])
	for index: int in track.route.checkpoint_indices:
		result.checkpoints.append(index)
	for collider: CollisionShape3D in track.find_children("*", "CollisionShape3D", true, false):
		var parent: Node3D = collider.get_parent()
		if parent is CharacterBody3D:
			continue
		var pose: Transform3D = collider.global_transform
		var shape: Shape3D = collider.shape
		var size: Vector3 = shape.size if shape is BoxShape3D else Vector3.ZERO
		result.collisions[String(track.get_path_to(collider))] = {"transform": var_to_str(pose), "size": [size.x, size.y, size.z], "type": shape.get_class(), "disabled": collider.disabled, "layer": parent.collision_layer, "mask": parent.collision_mask}
	for area: Area3D in track.find_children("*", "Area3D", true, false):
		result.areas[String(track.get_path_to(area))] = {"transform": var_to_str(area.global_transform), "layer": area.collision_layer, "mask": area.collision_mask, "monitoring": area.monitoring, "monitorable": area.monitorable}
	return result
