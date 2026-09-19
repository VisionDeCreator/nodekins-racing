extends Node3D
## Startup diagnostics only; no movement, input, races, or other gameplay.

@export var handling: KartHandling

func _ready() -> void:
	var failures: PackedStringArray = []
	var meshes := $BlenderExport.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != 1:
		failures.append("Expected one mesh from the Blender GLB.")
	else:
		var mesh: Mesh = meshes[0].mesh
		if mesh == null or mesh.get_surface_count() != 1:
			failures.append("Expected one imported mesh surface.")
		else:
			var triangles: int = int(mesh.surface_get_array_index_len(0) / 3.0)
			var size := mesh.get_aabb().size
			if triangles != 12:
				failures.append("Expected 12 triangles.")
			if not size.is_equal_approx(Vector3(1.0, 0.5, 1.5)):
				failures.append("Unexpected metre scale or Blender Z-up to Godot Y-up conversion.")
			if mesh.surface_get_material(0) == null:
				failures.append("Imported material missing.")
			print("[Phase 0] Blender GLB: triangles=%d, Godot size=%s, material=%s" % [triangles, size, mesh.surface_get_material(0) != null])
	if handling == null or handling.acceleration_curve == null or handling.steering_speed_curve == null:
		failures.append("Handling resource or curves missing.")
	elif handling.mini_turbo_thresholds.size() != 3 or handling.mini_turbo_speed_multipliers.size() != 3 or handling.mini_turbo_durations.size() != 3:
		failures.append("Expected three mini-turbo tiers.")
	else:
		print("[Phase 0] Handling loaded: %.1f m/s, %.1f s to top speed, %.1f deg/s, drift > %.1f deg" % [handling.top_speed, handling.time_to_top_speed, handling.low_speed_turn_rate, handling.drift_steer_threshold_degrees])
	if failures.is_empty():
		$HUD/Panel/Margin/Rows/Status.text = "PASS  /  Blender mesh + material + handling resource"
		print("[Phase 0] PASS: scene running; Blender import and handling resource verified. No gameplay implemented.")
	else:
		$HUD/Panel/Margin/Rows/Status.text = "FAIL  /  See Godot output"
		for failure in failures:
			push_error("[Phase 0] " + failure)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--phase0-screenshot="):
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var path: String = argument.trim_prefix("--phase0-screenshot=")
			var capture_error := get_viewport().get_texture().get_image().save_png(path)
			if capture_error != OK:
				failures.append("Unable to save diagnostic screenshot.")
			else:
				print("[Phase 0] Screenshot saved: " + path)
	if "--phase0-check" in OS.get_cmdline_user_args():
		get_tree().quit(0 if failures.is_empty() else 1)
