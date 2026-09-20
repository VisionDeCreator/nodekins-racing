extends Node3D
## Dedicated-server movement laboratory. This project has no production autoloads.
const Motor = preload("res://scripts/kart_motor.gd")
const View = preload("res://scripts/kart_view.gd")
const Link = preload("res://scripts/impaired_link.gd")
const INPUT_REDUNDANCY: int = 48
const MAX_PENDING: int = 512
const STAGE_SECONDS: float = 12.0
const STAGES: Array[String] = ["0ms", "75ms", "150ms", "150ms_loss_jitter"]
@export var server_role: bool = false
@export var benchmark: bool = false
@export var client_tag: String = "A"
var address: String = "127.0.0.1"
var bind_address: String = "127.0.0.1"
var port: int = 29088
var output_dir: String = ""
var quit_after: float = 0.0
var delay_ms: float = 0.0
var loss_fraction: float = 0.0
var jitter_ms: float = 0.0
var transport := ENetMultiplayerPeer.new()
var link := Link.new()
var tick: int = 0
var elapsed: float = 0.0
var racers: Dictionary = {}
var roster: Dictionary = {}
var views: Dictionary = {}
var remote_buffers: Dictionary = {}
var server_tick_seen: int = -1
var snapshot_arrival_ms: int = 0
var playhead: float = -1.0
var own_id: int = 0
var sequence: int = 0
var acknowledged: int = 0
var predicted: Dictionary = {}
var pending: Dictionary = {}
var predicted_history: Dictionary = {}
var connected: bool = false
var label: Label
var camera: Camera3D
var stage: int = -1
var stage_age: float = 0.0
var benchmark_epoch: int = -1
var completed: bool = false
var report_written: bool = false
var screenshot_written: bool = false
var fault_injected: bool = false
var fault_waiting: bool = false
var fault_recovered: bool = false
var fault_begin_seconds: float = 0.0
var rtt_ms: float = 0.0
var phase_data: Dictionary = {}
var phases: Array[Dictionary] = []
var rejected: int = 0
var stale_snapshots: int = 0
var remote_extrapolated_frames: int = 0
var remote_held_frames: int = 0
var correction_rebase_jump: float = 0.0
var max_correction_rate: float = 0.0

func _ready() -> void:
	_parse_arguments()
	output_dir = output_dir if not output_dir.is_empty() else ProjectSettings.globalize_path("res://../../artifacts/phase8a")
	DirAccess.make_dir_recursive_absolute(output_dir)
	link.rng.seed = 8021 if server_role else (8201 if client_tag == "A" else 8202)
	link.configure(delay_ms,loss_fraction,jitter_ms)
	multiplayer.server_relay = false
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected_to_server)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)
	if server_role:
		if DisplayServer.get_name() != "headless":
			push_error("The dedicated server must be launched with --headless.")
			get_tree().quit(2)
			return
		transport.set_bind_ip(bind_address)
		var error: Error = transport.create_server(port,2,3)
		if error != OK:
			push_error("Could not bind dedicated server: %s" % error)
			get_tree().quit(2)
			return
		multiplayer.multiplayer_peer = transport
		_log("server_ready",{"bind":bind_address,"port":port,"headless":true,"clients":0})
	else:
		_build_world()
		var error: Error = transport.create_client(address,port,3)
		if error != OK:
			push_error("Could not create client: %s" % error)
			get_tree().quit(2)
			return
		multiplayer.multiplayer_peer = transport
		_log("client_connecting",{"address":address,"port":port,"tag":client_tag})

func _parse_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.trim_prefix("--").split("=",true,1)
		var value: String = pair[1] if pair.size() > 1 else ""
		match pair[0]:
			"server": server_role = true
			"client": server_role = false
			"benchmark": benchmark = true
			"tag": client_tag = value
			"address": address = value
			"bind": bind_address = value
			"port": port = int(value)
			"latency": delay_ms = float(value)
			"loss": loss_fraction = float(value)
			"jitter": jitter_ms = float(value)
			"output": output_dir = value
			"quit-after": quit_after = float(value)

func _physics_process(delta: float) -> void:
	tick += 1
	elapsed += delta
	if server_role:
		_server_tick()
	elif connected and not predicted.is_empty():
		_client_tick()
	if stage >= 0:
		stage_age += delta
	if quit_after > 0 and elapsed >= quit_after:
		_write_report()
		transport.close()
		get_tree().quit()

