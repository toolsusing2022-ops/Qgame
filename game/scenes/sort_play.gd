# "Gỡ hạt" play screen: the picture with covers and holes, six 3x3 trays, flying beads, progress bar.
# Rules live in game/core/sort_state.gd; this file only draws, animates, plays sounds and saves.
extends Control

const SortState := preload("res://game/core/sort_state.gd")
const SortPuzzle := preload("res://game/core/sort_puzzle.gd")
const LevelLoader := preload("res://game/core/level_loader.gd")
const LevelHash := preload("res://game/core/level_hash.gd")
const BeadArt := preload("res://game/scenes/bead_art.gd")
const Feedback := preload("res://game/scenes/feedback.gd")
const ProgressWriter := preload("res://game/save/progress_writer.gd")
const MemoryBackend := preload("res://game/storage/memory_backend.gd")

signal exit_requested

const FLY_MS := 420.0
const STAGGER_MS := 18.0
const SAVE_VERSION := 1
const BG := Color("#e9e2d6")
const BOARD_BG := Color("#f4efe6")

var state
var level
var feedback: Node
var settings
var backend
var progress_dir := ""
var puzzle_seed := 0

var _writer
var _content_hash := ""
var _board_rect := Rect2()
var _cell := 10.0
var _tray_rect := Rect2()
var _flights: Array = []          # {color, from, to, start, dest_cell | dest_slot}
var _pending_cells := {}          # cell -> true while a bead is flying to it
var _pending_slots := 0           # tray beads still in the air
var _hint_cells := PackedInt32Array()
var _hint_until := 0
var _shake_until := 0
var _last_place_sound := 0
var _dirty := false
var _done_shown := false

var _title: Label
var _pct: Label
var _bar: ProgressBar
var _msg: Label
var _msg_until := 0
var _overlay: Control
var _btn_sound: Button


# Opens a level. backend/settings may be null (tests): then an in-memory backend is used.
func open_level(path: String, storage_backend = null, app_settings = null, dir := "user://progress") -> bool:
	var r := LevelLoader.load_file(path)
	if not r["ok"]:
		return false
	level = r["level"]
	settings = app_settings
	backend = storage_backend if storage_backend != null else MemoryBackend.new()
	progress_dir = dir
	_content_hash = LevelHash.content_hash(level)
	_writer = ProgressWriter.new(backend, progress_dir, level.id + ".sort")
	if not _restore():
		_new_puzzle(abs(hash(level.id)) % 100000)
	if not is_inside_tree():
		await ready
	_title.text = level.title
	if settings != null:
		feedback.sfx_enabled = settings.sfx_enabled
		feedback.set_ambient(settings.ambient)
	_update_sound_button()
	_layout()
	_refresh()
	return true


func _new_puzzle(seed_value: int) -> void:
	var g: Dictionary = SortPuzzle.generate(level, seed_value)
	state = g["state"]
	puzzle_seed = g["seed"]
	_done_shown = false
	_dirty = true


# --- persistence: atomic write protocol of GS-12.2 (writer), simple main -> .bak fallback on load ---------------

func _restore() -> bool:
	for p in [_writer.main_path, _writer.bak_path]:
		var rd: Dictionary = backend.read_file(p)
		if not rd["ok"]:
			continue
		var d = JSON.parse_string((rd["bytes"] as PackedByteArray).get_string_from_utf8())
		if typeof(d) != TYPE_DICTIONARY or int(d.get("save_version", 0)) != SAVE_VERSION:
			continue
		if d.get("level_id", "") != level.id or d.get("content_hash", "") != _content_hash:
			continue
		var st = SortState.new(level)
		if st.from_dict(d.get("state", {})) and st.check_invariants():
			state = st
			puzzle_seed = int(d.get("seed", 0))
			if p == _writer.main_path:
				_writer.h_commit = backend.sha256(rd["bytes"])
			return true
	return false


func _save(forced := false) -> void:
	if not _dirty or not _writer.may_attempt(Time.get_ticks_msec(), forced):
		return
	var bytes := JSON.stringify({"save_version": SAVE_VERSION, "level_id": level.id, "content_hash": _content_hash,
		"seed": puzzle_seed, "state": state.to_dict()}, "", true).to_utf8_buffer()
	if _writer.write(bytes, Time.get_ticks_msec())["committed"]:
		_dirty = false


