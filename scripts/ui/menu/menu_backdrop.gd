extends Control
## Code-drawn interface decoration, not a new game art asset.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0b202e"))
	draw_colored_polygon(PackedVector2Array([Vector2(size.x*.55,0),Vector2(size.x,0),size,Vector2(size.x*.32,size.y)]), Color("103440"))
	var center := Vector2(size.x*.78,size.y*.51)
	for radius in [190.0, 250.0, 310.0]:
		draw_arc(center, radius, 0, TAU, 96, Color("234954"), 1.5, true)
	for index in range(5):
		var x: float = 34.0 + index * 23.0
		draw_colored_polygon(PackedVector2Array([Vector2(x,size.y-10),Vector2(x+11,size.y-10),Vector2(x+22,size.y-30),Vector2(x+11,size.y-30)]), RacingUISkin.CYAN)
