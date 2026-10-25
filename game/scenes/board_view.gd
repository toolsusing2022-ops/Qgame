# Board rendering, camera (pan / pinch / animated zoom) and gesture handling (gameplay spec sections 5 and 7).
# Emits cell_tapped for taps that should be resolved by the rules (GS-6) and handles tap-to-zoom itself (GS-5.10).
extends Control

const Config := preload("res://game/core/config.gd")
const ViewMath := preload("res://game/core/view_math.gd")
const GestureTracker := preload("res://game/core/gesture_tracker.gd")

signal cell_tapped(index: int)
signal tap_to_zoom_used
signal camera_settled

const PLACE_ANIM_MS := 200.0
const UNDO_ANIM_MS := 150.0
const WRONG_NUMBER_MS := 600.0
const FIND_RING_MS := 900.0

var state                        # BoardState
var reduce_motion := false

var cell_size := 10.0            # pt per cell on screen
var center := Vector2.ZERO       # grid coordinates shown at the view centre

var _tracker = GestureTracker.new()
var _tween: Tween
var _down_cell_size := 0.0
var _down_center := Vector2.ZERO
var _panning := false
var _pinch_start_dist := 0.0
var _pinch_start_size := 0.0
var _pinch_anchor := Vector2.ZERO
var _anims := {}                 # cell -> {kind, start_ms}
var _wrong_numbers := {}         # cell -> start_ms
var _find_ring := {}             # {cell, start_ms}


func setup(board_state) -> void:
	state = board_state
	reset_view(false)


func fit_size() -> float:
	return ViewMath.fit_cell_size(size, state.level.width, state.level.height)


func is_animating() -> bool:
	return _tween != null and _tween.is_running()


# Toàn cảnh (GS-5.9).
func reset_view(animated := true) -> void:
	if state == null:
		return
	var target_center := Vector2(state.level.width, state.level.height) * 0.5
	_move_camera(fit_size(), target_center, animated)


func zoom_to(target_cell_size: float, target_center: Vector2, animated := true) -> void:
	_move_camera(ViewMath.clamp_cell_size(target_cell_size, fit_size()), target_center, animated)


func view_center() -> Vector2:
	return center


func is_cell_in_view(i: int) -> bool:
	var p := grid_to_view(Vector2(state.level.cell_x(i) + 0.5, state.level.cell_y(i) + 0.5))
	return Rect2(Vector2.ZERO, size).has_point(p)


func grid_to_view(g: Vector2) -> Vector2:
	return (g - center) * cell_size + size * 0.5


func view_to_grid(p: Vector2, at_cell_size := cell_size, at_center := center) -> Vector2:
	return (p - size * 0.5) / at_cell_size + at_center


# --- feedback hooks used by the play scene -------------------------------------------------------------------

func play_place(i: int) -> void:
	_anims[i] = {"kind": "place", "start": Time.get_ticks_msec()}
	queue_redraw()


func play_undo(i: int) -> void:
	_anims[i] = {"kind": "undo", "start": Time.get_ticks_msec()}
	queue_redraw()


func show_wrong_number(i: int) -> void:
	_wrong_numbers[i] = Time.get_ticks_msec()
	queue_redraw()


func show_find_ring(i: int) -> void:
	_find_ring = {"cell": i, "start": Time.get_ticks_msec()}
	queue_redraw()


# --- camera --------------------------------------------------------------------------------------------------

func _move_camera(target_size: float, target_center: Vector2, animated: bool) -> void:
	_stop_animation()
	target_center = _clamp_center(target_center)
	if not animated or reduce_motion:
		cell_size = target_size
		center = target_center
		queue_redraw()
		camera_settled.emit()
		return
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var secs := Config.FIND_ANIM_MS / 1000.0
	_tween.tween_property(self, "cell_size", target_size, secs)
	_tween.tween_property(self, "center", target_center, secs)
	_tween.chain().tween_callback(func(): camera_settled.emit())


func _stop_animation() -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = null


func _clamp_center(c: Vector2) -> Vector2:
	return Vector2(clampf(c.x, 0.0, state.level.width), clampf(c.y, 0.0, state.level.height))


