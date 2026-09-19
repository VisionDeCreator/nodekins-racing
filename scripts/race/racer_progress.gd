class_name RacerProgress
extends RefCounted
## Internal per-racer record. Consumers receive value snapshots from RaceManager.

var id: StringName
var display_name: String
var kart: ArcadeKart
var grid_transform: Transform3D
var registration_order: int = 0
var completed_laps: int = 0
var last_checkpoint: int = 0
var next_checkpoint: int = 1
var lap_distance: float = 0.0
var distance_progress: float = 0.0
var position: int = 1
var wrong_way: bool = false
var invalid_crossings: int = 0
var recovery_remaining: float = 0.0
var recovery_count: int = 0
var recovery_reason: String = ""
var stuck_time: float = 0.0
var off_track_time: float = 0.0
var notice: String = ""
var notice_remaining: float = 0.0
var finished: bool = false
var finish_time: float = -1.0
var finish_order: int = 0
var lap_start_time: float = 0.0
var lap_times: Array[float] = []