func _process(delta: float) -> void:
	_flush_link()
	if server_role:
		return
	if not views.is_empty():
		var own: PrototypeKartView = views.get(own_id)
		if own != null:
			own.present(delta)
			max_correction_rate = maxf(max_correction_rate,own.last_correction_step/maxf(delta,.000001))
			if fault_waiting and fault_recovered and own.correction.length() < .03:
				fault_waiting = false
				var settled_seconds: float = stage_age-fault_begin_seconds
				if not phase_data.is_empty():
					phase_data.fault_settle_seconds = settled_seconds
				_log("fault_visually_settled",{"stage":stage,"seconds":settled_seconds})
		if server_tick_seen >= 0:
			var desired: float = float(server_tick_seen)-6.0+float(Time.get_ticks_msec()-snapshot_arrival_ms)*.06
			playhead += delta*60.0
			playhead = lerpf(playhead,desired,1.0-exp(-2.5*delta))
		for id: int in views:
			if id != own_id:
				views[id].present(delta,_remote_state(id))
	_frame_karts(delta)
	_update_overlay()
	if completed and stage_age > 16.0 and not screenshot_written:
		screenshot_written = true
		_capture.call_deferred()
	if completed and stage_age > 17.0 and not report_written:
		_write_report()

func _server_tick() -> void:
	if benchmark and benchmark_epoch < 0 and racers.size() == 2:
		benchmark_epoch = tick+180
	if benchmark_epoch >= 0:
		var next_stage: int = mini(4,int(float(tick-benchmark_epoch)/(STAGE_SECONDS*60.0))) if tick >= benchmark_epoch else -1
		if next_stage != stage and next_stage >= 0:
			if next_stage == 4:
				completed = true
				stage = 4
				stage_age = 0.0
				for id: int in racers:
					finish_benchmark.rpc_id(id)
				_log("benchmark_drive_complete",{"states":_server_states()})
			else:
				stage = next_stage
				stage_age = 0.0
				fault_injected = false
				_configure_stage(stage)
				for id: int in racers:
					begin_stage.rpc_id(id,stage)
				_log("stage",{"index":stage,"name":STAGES[stage],"one_way_ms":link.latency_ms,"loss":link.loss,"jitter_ms":link.jitter_ms})
	if benchmark and stage >= 0 and stage < 4 and stage_age > 6.0 and not fault_injected:
		fault_injected = true
		for id: int in racers:
			racers[id].state.position += Vector2(0,2.0)
		_log("authority_fault_injected",{"stage":stage,"meters":2.0})
	for id: int in racers:
		var racer: Dictionary = racers[id]
		var now: int = Time.get_ticks_usec()
		# Wall-clock budget prevents a late server frame permanently increasing input age.
		# At most two fixed steps/frame, with no more than one second of accrued credit.
		racer.credit = minf(60.0,float(racer.credit)+float(now-int(racer.budget_stamp))*.00006)
		racer.budget_stamp = now
		var commands: Dictionary = racer.commands
		racer.max_queue = maxi(racer.max_queue,commands.size())
		if not racer.started:
			if commands.size() < 3:
				continue
			racer.started = true
		var steps: int = 2 if commands.size() > 6 else 1
		for step_index in range(steps):
			if float(racer.credit) < 1.0:
				break
			var next: int = racer.ack+1
			var command := Vector3.ZERO
			if commands.has(next):
				command = commands[next]
				commands.erase(next)
				racer.gap_wait = 0
			elif not commands.is_empty():
				racer.gap_wait += 1
				if racer.gap_wait <= 3:
					racer.stalls += 1
					break
				command = Vector3(0,1,0)
				racer.synthesized += 1
			else:
				racer.stalls += 1
				break
			racer.state = Motor.step(racer.state,command)
			racer.ack = next
			racer.credit -= 1.0
			if step_index > 0:
				racer.catchup_steps += 1
			if racer.state.boundary_hit:
				racer.boundary_hits += 1
	if tick % 3 == 0 and not racers.is_empty():
		var ids := PackedInt32Array()
		var acks := PackedInt32Array()
		var states := PackedFloat32Array()
		for id: int in racers:
			ids.append(id)
			acks.append(racers[id].ack)
			states.append_array(Motor.encode(racers[id].state))
		for id: int in racers:
			link.enqueue(&"snapshot",id,[tick,ids,acks,states])
	if tick % 600 == 0:
		_log("server_state",{"tick":tick,"clients":racers.size(),"states":_server_states()})
	if completed and stage_age > 8.0 and not report_written:
		_write_report()