# --- UI ------------------------------------------------------------------------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	feedback = Feedback.new()
	add_child(feedback)

	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size = Vector2(0, 48)
	add_child(top)
	top.add_child(_button("Tranh", "chevron-left", _on_back))
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", Color("#2b2622"))
	top.add_child(_title)
	_btn_sound = _button("Âm thanh", "volume-2", _on_toggle_sound)
	top.add_child(_btn_sound)

	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	add_child(_bar)
	_pct = Label.new()
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pct.add_theme_color_override("font_color", Color("#5a524b"))
	_pct.add_theme_font_size_override("font_size", 13)
	add_child(_pct)

	_msg = Label.new()
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.add_theme_color_override("font_color", Color("#5a3a2e"))
	add_child(_msg)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.name = "Actions"
	add_child(actions)
	actions.add_child(_button("Gợi ý", "search", _on_hint))
	actions.add_child(_button("Âm nền", "waves", _on_cycle_ambient))
	actions.add_child(_button("Chơi lại", "undo-2", _on_restart))

	_overlay = PanelContainer.new()
	_overlay.visible = false
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay.add_child(box)
	var l := Label.new()
	l.text = "Hoàn thành tranh!"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 22)
	box.add_child(l)
	for pair in [["Ngắm tranh", func(): _overlay.visible = false], ["Chơi lại", _on_restart],
			["Về danh sách tranh", _on_back]]:
		var b := Button.new()
		b.text = pair[0]
		b.custom_minimum_size = Vector2(0, 44)
		b.pressed.connect(pair[1])
		box.add_child(b)
	add_child(_overlay)
	resized.connect(_layout)


