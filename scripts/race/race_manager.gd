extends Node
## Autoload: ordered race progression and recovery. No scene paths or movement internals.

signal countdown_changed(text: String)
signal race_started
signal checkpoint_passed(racer_id: StringName, checkpoint: int)
signal lap_completed(racer_id: StringName, completed_laps: int, lap_time: float)
signal racer_finished(racer_id: StringName, finish_position: int, finish_time: float)
signal race_finished
signal route_violation(racer_id: StringName, reason: String)
signal recovery_started(racer_id: StringName, checkpoint: int, reason: String)
signal recovery_completed(racer_id: StringName, checkpoint: int)

enum Phase { IDLE, COUNTDOWN, RACING, FINISHED }
const RECOVERY_DELAY: float = 0.9
const STUCK_DELAY: float = 2.5
var replica_mode: bool = false
var _replicated_rows: Array[Dictionary] = []
var phase: Phase = Phase.IDLE
var total_laps: int = 3
var elapsed: float = 0.0
var countdown_text: String = ""
var route: TrackRoute
var _countdown_remaining: float = 0.0
var _go_remaining: float = 0.0
var _finish_count: int = 0
var _registration_counter: int = 0
var _racers: Dictionary = {}
var _body_ids: Dictionary = {}

func _ready() -> void:
	process_physics_priority = 50

func configure(track_route: TrackRoute, laps: int = 3) -> void:
	clear_race()
	route = track_route
	route.prepare()
	total_laps = maxi(1, laps)

func register_kart(kart: ArcadeKart, racer_id: StringName, display_name: String) -> bool:
	if phase != Phase.IDLE or route == null or _racers.has(racer_id) or _body_ids.has(kart.get_instance_id()):
		return false
	var racer := RacerProgress.new()
	racer.id = racer_id
	racer.kart = kart
	racer.display_name = display_name
	racer.grid_transform = kart.global_transform
	racer.registration_order = _registration_counter
	_registration_counter += 1
	_racers[racer_id] = racer
	_body_ids[kart.get_instance_id()] = racer_id
	kart.recovery_requested.connect(_on_recovery_requested.bind(racer_id))
	kart.tree_exiting.connect(unregister_kart.bind(racer_id), CONNECT_ONE_SHOT)
	_update_distance(racer)
	_rank()
	return true

func unregister_kart(racer_id: StringName) -> void:
	if not _racers.has(racer_id):
		return
	var racer: RacerProgress = _racers[racer_id]
	if is_instance_valid(racer.kart):
		var callback: Callable = _on_recovery_requested.bind(racer_id)
		if racer.kart.recovery_requested.is_connected(callback):
			racer.kart.recovery_requested.disconnect(callback)
		var exit_callback: Callable = unregister_kart.bind(racer_id)
		if racer.kart.tree_exiting.is_connected(exit_callback):
			racer.kart.tree_exiting.disconnect(exit_callback)
		racer.kart.controls.set_locked(false)
		_body_ids.erase(racer.kart.get_instance_id())
	_racers.erase(racer_id)
	_rank()
	if _racers.is_empty():
		phase = Phase.IDLE
	elif phase == Phase.RACING:
		_check_race_finished()

func clear_race() -> void:
	phase = Phase.IDLE
	for racer_id in _racers.keys():
		unregister_kart(racer_id)
	_body_ids.clear()
	route = null
	elapsed = 0.0
	_finish_count = 0
	_registration_counter = 0
	countdown_text = ""

func start_race() -> void:
	if replica_mode:
		return
	if route == null or _racers.is_empty():
		return
	elapsed = 0.0
	_finish_count = 0
	_go_remaining = 0.0
	phase = Phase.COUNTDOWN
	_countdown_remaining = 3.0
	for racer: RacerProgress in _racers.values():
		racer.completed_laps = 0
		racer.last_checkpoint = 0
		racer.next_checkpoint = 1
		racer.wrong_way = false
		racer.invalid_crossings = 0
		racer.recovery_remaining = 0.0
		racer.recovery_count = 0
		racer.stuck_time = 0.0
		racer.off_track_time = 0.0
		racer.notice = ""
		racer.notice_remaining = 0.0
		racer.finished = false
		racer.finish_time = -1.0
		racer.finish_order = 0
		racer.lap_start_time = 0.0
		racer.lap_times.clear()
		racer.kart.controls.set_locked(true)
		racer.kart.respawn_at(racer.grid_transform)
		_update_distance(racer)
	_rank()
	_set_countdown("3")

