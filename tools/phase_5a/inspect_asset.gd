extends Node

func _ready() -> void:
	var model: Node = load("res://assets/karts/kart_01.glb").instantiate()
	add_child(model)
	model.print_tree_pretty()
	for mesh_node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		print("[Asset import] ", mesh_node.get_path(), " local=", mesh_node.transform, " aabb=", mesh_node.mesh.get_aabb(), " triangles=", int(mesh_node.mesh.get_faces().size() / 3.0), " surfaces=", mesh_node.mesh.get_surface_count())
	print("[Asset import] COMPLETE")
