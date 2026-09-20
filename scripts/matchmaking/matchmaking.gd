extends Node
## Queue/assignment control plane. Its ENet peer is independent of the race's peer.
signal changed
signal failed(message: String)
const SETTINGS = preload("res://resources/matchmaking/default_settings.tres")
var settings: MatchmakingSettings = SETTINGS.duplicate()
var api := SceneMultiplayer.new()
var peer := ENetMultiplayerPeer.new()
var wire: Node
var service: bool = false
var state: String = "idle"
var message: String = "Ready to race online."
var request_id: int = 0
var search_started: int = 0
var assignment: Dictionary = {}
var queued: Array[int] = []
var requests: Dictionary = {}
var active: Dictionary = {}
var rng := RandomNumberGenerator.new()
var eligible_since: float = -1.0
var now: float = 0.0
var next_poll: float = 0.0
var events: Array[Dictionary] = []
var output: String = ""
var worker_executable: String = ""
var pending_profile: PackedByteArray
var connection_deadline: float = 0.0
var assignment_deadline: float = 0.0
var verification: bool = false
var test_tag: String = "A"
var test_scenario: String = "race"
var test_delay: float = 0.0
var test_latency: float = 75.0
var test_quit_after: float = 0.0
var test_driver: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_args()
	api.root_path = get_path()
	api.server_relay = false
	get_tree().set_multiplayer(api,get_path())
	wire = Node.new()
	wire.name = "Wire"
	wire.set_script(preload("res://scripts/matchmaking/match_wire.gd"))
	add_child(wire)
	api.connected_to_server.connect(_service_connected)
	api.connection_failed.connect(func() -> void: fail("Matchmaking is unavailable. Please try again."))
	api.server_disconnected.connect(_service_lost)
	api.peer_disconnected.connect(_peer_left)
	rng.randomize()
	if verification and not service:
		start_test.call_deferred()

func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = arg.trim_prefix("--").split("=",true,1)
		var value: String = pair[1] if pair.size() > 1 else ""
		match pair[0]:
			"match-service": service = true
			"mm-address": settings.service_address = value
			"mm-port": settings.service_port = int(value)
			"mm-race-port": settings.race_port = int(value)
			"mm-bind": settings.bind_address = value
			"mm-advertise": settings.advertised_race_address = value
			"mm-output": output = value
			"mm-worker-executable": worker_executable = value
			"mm-verify": verification = true
			"mm-tag": test_tag = value
			"mm-scenario": test_scenario = value
			"mm-delay": test_delay = float(value)
			"mm-latency": test_latency = float(value)
			"mm-quit-after": test_quit_after = float(value)
	output = ProjectSettings.globalize_path(output if not output.is_empty() else "user://matchmaking")

func start_service() -> void:
	service = true
	if DisplayServer.get_name() != "headless":
		push_error("Matchmaking service must run independently with --headless.")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	peer.set_bind_ip(settings.bind_address)
	var error: Error = peer.create_server(settings.service_port,64)
	if error != OK:
		push_error("Matchmaking service bind failed: %s" % error)
		get_tree().quit(2)
		return
	api.multiplayer_peer = peer
	_log("service_ready",{"port":settings.service_port,"minimum":settings.minimum_players,"worker_slots":1})

func find_match() -> void:
	if service or state in ["connecting","queued","allocating","connecting_race","in_race"]:
		return
	request_id += 1
	assignment.clear()
	pending_profile = GameSession.profile.to_wire()
	search_started = Time.get_ticks_msec()
	_set_state("connecting","Contacting matchmaking…")
	connection_deadline = now+settings.connect_timeout
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_service_connected()
		return
	peer.close()
	peer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(settings.service_address,settings.service_port)
	if error != OK:
		fail("Could not contact matchmaking. Please try again.")
		return
	api.multiplayer_peer = peer

func _service_connected() -> void:
	if service or state != "connecting":
		return
	wire.find_match.rpc_id(1,request_id,pending_profile)
	_set_state("queued","Searching for racers…")

func cancel() -> void:
	if service:
		return
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		wire.cancel_match.rpc_id(1,request_id)
	request_id += 1 # Any delayed status/assignment for the canceled request is obsolete.
	assignment.clear()
	connection_deadline = 0
	assignment_deadline = 0
	_set_state("idle","Search canceled. Find another match whenever you're ready.")

func fail(reason: String) -> void:
	if service or state == "error":
		return
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		wire.cancel_match.rpc_id(1,request_id)
	request_id += 1
	assignment.clear()
	assignment_deadline = 0
	_set_state("error",reason)
	failed.emit(reason)

