# Entry scene: level list from content/catalog.json, then the play screen.
extends Control

const Config := preload("res://game/core/config.gd")
const Play := preload("res://game/scenes/play.gd")

const CATALOG_PATH := "res://content/catalog.json"
const DIFFICULTY_LABEL := {"easy": "Dễ", "relax": "Thư giãn", "challenge": "Thử thách"}

var _list: VBoxContainer
var _play: Control


func _ready() -> void:
	var errors := Config.constraint_errors()
	if OS.is_debug_build() and not errors.is_empty():
		push_error("Cấu hình tham số sai: %s" % ", ".join(errors))   # TC-5.23
		get_tree().quit(1)
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("#e9e2d6")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 12)
	margin.add_child(_list)
	var title := Label.new()
	title.text = "Chọn tranh"
	title.add_theme_font_size_override("font_size", 26)
	_list.add_child(title)
	for entry in _load_catalog():
		_add_level_button(entry)


func _load_catalog() -> Array:
	var text := FileAccess.get_file_as_string(CATALOG_PATH)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or not data.has("levels"):
		push_error("Không đọc được %s" % CATALOG_PATH)
		return []
	return data["levels"]


func _add_level_button(entry: Dictionary) -> void:
	var path := "res://content".path_join(entry["file"])
	var meta = JSON.parse_string(FileAccess.get_file_as_string(path))
	var label: String = entry["level_id"]
	if typeof(meta) == TYPE_DICTIONARY:
		label = "%s — %s (%dx%d)" % [meta.get("title", label), DIFFICULTY_LABEL.get(meta.get("difficulty", ""), ""),
			int(meta.get("width", 0)), int(meta.get("height", 0))]
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, 56)
	b.pressed.connect(func(): open_level(path))
	_list.add_child(b)


func open_level(path: String) -> void:
	_play = Play.new()
	add_child(_play)
	_play.exit_requested.connect(_close_level)
	if not _play.load_level_file(path):
		_close_level()
		return
	_list.get_parent().visible = false


func _close_level() -> void:
	if _play != null:
		_play.queue_free()
		_play = null
	_list.get_parent().visible = true