func _client_tick() -> void:
	if pending.size() >= MAX_PENDING:
		# A long outage cannot grow replay work or memory without bound.
		_log("prediction_window_exhausted",{"unacknowledged":pending.size()})
		connected = false
		transport.close()
		label.text = "Connection stalled beyond replay window. Restart client to reconnect."
		return
	var command: Vector3 = _benchmark_input() if benchmark else _read_input()
	sequence += 1
	pending[sequence] = command
	predicted = Motor.step(predicted,command)
	predicted_history[sequence] = predicted.duplicate()
	var own: PrototypeKartView = views[own_id]
	own.tick(predicted)
	if tick % 2 == 0:
		var first: int = acknowledged+1
		var commands := PackedVector3Array()
		for number in range(first,mini(sequence+1,first+INPUT_REDUNDANCY)):
			if pending.has(number):
				commands.append(pending[number])
		if not commands.is_empty():
			link.enqueue(&"input",1,[first,commands])
	if tick % 30 == 0:
		link.enqueue(&"ping",1,[Time.get_ticks_msec()])
	if stage >= 0 and stage < 4 and not completed and stage_age > 2.0:
		phase_data.max_pending = maxi(phase_data.max_pending,pending.size())
		if command.x > .1 and float(predicted.speed) > 0 and float(phase_data.input_response_ms) < 0:
			phase_data.input_response_ms = 1000.0/60.0

func _benchmark_input() -> Vector3:
	if stage < 0 or completed or stage_age < 1 or stage_age >= 9:
		return Vector3(0,1,0)
	var slot: int = roster.get(own_id,0)
	return Vector3(1,0,.85 if slot == 0 else -.85)

func _read_input() -> Vector3:
	var throttle: float = 1.0 if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP) else 0.0
	var brake: float = 1.0 if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN) else 0.0
	var steer: float = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var pads: Array[int] = Input.get_connected_joypads()
	if not pads.is_empty():
		var device: int = pads[0]
		var axis: float = Input.get_joy_axis(device,JOY_AXIS_LEFT_X)
		if absf(axis) > .15:
			steer = signf(axis)*(absf(axis)-.15)/.85
		throttle = maxf(throttle,maxf(0,Input.get_joy_axis(device,JOY_AXIS_TRIGGER_RIGHT)))
		brake = maxf(brake,maxf(0,Input.get_joy_axis(device,JOY_AXIS_TRIGGER_LEFT)))
	return Vector3(throttle,brake,steer)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and connected:
		if event.keycode == KEY_F8:
			_inject_fault()
		elif event.keycode == KEY_F5:
			benchmark = false
			_log("manual_input_enabled",{})

func _peer_connected(id: int) -> void:
	if not server_role:
		return
	var slot: int = 0
	for racer: Dictionary in racers.values():
		if racer.slot == 0:
			slot = 1
	racers[id] = {"slot":slot,"state":Motor.spawn(slot),"ack":0,"commands":{},"started":false,"gap_wait":0,"stalls":0,"synthesized":0,"packets_tick":0,"packets":0,"boundary_hits":0,"credit":0.0,"budget_stamp":Time.get_ticks_usec(),"catchup_steps":0,"max_queue":0}
	roster[id] = slot
	_log("client_joined",{"peer":id,"slot":slot})
	for peer: int in racers:
		welcome.rpc_id(peer,roster)

func _peer_disconnected(id: int) -> void:
	if server_role:
		_log("client_left",{"peer":id,"remaining":maxi(0,racers.size()-1)})
		racers.erase(id)
		roster.erase(id)
		for peer: int in racers:
			welcome.rpc_id(peer,roster)

func _connected_to_server() -> void:
	own_id = multiplayer.get_unique_id()
	connected = true
	_log("connected",{"own_id":own_id,"dedicated_server":1})

func _connection_failed() -> void:
	_log("connection_failed",{"address":address,"port":port})
	if label != null:
		label.text = "Connection failed. Start the separate dedicated server first."
	get_tree().quit(3)

func _server_disconnected() -> void:
	connected = false
	_log("server_disconnected",{})
	if label != null:
		label.text = "Dedicated server disconnected. Restart this client to reconnect."

