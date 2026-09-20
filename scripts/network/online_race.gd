extends Node3D
## Dedicated online entry point. Main.tscn and its single-player flow remain independent.
const Link = preload("res://scripts/network/online_link.gd")
const World = preload("res://scripts/network/online_world.gd")
const Presentation = preload("res://scripts/network/online_presentation.gd")
const Pilot = preload("res://scripts/network/online_test_pilot.gd")
const COMMAND_WIDTH: int = 6
const REDUNDANCY: int = 48
const MAX_PENDING: int = 512
@export var server_role: bool = false
@export var verification: bool = false
@export var client_tag: String = "A"
@export var latency_ms: float = 0.0
var loss: float = 0.0
var jitter_ms: float = 0.0
var port: int = 29188
var expected_players: int = 2
var address: String = "127.0.0.1"
var bind_address: String = "127.0.0.1"
var output_dir: String = ""
var quit_after: float = 0.0
var disconnect_at: float = -1.0
var transport := ENetMultiplayerPeer.new()
var link := Link.new()
var world: OnlineRaceWorld
var peers: Dictionary = {}
var roster: Array[Dictionary] = []
var server_drivers: Dictionary = {}
var views: Dictionary = {}
var own_id: String = ""
var connected: bool = false
var assembled: bool = false
var tick: int = 0
var elapsed: float = 0.0
var start_tick: int = -1
var sequence: int = 0
var ack: int = 0
var pending: Dictionary = {}
var predicted_history: Dictionary = {}
var queued_snapshot: Dictionary = {}
var latest_tick: int = -1
var arrival_ms: int = 0
var playhead: float = -1.0
var motion_epochs: Dictionary = {}
var remote_epochs: Dictionary = {}
var event_sequence: int = 0
var last_event: int = 0
var event_buffer: Dictionary = {}
var events: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var profiles_seen: Dictionary = {}
var rejected_inputs: int = 0
var max_pending: int = 0
var corrections: Array[float] = []
var semantic_mismatches: int = 0
var snapshot_count: int = 0
var rtts: Array[float] = []
var rtt: float = 0.0
var hud: Label
var status_text: String = "Connecting to dedicated server…"
var evidence_tick: int = -1
var evidence_saved: bool = false
var report_written: bool = false
var finished_at: float = -1.0
var evidence_camera: Camera3D
var presentation_camera: Camera3D
var notify_events: Array[Dictionary] = []
var counted_glides: Dictionary = {}
var counted_drift_boosts: Dictionary = {}
var profiles: Dictionary = {}
var impact_ticks: Dictionary = {}
var fragments: Dictionary = {}
var maximum_datagram_payload: int = 0
var pending_effects: Array[Dictionary] = []
var measured_effects: Array[Dictionary] = []

func _ready() -> void:
	_parse_args()
	process_physics_priority = 0
	process_priority = -20
	output_dir = ProjectSettings.globalize_path(output_dir if not output_dir.is_empty() else "res://artifacts/phase8b")
	DirAccess.make_dir_recursive_absolute(output_dir)
	link.rng.seed = 881 if server_role else (882 if client_tag == "A" else 883)
	link.configure(latency_ms,loss,jitter_ms)
	multiplayer.server_relay = false
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_left)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func() -> void: _connection_error("No dedicated server at %s:%d" % [address,port]))
	multiplayer.server_disconnected.connect(func() -> void: _connection_error("Dedicated server disconnected. Return to the title screen with Escape."))
	if server_role and DisplayServer.get_name() != "headless":
		push_error("Online authority requires a separate --headless server process.")
		get_tree().quit(2)
		return
	world = _create_world()
	world.name = "World"
	world.server = server_role
	add_child(world)
	if server_role:
		AudioServer.set_bus_mute(0,true)
		transport.set_bind_ip(bind_address)
		var error: Error = transport.create_server(port,4,3)
		if error != OK:
			push_error("Dedicated bind failed: %s" % error)
			get_tree().quit(2)
			return
		multiplayer.multiplayer_peer = transport
		_connect_race_events()
		_log("server_ready",{"port":port,"players":expected_players,"headless":true,"latency":latency_ms})
	else:
		_setup_client_ui()
		var error: Error = transport.create_client(address,port,3)
		if error != OK:
			_connection_error("Cannot create client: %s" % error)
			return
		multiplayer.multiplayer_peer = transport
		_log("client_connecting",{"tag":client_tag,"address":address,"port":port})

## Session bootstrap hook; authority/prediction behavior is independent of world selection.
func _create_world() -> OnlineRaceWorld:
	return World.new()