func _service_lost() -> void:
	if state == "in_race":
		return # The separate race connection remains authoritative and usable.
	if state in ["connecting","queued","allocating","connecting_race"]:
		fail("Lost the matchmaking connection. Please try again.")

func queue_request(sender: int, number: int, profile: PackedByteArray) -> void:
	if not service or number < 1 or number > 2147483647:
		return
	if profile.size() != 13 or not GameSession.library.accepts(CustomizationProfile.from_values(profile)):
		_publish(sender,number,"error","Your appearance data is unsupported. Update the game and try again.")
		return
	if requests.has(sender):
		return # Idempotent; one outstanding request per connection.
	requests[sender] = {"request":number,"profile":profile.duplicate()}
	queued.append(sender)
	_publish(sender,number,"queued","Searching for racers…")
	_log("queued",{"peer":sender,"request":number,"profile":Array(profile),"waiting":queued.size()})

func queue_cancel(sender: int, number: int) -> void:
	if not service or not requests.has(sender) or requests[sender].request != number:
		return
	_remove_request(sender)
	_log("canceled",{"peer":sender,"request":number,"waiting":queued.size()})

func _peer_left(sender: int) -> void:
	if service and requests.has(sender):
		_remove_request(sender)
		_log("queue_disconnect",{"peer":sender,"waiting":queued.size()})

func _remove_request(sender: int) -> void:
	queued.erase(sender)
	requests.erase(sender)
	if not active.is_empty():
		for member: Dictionary in active.members:
			if member.peer == sender:
				active.canceled.append(member.ticket)
				_write_json(active.directory+"/canceled.json",{"tickets":active.canceled})
	if queued.size() < settings.minimum_players:
		eligible_since = -1

func receive_status(number: int, value: String, detail: String, data: Dictionary) -> void:
	if service or number != request_id or state in ["idle","error","in_race"]:
		return
	if value == "assigned":
		var entry: RaceTrackEntry = GameSession.catalog.track(StringName(data.get("track","")))
		if entry == null or entry.online_world == null or not data.has_all(["address","port","ticket","match"]):
			fail("This match needs an unavailable track. Update the game and try again.")
			return
		assignment = data.duplicate(true)
		assignment.profile = pending_profile.duplicate()
		assignment_deadline = now+settings.admission_timeout+settings.connect_timeout+5
		_set_state("connecting_race","Match found · "+entry.display_name+"\nConnecting to your race…")
		_log("assigned",{"match":data.match,"track":data.track,"port":data.port})
		_enter_race.call_deferred(number)
	elif value == "error":
		fail(detail)
	else:
		_set_state(value,detail)

func _enter_race(number: int) -> void:
	if number != request_id or state != "connecting_race":
		return
	if verification and test_scenario == "transition_drop":
		peer.close()
		fail("Test connection interrupted during race assignment. Please try again.")
		return
	var error: Error = get_tree().change_scene_to_file("res://scenes/matchmaking/MatchedRace.tscn")
	if error != OK:
		fail("The race could not load. Please try again.")

func race_connected() -> void:
	if state == "connecting_race":
		assignment_deadline = 0
		_set_state("in_race","Connected to your race.")

func _set_state(value: String, detail: String) -> void:
	if state == value and message == detail:
		return
	state = value
	message = detail
	changed.emit()

func search_seconds() -> float:
	return maxf(0,(Time.get_ticks_msec()-search_started)/1000.0)

func _publish(target: int, number: int, value: String, detail: String, data: Dictionary = {}) -> void:
	if api.get_peers().has(target):
		wire.update_status.rpc_id(target,number,value,detail,data)

func _process(delta: float) -> void:
	now += delta
	if service:
		if now >= next_poll:
			next_poll = now+.2
			_service_tick()
	elif state == "connecting" and now > connection_deadline:
		peer.close()
		fail("Matchmaking did not respond. Please try again.")
	elif state == "connecting_race" and assignment_deadline > 0 and now > assignment_deadline:
		fail("The race connection timed out. Please try again.")
	if test_quit_after > 0 and now > test_quit_after:
		get_tree().quit()