func _physics_process(delta: float) -> void:
	if replica_mode:
		return
	if phase == Phase.COUNTDOWN:
		_countdown_remaining = maxf(0.0, _countdown_remaining - delta)
		if _countdown_remaining <= 0.00001:
			phase = Phase.RACING
			_go_remaining = 0.8
			_set_countdown("GO!")
			for racer: RacerProgress in _racers.values():
				racer.kart.controls.set_locked(false)
			race_started.emit()
		else:
			_set_countdown(str(ceili(_countdown_remaining - 0.00001)))
		return
	if phase != Phase.RACING:
		return
	elapsed += delta
	if _go_remaining > 0.0:
		_go_remaining -= delta
		if _go_remaining <= 0.0:
			_set_countdown("")
	for racer: RacerProgress in _racers.values():
		if racer.finished or not is_instance_valid(racer.kart):
			continue
		racer.notice_remaining = maxf(0.0, racer.notice_remaining - delta)
		if racer.recovery_remaining > 0.0:
			racer.recovery_remaining = maxf(0.0, racer.recovery_remaining - delta)
			if racer.recovery_remaining <= 0.0:
				_finish_recovery(racer)
			continue
		_update_distance(racer)
		if racer.kart.global_position.y < route.points[0].y - 6.0:
			request_recovery(racer.id, "fell off track")
			continue
		if racer.kart.controls.throttle > 0.2 and racer.kart.speed < 0.7:
			racer.stuck_time += delta
		else:
			racer.stuck_time = 0.0
		if racer.stuck_time >= STUCK_DELAY:
			request_recovery(racer.id, "stuck")
		var projection: Dictionary = route.project_sector(racer.kart.global_position, racer.last_checkpoint)
		if float(projection.offset) > route.road_width * 0.8:
			racer.off_track_time += delta
			if racer.off_track_time > 2.0:
				request_recovery(racer.id, "off the valid route")
		else:
			racer.off_track_time = 0.0
		var along: float = racer.kart.velocity.dot(projection.forward)
		if absf(along) > 1.0:
			racer.wrong_way = along < 0.0
	_rank()

func report_checkpoint(kart: ArcadeKart, checkpoint: int, forward_crossing: bool) -> void:
	if replica_mode:
		return
	if phase != Phase.RACING or not _body_ids.has(kart.get_instance_id()):
		return
	var racer: RacerProgress = _racers[_body_ids[kart.get_instance_id()]]
	if racer.finished or racer.recovery_remaining > 0.0:
		return
	if not forward_crossing:
		racer.wrong_way = true
		_notice(racer, "WRONG WAY — turn around")
		return
	if checkpoint == racer.last_checkpoint:
		return # Re-crossing an already accepted gate never adds progress.
	if checkpoint != racer.next_checkpoint:
		racer.invalid_crossings += 1
		var message: String = "MISSED CHECKPOINT %d — crossed %d" % [racer.next_checkpoint, checkpoint]
		_notice(racer, message)
		request_recovery(racer.id, message)
		return
	if checkpoint == 0:
		racer.completed_laps += 1
		var lap_time: float = elapsed - racer.lap_start_time
		racer.lap_times.append(lap_time)
		racer.lap_start_time = elapsed
		lap_completed.emit(racer.id, racer.completed_laps, lap_time)
	racer.last_checkpoint = checkpoint
	racer.next_checkpoint = (checkpoint + 1) % route.checkpoint_indices.size()
	racer.wrong_way = false
	_update_distance(racer)
	if racer.completed_laps >= total_laps:
		racer.finished = true
		racer.finish_time = elapsed
		_finish_count += 1
		racer.finish_order = _finish_count
		racer.distance_progress = total_laps * route.length()
		racer.kart.controls.set_locked(true)
		racer_finished.emit(racer.id, racer.finish_order, racer.finish_time)
	_rank()
	checkpoint_passed.emit(racer.id, checkpoint)
	_check_race_finished()

func request_recovery(racer_id: StringName, reason: String = "manual reset") -> void:
	if replica_mode:
		return
	if phase != Phase.RACING or not _racers.has(racer_id):
		return
	var racer: RacerProgress = _racers[racer_id]
	if racer.finished or racer.recovery_remaining > 0.0:
		return
	racer.recovery_remaining = RECOVERY_DELAY
	racer.recovery_reason = reason
	racer.kart.controls.set_locked(true)
	recovery_started.emit(racer_id, racer.last_checkpoint, reason)

