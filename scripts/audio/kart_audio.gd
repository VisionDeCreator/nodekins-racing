class_name KartAudio
extends Node3D
## Signal-only presentation adapter shared by the player and all CPU instances.
@export var impact_minimum_speed: float = 2.5
@export var impact_cooldown_seconds: float = 0.28
@onready var kart: ArcadeKart = get_parent() as ArcadeKart
@onready var engine: ObjectSound3D = $Engine
@onready var charge: ObjectSound3D = $Charge
var _next_impact_ms: int = 0

func _ready() -> void:
	kart.ready.connect(_connect_kart,CONNECT_ONE_SHOT)
	kart.child_entered_tree.connect(_child_added)

func _connect_kart() -> void:
	kart.motion_updated.connect(_motion)
	kart.collision_impact.connect(_impact)
	kart.drift.drift_started.connect(_drift_start)
	kart.drift.drift_ended.connect(charge.stop)
	kart.drift.charge_tier_changed.connect(_tier)
	kart.drift.boost_started.connect(_boost)
	kart.glide.launched.connect(_deploy)
	kart.glide.ended.connect(_land)
	kart.respawned.connect(charge.stop)
	engine.trigger(&"engine",preload("res://assets/audio/engine_loop.wav"),.78,-12.0)

func _motion(speed: float, throttle: float, brake: float) -> void:
	var fraction: float = clampf(speed / kart.stats.top_speed,0.0,1.6)
	engine.pitch_scale = lerpf(engine.pitch_scale,.78 + fraction*.72 + throttle*.12,.15)
	engine.volume_db = lerpf(engine.volume_db,-22.0 + minf(fraction,1.0)*6.0 + throttle*3.0 - brake*2.0,.12)

func _drift_start() -> void:
	$Movement.trigger(&"drift_start",preload("res://assets/audio/drift_start.wav"))
	charge.trigger(&"drift_charge",preload("res://assets/audio/drift_loop.wav"),.85,-8.0)

func _tier(tier: int) -> void:
	charge.pitch_scale = .85 + tier*.22
	charge.volume_db = -18.0 + tier*2.0
	$Movement.trigger(StringName("drift_tier_%d" % tier),preload("res://assets/audio/drift_tier.wav"),1.0 + (tier-1)*.16)

func _boost(_tier_value: int, _multiplier: float, _duration: float) -> void:
	$Boost.trigger(&"boost",preload("res://assets/audio/boost.wav"))

func _deploy() -> void:
	$Glide.trigger(&"glide_deploy",preload("res://assets/audio/glide_deploy.wav"))

func _land(flight: Dictionary) -> void:
	if flight.reason == "landed":
		$Glide.trigger(&"glide_land",preload("res://assets/audio/glide_land.wav"))

func _impact(normal_speed: float) -> void:
	var now: int = Time.get_ticks_msec()
	if normal_speed < impact_minimum_speed or now < _next_impact_ms:
		return
	_next_impact_ms = now + roundi(impact_cooldown_seconds*1000)
	$Impact.trigger(&"impact",preload("res://assets/audio/impact.wav"),clampf(1.15-normal_speed*.008,.8,1.15),lerpf(-8,0,clampf(normal_speed/15.0,0,1)))

func _child_added(child: Node) -> void:
	if child is KartInventory:
		child.item_used.connect(_item_used)
		child.item_hit.connect(_item_hit)

func _item_used(item: ItemDefinition) -> void:
	if item.use_sound != null:
		$Item.trigger(StringName("item_" + String(item.id)),item.use_sound)

func _item_hit(_item: ItemDefinition) -> void:
	$Hit.trigger(&"spinout",preload("res://assets/audio/spinout.wav"))