func _service_tick() -> void:
	if not active.is_empty():
		var status: Dictionary = _read_json(active.directory+"/status.json")
		if not OS.is_process_running(active.pid):
			_end_session("The race server stopped before the match could finish. Please try again.")
		elif status.get("state","") == "finished":
			_end_session("")
		elif now-active.created > settings.match_timeout:
			_end_session("The race server timed out. Please try again.")
		elif not active.delivered:
			if status.get("state","") == "admitting" and status.get("match","") == active.id:
				active.delivered = true
				for member: Dictionary in active.members:
					if requests.has(member.peer) and requests[member.peer].request == member.request:
						_publish(member.peer,member.request,"assigned","Match ready",{"address":settings.advertised_race_address,"port":settings.race_port,"track":active.track,"match":active.id,"ticket":member.ticket})
				_log("assigned",{"match":active.id,"track":active.track,"members":active.members.size()})
			elif now-active.created > settings.assignment_timeout:
				_end_session("A race server could not be assigned. Please try again.")
		elif status.get("state","") == "running" and not active.running:
			active.running = true
			_log("race_running",{"match":active.id,"track":active.track,"humans":status.get("humans",0)})
	if not active.is_empty():
		for id: int in queued:
			_publish(id,requests[id].request,"queued","Searching… waiting for the next available race server.")
		return
	if queued.size() >= settings.minimum_players:
		if eligible_since < 0:
			eligible_since = now
		elif now-eligible_since >= settings.grouping_seconds:
			_form_match()

func _form_match() -> void:
	var available: Array[RaceTrackEntry] = []
	for entry: RaceTrackEntry in GameSession.catalog.tracks:
		if entry.online_world != null:
			available.append(entry)
	if available.is_empty():
		for id: int in queued.duplicate():
			_publish(id,requests[id].request,"error","No race tracks are available. Please try again later.")
			requests.erase(id)
		queued.clear()
		return
	var track: RaceTrackEntry = available[rng.randi_range(0,available.size()-1)]
	var identity: String = Crypto.new().generate_random_bytes(8).hex_encode()
	var directory: String = output+"/match_"+identity
	DirAccess.make_dir_recursive_absolute(directory)
	var members: Array[Dictionary] = []
	while not queued.is_empty() and members.size() < settings.maximum_players:
		var id: int = queued.pop_front()
		members.append({"peer":id,"request":requests[id].request,"profile":Array(requests[id].profile),"ticket":Crypto.new().generate_random_bytes(24).hex_encode()})
		_publish(id,requests[id].request,"allocating","Racers found. Preparing your race…")
	eligible_since = -1
	var manifest: Dictionary = {"match":identity,"track":str(track.id),"members":members,"admission_timeout":settings.admission_timeout,"created":Time.get_unix_time_from_system()}
	_write_json(directory+"/reservation.json",manifest)
	var executable: String = worker_executable if not worker_executable.is_empty() else OS.get_executable_path()
	var args := PackedStringArray(["--headless","--debug","--path",ProjectSettings.globalize_path("res://"),"--log-file",directory+"/server.log","res://scenes/matchmaking/MatchedRace.tscn","--","--server","--port="+str(settings.race_port),"--bind="+settings.bind_address,"--reservation="+directory+"/reservation.json","--output="+directory,"--quit-after="+str(settings.match_timeout+30)])
	if verification:
		args.append_array(["--verify","--latency="+str(test_latency)])
	var pid: int = OS.create_process(executable,args) if FileAccess.file_exists(executable) else -1
	active = {"id":identity,"track":str(track.id),"directory":directory,"members":members,"canceled":[],"pid":pid,"created":now,"delivered":false,"running":false}
	_log("grouped",{"match":identity,"track":str(track.id),"candidate_count":available.size(),"humans":members.size(),"pid":pid,"directory":directory})
	if pid < 0:
		_end_session("A race server could not be started. Please try again.")

func _end_session(reason: String) -> void:
	if active.is_empty():
		return
	for member: Dictionary in active.members:
		if not reason.is_empty():
			_publish(member.peer,member.request,"error",reason)
		if requests.has(member.peer) and requests[member.peer].request == member.request:
			requests.erase(member.peer)
	if active.pid > 0 and OS.is_process_running(active.pid):
		OS.kill(active.pid)
	_log("session_released",{"match":active.id,"reason":reason})
	active.clear()

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data,"\t"))
		file.close()
		DirAccess.rename_absolute(path+".tmp",path)

func _log(kind: String, data: Dictionary) -> void:
	var event: Dictionary = {"event":kind,"time":now,"data":data}
	events.append(event)
	print("MATCHMAKING ",JSON.stringify(event))
	if service:
		_write_json(output+"/service.json",{"events":events,"queue_size":queued.size()})

func start_test() -> void:
	if test_driver != null:
		return
	test_driver = Node.new()
	test_driver.set_script(load("res://tools/phase_8c/verify_client.gd"))
	add_child(test_driver)

func _exit_tree() -> void:
	if service and not active.is_empty() and active.pid > 0 and OS.is_process_running(active.pid):
		OS.kill(active.pid)
	peer.close()