# --- input (GS-5) --------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if state == null or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if handle_touch(event.index, local, event.pressed):
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if handle_drag(event.index, local, event.relative):
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		# Desktop convenience only (not part of the touch spec): mouse wheel zooms around the cursor.
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if not Rect2(Vector2.ZERO, size).has_point(local):
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_around(local, cell_size * 1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_around(local, cell_size / 1.15)


# Touch entry points in board-local coordinates (also used by integration tests). Return true if consumed.
func handle_touch(index: int, local: Vector2, pressed: bool) -> bool:
	if pressed:
		# Sessions that start outside the board belong to the tray / buttons (GS-5.6).
		if not _tracker.in_session() and not Rect2(Vector2.ZERO, size).has_point(local):
			return false
		_on_touch_down(index, local)
		return true
	if not _tracker.in_session():
		return false
	_on_touch_up(index, local)
	return true


func handle_drag(index: int, local: Vector2, relative: Vector2) -> bool:
	if not _tracker.in_session():
		return false
	_on_touch_drag(index, local, relative)
	return true


func _on_touch_down(index: int, local: Vector2) -> void:
	var moving := is_animating()
	_stop_animation()                         # GS-5.3: a touch stops camera motion
	if not _tracker.in_session():
		_down_cell_size = cell_size
		_down_center = center
		_panning = false
	_tracker.touch_down(index, local, Time.get_ticks_msec(), moving)
	if _tracker.finger_count() == 2:
		var pts: Array = _tracker.touch_positions()
		_pinch_start_dist = maxf((pts[0] as Vector2).distance_to(pts[1]), 1.0)
		_pinch_start_size = cell_size
		_pinch_anchor = view_to_grid(((pts[0] as Vector2) + pts[1]) * 0.5)


func _on_touch_drag(index: int, local: Vector2, relative: Vector2) -> void:
	_tracker.touch_move(index, local)
	var fingers: int = _tracker.finger_count()
	if fingers == 1:
		if not _panning and local.distance_to(_tracker.session_down_pos()) > Config.TAP_SLOP:
			_panning = true
		if _panning or _tracker.session_max_fingers() >= 2:
			center = _clamp_center(center - relative / cell_size)
			queue_redraw()
	elif fingers == 2:
		var pts: Array = _tracker.touch_positions()
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[1]
		var mid := (a + b) * 0.5
		var new_size := ViewMath.clamp_cell_size(_pinch_start_size * a.distance_to(b) / _pinch_start_dist, fit_size())
		cell_size = new_size
		# Keep the grid point that was under the pinch centre under the current centre (GS-5.9).
		center = _clamp_center(_pinch_anchor - (mid - size * 0.5) / cell_size)
		queue_redraw()
	# 3+ fingers: ignored (GS-5.7)


func _on_touch_up(index: int, local: Vector2) -> void:
	var fingers_before: int = _tracker.finger_count()
	var result: Dictionary = _tracker.touch_up(index, local, Time.get_ticks_msec())
	if fingers_before == 2 and _tracker.finger_count() == 1:
		_panning = true                       # the remaining finger keeps panning smoothly (GS-5.2)
	if result.is_empty() or not result["tap"]:
		return
	if not Rect2(Vector2.ZERO, size).has_point(result["up_pos"]):
		return                                # GS-5.6
	# GS-5.4: resolve the cell from the touch-down point and the camera at touch-down.
	var g := view_to_grid(result["down_pos"], _down_cell_size, _down_center)
	var cell := ViewMath.cell_at(g * _down_cell_size, _down_cell_size, state.level.width, state.level.height)
	if ViewMath.needs_zoom_to_place(_down_cell_size):
		# GS-5.10: tap-to-zoom, no placement, no wrong-tap feedback.
		zoom_to(Config.PLACE_ZOOM_CELL, g)
		tap_to_zoom_used.emit()
		return
	cell_tapped.emit(cell)


func _zoom_around(local: Vector2, new_size: float) -> void:
	_stop_animation()
	var anchor := view_to_grid(local)
	cell_size = ViewMath.clamp_cell_size(new_size, fit_size())
	center = _clamp_center(anchor - (local - size * 0.5) / cell_size)
	queue_redraw()


# --- drawing (GS-7) ------------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if is_animating() or not _anims.is_empty() or not _wrong_numbers.is_empty() or not _find_ring.is_empty():
		queue_redraw()


func _draw() -> void:
	if state == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("#f4efe6"))
	var level = state.level
	var now := Time.get_ticks_msec()
	var font := get_theme_default_font()
	var show_numbers := cell_size >= Config.NUMBER_VISIBLE_CELL
	var g0 := view_to_grid(Vector2.ZERO).floor()
	var g1 := view_to_grid(size).ceil()
	var x0 := clampi(int(g0.x), 0, level.width)
	var y0 := clampi(int(g0.y), 0, level.height)
	var x1 := clampi(int(g1.x), 0, level.width)
	var y1 := clampi(int(g1.y), 0, level.height)
	var r := cell_size * 0.5
	for y in range(y0, y1):
		for x in range(x0, x1):
			var i: int = y * level.width + x
			var c: int = level.cells[i]
			if c < 0:
				continue
			var origin := grid_to_view(Vector2(x, y))
			var mid := origin + Vector2(r, r)
			var col: Color = level.colors[c]
			var anim: Dictionary = _anims.get(i, {})
			if state.placed[i] != 0:
				var scale := 1.0
				var alpha := 1.0
				if anim.get("kind", "") == "place":
					var t := (now - int(anim["start"])) / PLACE_ANIM_MS
					if t >= 1.0:
						_anims.erase(i)
					elif reduce_motion:
						alpha = clampf(t, 0.0, 1.0)
					else:
						scale = 1.0 + 0.15 * sin(clampf(t, 0.0, 1.0) * PI)
				_draw_bead(mid, r * 0.9 * scale, col, alpha)
			else:
				var valid: bool = c == state.selected and not state.completed
				var tint := col.lerp(Color.WHITE, 0.55 if valid else 0.8)
				draw_rect(Rect2(origin + Vector2(1, 1), Vector2(cell_size - 2, cell_size - 2)), tint)
				if valid:
					draw_rect(Rect2(origin + Vector2(1.5, 1.5), Vector2(cell_size - 3, cell_size - 3)),
						col.darkened(0.15), false, maxf(1.0, cell_size * 0.06))
				if anim.get("kind", "") == "undo":
					var t := (now - int(anim["start"])) / UNDO_ANIM_MS
					if t >= 1.0:
						_anims.erase(i)
					else:
						var scale := 1.0 if reduce_motion else 1.0 - 0.5 * t
						_draw_bead(mid, r * 0.9 * scale, col, 1.0 - t)
				var wrong_start: int = _wrong_numbers.get(i, -1)
				var show_this := show_numbers
				if wrong_start >= 0:
					if now - wrong_start > WRONG_NUMBER_MS:
						_wrong_numbers.erase(i)
					else:
						show_this = true
				if show_this and cell_size >= 8.0:
					var fs := int(clampf(cell_size * 0.42, 8.0, 28.0))
					var label := str(c + 1)
					var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
					draw_string(font, mid + Vector2(-tw * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
						fs, Color(0, 0, 0, 0.55))
	if not _find_ring.is_empty():
		var t := (now - int(_find_ring["start"])) / FIND_RING_MS
		if t >= 1.0:
			_find_ring = {}
		else:
			var fi: int = _find_ring["cell"]
			var p := grid_to_view(Vector2(level.cell_x(fi) + 0.5, level.cell_y(fi) + 0.5))
			draw_arc(p, r * (1.2 + 0.6 * t), 0, TAU, 32, Color(1, 1, 1, 1.0 - t), maxf(2.0, r * 0.25))


# Bead look constrained by GS-7.4: highlight only in the upper-left quadrant, shadow only at r > 0.65.
func _draw_bead(mid: Vector2, radius: float, col: Color, alpha: float) -> void:
	var base := Color(col, alpha)
	draw_circle(mid, radius, base)
	draw_arc(mid, radius * 0.84, 0, TAU, 32, Color(col.darkened(0.25), alpha), maxf(1.0, radius * 0.16))
	draw_circle(mid + Vector2(-0.33, -0.33) * radius, radius * 0.16, Color(col.lightened(0.45), alpha * 0.9))
