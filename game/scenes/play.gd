# Play screen: wires BoardState rules to the board view, tray, action row, hints and feedback
# (gameplay spec sections 4, 6, 8, 9, 10, 11). The UI is built in code so it stays reviewable as text.
extends Control

const BoardState := preload("res://game/core/board_state.gd")
const LevelLoader := preload("res://game/core/level_loader.gd")
const Config := preload("res://game/core/config.gd")
const BoardView := preload("res://game/scenes/board_view.gd")
const Swatch := preload("res://game/scenes/swatch.gd")
const Feedback := preload("res://game/scenes/feedback.gd")

signal exit_requested

const HINT_ZOOM := "Phóng to để đặt hạt"
const HINT_PICK_OTHER := "Chọn màu khác để tiếp tục"
const HINT_NO_SELECTION := "Hãy chọn một màu chưa xong"
const HINT_WRONG := "Ô này thuộc màu khác — xem số trên ô"
const HINT_UNDO_OFFSCREEN := "Đã hoàn tác 1 hạt"

var state
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
var _overlay: Control
var _hint_until_ms := 0
var _zoom_hint_shown := false


func load_level_file(path: String) -> bool:
	var r := LevelLoader.load_file(path)
	if not r["ok"]:
		push_warning("Không mở được tranh này: %s %s" % [path, r["errors"]])
		return false
	start(BoardState.new(r["level"]))
	return true


func start(board_state) -> void:
	state = board_state
	if not is_inside_tree():
		await ready
	state.enter_level()
	_title.text = state.level.title
	board.setup(state)
	_build_tray()
	_refresh()
	if state.completed:
		_show_completed(false)


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
	back.text = "‹ Tranh"
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
	_btn_find = _action_button(actions, "Tìm", _on_find)
	_btn_undo = _action_button(actions, "Hoàn tác", _on_undo)
	_btn_overview = _action_button(actions, "Toàn cảnh", func(): board.reset_view())
	_btn_settings = _action_button(actions, "Âm thanh", _on_toggle_sound)

	_overlay = _build_overlay()
	add_child(_overlay)


func _action_button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(88, 44)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


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
				feedback.play("level_complete")
				_show_completed(true)
			_request_save()
		BoardState.TAP_WRONG:
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
	board.play_undo(r["cell"])
	feedback.play("lift")
	if not board.is_cell_in_view(r["cell"]):
		_show_hint(HINT_UNDO_OFFSCREEN, 1500)
	_request_save()
	_refresh()


func _on_find() -> void:
	var target: int = state.find_target(board.view_center(), board.is_cell_in_view)
	if target < 0:
		return
	var g := Vector2(state.level.cell_x(target) + 0.5, state.level.cell_y(target) + 0.5)
	board.camera_settled.connect(func(): board.show_find_ring(target), CONNECT_ONE_SHOT)
	board.zoom_to(maxf(board.cell_size, Config.PLACE_ZOOM_CELL), g)


func _on_toggle_sound() -> void:
	feedback.sfx_enabled = not feedback.sfx_enabled
	_btn_settings.text = "Âm thanh" if feedback.sfx_enabled else "Tắt tiếng"


func _on_back() -> void:
	if state != null:
		state.leave_level()
	exit_requested.emit()


func _show_completed(animate: bool) -> void:
	_overlay.visible = true
	_overlay.modulate.a = 0.0 if animate else 1.0
	if animate:
		create_tween().tween_property(_overlay, "modulate:a", 1.0, 0.4)
	board.reset_view(animate)


func _show_hint(text: String, ms: int) -> void:
	_hint.text = text
	_hint_until_ms = Time.get_ticks_msec() + ms


# Persistence is added with the storage stack (gameplay spec section 12); until then progress lives in memory.
func _request_save() -> void:
	pass


func _process(_delta: float) -> void:
	if _hint.text != "" and Time.get_ticks_msec() > _hint_until_ms:
		_hint.text = ""


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
