class_name RaceTrackMap
extends Control
## Map markers use RaceManager's accepted progress, including airborne checkpoints.
var route: TrackRoute
var glide_section: GlideSection
var live: bool = false
var marker_positions: Dictionary = {}
var _minimum: Vector2
var _extent: Vector2
const COLORS: Dictionary = {"player":Color("51e0d0"), "cpu_1":Color("ff805e"), "cpu_2":Color("83e870"), "cpu_3":Color("e3b455")}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_route(value: TrackRoute, glide: GlideSection = null) -> void:
	route = value
	glide_section = glide
	_minimum = Vector2(INF,INF)
	var maximum := Vector2(-INF,-INF)
	for point: Vector3 in route.points:
		var flat := Vector2(point.z,-point.x)
		_minimum = _minimum.min(flat)
		maximum = maximum.max(flat)
	_extent = maximum - _minimum
	queue_redraw()

func map_point(point: Vector3) -> Vector2:
	var available: Vector2 = (size - Vector2(40,40)).max(Vector2.ONE)
	var factor: float = minf(available.x / maxf(_extent.x,1), available.y / maxf(_extent.y,1))
	return (Vector2(point.z,-point.x) - _minimum - _extent*.5) * factor + size*.5

func _process(_delta: float) -> void:
	if live:
		queue_redraw()

func _draw() -> void:
	if route == null or route.points.is_empty():
		return
	var distance: float = 0.0
	for index in range(route.points.size()):
		var a: Vector3 = route.points[index]
		var b: Vector3 = route.points[(index+1) % route.points.size()]
		var middle: float = distance + a.distance_to(b)*.5
		distance += a.distance_to(b)
		var gap: bool = glide_section != null and middle > glide_section.ramp_end and middle < glide_section.landing_start
		if gap:
			draw_dashed_line(map_point(a),map_point(b),RacingUISkin.CYAN,2,4,true,true)
		else:
			draw_line(map_point(a),map_point(b),Color("396373"),14,true)
			draw_line(map_point(a),map_point(b),Color("91b5bc"),2,true)
	var start: Vector2 = map_point(route.points[0])
	draw_rect(Rect2(start-Vector2(3,9),Vector2(6,18)),RacingUISkin.WHITE)
	marker_positions.clear()
	if not live:
		return
	var standings: Array[Dictionary] = RaceManager.get_standings()
	standings.reverse() # Player gets a halo, and leaders render above trailing markers.
	for state: Dictionary in standings:
		var at: Vector2 = map_point(route.sample(0.0 if state.finished else float(state.lap_distance)).origin)
		marker_positions[state.id] = at
		var color: Color = COLORS.get(state.id, RacingUISkin.WHITE)
		if state.id == "player":
			draw_circle(at,10,RacingUISkin.WHITE)
		draw_circle(at,7,Color("0b202e"))
		draw_circle(at,5,color)
