# Play screen: wires BoardState rules to the board view, tray, action row, hints and feedback
# (gameplay spec sections 4, 6, 8, 9, 10, 11). The UI is built in code so it stays reviewable as text.
extends Control

const BoardState := preload("res://game/core/board_state.gd")
const LevelLoader := preload("res://game/core/level_loader.gd")
const Config := preload("res://game/core/config.gd")
const BoardView := preload("res://game/scenes/board_view.gd")
const Swatch := preload("res://game/scenes/swatch.gd")
const Feedback := preload("res://game/scenes/feedback.gd")
const MemoryBackend := preload("res://game/storage/memory_backend.gd")
const EventStore := preload("res://game/events/event_store.gd")
const Dispatcher := preload("res://game/events/dispatcher.gd")
const ProgressSession := preload("res://game/save/progress_session.gd")
const Restore := preload("res://game/save/restore.gd")

signal exit_requested

const HINT_ZOOM := "Phóng to để đặt hạt"
const HINT_PICK_OTHER := "Chọn màu khác để tiếp tục"
const HINT_NO_SELECTION := "Hãy chọn một màu chưa xong"
const HINT_WRONG := "Ô này thuộc màu khác — xem số trên ô"
const HINT_UNDO_OFFSCREEN := "Đã hoàn tác 1 hạt"
const BANNER_SAVE_BLOCKED := "Không lưu được tiến độ. Tiến độ hiện chỉ còn trong phiên này."

var state
var session                   # ProgressSession (restore, outbox, saving)
var settings                  # Settings or null
var mode := "zen"                 # "zen" | "journey" (section 15)
var wrong_feedback_enabled := true

var board: Control
var feedback: Node
var _title: Label
var _hint: Label
var _tray: HBoxContainer
var _swatches: Array = []
var _btn_find: Button
var _btn_undo: Button
var _btn_overview: Button
var _btn_settings: Button
var _btn_ambient: Button
var _overlay: Control
var _banner: Label
var _hint_until_ms := 0
var _zoom_hint_shown := false
var _notices: PackedStringArray = []
var _stats := {"placed": 0, "wrong": 0, "undo": 0, "find": 0, "tap_to_zoom": 0}
var _start_ms := 0


# Opens a level with progress restored through the storage stack (sections 12-14).
# Returns {ok, message}. archive_failed and invalid levels do not open (GS-2.6, GS-13.4 E3.1).
func open_level(path: String, entry: Dictionary, backend, dispatcher, app_settings, progress_dir: String) -> Dictionary:
	var r := LevelLoader.load_file(path)
	if not r["ok"]:
		push_warning("Không mở được tranh này: %s %s" % [path, r["errors"]])
		return {"ok": false, "message": "Không mở được tranh này"}
	settings = app_settings
	var install_id: String = settings.install_id if settings != null else "test"
	session = ProgressSession.new(backend, dispatcher, r["level"], entry, progress_dir, install_id)
	session.mode = mode
	var res: Dictionary = session.open()
	if res["outcome"] == "archive_failed":
		return {"ok": false, "message": Restore.MESSAGES["archive_failed"]}
	_notices = res["notices"]
	start(session.board)
	return {"ok": true, "message": ""}


# Test helper: opens a level with an in-memory backend (nothing is written to user://).
func load_level_file(path: String) -> bool:
	var mem = MemoryBackend.new()
	var disp = Dispatcher.new(EventStore.new(mem, "mem/events/events.jsonl"))
	return open_level(path, {"content_version": 1}, mem, disp, null, "mem/progress")["ok"]


