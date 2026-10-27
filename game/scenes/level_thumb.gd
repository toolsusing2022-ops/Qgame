# Small bead-grid preview of a level for the level list (draws straight from level JSON data).
extends Control

var width := 0
var height := 0
var cells: Array = []
var colors: Array[Color] = []


func setup(data: Dictionary) -> void:
	width = int(data.get("width", 0))
	height = int(data.get("height", 0))
	cells = data.get("cells", [])
	for e in data.get("palette", []):
		colors.append(Color.html(String(e.get("hex", "#000000"))))
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#f4efe6"))
	if width == 0 or height == 0:
		return
	var cell := minf(size.x / width, size.y / height)
	var origin := (size - Vector2(width, height) * cell) * 0.5
	for i in cells.size():
		var c := int(cells[i])
		if c < 0 or c >= colors.size():
			continue
		var p := origin + Vector2(i % width + 0.5, i / width + 0.5) * cell
		draw_circle(p, cell * 0.45, colors[c])
