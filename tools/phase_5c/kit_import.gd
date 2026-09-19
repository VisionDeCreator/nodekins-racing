@tool
extends EditorScenePostImport
func _post_import(scene: Node) -> Object:
	for node: Node in scene.find_children("*", "Node", true, false):
		# Blender needs globally unique object names; Godot only needs local names.
		if String(node.name).contains("__"):
			node.name = String(node.name).get_slice("__", 1)
		if node is MeshInstance3D:
			for index in range(node.mesh.get_surface_count()):
				var material := node.mesh.surface_get_material(index) as StandardMaterial3D
				if material != null:
					material.vertex_color_use_as_albedo = true
					material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
					material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return scene
