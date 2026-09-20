class_name MatchmakingSettings
extends Resource
@export var service_address: String = "127.0.0.1"
@export var service_port: int = 29200
@export var bind_address: String = "127.0.0.1"
@export var advertised_race_address: String = "127.0.0.1"
@export var race_port: int = 29201
@export_range(2,4) var minimum_players: int = 2
@export_range(2,4) var maximum_players: int = 2
@export var grouping_seconds: float = 3.0
@export var assignment_timeout: float = 15.0
@export var admission_timeout: float = 12.0
@export var connect_timeout: float = 8.0
@export var match_timeout: float = 300.0
