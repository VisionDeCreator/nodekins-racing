class_name PrototypeKartMotor
extends RefCounted
## Shared, fixed-step, replayable prototype. No physics-world or presentation dependencies.
const DT: float = 1.0 / 60.0
const TOP_SPEED: float = 20.0
const LIMIT: float = 114.0

static func spawn(slot: int) -> Dictionary:
	return {"position":Vector2(-4.0 if slot == 0 else 4.0,14.0),"yaw":0.0,"speed":0.0,"steer":0.0}

static func step(state: Dictionary, input: Vector3) -> Dictionary:
	var result: Dictionary = state.duplicate()
	var speed: float = state.speed
	var target: float = TOP_SPEED * input.x
	if input.y > 0:
		speed = move_toward(speed,0.0,38.0*input.y*DT)
	elif input.x <= .001:
		speed = move_toward(speed,0.0,8.0*DT)
	elif speed > target:
		speed = move_toward(speed,target,12.0*DT)
	else:
		speed = minf(target,speed+(34.0-22.0*clampf(speed/TOP_SPEED,0,1))*DT)
	var steer: float = lerpf(float(state.steer),input.z,1.0-exp(-10.0*DT))
	var turn_rate: float = lerpf(180,65,clampf(speed/TOP_SPEED,0,1))*minf(speed/4.0,1.0)
	var yaw: float = wrapf(float(state.yaw)-deg_to_rad(turn_rate)*steer*DT,-PI,PI)
	var position: Vector2 = state.position + Vector2(-sin(yaw),-cos(yaw))*speed*DT
	var bounded := Vector2(clampf(position.x,-LIMIT,LIMIT),clampf(position.y,-LIMIT,LIMIT))
	if bounded != position:
		speed = 0.0
	result.boundary_hit = bounded != position
	result.position = bounded
	result.yaw = yaw
	result.speed = speed
	result.steer = steer
	return result

static func encode(state: Dictionary) -> PackedFloat32Array:
	return PackedFloat32Array([state.position.x,state.position.y,state.yaw,state.speed,state.steer])

static func decode(values: PackedFloat32Array, offset: int = 0) -> Dictionary:
	return {"position":Vector2(values[offset],values[offset+1]),"yaw":float(values[offset+2]),"speed":float(values[offset+3]),"steer":float(values[offset+4])}

static func blend(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	return {"position":a.position.lerp(b.position,weight),"yaw":lerp_angle(float(a.yaw),float(b.yaw),weight),"speed":lerpf(float(a.speed),float(b.speed),weight),"steer":lerpf(float(a.steer),float(b.steer),weight)}
