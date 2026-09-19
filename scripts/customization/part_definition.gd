class_name CustomizationPart
extends Resource
## Registry-only local lookup data. None of these names or resources go in a player profile.
@export_range(0,255) var id: int = 0
@export var display_name: String
@export var asset: PackedScene
@export var mesh_name: StringName
@export var material: ShaderMaterial
@export var tint_source: StringName
@export var tint_uniform: StringName = &"paint_color"
@export var color: Color = Color.WHITE
@export var legacy_key: StringName
