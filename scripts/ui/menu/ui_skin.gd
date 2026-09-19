class_name RacingUISkin
extends RefCounted
const INK: Color = Color("0b202e")
const PANEL: Color = Color("123341")
const WHITE: Color = Color("edf8f4")
const MUTED: Color = Color("a2bfcb")
const CYAN: Color = Color("51e0d0")
const ORANGE: Color = Color("ffa16b")

static func box(color: Color, radius: int = 16, border: Color = Color.TRANSPARENT, width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(width)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style

static func make_theme() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Avenir Next", "DejaVu Sans", "Arial"])
	font.font_weight = 600
	result.default_font = font
	result.default_font_size = 20
	result.set_color("font_color", "Label", WHITE)
	result.set_color("font_color", "Button", WHITE)
	result.set_color("font_hover_color", "Button", WHITE)
	result.set_color("font_pressed_color", "Button", INK)
	result.set_color("font_focus_color", "Button", WHITE)
	result.set_stylebox("normal", "Button", box(PANEL, 12, Color("315263"), 1))
	result.set_stylebox("hover", "Button", box(Color("205261"), 12, CYAN, 2))
	result.set_stylebox("pressed", "Button", box(CYAN, 12))
	result.set_stylebox("focus", "Button", box(Color.TRANSPARENT, 12, WHITE, 3))
	result.set_stylebox("panel", "PanelContainer", box(PANEL))
	result.set_constant("separation", "VBoxContainer", 14)
	result.set_constant("separation", "HBoxContainer", 18)
	return result

static func label(text: String, size: int = 20, color: Color = WHITE) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

static func paragraph(text: String, size: int = 20, color: Color = MUTED) -> Label:
	var node: Label = label(text, size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node

static func ordinal(value: int) -> String:
	if value % 100 in [11, 12, 13]:
		return str(value) + "th"
	return str(value) + ({1:"st", 2:"nd", 3:"rd"}.get(value % 10, "th") as String)

static func clock_text(seconds: float) -> String:
	return "%02d:%05.2f" % [int(seconds / 60.0), fmod(seconds, 60.0)]
