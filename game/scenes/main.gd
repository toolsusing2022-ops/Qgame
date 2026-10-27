# Entry scene: app services (storage backend, event store, settings), startup pending scan, level list from
# content/catalog.json, then the play screen.
extends Control

const Config := preload("res://game/core/config.gd")
const Play := preload("res://game/scenes/play.gd")
const GodotFileBackend := preload("res://game/storage/godot_file_backend.gd")
const EventStore := preload("res://game/events/event_store.gd")
const Dispatcher := preload("res://game/events/dispatcher.gd")
const Settings := preload("res://game/save/settings.gd")
const PendingScan := preload("res://game/save/pending_scan.gd")
const LevelThumb := preload("res://game/scenes/level_thumb.gd")

const CATALOG_PATH := "res://content/catalog.json"
const PROGRESS_DIR := "user://progress"
const DIFFICULTY_LABEL := {"easy": "Dễ", "relax": "Thư giãn", "challenge": "Thử thách"}

var backend
var dispatcher
var settings
var _list: VBoxContainer
var _message: Label
var _play: Control


func _ready() -> void:
	var errors := Config.constraint_errors()
	if OS.is_debug_build() and not errors.is_empty():
		push_error("Cấu hình tham số sai: %s" % ", ".join(errors))   # TC-5.23
		get_tree().quit(1)
		return
	backend = GodotFileBackend.new()
	dispatcher = Dispatcher.new(EventStore.new(backend))
	settings = Settings.new(backend)
	settings.load_or_create()
	PendingScan.run(backend, dispatcher, PROGRESS_DIR, Time.get_ticks_msec())   # GS-14.9

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
	title.add_theme_color_override("font_color", Color("#2b2622"))
	_list.add_child(title)
	var help := Label.new()
	help.text = "Chọn một màu ở khay, rồi chạm vào các ô có cùng số. Ô nhỏ quá thì chạm để phóng to; " \
		+ "kéo để di chuyển, chụm hai ngón (hoặc lăn chuột) để zoom."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_color_override("font_color", Color("#5a524b"))
	help.add_theme_font_size_override("font_size", 14)
	_list.add_child(help)
	for entry in _load_catalog():
		_add_level_button(entry)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(_message)


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
		label = "%s\n%s · %d×%d" % [meta.get("title", label), DIFFICULTY_LABEL.get(meta.get("difficulty", ""), ""),
			int(meta.get("width", 0)), int(meta.get("height", 0))]
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 112)
	b.pressed.connect(func(): open_level(path, entry))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	b.add_child(row)
	var thumb := LevelThumb.new()
	thumb.custom_minimum_size = Vector2(96, 96)
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if typeof(meta) == TYPE_DICTIONARY:
		thumb.setup(meta)
	row.add_child(thumb)
	var text := Label.new()
	text.text = label
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	_list.add_child(b)


func open_level(path: String, entry := {"content_version": 1}) -> void:
	_message.text = ""
	_play = Play.new()
	add_child(_play)
	_play.exit_requested.connect(_close_level)
	var r: Dictionary = _play.open_level(path, entry, backend, dispatcher, settings, PROGRESS_DIR)
	if not r.get("ok", false):
		_message.text = r.get("message", "Không mở được tranh này")
		_close_level()
		return
	_list.get_parent().visible = false


func _close_level() -> void:
	if _play != null:
		_play.queue_free()
		_play = null
	_list.get_parent().visible = true
