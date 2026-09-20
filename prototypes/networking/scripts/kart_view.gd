class_name PrototypeKartView
extends Node3D
## Render-only. Corrections rebase simulation endpoints while preserving visible pose.
var previous: Dictionary
var current: Dictionary
var correction: Vector2 = Vector2.ZERO
var yaw_correction: float = 0.0
var local: bool = false
var last_correction_step: float = 0.0
var maximum_correction_step: float = 0.0
var correction_speed_limit: float = 4.0
var correction_changed: bool = false

func setup(slot: int, is_local: bool, state: Dictionary) -> void:
	local = is_local
	previous = state.duplicate()
	current = state.duplicate()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("35dbdb") if slot == 0 else Color("e983c4")
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.4,.65,2.0)
	body.mesh = box
	body.material_override = material
	body.position.y = .5
	add_child(body)
	var nose := MeshInstance3D.new()
	box = BoxMesh.new()
	box.size = Vector3(.75,.12,.45)
	nose.mesh = box
	nose.position = Vector3(0,.88,-.65)
	add_child(nose)
	var label := Label3D.new()
	label.text = ("A" if slot == 0 else "B") + (" · YOU" if local else " · REMOTE")
	label.position.y = 1.8
	label.font_size = 40
	label.pixel_size = .025
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	position = Vector3(state.position.x,0,state.position.y)
	rotation.y = state.yaw

func tick(state: Dictionary) -> void:
	previous = current
	current = state.duplicate()

func rebase(delta: Vector2, yaw_delta: float) -> void:
	previous.position += delta
	current.position += delta
	previous.yaw += yaw_delta
	current.yaw += yaw_delta
	correction -= delta
	yaw_correction -= yaw_delta
	correction_changed = true

func present(delta: float, remote_state: Dictionary = {}) -> void:
	if local:
		var old: Vector2 = correction
		var fraction: float = 1.0-exp(-8.0*delta)
		correction = correction.move_toward(Vector2.ZERO,minf(correction.length()*fraction,correction_speed_limit*delta))
		yaw_correction = move_toward(yaw_correction,0.0,minf(absf(yaw_correction)*fraction,PI*delta))
		last_correction_step = old.distance_to(correction)
		maximum_correction_step = maxf(maximum_correction_step,last_correction_step)
		var state: Dictionary = PrototypeKartMotor.blend(previous,current,Engine.get_physics_interpolation_fraction())
		var at: Vector2 = state.position+correction
		position = Vector3(at.x,0,at.y)
		rotation.y = float(state.yaw)+yaw_correction
	elif not remote_state.is_empty():
		var target := Vector3(remote_state.position.x,0,remote_state.position.y)
		position = position.lerp(target,1.0-exp(-25.0*delta))
		rotation.y = lerp_angle(rotation.y,float(remote_state.yaw),1.0-exp(-25.0*delta))
