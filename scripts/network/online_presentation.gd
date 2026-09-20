class_name OnlineKartPresentation
extends RefCounted
var kart: ArcadeKart
var offset: Vector3 = Vector3.ZERO
var yaw_offset: float = 0.0
var buffer: Array[Dictionary] = []
var local: bool = false
var max_rebase_jump: float = 0.0
var max_correction_rate: float = 0.0
var max_offset: float = 0.0
var held_frames: int = 0

func _init(body: ArcadeKart, owned: bool) -> void:
	kart = body
	local = owned
	kart.set_meta(&"online_render_pose",kart.global_transform)

func reconcile(previous: Transform3D, teleport: bool) -> void:
	if teleport:
		offset = Vector3.ZERO
		yaw_offset = 0.0
		kart.get_node("ChaseCamera").snap_to_target()
		return
	var old_visible: Vector3 = previous.origin+offset
	offset += previous.origin-kart.global_position
	yaw_offset += angle_difference(kart.rotation.y,previous.basis.get_euler().y)
	max_rebase_jump = maxf(max_rebase_jump,old_visible.distance_to(kart.global_position+offset))
	max_offset = maxf(max_offset,offset.length())

func enqueue(server_tick: int, state: Dictionary) -> void:
	buffer.append({"tick":server_tick,"state":state})
	while buffer.size() > 48:
		buffer.pop_front()

func render(delta: float, playhead: float) -> void:
	if local:
		var old: Vector3 = offset
		offset = offset.move_toward(Vector3.ZERO,minf(offset.length()*(1-exp(-10*delta)),8*delta))
		max_correction_rate = maxf(max_correction_rate,old.distance_to(offset)/maxf(delta,.00001))
		yaw_offset = move_toward(yaw_offset,0,minf(absf(yaw_offset)*(1-exp(-10*delta)),PI*delta))
		kart.get_node("Visuals").position = kart.global_basis.inverse()*offset
		kart.get_node("Glide").position = kart.global_basis.inverse()*offset
		kart.get_node("Visuals/Model").rotation.y = yaw_offset
		kart.get_node("Visuals/Rider").rotation.y = yaw_offset
		kart.get_node("Glide/Canopy").rotation.y = yaw_offset
		kart.set_meta(&"online_render_pose",Transform3D(Basis(Vector3.UP,yaw_offset)*kart.global_basis,kart.global_position+offset))
	elif not buffer.is_empty():
		var pose: Transform3D = buffer.back().state.pose
		var found: bool = false
		for index in range(1,buffer.size()):
			if buffer[index].tick >= playhead:
				var a: Dictionary = buffer[index-1]
				var b: Dictionary = buffer[index]
				pose = a.state.pose.interpolate_with(b.state.pose,clampf((playhead-float(a.tick))/float(b.tick-a.tick),0,1))
				found = true
				break
		if not found:
			var age: float = maxf(0,(playhead-float(buffer.back().tick))/60.0)
			pose.origin += buffer.back().state.velocity*minf(age,.1)
			if age > .1:
				held_frames += 1
		kart.global_transform = kart.global_transform.interpolate_with(pose,1-exp(-25*delta))
		kart.set_meta(&"online_render_pose",kart.global_transform)