func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = arg.trim_prefix("--").split("=",true,1)
		var value: String = pair[1] if pair.size() > 1 else ""
		match pair[0]:
			"server": server_role = true
			"client": server_role = false
			"verify": verification = true
			"tag": client_tag = value
			"address": address = value
			"bind": bind_address = value
			"port": port = int(value)
			"players": expected_players = clampi(int(value),2,4)
			"latency": latency_ms = float(value)
			"loss": loss = float(value)
			"jitter": jitter_ms = float(value)
			"output": output_dir = value
			"quit-after": quit_after = float(value)
			"disconnect-at": disconnect_at = float(value)

func _setup_client_ui() -> void:
	get_window().title = "Nodekins Online — Client "+client_tag
	get_window().size = Vector2i(640,560)
	get_window().content_scale_size = Vector2i(960,840)
	get_window().position = Vector2i(12 if client_tag == "A" else 660,80)
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := ColorRect.new()
	panel.color = Color(0.025,0.06,0.1,.85)
	panel.position = Vector2(14,14)
	panel.size = Vector2(930,254)
	layer.add_child(panel)
	hud = Label.new()
	hud.position = Vector2(28,24)
	hud.add_theme_font_size_override("font_size",22)
	layer.add_child(hud)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(100,150,140)
	camera.look_at(Vector3(0,4,0))
	camera.make_current()
	evidence_camera = Camera3D.new()
	add_child(evidence_camera)
	evidence_camera.fov = 65
	_update_hud()

func _peer_connected(id: int) -> void:
	if not server_role:
		return
	if assembled or peers.size() >= expected_players:
		deny.rpc_id(id,"This race has already started or is full. Rejoin the next server session.")
		return
	peers[id] = {"profile":PackedByteArray(),"ready":false,"ack":0,"commands":{},"credit":0.0,"stamp":Time.get_ticks_usec(),"started":false,"stalls":0,"catchups":0,"packets_tick":0,"packets":0}

func _connected() -> void:
	connected = true
	var profile: CustomizationProfile = GameSession.profile
	if verification:
		profile = CustomizationProfile.from_values([1,1,1,1,1,7,1,2,1,1,1,1,4] if client_tag == "A" else [0,1,0,1,0,4,0,0,2,0,0,0,2])
	hello.rpc_id(1,1,profile.to_wire())
	status_text = "Connected — waiting for the dedicated server's grid"

@rpc("any_peer","call_remote","reliable",0)
func hello(version: int, wire: PackedByteArray) -> void:
	if not server_role:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not peers.has(sender) or assembled:
		return
	var profile: CustomizationProfile = CustomizationProfile.from_values(wire)
	if version != 1 or wire.size() != 13 or not GameSession.library.accepts(profile):
		deny.rpc_id(sender,"Unsupported customization IDs or protocol version.")
		return
	peers[sender].profile = wire.duplicate()
	_log("profile_accepted",{"peer":sender,"bytes":wire.size(),"ids":Array(wire)})
	if peers.size() != expected_players:
		return
	for entry: Dictionary in peers.values():
		if entry.profile.is_empty():
			return
	_assemble_server()

func _assemble_server() -> void:
	assembled = true
	var slot: int = 0
	for peer: int in peers:
		var id: String = "player_%d" % (slot+1)
		peers[peer].id = id
		roster.append({"id":id,"slot":slot,"peer":peer,"profile":peers[peer].profile,"cpu":false})
		slot += 1
	while slot < 4:
		var profile := CustomizationProfile.new()
		profile.primary_color = 2 if slot == 2 else 3
		profile.body_type_id = slot % 2
		roster.append({"id":"cpu_%d" % (slot-expected_players+1),"slot":slot,"peer":0,"profile":profile.to_wire(),"cpu":true})
		slot += 1
	for entry: Dictionary in roster:
		var kart: ArcadeKart = world.add_kart(entry.id,entry.slot,entry.profile,entry.cpu)
		motion_epochs[entry.id] = 0
		profiles[entry.id] = Array(entry.profile)
		_watch_kart(kart,entry.id)
		if entry.cpu:
			var driver := KartAI.new()
			driver.racer_id = StringName(entry.id)
			driver.tuning = preload("res://resources/ai/default_ai.tres")
			driver.lane_offset = -3.2 if entry.slot == 2 else 0.0
			kart.add_child(driver)
			server_drivers[entry.id] = driver
	for peer: int in peers:
		welcome.rpc_id(peer,roster,event_sequence)
	_log("grid_assembled",{"humans":expected_players,"cpus":4-expected_players,"profiles":profiles})