@rpc("authority","call_remote","reliable",0)
func welcome(new_roster: Dictionary) -> void:
	if server_role:
		return
	roster = new_roster
	own_id = multiplayer.get_unique_id()
	for id: int in views.keys():
		if not roster.has(id):
			views[id].queue_free()
			views.erase(id)
			remote_buffers.erase(id)
	for id: int in roster:
		if views.has(id):
			continue
		var initial: Dictionary = Motor.spawn(roster[id])
		var view := View.new()
		add_child(view)
		view.setup(roster[id],id == own_id,initial)
		views[id] = view
		remote_buffers[id] = []
		if id == own_id:
			predicted = initial
	_log("roster",{"own_id":own_id,"slots":roster})

@rpc("any_peer","call_remote","unreliable",1)
func submit_input(first: int, commands: PackedVector3Array) -> void:
	if not server_role:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not racers.has(sender):
		rejected += 1
		return
	var racer: Dictionary = racers[sender]
	if racer.packets_tick != tick:
		racer.packets_tick = tick
		racer.packets = 0
	racer.packets += 1
	if racer.packets > 12 or commands.is_empty() or commands.size() > INPUT_REDUNDANCY or first < 1 or first > racer.ack+120:
		rejected += 1
		return
	for index in range(commands.size()):
		var number: int = first+index
		var command: Vector3 = commands[index]
		if not command.is_finite() or command.x < 0 or command.x > 1 or command.y < 0 or command.y > 1 or absf(command.z) > 1 or number > racer.ack+120:
			rejected += 1
			return
	for index in range(commands.size()):
		var number: int = first+index
		if number > racer.ack and not racer.commands.has(number):
			racer.commands[number] = commands[index]

@rpc("authority","call_remote","unreliable",2)
func receive_snapshot(server_tick: int, ids: PackedInt32Array, acks: PackedInt32Array, states: PackedFloat32Array) -> void:
	if server_role or ids.size() != acks.size() or states.size() != ids.size()*5:
		return
	if server_tick <= server_tick_seen:
		stale_snapshots += 1
		return
	server_tick_seen = server_tick
	snapshot_arrival_ms = Time.get_ticks_msec()
	if playhead < 0:
		playhead = float(server_tick)-6.0
	for index in range(ids.size()):
		var id: int = ids[index]
		if not views.has(id):
			continue
		var state: Dictionary = Motor.decode(states,index*5)
		if id == own_id:
			_reconcile(acks[index],state)
		else:
			var buffer: Array = remote_buffers[id]
			buffer.append({"tick":server_tick,"state":state})
			while buffer.size() > 48:
				buffer.pop_front()

func _reconcile(ack: int, authority: Dictionary) -> void:
	if ack < acknowledged or ack > sequence:
		return
	var error_at_ack: float = 0.0
	if predicted_history.has(ack):
		error_at_ack = predicted_history[ack].position.distance_to(authority.position)
	var before: Dictionary = predicted
	predicted = authority.duplicate()
	acknowledged = ack
	for number: int in pending.keys():
		if number <= ack:
			pending.erase(number)
			predicted_history.erase(number)
	for number in range(ack+1,sequence+1):
		if pending.has(number):
			predicted = Motor.step(predicted,pending[number])
			predicted_history[number] = predicted.duplicate()
	var shift: Vector2 = predicted.position-before.position
	var yaw_shift: float = angle_difference(float(before.yaw),float(predicted.yaw))
	var own: PrototypeKartView = views[own_id]
	var old_visible: Vector2 = own.current.position+own.correction
	own.rebase(shift,yaw_shift)
	correction_rebase_jump = maxf(correction_rebase_jump,old_visible.distance_to(own.current.position+own.correction))
	if stage >= 0 and stage < 4 and not completed and stage_age > 2.0:
		phase_data.errors.append(error_at_ack)
		phase_data.max_replay_correction = maxf(phase_data.max_replay_correction,shift.length())
	if shift.length() > 1.0:
		fault_waiting = true
		fault_recovered = true
		fault_begin_seconds = stage_age
		if not phase_data.is_empty():
			phase_data.fault_at = stage_age
		_log("fault_reconciled",{"stage":stage,"meters":shift.length(),"ack":ack,"pending":pending.size(),"visible_rebase_jump":correction_rebase_jump})

func _remote_state(id: int) -> Dictionary:
	var buffer: Array = remote_buffers.get(id,[])
	if buffer.is_empty():
		return {}
	for index in range(1,buffer.size()):
		if float(buffer[index].tick) >= playhead:
			var a: Dictionary = buffer[index-1]
			var b: Dictionary = buffer[index]
			var weight: float = clampf((playhead-float(a.tick))/float(b.tick-a.tick),0,1)
			return Motor.blend(a.state,b.state,weight)
	var latest: Dictionary = buffer.back()
	var result: Dictionary = latest.state.duplicate()
	var age: float = maxf(0,(playhead-float(latest.tick))/60.0)
	if age > 0:
		remote_extrapolated_frames += 1
	if age > .1:
		remote_held_frames += 1
	var yaw: float = result.yaw
	result.position += Vector2(-sin(yaw),-cos(yaw))*float(result.speed)*minf(age,.1)
	return result