func start(board_state) -> void:
	state = board_state
	if not is_inside_tree():
		await ready
	_start_ms = Time.get_ticks_msec()
	if settings != null:
		feedback.sfx_enabled = settings.sfx_enabled
		feedback.haptic_enabled = settings.haptic_enabled
		feedback.set_ambient(settings.ambient)
	_update_sound_buttons()
	_title.text = state.level.title
	board.setup(state)
	_build_tray()
	_refresh()
	if state.completed:
		_show_completed(false)
	_show_next_notice()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	feedback = Feedback.new()
	add_child(feedback)
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#e9e2d6")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var top := HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 48)
	root.add_child(top)
	var back := Button.new()
	back.text = "Tranh"
	back.icon = _icon("chevron-left")
	back.custom_minimum_size = Vector2(88, 44)
	back.pressed.connect(_on_back)
	top.add_child(back)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 18)
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(_title)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(88, 44)
	top.add_child(spacer)

	_hint = Label.new()
	_hint.custom_minimum_size = Vector2(0, 24)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color(0.25, 0.25, 0.25))
	root.add_child(_hint)

	# KT-7: fixed, non-blocking banner while saving is blocked; removed only after a replaced write.
	_banner = Label.new()
	_banner.visible = false
	_banner.text = BANNER_SAVE_BLOCKED
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_color", Color(0.55, 0.1, 0.1))
	root.add_child(_banner)

	board = BoardView.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.clip_contents = true
	board.cell_tapped.connect(_on_cell_tapped)
	board.tap_to_zoom_used.connect(_on_tap_to_zoom)
	board.resized.connect(func(): if state != null: board.reset_view(false))
	root.add_child(board)

	var tray_scroll := ScrollContainer.new()
	tray_scroll.custom_minimum_size = Vector2(0, 72)
	tray_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(tray_scroll)
	_tray = HBoxContainer.new()
	_tray.add_theme_constant_override("separation", 2)
	tray_scroll.add_child(_tray)

	var actions := HBoxContainer.new()
	actions.custom_minimum_size = Vector2(0, 52)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(actions)
	_btn_find = _action_button(actions, "Tìm", "search", _on_find)
	_btn_undo = _action_button(actions, "Hoàn tác", "undo-2", _on_undo)
	_btn_overview = _action_button(actions, "Toàn cảnh", "scan", func(): board.reset_view())
	_btn_settings = _action_button(actions, "Âm thanh", "volume-2", _on_toggle_sound)
	_btn_ambient = _action_button(actions, "Âm nền", "waves", _on_cycle_ambient)

	_overlay = _build_overlay()
	add_child(_overlay)