@rpc("authority","call_remote","reliable",0)
func welcome(entries: Array, event_base: int) -> void:
	if server_role or assembled:
		return
	assembled = true
	roster.assign(entries)
	last_event = event_base
	for entry: Dictionary in roster:
		var local: bool = entry.peer == multiplayer.get_unique_id()
		var kart: ArcadeKart = world.add_kart(entry.id,entry.slot,entry.profile,entry.cpu)
		views[entry.id] = Presentation.new(kart,local)
		var applied: PackedByteArray = kart.get_node("Visuals").customization_profile.to_wire()
		var rider: PackedByteArray = kart.get_node("Visuals/Rider/Character").profile.to_wire()
		profiles_seen[entry.id] = {"wire":Array(entry.profile),"visual_match":applied == entry.profile,"rider_match":rider == entry.profile,"body":kart.get_node("Visuals/Rider/Character").body.name,"hair":GameSession.library.part(&"hair_id",int(entry.profile[7])).display_name}
		_log("customization_applied",{"id":entry.id,"evidence":profiles_seen[entry.id]})
		if local:
			own_id = entry.id
			kart.get_node("ChaseCamera").set_process(true)
			presentation_camera = kart.get_node("ChaseCamera/SpringArm3D/Camera3D")
			presentation_camera.make_current()
			if verification:
				var pilot: KartAI = Pilot.new()
				pilot.racer_id = StringName(own_id)
				pilot.tuning = preload("res://resources/ai/default_ai.tres")
				pilot.lane_offset = -2.7 if entry.slot == 0 else 3.2
				pilot.apply_rubber_band = false
				kart.add_child(pilot)
	# Each Kart scene has a current camera at instantiation; select ours after the full grid exists.
	presentation_camera.make_current()
	var race_audio: Node = preload("res://scenes/audio/RaceAudio.tscn").instantiate()
	race_audio.local_racer_id = StringName(own_id)
	add_child(race_audio)
	client_ready.rpc_id(1)
	status_text = "Grid ready — waiting for official countdown"

@rpc("any_peer","call_remote","reliable",0)
func client_ready() -> void:
	if not server_role or not assembled or not peers.has(multiplayer.get_remote_sender_id()):
		return
	if peers[multiplayer.get_remote_sender_id()].ready:
		return
	peers[multiplayer.get_remote_sender_id()].ready = true
	for entry: Dictionary in peers.values():
		if not entry.ready:
			return
	start_tick = tick+120

@rpc("authority","call_remote","reliable",0)
func deny(reason: String) -> void:
	_connection_error(reason)
	transport.close()

func _connection_error(reason: String) -> void:
	connected = false
	status_text = reason
	_log("connection_closed",{"reason":reason})
	_update_hud()

func _physics_process(delta: float) -> void:
	tick += 1
	elapsed += delta
	if server_role:
		_server_tick()
	elif connected and assembled and not own_id.is_empty():
		if not queued_snapshot.is_empty():
			_apply_snapshot(queued_snapshot)
			queued_snapshot = {}
		_client_tick()
	if quit_after > 0 and elapsed >= quit_after:
		_write_report()
		transport.close()
		get_tree().quit()
	if not server_role and disconnect_at > 0 and RaceManager.elapsed >= disconnect_at and connected:
		_log("intentional_disconnect",{"race_time":RaceManager.elapsed})
		transport.close()
		connected = false
		status_text = "Disconnected test client — server continues without this kart"
		_write_report()

func _server_tick() -> void:
	for measurement: Dictionary in pending_effects.duplicate():
		if RaceManager.elapsed >= measurement.due:
			if world.karts.has(measurement.subject):
				var kart: ArcadeKart = world.karts[measurement.subject]
				measurement.speed_after = kart.speed
				measurement.suppression = kart.controls.suppression_remaining
				measurement.boost_remaining = kart.drift.boost_remaining
				measured_effects.append(measurement)
				_log("effect_measured",measurement)
			pending_effects.erase(measurement)
	if start_tick > 0 and tick >= start_tick:
		start_tick = -1
		RaceManager.start_race()
	for peer: int in peers:
		var entry: Dictionary = peers[peer]
		if not entry.has("id") or not world.karts.has(entry.id):
			continue
		var now: int = Time.get_ticks_usec()
		entry.credit = minf(60,entry.credit+float(now-int(entry.stamp))*.00006)
		entry.stamp = now
		var commands: Dictionary = entry.commands
		if not entry.started:
			if commands.size() < 3:
				continue
			entry.started = true
		var steps: int = 2 if commands.size() > 6 else 1
		for index in range(steps):
			if entry.credit < 1:
				break
			var next: int = entry.ack+1
			if not commands.has(next):
				entry.stalls += 1
				break
			world.simulate(world.karts[entry.id],commands[next])
			commands.erase(next)
			entry.ack = next
			entry.credit -= 1
			if index > 0:
				entry.catchups += 1
	for id: String in server_drivers:
		if world.karts.has(id):
			world.simulate(world.karts[id],world.karts[id].controls.network_command())
	# Snapshot after RaceManager, Areas, inventory timers and projectile sweeps have run.
	if assembled and tick % 3 == 0:
		_send_snapshot.call_deferred()