@rpc("any_peer","call_remote","unreliable",1)
func ping(stamp: int) -> void:
	if server_role and racers.has(multiplayer.get_remote_sender_id()):
		link.enqueue(&"pong",multiplayer.get_remote_sender_id(),[stamp])

@rpc("authority","call_remote","unreliable",2)
func pong(stamp: int) -> void:
	rtt_ms = Time.get_ticks_msec()-stamp
	if stage >= 0 and stage < 4 and not completed and stage_age > 2.0:
		phase_data.rtts.append(rtt_ms)

func _flush_link() -> void:
	if transport.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	for packet: Dictionary in link.take_ready():
		var peer: int = packet.peer
		if server_role and not racers.has(peer):
			continue
		var args: Array = packet.args
		match packet.kind:
			&"input": submit_input.rpc_id(peer,args[0],args[1])
			&"snapshot": receive_snapshot.rpc_id(peer,args[0],args[1],args[2],args[3])
			&"ping": ping.rpc_id(peer,args[0])
			&"pong": pong.rpc_id(peer,args[0])

@rpc("authority","call_remote","reliable",0)
func begin_stage(index: int) -> void:
	_finish_phase()
	stage = index
	stage_age = 0.0
	fault_injected = false
	fault_waiting = false
	fault_recovered = false
	_configure_stage(index)
	phase_data = {"stage":STAGES[index],"one_way_ms":link.latency_ms,"loss":link.loss,"jitter_ms":link.jitter_ms,"rtts":[],"errors":[],"max_pending":0,"max_replay_correction":0.0,"input_response_ms":-1.0,"fault_at":0.0,"fault_settle_seconds":-1.0}
	_log("stage",{"index":stage,"name":STAGES[stage],"one_way_ms":link.latency_ms})

func _configure_stage(index: int) -> void:
	link.configure([0.0,75.0,150.0,150.0][index],.05 if index == 3 else 0.0,20.0 if index == 3 else 0.0)

@rpc("authority","call_remote","reliable",0)
func finish_benchmark() -> void:
	_finish_phase()
	completed = true
	# Keep last stage's age so screenshots are made after both clients settle.
	_log("benchmark_drive_complete",{"position":_state_json(predicted)})

func _finish_phase() -> void:
	if phase_data.is_empty():
		return
	var result: Dictionary = phase_data.duplicate(true)
	result.rtt_median_ms = _percentile(result.rtts,.5)
	result.rtt_p95_ms = _percentile(result.rtts,.95)
	result.ack_error_p95_m = _percentile(result.errors,.95)
	result.ack_error_max_m = _percentile(result.errors,1.0)
	result.erase("rtts")
	result.erase("errors")
	phases.append(result)
	_log("phase_metrics",result)
	phase_data = {}

func _inject_fault() -> void:
	if predicted.is_empty():
		return
	var bias := Vector2(2.0,0.0)
	predicted.position += bias
	views[own_id].rebase(bias,0.0)
	fault_injected = true
	fault_waiting = true
	fault_recovered = false
	if not phase_data.is_empty():
		phase_data.fault_at = stage_age
	_log("fault_injected",{"stage":stage,"bias_m":2.0,"presentation_preserved":true})

