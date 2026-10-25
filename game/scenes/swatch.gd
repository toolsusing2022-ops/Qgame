# One colour in the tray (gameplay spec GS-8.1): colour, number, remaining; selected is larger and outlined,
# finished is faded with a check mark. At least 44x44 pt.
extends Control

signal picked(color_id: int)

var color_id := 0
var color := Color.WHITE
var remaining := 0
var selected := false
var done := false
var flash_until_ms := 0
var nudge_until_ms := 0


func _init() -> void:
	custom_minimum_size = Vector2(52, 64)
	mouse_filter = Control.MOUSE_FILTER_STOP


func flash() -> void:
	flash_until_ms = Time.get_ticks_msec() + 600
	queue_redraw()


func nudge(ms: int) -> void:
	nudge_until_ms = Time.get_ticks_msec() + ms
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		picked.emit(color_id)
		accept_event()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now < flash_until_ms + 50 or now < nudge_until_ms + 50:
		queue_redraw()


func _draw() -> void:
	var now := Time.get_ticks_msec()
	var mid := Vector2(size.x * 0.5, 24)
	var radius := 19.0 if selected else 15.0
	var alpha := 0.35 if done else 1.0
	if selected:
		draw_circle(mid, radius + 4, Color(0.15, 0.15, 0.15))
	if now < flash_until_ms or now < nudge_until_ms:
		draw_arc(mid, radius + 7, 0, TAU, 32, Color(1, 0.85, 0.3), 3.0)
	draw_circle(mid, radius, Color(color, alpha))
	var font := get_theme_default_font()
	var number := str(color_id + 1)
	var text_col := Color.BLACK if color.get_luminance() > 0.55 else Color.WHITE
	var tw := font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(font, mid + Vector2(-tw * 0.5, 5), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(text_col, alpha))
	var label := "✓" if done else str(remaining)
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, Vector2(size.x * 0.5 - lw * 0.5, 58), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(0.2, 0.2, 0.2, 0.9))