func _client_tick() -> void:
	var kart: ArcadeKart = world.karts[own_id]
	if pending.size() >= MAX_PENDING:
		_connection_error("Input acknowledgement timed out. Restart client for the next race.")
		transport.close()
		return
	if not verification:
		kart.controls.use_player_input()
	var command: PackedFloat32Array = kart.controls.network_command()
	sequence += 1
	pending[sequence] = command
	world.simulate(kart,command,true)
	predicted_history[sequence] = kart.network_snapshot()
	max_pending = maxi(max_pending,pending.size())
	if tick % 2 == 0:
		var first: int = ack+1
		var values := PackedFloat32Array()
		for number in range(first,mini(sequence+1,first+REDUNDANCY)):
			if pending.has(number):
				values.append_array(pending[number])
		if not values.is_empty():
			link.enqueue(&"input",1,[first,values])
	if tick % 30 == 0:
		link.enqueue(&"ping",1,[Time.get_ticks_msec()])
	kart.set_block_signals(false)
	kart.motion_updated.emit(kart.speed,kart.controls.throttle,kart.controls.brake)
	kart.set_block_signals(true)

@rpc("any_peer","call_remote","unreliable",1)
func submit_input(first: int, packed: PackedFloat32Array) -> void:
	if not server_role:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not peers.has(sender) or not peers[sender].has("id"):
		return
	var entry: Dictionary = peers[sender]
	if entry.packets_tick != tick:
		entry.packets_tick = tick
		entry.packets = 0
	entry.packets += 1
	if entry.packets > 12 or packed.is_empty() or packed.size() % COMMAND_WIDTH != 0 or packed.size() > REDUNDANCY*COMMAND_WIDTH or first < 1 or first > entry.ack+120:
		rejected_inputs += 1
		return
	var count: int = int(packed.size()/float(COMMAND_WIDTH))
	for index in range(count):
		var command: PackedFloat32Array = packed.slice(index*COMMAND_WIDTH,(index+1)*COMMAND_WIDTH)
		for field in range(COMMAND_WIDTH):
			if not is_finite(command[field]) or command[field] < (-1.0 if field == 2 else 0.0) or command[field] > 1.0:
				rejected_inputs += 1
				return
		if first+index > entry.ack+120:
			rejected_inputs += 1
			return
	for index in range(count):
		var number: int = first+index
		if number > entry.ack and not entry.commands.has(number):
			entry.commands[number] = packed.slice(index*COMMAND_WIDTH,(index+1)*COMMAND_WIDTH)

func _send_snapshot() -> void:
	var states: Dictionary = {}
	var acks: Dictionary = {}
	for id: String in world.karts:
		states[id] = world.karts[id].network_snapshot()
		acks[id] = -1
	for peer: int in peers:
		if peers[peer].has("id"):
			acks[peers[peer].id] = peers[peer].ack
	var race: Dictionary = RaceManager.online_snapshot()
	var capture: bool = verification and evidence_tick < 0 and RaceManager.phase == RaceManager.Phase.RACING and RaceManager.elapsed >= 4.0
	if capture:
		evidence_tick = tick
	var packet: Dictionary = {"tick":tick,"states":states,"acks":acks,"epochs":motion_epochs.duplicate(),"race":race,"items":world.item_snapshot(),"digest":_race_digest(race),"capture":capture}
	var raw: PackedByteArray = var_to_bytes(packet)
	var compressed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var fragment_count: int = ceili(compressed.size()/900.0)
	for peer: int in peers:
		if peers[peer].ready:
			for part in range(fragment_count):
				var payload: PackedByteArray = compressed.slice(part*900,(part+1)*900)
				maximum_datagram_payload = maxi(maximum_datagram_payload,payload.size())
				link.enqueue(&"fragment",peer,[tick,part,fragment_count,raw.size(),payload])
	if capture:
		# Reliable delivery of the same actual race snapshot ensures both evidence frames exist.
		for peer: int in peers:
			link.enqueue(&"evidence",peer,[packet],true)
		_log("evidence_moment",{"tick":tick,"digest":packet.digest,"race":race})
	if tick % 150 == 0:
		var sample: Dictionary = {"tick":tick,"digest":packet.digest,"race":race}
		samples.append(sample)
		_log("race_sample",sample)
	if RaceManager.phase == RaceManager.Phase.FINISHED:
		if finished_at < 0:
			finished_at = elapsed
		elif elapsed-finished_at > 4 and not report_written:
			_write_report()