func _button(text: String, icon_name: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	var path := "res://game/assets/icons/%s.svg" % icon_name
	if ResourceLoader.exists(path):
		b.icon = load(path)
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size = Vector2(88, 44)
	b.pressed.connect(cb)
	return b


# Board on top, trays under it, then the action row; everything sized from the screen width.
func _layout() -> void:
	if level == null:
		return
	var w := size.x
	var margin := 12.0
	_bar.position = Vector2(48, 54)
	_bar.size = Vector2(w - 96, 10)
	_pct.position = Vector2(0, 64)
	_pct.size = Vector2(w, 18)
	var actions: Control = get_node("Actions")
	var actions_h := 52.0
	var tray_h := (w - 2 * margin) / SortState.TRAY_COUNT * 0.9
	var avail_h := size.y - 90.0 - tray_h - actions_h - 50.0
	_cell = minf((w - 2 * margin) / level.width, avail_h / level.height)
	var bw: float = _cell * level.width
	var bh: float = _cell * level.height
	_board_rect = Rect2(Vector2((w - bw) * 0.5, 90.0 + (avail_h - bh) * 0.5), Vector2(bw, bh))
	_msg.position = Vector2(16, _board_rect.end.y + 4)
	_msg.size = Vector2(w - 32, 24)
	_tray_rect = Rect2(Vector2(margin, _board_rect.end.y + 30), Vector2(w - 2 * margin, tray_h))
	actions.position = Vector2(0, size.y - actions_h - 6)
	actions.size = Vector2(w, actions_h)
	_overlay.position = Vector2(w * 0.5 - 140, size.y * 0.4 - 90)
	_overlay.size = Vector2(280, 180)
	queue_redraw()


func cell_center(i: int) -> Vector2:
	return _board_rect.position + (Vector2(level.cell_x(i), level.cell_y(i)) + Vector2(0.5, 0.5)) * _cell


func slot_center(slot: int) -> Vector2:
	var tw := _tray_rect.size.x / SortState.TRAY_COUNT
	var t := slot / SortState.TRAY_SLOTS
	var k := slot % SortState.TRAY_SLOTS
	var inner := tw * 0.86
	var origin := _tray_rect.position + Vector2(t * tw + (tw - inner) * 0.5, (_tray_rect.size.y - inner) * 0.5)
	return origin + (Vector2(k % 3, k / 3) + Vector2(0.5, 0.5)) * (inner / 3.0)


func slot_radius() -> float:
	return _tray_rect.size.x / SortState.TRAY_COUNT * 0.86 / 3.0 * 0.42


# --- input ---------------------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	# Touches reach the GUI as emulated mouse events (and desktop mice as themselves), so one path covers both.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _board_rect.has_point(event.position):
			tap_board(event.position)
			accept_event()


# A tap at a board position (also called by tests). Near misses snap to an actionable neighbour.
func tap_board(pos: Vector2) -> Dictionary:
	if state == null or state.completed():
		return {}
	var g := (pos - _board_rect.position) / _cell
	var gx := floori(g.x)
	var gy := floori(g.y)
	var best := -1
	for r in [0, 1]:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x: int = gx + dx
				var y: int = gy + dy
				if x < 0 or y < 0 or x >= level.width or y >= level.height:
					continue
				var i: int = y * level.width + x
				if best < 0 and state.action_at(i) != "none" and not _pending_cells.has(i):
					best = i
		if best >= 0:
			break
	if best < 0:
		return {}
	return apply_tap(best)


func apply_tap(i: int) -> Dictionary:
	var before_slots: Array = state.tray.duplicate()
	var r: Dictionary = state.tap(i)
	var now := Time.get_ticks_msec()
	match r["kind"]:
		"lift":
			feedback.play("pick")
			feedback.haptic_place()
			var k := 0
			for m in r["moves"]:
				var to: Vector2
				var f := {"color": m["color"], "from": cell_center(m["from_cell"]), "start": now + k * STAGGER_MS}
				if m.has("to_cell"):
					to = cell_center(m["to_cell"])
					f["dest_cell"] = m["to_cell"]
					_pending_cells[m["to_cell"]] = true
				else:
					to = slot_center(m["to_tray"])
					f["dest_slot"] = m["to_tray"]
					_pending_slots += 1
				f["to"] = to
				_flights.append(f)
				k += 1
			_dirty = true
		"fill":
			feedback.play("pick")
			var k := 0
			for m in r["moves"]:
				_flights.append({"color": m["color"], "from": slot_center(m["from_tray"]), "to": cell_center(m["to_cell"]),
					"start": now + k * STAGGER_MS, "dest_cell": m["to_cell"]})
				_pending_cells[m["to_cell"]] = true
				k += 1
			_dirty = true
		"tray_full":
			feedback.play("wrong", -6.0)
			_shake_until = now + 350
			_say("Khay không đủ chỗ: cần %d ô trống, còn %d. Hãy lấp các chỗ trống trước." % [r["needed"], r["free"]], 3000)
		"need_beads":
			feedback.play("wrong", -6.0)
			_hint_cells = r["cells"]
			_hint_until = now + 900
			_say("Chưa có hạt màu này trong khay. Gỡ các mảng hạt sai màu để lấy hạt.", 2500)
	_refresh()
	return r


func _say(text: String, ms: int) -> void:
	_msg.text = text
	_msg_until = Time.get_ticks_msec() + ms


# --- actions -------------------------------------------------------------------------------------------------

func _on_hint() -> void:
	var probe = state.duplicate_state()
	var m: int = SortPuzzle.best_move(probe)
	if m < 0:
		_say("Không còn nước đi. Hãy bấm Chơi lại.", 3000)
		return
	_hint_cells = state.cover_cluster(m) if state.action_at(m) == "lift" else state.empty_cluster(m)
	_hint_until = Time.get_ticks_msec() + 1500


func _on_restart() -> void:
	_flights.clear()
	_pending_cells.clear()
	_pending_slots = 0
	_overlay.visible = false
	_new_puzzle(puzzle_seed + 1)
	_save(true)
	_refresh()


func _on_toggle_sound() -> void:
	feedback.sfx_enabled = not feedback.sfx_enabled
	_update_sound_button()
	if settings != null:
		settings.sfx_enabled = feedback.sfx_enabled
		settings.save()


func _on_cycle_ambient() -> void:
	var names: Array = feedback.AMBIENT_NAMES
	var next: String = names[(names.find(feedback.ambient_name) + 1) % names.size()]
	feedback.set_ambient(next)
	_say({"off": "Âm nền: tắt", "sea": "Âm nền: biển", "rain": "Âm nền: mưa"}[next], 1200)
	if settings != null:
		settings.ambient = next
		settings.save()


func _update_sound_button() -> void:
	_btn_sound.text = "Âm thanh" if feedback.sfx_enabled else "Tắt tiếng"
	var path := "res://game/assets/icons/%s.svg" % ("volume-2" if feedback.sfx_enabled else "volume-x")
	if ResourceLoader.exists(path):
		_btn_sound.icon = load(path)


func _on_back() -> void:
	_save(true)
	exit_requested.emit()


func _notification(what: int) -> void:
	if state != null and what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT,
			NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		_save(true)


# --- frame ---------------------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if state == null:
		return
	var now := Time.get_ticks_msec()
	var still := []
	for f in _flights:
		if now - int(f["start"]) >= FLY_MS:
			if f.has("dest_cell"):
				_pending_cells.erase(f["dest_cell"])
				if now - _last_place_sound > 55:
					feedback.play("place")
					_last_place_sound = now
			else:
				_pending_slots -= 1
		else:
			still.append(f)
	_flights = still
	if _msg.text != "" and now > _msg_until:
		_msg.text = ""
	if _flights.is_empty():
		_save()
		if state.completed() and not _done_shown:
			_done_shown = true
			feedback.duck_ambient()
			feedback.play("level_complete")
			_overlay.visible = true
	queue_redraw()


func _refresh() -> void:
	_bar.value = state.progress()
	_pct.text = "%d%%" % int(round(state.progress() * 100.0))
	queue_redraw()


func _draw() -> void:
	if state == null:
		return
	var now := Time.get_ticks_msec()
	draw_rect(Rect2(Vector2.ZERO, size), BG)        # children (buttons, labels) draw on top of this
	draw_rect(_board_rect.grow(6), BOARD_BG)
	var r := _cell * 0.46
	var hint_on := now < _hint_until and int((now / 180) % 2) == 0
	var hint := {}
	if hint_on:
		for i in _hint_cells:
			hint[i] = true
	for i in level.cell_count():
		var t: int = level.cells[i]
		if t < 0:
			continue
		var mid := cell_center(i)
		if state.cover[i] != SortState.NONE:
			BeadArt.bead(self, mid, r, level.colors[state.cover[i]])
		elif state.filled[i] == 1 and not _pending_cells.has(i):
			BeadArt.bead(self, mid, r, level.colors[t])
		else:
			BeadArt.hollow(self, mid, r, level.colors[t])
		if hint.has(i):
			draw_arc(mid, r * 1.05, 0, TAU, 16, Color(1, 1, 1, 0.95), maxf(1.5, r * 0.25))
	# trays
	var shake := sin(now * 0.08) * 4.0 if now < _shake_until else 0.0
	var tw := _tray_rect.size.x / SortState.TRAY_COUNT
	for t in SortState.TRAY_COUNT:
		var rect := Rect2(_tray_rect.position + Vector2(t * tw + 3 + shake, 0), Vector2(tw - 6, _tray_rect.size.y))
		draw_style_box(_tray_box(), rect)
	var visible_slots: int = state.tray.size() - _pending_slots
	for s in SortState.CAPACITY:
		var c := slot_center(s) + Vector2(shake, 0)
		if s < visible_slots:
			BeadArt.bead(self, c, slot_radius(), level.colors[state.tray[s]])
		else:
			draw_circle(c, slot_radius() * 0.9, Color(0.86, 0.84, 0.82))
	# flying beads, arcing upwards
	for f in _flights:
		var u := clampf((now - int(f["start"])) / FLY_MS, 0.0, 1.0)
		if u <= 0.0:
			continue
		var e := 1.0 - pow(1.0 - u, 3.0)
		var a: Vector2 = f["from"]
		var b: Vector2 = f["to"]
		var p := a.lerp(b, e) + Vector2(0, -sin(e * PI) * 40.0)
		BeadArt.bead(self, p, maxf(r, slot_radius()) * (1.0 + 0.25 * sin(e * PI)), level.colors[f["color"]])


static var _box: StyleBoxFlat

static func _tray_box() -> StyleBoxFlat:
	if _box == null:
		_box = StyleBoxFlat.new()
		_box.bg_color = Color(1, 1, 1, 0.9)
		_box.set_corner_radius_all(8)
		_box.shadow_color = Color(0, 0, 0, 0.12)
		_box.shadow_size = 3
	return _box