func _finish_recovery(racer: RacerProgress) -> void:
	racer.kart.respawn_at(route.recovery_transform(racer.last_checkpoint))
	racer.kart.controls.set_locked(false)
	racer.stuck_time = 0.0
	racer.off_track_time = 0.0
	racer.wrong_way = false
	racer.recovery_count += 1
	_update_distance(racer)
	recovery_completed.emit(racer.id, racer.last_checkpoint)

func _on_recovery_requested(reason: String, racer_id: StringName) -> void:
	request_recovery(racer_id, reason)

func _update_distance(racer: RacerProgress) -> void:
	var projection: Dictionary = route.project_sector(racer.kart.global_position, racer.last_checkpoint)
	racer.lap_distance = float(projection.distance)
	racer.distance_progress = racer.completed_laps * route.length() + racer.lap_distance

func _rank() -> void:
	var ordered: Array = _racers.values()
	ordered.sort_custom(_rank_before)
	for index in range(ordered.size()):
		ordered[index].position = index + 1

func _rank_before(a: RacerProgress, b: RacerProgress) -> bool:
	if a.finished != b.finished:
		return a.finished
	if a.finished:
		return a.finish_order < b.finish_order
	# Integer millimetre buckets give a transitive, stable tie rule for sorting.
	var a_distance: int = roundi(a.distance_progress * 1000.0)
	var b_distance: int = roundi(b.distance_progress * 1000.0)
	if a_distance != b_distance:
		return a_distance > b_distance
	return a.registration_order < b.registration_order

func _check_race_finished() -> void:
	if phase != Phase.RACING or _racers.is_empty():
		return
	for racer: RacerProgress in _racers.values():
		if not racer.finished:
			return
	phase = Phase.FINISHED
	_set_countdown("")
	race_finished.emit()

func _notice(racer: RacerProgress, text: String) -> void:
	racer.notice = text
	racer.notice_remaining = 2.5
	route_violation.emit(racer.id, text)

func _set_countdown(text: String) -> void:
	if countdown_text != text:
		countdown_text = text
		countdown_changed.emit(text)

func get_racer_state(racer_id: StringName) -> Dictionary:
	if replica_mode:
		for row: Dictionary in _replicated_rows:
			if row.id == str(racer_id):
				return row.duplicate(true)
		return {}
	if not _racers.has(racer_id):
		return {}
	var racer: RacerProgress = _racers[racer_id]
	return {"id": str(racer.id), "name": racer.display_name, "lap": mini(racer.completed_laps + 1, total_laps),
		"completed_laps": racer.completed_laps, "total_laps": total_laps, "last_checkpoint": racer.last_checkpoint,
		"next_checkpoint": racer.next_checkpoint, "lap_distance": racer.lap_distance,
		"distance_progress": racer.distance_progress, "position": racer.position, "racer_count": _racers.size(),
		"elapsed": elapsed, "wrong_way": racer.wrong_way, "invalid_crossings": racer.invalid_crossings,
		"respawning": racer.recovery_remaining > 0.0, "recovery_remaining": racer.recovery_remaining,
		"recovery_count": racer.recovery_count, "recovery_reason": racer.recovery_reason,
		"notice": racer.notice if racer.notice_remaining > 0.0 else "", "finished": racer.finished,
		"finish_time": racer.finish_time, "finish_order": racer.finish_order, "lap_times": racer.lap_times.duplicate()}

func get_standings() -> Array[Dictionary]:
	if replica_mode:
		return _replicated_rows.duplicate(true)
	var snapshots: Array[Dictionary] = []
	for racer_id in _racers:
		snapshots.append(get_racer_state(racer_id))
	snapshots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.position) < int(b.position))
	return snapshots

## Explicit online read model. Clients cannot count gates, recover or start races.
func set_replica_mode(value: bool) -> void:
	clear_race()
	replica_mode = value
	_replicated_rows.clear()

func online_snapshot() -> Dictionary:
	return {"phase":int(phase),"elapsed":elapsed,"countdown":countdown_text,"laps":total_laps,"rows":get_standings()}

func apply_online_snapshot(state: Dictionary) -> void:
	if not replica_mode:
		return
	phase = state.phase as Phase
	elapsed = state.elapsed
	total_laps = state.laps
	countdown_text = state.countdown
	_replicated_rows.assign(state.rows)