@rpc("authority","call_remote","unreliable",2)
func receive_fragment(stamp: int, index: int, count: int, raw_size: int, payload: PackedByteArray) -> void:
	if server_role or stamp <= latest_tick or count < 1 or count > 64 or index < 0 or index >= count or raw_size < 1 or raw_size > 65536 or payload.size() > 900:
		return
	if not fragments.has(stamp):
		fragments[stamp] = {"count":count,"size":raw_size,"parts":{}}
	var entry: Dictionary = fragments[stamp]
	if entry.count != count or entry.size != raw_size:
		return
	entry.parts[index] = payload
	if entry.parts.size() == count:
		var packed := PackedByteArray()
		for part in range(count):
			packed.append_array(entry.parts[part])
		var decoded: Variant = bytes_to_var(packed.decompress(raw_size,FileAccess.COMPRESSION_DEFLATE))
		if decoded is Dictionary and decoded.get("tick",-1) == stamp:
			_receive_snapshot(decoded)
		fragments.erase(stamp)
	for old: int in fragments.keys():
		if old <= latest_tick or old < stamp-30:
			fragments.erase(old)

func _receive_snapshot(packet: Dictionary) -> void:
	if server_role or int(packet.tick) <= latest_tick:
		return
	queued_snapshot = packet
	latest_tick = packet.tick
	arrival_ms = Time.get_ticks_msec()
	if playhead < 0:
		playhead = latest_tick-6.0

func _apply_snapshot(packet: Dictionary) -> void:
	RaceManager.apply_online_snapshot(packet.race)
	world.apply_items(packet.items)
	if _race_digest(RaceManager.online_snapshot()) != packet.digest:
		semantic_mismatches += 1
	snapshot_count += 1
	for id: String in packet.states:
		if not world.karts.has(id):
			continue
		var kart: ArcadeKart = world.karts[id]
		var state: Dictionary = packet.states[id]
		if id == own_id:
			var next_ack: int = packet.acks[id]
			if next_ack < ack or next_ack > sequence:
				continue
			var previous: Transform3D = kart.global_transform
			var epoch: int = packet.epochs[id]
			var teleport: bool = remote_epochs.has(id) and remote_epochs[id] != epoch
			remote_epochs[id] = epoch
			if predicted_history.has(next_ack):
				corrections.append(predicted_history[next_ack].pose.origin.distance_to(state.pose.origin))
			ack = next_ack
			kart.network_restore(state)
			for number: int in pending.keys():
				if number <= ack:
					pending.erase(number)
					predicted_history.erase(number)
			for number in range(ack+1,sequence+1):
				if pending.has(number):
					world.simulate(kart,pending[number],true)
					predicted_history[number] = kart.network_snapshot()
			views[id].reconcile(previous,teleport)
		else:
			# Keep the rendered pose on its interpolation timeline when mechanics refresh.
			var rendered_pose: Transform3D = kart.global_transform
			kart.network_restore(state,false)
			kart.global_transform = rendered_pose
			views[id].enqueue(packet.tick,state)
			kart.set_block_signals(false)
			kart.motion_updated.emit(kart.speed,kart.controls.throttle,kart.controls.brake)
			kart.set_block_signals(true)
	if packet.tick % 150 == 0:
		samples.append({"tick":packet.tick,"digest":packet.digest,"race":RaceManager.online_snapshot()})
	if RaceManager.phase == RaceManager.Phase.FINISHED:
		if finished_at < 0:
			finished_at = elapsed
		elif elapsed-finished_at > 3 and not report_written:
			_write_report()
	status_text = "LIVE — server tick %d · %s" % [packet.tick,RaceManager.countdown_text if not RaceManager.countdown_text.is_empty() else ("RESULTS" if RaceManager.phase == RaceManager.Phase.FINISHED else "authoritative standings")]

func _process(delta: float) -> void:
	_flush_link()
	if server_role:
		return
	if latest_tick >= 0:
		var desired: float = latest_tick-6.0+(Time.get_ticks_msec()-arrival_ms)*.06
		playhead += delta*60.0
		playhead = lerpf(playhead,desired,1-exp(-2.5*delta))
	for id: String in views:
		if world.karts.has(id):
			views[id].render(delta,playhead)
	for box: ItemBox in world.items.boxes:
		box.visual.rotation.y += delta*1.8
	_update_hud()

func _update_hud() -> void:
	if hud == null:
		return
	var text: String = "NODEKINS ONLINE · CLIENT %s · +%.0fms one-way / RTT %.0fms\n%s\n" % [client_tag,latency_ms,rtt,status_text]
	for row: Dictionary in RaceManager.get_standings():
		var inv: KartInventory = world.items.inventories.get(StringName(row.id))
		var item: String = str(inv.held.display_name) if inv != null and inv.held != null else "—"
		text += "%d. %-10s  LAP %d/3  CP %d  %-8s %s\n" % [row.position,row.id,row.lap,row.last_checkpoint,"FINISHED" if row.finished else "ITEM "+item,"YOU" if row.id == own_id else ""]
	text += "WASD / gamepad · Space drift · E item · R recovery · Esc title"
	hud.text = text