func _action_button(parent: Control, text: String, icon_name: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = _icon(icon_name)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.add_theme_font_size_override("font_size", 12)
	b.custom_minimum_size = Vector2(68, 56)     # >= 44 pt (GS-8.4)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# Lucide icons (ISC), see game/assets/icons/LICENSE_lucide.txt.
static func _icon(name: String) -> Texture2D:
	var path := "res://game/assets/icons/%s.svg" % name
	return load(path) if ResourceLoader.exists(path) else null


func _update_sound_buttons() -> void:
	_btn_settings.text = "Âm thanh" if feedback.sfx_enabled else "Tắt tiếng"
	_btn_settings.icon = _icon("volume-2" if feedback.sfx_enabled else "volume-x")
	var labels := {"off": ["Âm nền tắt", "bell-off"], "sea": ["Biển", "waves"], "rain": ["Mưa", "cloud-rain"]}
	var l: Array = labels.get(feedback.ambient_name, labels["off"])
	_btn_ambient.text = l[0]
	_btn_ambient.icon = _icon(l[1])


func _on_cycle_ambient() -> void:
	var names: Array = feedback.AMBIENT_NAMES
	var next: String = names[(names.find(feedback.ambient_name) + 1) % names.size()]
	feedback.set_ambient(next)
	_update_sound_buttons()
	session.record_best_effort("setting_changed", {"key": "ambient", "value": next})
	if settings != null:
		settings.ambient = next
		settings.save()


func _build_overlay() -> Control:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(280, 160)
	panel.position = Vector2(-140, -80)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	var label := Label.new()
	label.text = "Hoàn thành tranh!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	box.add_child(label)
	var view := Button.new()
	view.text = "Ngắm tranh"
	view.custom_minimum_size = Vector2(0, 44)
	view.pressed.connect(func(): _overlay.visible = false)
	box.add_child(view)
	var done := Button.new()
	done.text = "Về danh sách tranh"
	done.custom_minimum_size = Vector2(0, 44)
	done.pressed.connect(_on_back)
	box.add_child(done)
	return panel


func _build_tray() -> void:
	for s in _swatches:
		s.queue_free()
	_swatches.clear()
	for c in state.level.color_count():
		var s = Swatch.new()
		s.color_id = c
		s.color = state.level.colors[c]
		s.picked.connect(_on_swatch_picked)
		_tray.add_child(s)
		_swatches.append(s)


# --- rules -> feedback ---------------------------------------------------------------------------------------

func _on_cell_tapped(i: int) -> void:
	var r: Dictionary = state.tap(i)
	match r["kind"]:
		BoardState.TAP_PLACED:
			_stats["placed"] += 1
			session.on_tap_result(r)
			board.play_place(i)
			feedback.play("place")
			feedback.haptic_place()
			if r["color_completed"]:
				feedback.play("color_complete")
				if not r["level_completed"]:
					_show_hint(HINT_PICK_OTHER, 1500)
					for s in _swatches:
						if not state.is_color_done(s.color_id):
							s.nudge(1500)
			if r["level_completed"]:
				session.flush(true)          # GS-4.5: completed + level_complete in one atomic write
				feedback.duck_ambient()
				feedback.play("level_complete")
				_show_completed(true)
		BoardState.TAP_WRONG:
			_stats["wrong"] += 1
			session.record_best_effort("wrong_tap", {"cell": i, "cell_color": r["color"], "selected": state.selected})
			if wrong_feedback_enabled or mode == "journey":
				board.show_wrong_number(i)
				_swatches[r["color"]].flash()
				feedback.play("wrong", -6.0)
				if r["show_hint"]:
					_show_hint(HINT_WRONG, 3000)
		BoardState.TAP_NO_SELECTION:
			_show_hint(HINT_NO_SELECTION, 2000)
		_:
			pass  # already placed, empty, locked: silent (GS-6.3, 6.4)
	_refresh()


func _on_tap_to_zoom() -> void:
	_stats["tap_to_zoom"] += 1
	session.record_best_effort("tap_to_zoom", {"cell_size_pt": board.cell_size})
	if not _zoom_hint_shown:
		_zoom_hint_shown = true
		_show_hint(HINT_ZOOM, 2000)


func _on_swatch_picked(c: int) -> void:
	if state.completed:
		return
	if state.select_color(c)["changed"]:
		feedback.play("pick")
	_refresh()


func _on_undo() -> void:
	var r: Dictionary = state.undo()
	if not r["ok"]:
		return
	_stats["undo"] += 1
	session.on_undo_result(r)
	board.play_undo(r["cell"])
	feedback.play("lift")
	if not board.is_cell_in_view(r["cell"]):
		_show_hint(HINT_UNDO_OFFSCREEN, 1500)
	_refresh()


func _on_find() -> void:
	var target: int = state.find_target(board.view_center(), board.is_cell_in_view)
	if target < 0:
		return
	var g := Vector2(state.level.cell_x(target) + 0.5, state.level.cell_y(target) + 0.5)
	_stats["find"] += 1
	session.record_best_effort("find_used", {"color": state.selected, "target_cell": target,
		"was_offscreen": not board.is_cell_in_view(target)})
	board.camera_settled.connect(func(): board.show_find_ring(target), CONNECT_ONE_SHOT)
	board.zoom_to(maxf(board.cell_size, Config.PLACE_ZOOM_CELL), g)


func _on_toggle_sound() -> void:
	feedback.sfx_enabled = not feedback.sfx_enabled
	_update_sound_buttons()
	session.record_best_effort("setting_changed", {"key": "sfx", "value": feedback.sfx_enabled})
	if settings != null:
		settings.sfx_enabled = feedback.sfx_enabled
		settings.save()


func _on_back() -> void:
	if state != null:
		session.flush(true)
		session.record_best_effort("session_end", {"duration": Time.get_ticks_msec() - _start_ms,
			"placed": _stats["placed"], "wrong": _stats["wrong"], "undo": _stats["undo"],
			"find": _stats["find"], "tap_to_zoom": _stats["tap_to_zoom"]})
		state.leave_level()
	exit_requested.emit()


# Saving on background / focus loss (GS-12.1). No reliance on termination callbacks.
func _notification(what: int) -> void:
	if session == null or not session.opened:
		return
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT,
			NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		session.flush(true)


func _show_completed(animate: bool) -> void:
	_overlay.visible = true
	_overlay.modulate.a = 0.0 if animate else 1.0
	if animate:
		create_tween().tween_property(_overlay, "modulate:a", 1.0, 0.4)
	board.reset_view(animate)


func _show_hint(text: String, ms: int) -> void:
	_hint.text = text
	_hint_until_ms = Time.get_ticks_msec() + ms


# Restore notices (GS-13.12, 13.14): shown one after another, the .bak notice first.
func _show_next_notice() -> void:
	if _notices.is_empty():
		return
	var text := _notices[0]
	_notices.remove_at(0)
	_show_hint(text, 3500)


func _process(_delta: float) -> void:
	if session != null and session.opened:
		session.flush()                     # at most one write per frame; coalesces taps (GS-12.1)
		_banner.visible = session.is_save_blocked()
	if _hint.text != "" and Time.get_ticks_msec() > _hint_until_ms:
		_hint.text = ""
		_show_next_notice()


func _refresh() -> void:
	for s in _swatches:
		s.remaining = state.remaining[s.color_id]
		s.done = state.is_color_done(s.color_id)
		s.selected = s.color_id == state.selected
		s.queue_redraw()
	# GS-8.4: disabled state must be visible.
	_btn_find.disabled = not state.can_find()
	_btn_undo.disabled = not state.can_undo()
	board.queue_redraw()
