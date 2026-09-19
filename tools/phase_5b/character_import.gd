@tool
extends EditorScenePostImport
func _post_import(scene: Node) -> Object:
	for instance: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		for index in range(instance.mesh.get_surface_count()):
			var material: StandardMaterial3D = instance.mesh.surface_get_material(index) as StandardMaterial3D
			if material != null:
				material.vertex_color_use_as_albedo = true
				material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	for player: AnimationPlayer in scene.find_children("*", "AnimationPlayer", true, false):
		for animation_name: String in player.get_animation_list():
			if animation_name != "RESET":
				player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
	return scene