func _watch_kart(kart: ArcadeKart, id: String) -> void:
	kart.collision_impact.connect(func(strength: float) -> void:
		if strength >= 2.5 and tick-int(impact_ticks.get(id,-30)) >= 18:
			impact_ticks[id] = tick
			_record("impact",{"id":id,"strength":strength}))
	kart.respawned.connect(func() -> void: motion_epochs[id] = int(motion_epochs.get(id,0))+1)
	kart.drift.drift_started.connect(func() -> void: _record("drift_start",{"id":id}))
	kart.drift.drift_ended.connect(func() -> void: _record("drift_end",{"id":id}))
	kart.drift.charge_tier_changed.connect(func(value: int) -> void: _record("drift_tier",{"id":id,"tier":value}))
	kart.drift.boost_started.connect(func(tier: int,multiplier: float,duration: float) -> void:
		counted_drift_boosts[id] = int(counted_drift_boosts.get(id,0))+1
		_record("boost",{"id":id,"tier":tier,"multiplier":multiplier,"duration":duration}))
	kart.glide.launched.connect(func() -> void: _record("glide_launch",{"id":id}))
	kart.glide.ended.connect(func(flight: Dictionary) -> void:
		if flight.reason == "landed":
			counted_glides[id] = int(counted_glides.get(id,0))+1
		_record("glide_end",{"id":id,"flight":flight}))

func _connect_race_events() -> void:
	RaceManager.race_finished.connect(func() -> void: _record("race_end",{}))
	world.items.item_event.connect(func(event: Dictionary) -> void: _record("item",event))
	RaceManager.countdown_changed.connect(func(text: String) -> void: _record("countdown",{"text":text}))
	RaceManager.checkpoint_passed.connect(func(id: StringName,checkpoint: int) -> void: _record("checkpoint",{"id":str(id),"checkpoint":checkpoint,"state":RaceManager.get_racer_state(id)}))
	RaceManager.lap_completed.connect(func(id: StringName,laps: int,lap_time: float) -> void: _record("lap",{"id":str(id),"laps":laps,"lap_time":lap_time}))
	RaceManager.racer_finished.connect(func(id: StringName,finish_position: int,time: float) -> void: _record("finish",{"id":str(id),"position":finish_position,"time":time}))
	RaceManager.recovery_started.connect(func(id: StringName,checkpoint: int,reason: String) -> void: _record("recovery",{"id":str(id),"checkpoint":checkpoint,"reason":reason}))

func _record(kind: String, data: Dictionary) -> void:
	if kind == "item" and data.kind in ["hit","boost"]:
		pending_effects.append({"kind":data.kind,"item":data.item,"subject":data.target if data.kind == "hit" else data.racer,"due":RaceManager.elapsed+.35,"speed_before":data.get("speed_before",0.0),"event_time":RaceManager.elapsed})
	event_sequence += 1
	var event: Dictionary = {"serial":event_sequence,"kind":kind,"data":data.duplicate(true),"tick":tick,"time":RaceManager.elapsed}
	events.append(event)
	for peer: int in peers:
		if peers[peer].ready:
			link.enqueue(&"event",peer,[event],true)
	if kind in ["lap","finish","item","recovery","glide_launch","glide_end"]:
		_log("event",event)

@rpc("authority","call_remote","reliable",0)
func receive_event(event: Dictionary) -> void:
	if server_role or event.serial <= last_event:
		return
	event_buffer[event.serial] = event
	while event_buffer.has(last_event+1):
		last_event += 1
		var next: Dictionary = event_buffer[last_event]
		event_buffer.erase(last_event)
		events.append(next)
		_present_event(next)
		if next.kind in ["lap","finish","item","glide_launch","glide_end","disconnect"]:
			_log("event_received",next)