func _percentile(values: Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	return float(sorted[clampi(int(ceil(fraction*sorted.size()))-1,0,sorted.size()-1)])

func _state_json(state: Dictionary) -> Dictionary:
	if state.is_empty():
		return {}
	return {"x":state.position.x,"z":state.position.y,"yaw":state.yaw,"speed":state.speed}

func _server_states() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: int in racers:
		var racer: Dictionary = racers[id]
		result.append({"peer":id,"slot":racer.slot,"ack":racer.ack,"state":_state_json(racer.state),"stalls":racer.stalls,"synthesized":racer.synthesized,"boundary_hits":racer.boundary_hits,"catchup_steps":racer.catchup_steps,"max_queue":racer.max_queue})
	return result

func _write_report() -> void:
	if report_written:
		return
	report_written = true
	var rendered: Array[Dictionary] = []
	for id: int in views:
		var view: PrototypeKartView = views[id]
		rendered.append({"peer":id,"slot":roster[id],"x":view.position.x,"z":view.position.z,"yaw":view.rotation.y})
	var report: Dictionary = {"role":"server" if server_role else "client_"+client_tag,"headless":DisplayServer.get_name() == "headless","phases":phases,"dropped_outgoing":link.dropped,"sent_outgoing":link.sent,"rejected_inputs":rejected,"stale_snapshots":stale_snapshots,"remote_extrapolated_frames":remote_extrapolated_frames,"remote_held_frames":remote_held_frames,"max_visible_rebase_jump_m":correction_rebase_jump,"max_visual_correction_rate_mps":max_correction_rate,"predicted":_state_json(predicted),"rendered":rendered,"server_states":_server_states(),"elapsed_seconds":elapsed}
	var filename: String = output_dir+"/"+str(report.role)+".json"
	var file := FileAccess.open(filename,FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report,"\t"))
	_log("report_written",{"file":filename,"summary":report})

func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var filename: String = output_dir+"/client_"+client_tag+".png"
	get_viewport().get_texture().get_image().save_png(filename)
	_log("screenshot",{"file":filename})

func _log(event: String, data: Dictionary) -> void:
	print("NETLAB ",JSON.stringify({"event":event,"role":"server" if server_role else client_tag,"ms":Time.get_ticks_msec(),"data":data}))

func _build_world() -> void:
	DisplayServer.window_set_title("Nodekins NetLab — Client "+client_tag)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_position(Vector2i(12 if client_tag == "A" else 660,80))
	var environment := WorldEnvironment.new()
	var sky := Environment.new()
	sky.background_mode = Environment.BG_COLOR
	sky.background_color = Color("16232b")
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.ambient_light_color = Color.WHITE
	sky.ambient_light_energy = .7
	environment.environment = sky
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65,-20,0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(240,240)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("35464d")
	ground.material_override = material
	add_child(ground)
	var line_material := StandardMaterial3D.new()
	line_material.albedo_color = Color("51676f")
	for offset in range(-110,111,10):
		for axis in range(2):
			var line := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(.06,.015,230) if axis == 0 else Vector3(230,.015,.06)
			line.mesh = box
			line.material_override = line_material
			line.position = Vector3(offset,.01,0) if axis == 0 else Vector3(0,.01,offset)
			add_child(line)
	camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0,58,56)
	camera.look_at(Vector3(0,0,15))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 90
	camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	label = Label.new()
	label.position = Vector2(20,16)
	label.add_theme_font_size_override("font_size",17)
	label.add_theme_color_override("font_color",Color("e3f4f6"))
	layer.add_child(label)

func _update_overlay() -> void:
	if label == null or not connected:
		return
	var mode: String = "WASD / arrows · gamepad · F8: 2m prediction fault"
	if benchmark:
		mode = "Automated input · waiting for both clients" if stage < 0 else ("SETTLED — compare both clients" if completed else "Benchmark: "+STAGES[stage])
	var coordinates: String = ""
	for id: int in views:
		var view: PrototypeKartView = views[id]
		coordinates += "\n%s  x %6.2f   z %6.2f  %s" % ["A" if roster[id] == 0 else "B",view.position.x,view.position.z,"YOU" if id == own_id else "REMOTE"]
	label.text = "NODEKINS / NETWORK LAB\nCLIENT %s → dedicated %s:%d\n%s\nOne-way +%.0fms   RTT %.0fms   loss %.0f%%\nLocal: predicted + replayed · Remote: buffered 100ms\n%s" % [client_tag,address,port,mode,link.latency_ms,rtt_ms,link.loss*100,coordinates]

func _frame_karts(delta: float) -> void:
	if camera == null or views.is_empty():
		return
	var low := Vector3(INF,0,INF)
	var high := Vector3(-INF,0,-INF)
	for view: PrototypeKartView in views.values():
		low.x = minf(low.x,view.position.x)
		low.z = minf(low.z,view.position.z)
		high.x = maxf(high.x,view.position.x)
		high.z = maxf(high.z,view.position.z)
	var center: Vector3 = (low+high)*.5
	var fraction: float = 1.0-exp(-3.0*delta)
	camera.position = camera.position.lerp(center+Vector3(0,58,56),fraction)
	camera.rotation = Vector3(deg_to_rad(-46),0,0)
	var size: float = maxf(36.0,maxf(high.x-low.x,high.z-low.z)*1.2+18.0)
	camera.size = lerpf(camera.size,size,fraction)
