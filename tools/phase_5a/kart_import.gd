@tool
extends EditorScenePostImport
## Preserve Blender's vertex-color livery in Godot's imported StandardMaterials.
func _post_import(scene: Node) -> Object:
	for instance: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		for surface in range(instance.mesh.get_surface_count()):
			var material: StandardMaterial3D = instance.mesh.surface_get_material(surface) as StandardMaterial3D
			if material != null:
				material.vertex_color_use_as_albedo = true
				material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return scene