func _present_event(event: Dictionary) -> void:
	var data: Dictionary = event.data
	if event.kind == "countdown":
		RaceManager.countdown_changed.emit(data.text)
		return
	if event.kind == "lap":
		RaceManager.lap_completed.emit(StringName(data.id),data.laps,data.lap_time)
		return
	if event.kind == "finish":
		RaceManager.racer_finished.emit(StringName(data.id),data.position,data.time)
		if data.id == own_id:
			var sound := AudioStreamPlayer.new()
			sound.bus = &"SFX"
			sound.stream = preload("res://assets/audio/victory.wav") if data.position == 1 else preload("res://assets/audio/results.wav")
			add_child(sound)
			sound.play()
			sound.finished.connect(sound.queue_free)
		return
	if event.kind == "race_end":
		RaceManager.race_finished.emit()
		return
	if event.kind == "impact" and world.karts.has(data.id):
		var body: ArcadeKart = world.karts[data.id]
		body.set_block_signals(false)
		body.collision_impact.emit(data.strength)
		body.set_block_signals(true)
		return
	if event.kind == "item":
		var id: String = str(data.get("target",data.get("racer","")))
		var inv: KartInventory = world.items.inventories.get(StringName(id))
		var definition: ItemDefinition = world.item_definition(data.get("item",""))
		if inv != null and definition != null:
			if data.kind == "hit":
				inv.item_hit.emit(definition)
			elif data.kind == "use":
				inv.item_used.emit(definition)
		if data.kind == "pickup":
			var box: Node = world.items.get_node_or_null(NodePath(data.box))
			if box != null:
				box.picked_up.emit()
		return
	if not data.has("id") or not world.karts.has(data.id):
		return
	var kart: ArcadeKart = world.karts[data.id]
	kart.drift.set_block_signals(false)
	kart.glide.set_block_signals(false)
	match event.kind:
		"drift_start": kart.drift.drift_started.emit()
		"drift_end": kart.drift.drift_ended.emit()
		"drift_tier": kart.drift.charge_tier_changed.emit(data.tier)
		"boost": kart.drift.boost_started.emit(data.tier,data.multiplier,data.duration)
		"glide_launch": kart.glide.launched.emit()
		"glide_end": kart.glide.ended.emit(data.flight)
	kart.drift.set_block_signals(true)
	kart.glide.set_block_signals(true)

func _peer_left(peer: int) -> void:
	if not server_role or not peers.has(peer):
		return
	var entry: Dictionary = peers[peer]
	peers.erase(peer)
	if entry.has("id"):
		var id: String = entry.id
		world.remove_kart(id)
		motion_epochs.erase(id)
		_record("disconnect",{"id":id,"remaining_humans":peers.size()})
		for other: int in peers:
			remove_racer.rpc_id(other,id)
		_log("racer_removed",{"id":id,"remaining":peers.size(),"race_continues":true})

@rpc("authority","call_remote","reliable",0)
func remove_racer(id: String) -> void:
	if server_role:
		return
	world.remove_kart(id)
	views.erase(id)
	_log("racer_removed",{"id":id})

@rpc("any_peer","call_remote","unreliable",1)
func ping(stamp: int) -> void:
	if server_role and peers.has(multiplayer.get_remote_sender_id()):
		link.enqueue(&"pong",multiplayer.get_remote_sender_id(),[stamp])

@rpc("authority","call_remote","unreliable",2)
func pong(stamp: int) -> void:
	rtt = Time.get_ticks_msec()-stamp
	rtts.append(rtt)

func _flush_link() -> void:
	if transport.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	for packet: Dictionary in link.take_ready():
		if server_role and not peers.has(packet.peer):
			continue
		var args: Array = packet.args
		match packet.kind:
			&"input": submit_input.rpc_id(packet.peer,args[0],args[1])
			&"fragment": receive_fragment.rpc_id(packet.peer,args[0],args[1],args[2],args[3],args[4])
			&"event": receive_event.rpc_id(packet.peer,args[0])
			&"evidence": evidence.rpc_id(packet.peer,args[0])
			&"ping": ping.rpc_id(packet.peer,args[0])
			&"pong": pong.rpc_id(packet.peer,args[0])

@rpc("authority","call_remote","reliable",0)
func evidence(packet: Dictionary) -> void:
	if server_role or evidence_saved:
		return
	evidence_saved = true
	evidence_tick = packet.tick
	var sample: Dictionary = {"tick":packet.tick,"digest":packet.digest,"race":packet.race,"items":packet.items.inventories,"profiles":profiles_seen}
	_save_json("client_"+client_tag+"_moment.json",sample)
	_capture_moment.call_deferred(packet)

