extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var track: Node3D = load("res://scenes/track/Track.tscn").instantiate()
	root.add_child(track)
	for piece: Node3D in track.get_node("EnvironmentKit").get_children():
		if not piece.get_meta("road_piece",false):
			continue
		var surface: MeshInstance3D = piece.find_child("Surface",true,false)
		for socket_name: String in ["socket_in","socket_out"]:
			var socket: Node3D = piece.find_child(socket_name,true,false)
			for side: float in [-1.0,1.0]:
				var wanted: Vector3 = socket.global_position + socket.global_basis.x * side * 7.0
				var closest: float = INF
				for v: Vector3 in surface.mesh.get_faces():
					closest = minf(closest,(surface.global_transform * v).distance_to(wanted))
				if closest > 0.0001:
					print("[Edge] ",piece.name," ",socket_name," ",side," nearest=",closest," expected=",wanted)
	quit()
