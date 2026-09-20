extends "res://scripts/network/online_race.gd"
## Admission/lifecycle adapter only; race authority, simulation and RPC replication are inherited.
var reservation: Dictionary = {}
var reservation_path: String = ""
var selected_track: RaceTrackEntry
var admitted: Dictionary = {}
var arrived_at: Dictionary = {}
var admission_closed: bool = false
var status_path: String = ""
var next_status: float = 0.0
var return_pending: bool = false

func _ready() -> void:
	_parse_args()
	if selected_track == null or selected_track.online_world == null:
		if server_role:
			get_tree().quit(2)
		else:
			Matchmaking.fail("The assigned track could not load. Please try again.")
			_return_to_online.call_deferred()
		return
	super._ready()
	if server_role:
		status_path = output_dir+"/status.json"
		_write_status("admitting")
	else:
		Matchmaking.failed.connect(_matchmaking_failed)

func _parse_args() -> void:
	super._parse_args()
	if server_role:
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--reservation="):
				reservation_path = arg.trim_prefix("--reservation=")
		reservation = Matchmaking._read_json(reservation_path)
		selected_track = GameSession.catalog.track(StringName(reservation.get("track","")))
		expected_players = reservation.get("members",[]).size()
	else:
		var data: Dictionary = Matchmaking.assignment
		selected_track = GameSession.catalog.track(StringName(data.get("track","")))
		address = data.get("address","127.0.0.1")
		port = data.get("port",29201)
		verification = Matchmaking.verification
		client_tag = Matchmaking.test_tag
		latency_ms = Matchmaking.test_latency if verification else 0.0
		output_dir = Matchmaking.output+"/clients"

func _create_world() -> OnlineRaceWorld:
	return selected_track.online_world.instantiate() as OnlineRaceWorld

func _connected() -> void:
	connected = true
	redeem.rpc_id(1,str(Matchmaking.assignment.ticket))
	status_text = "Joining "+selected_track.display_name+" — waiting for racers"

@rpc("any_peer","call_remote","reliable",0)
func hello(_version: int, _wire: PackedByteArray) -> void:
	# Direct-connect admission is disabled for assigned sessions. No client profile overrides.
	pass

@rpc("any_peer","call_remote","reliable",0)
func redeem(ticket: String) -> void:
	if not server_role or assembled or ticket.length() != 48:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not peers.has(sender) or admitted.has(sender) or admitted.values().has(ticket):
		return
	var canceled: Array = Matchmaking._read_json(output_dir+"/canceled.json").get("tickets",[])
	for member: Dictionary in reservation.members:
		if member.ticket == ticket and not canceled.has(ticket):
			admitted[sender] = ticket
			# Keep the original 8b validation/grid assembly. Identity/profile come from reservation.
			super.hello(1,PackedByteArray(member.profile))
			_write_status("admitting")
			return
	deny.rpc_id(sender,"This match assignment expired. Please find another match.")

@rpc("authority","call_remote","reliable",0)
func welcome(entries: Array, event_base: int) -> void:
	super.welcome(entries,event_base)
	if not server_role and assembled:
		Matchmaking.race_connected()
		_save_json("assignment_"+client_tag+".json",{"match":Matchmaking.assignment.match,"track":str(selected_track.id),"port":port,"profile":Array(Matchmaking.assignment.profile),"roster":profiles_seen})

func _peer_connected(id: int) -> void:
	super._peer_connected(id)
	if server_role:
		arrived_at[id] = elapsed

func _peer_left(id: int) -> void:
	super._peer_left(id)
	admitted.erase(id)
	arrived_at.erase(id)
	_maybe_start_remaining()

func _process(delta: float) -> void:
	super._process(delta)
	if not server_role or elapsed < next_status:
		return
	next_status = elapsed+.25
	if RaceManager.phase == RaceManager.Phase.IDLE:
		_admission_tick()
	elif RaceManager.phase in [RaceManager.Phase.COUNTDOWN,RaceManager.Phase.RACING]:
		admission_closed = true
		_write_status("running")
	elif RaceManager.phase == RaceManager.Phase.FINISHED and finished_at > 0 and elapsed-finished_at > 6:
		_write_status("finished") # Allow 8b's server and client reports to finish first.

func _admission_tick() -> void:
	if admission_closed:
		return
	var canceled: Array = Matchmaking._read_json(output_dir+"/canceled.json").get("tickets",[])
	for id: int in peers.keys():
		if (not admitted.has(id) and elapsed-float(arrived_at.get(id,elapsed)) > 3) or canceled.has(admitted.get(id,"")):
			transport.disconnect_peer(id)
			_peer_left(id)
	if elapsed >= float(reservation.get("admission_timeout",12)):
		for id: int in peers.keys():
			if not admitted.has(id) or (assembled and not peers[id].ready):
				transport.disconnect_peer(id)
				_peer_left(id)
		if peers.is_empty():
			_write_status("empty")
			get_tree().quit()
			return
		if not assembled:
			expected_players = peers.size()
			_log("admission_fallback",{"humans":expected_players,"cpus":4-expected_players})
			_assemble_server()
		_maybe_start_remaining()
	_write_status("admitting")

func _maybe_start_remaining() -> void:
	if not server_role or not assembled or peers.is_empty() or RaceManager.phase != RaceManager.Phase.IDLE or start_tick > 0:
		return
	for entry: Dictionary in peers.values():
		if not entry.ready:
			return
	start_tick = tick+120

func _write_status(value: String) -> void:
	if not status_path.is_empty():
		Matchmaking._write_json(status_path,{"state":value,"match":reservation.get("match",""),"track":str(selected_track.id),"humans":admitted.size(),"elapsed":elapsed})

func _update_hud() -> void:
	super._update_hud()
	if hud != null and selected_track != null:
		hud.text = hud.text.replace("NODEKINS ONLINE",selected_track.display_name)

func _connection_error(reason: String) -> void:
	if RaceManager.phase == RaceManager.Phase.FINISHED:
		return # Normal session retirement leaves final standings available until the player exits.
	super._connection_error(reason)
	Matchmaking.fail("The race connection was lost. Please try again.")
	_return_to_online.call_deferred()

func _matchmaking_failed(_reason: String) -> void:
	_return_to_online.call_deferred()

func _return_to_online() -> void:
	if return_pending or server_role:
		return
	return_pending = true
	transport.close()
	get_tree().change_scene_to_file("res://scenes/ui/Main.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if not server_role and event.is_action_pressed("ui_cancel"):
		Matchmaking.cancel()
	super._unhandled_input(event)