func _capture_moment(packet: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output_dir+"/client_"+client_tag+"_live.png")
	# Synchronized evidence view of a real server tick. Live simulation continues below.
	var duplicates: Array[Node3D] = []
	var previous_visibility: Dictionary = {}
	for id: String in packet.states:
		if not world.karts.has(id):
			continue
		var kart: ArcadeKart = world.karts[id]
		previous_visibility[id] = kart.visible
		kart.hide()
		var copy: Node3D = kart.get_node("Visuals").duplicate()
		copy.set_script(null)
		copy.process_mode = Node.PROCESS_MODE_DISABLED
		# Clear scripts recursively so duplicates are evidence meshes/poses, not controllers.
		for node: Node in copy.find_children("*","",true,false):
			if node.get_script() != null:
				node.set_script(null)
		add_child(copy)
		copy.global_transform = packet.states[id].pose
		var canopy: Node3D = kart.get_node("Glide/Canopy").duplicate()
		copy.add_child(canopy)
		canopy.position = Vector3.ZERO
		canopy.rotation = Vector3(0,0,packet.states[id].glide.bank)
		canopy.visible = packet.states[id].glide.active
		duplicates.append(copy)
	var low := Vector3(INF,INF,INF)
	var high := Vector3(-INF,-INF,-INF)
	for state: Dictionary in packet.states.values():
		low = low.min(state.pose.origin)
		high = high.max(state.pose.origin)
	var focus: Vector3 = (low+high)*.5
	var reach: float = maxf(1.0,Vector2(high.x-low.x,high.z-low.z).length()/18.0)
	evidence_camera.position = focus+Vector3(12,11,17)*reach
	evidence_camera.look_at(focus+Vector3.UP)
	evidence_camera.make_current()
	var old_text: String = hud.text
	hud.text = "NODEKINS ONLINE · CLIENT %s\nSYNCED EVIDENCE · SERVER TICK %d · %.2fs\n" % [client_tag,packet.tick,packet.race.elapsed]
	for row: Dictionary in packet.race.rows:
		hud.text += "%d. %-10s  LAP %d/3  CP %d  %s\n" % [row.position,row.id,row.lap,row.last_checkpoint,"YOU" if row.id == own_id else ""]
	set_process(false)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output_dir+"/client_"+client_tag+"_race.png")
	set_process(true)
	hud.text = old_text
	for id: String in previous_visibility:
		if world.karts.has(id):
			world.karts[id].visible = previous_visibility[id]
	for copy: Node3D in duplicates:
		copy.queue_free()
	presentation_camera.make_current()
	_log("screenshot",{"tick":packet.tick,"path":output_dir+"/client_"+client_tag+"_race.png","type":"synchronized_authoritative_tick"})

func _race_digest(state: Dictionary) -> String:
	var values: Array = [state.phase,state.countdown,state.laps]
	for row: Dictionary in state.rows:
		values.append([row.id,row.position,row.completed_laps,row.last_checkpoint,row.next_checkpoint,row.finished,row.finish_order,row.finish_time])
	return JSON.stringify(values).sha256_text()

func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0
	var ordered: Array[float] = values.duplicate()
	ordered.sort()
	return ordered[clampi(ceili(fraction*ordered.size())-1,0,ordered.size()-1)]

func _save_json(filename: String, value: Dictionary) -> void:
	var file := FileAccess.open(output_dir+"/"+filename,FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value,"\t"))

func _write_report() -> void:
	if report_written:
		return
	report_written = true
	var correction_report: Dictionary = {}
	for id: String in views:
		correction_report[id] = {"max_rebase_jump":views[id].max_rebase_jump,"max_offset":views[id].max_offset,"max_correction_rate":views[id].max_correction_rate,"held_frames":views[id].held_frames}
	var queues: Dictionary = {}
	for peer: int in peers:
		queues[str(peer)] = {"ack":peers[peer].ack,"stalls":peers[peer].stalls,"catchups":peers[peer].catchups}
	var report: Dictionary = {"role":"server" if server_role else client_tag,"latency_ms":latency_ms,"loss":loss,"jitter_ms":jitter_ms,"headless":DisplayServer.get_name() == "headless","race":RaceManager.online_snapshot(),"events":events,"samples":samples,"profiles":profiles if server_role else profiles_seen,"rejected_inputs":rejected_inputs,"snapshots":snapshot_count,"race_mismatches":semantic_mismatches,"max_pending":max_pending,"prediction_error_p95":_percentile(corrections,.95),"prediction_error_max":_percentile(corrections,1),"presentation":correction_report,"rtt_median":_percentile(rtts,.5),"rtt_p95":_percentile(rtts,.95),"glide_landings":counted_glides,"boosts":counted_drift_boosts,"peer_queues":queues,"measured_effects":measured_effects,"last_event":event_sequence if server_role else last_event,"dropped":link.dropped,"maximum_snapshot_payload":maximum_datagram_payload,"elapsed":elapsed}
	var filename: String = "server.json" if server_role else "client_"+client_tag+".json"
	_save_json(filename,report)
	_log("report",{"file":output_dir+"/"+filename,"standings":RaceManager.get_standings(),"mismatches":semantic_mismatches})

func _unhandled_input(event: InputEvent) -> void:
	if not server_role and event.is_action_pressed("ui_cancel"):
		transport.close()
		get_tree().change_scene_to_file("res://scenes/ui/Main.tscn")

func _exit_tree() -> void:
	transport.close()
	RaceManager.set_replica_mode(false)
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _log(kind: String, data: Dictionary) -> void:
	print("ONLINE ",JSON.stringify({"event":kind,"role":"server" if server_role else client_tag,"data":data}))
