# Gesture sessions and tap classification (gameplay spec GS-5.1, 5.2, 5.3, 5.7). Pure logic: the caller feeds
# touch events with timestamps and asks whether the finished session was a tap.
extends RefCounted

const Config := preload("res://game/core/config.gd")

var tap_slop := Config.TAP_SLOP
var tap_max_ms := Config.TAP_MAX_MS
var multi_touch_cooldown_ms := Config.MULTI_TOUCH_COOLDOWN_MS

var _touches := {}               # index -> current position
var _in_session := false
var _max_fingers := 0
var _down_pos := Vector2.ZERO
var _down_ms := 0
var _max_move := 0.0
var _started_while_moving := false
var _last_multi_end_ms := -1000000000


func finger_count() -> int:
	return _touches.size()


func in_session() -> bool:
	return _in_session


func touch_positions() -> Array:
	return _touches.values()


func session_down_pos() -> Vector2:
	return _down_pos


func session_max_fingers() -> int:
	return _max_fingers


func touch_down(index: int, pos: Vector2, t_ms: int, camera_moving: bool) -> void:
	if not _in_session:
		_in_session = true
		_max_fingers = 0
		_down_pos = pos
		_down_ms = t_ms
		_max_move = 0.0
		_started_while_moving = camera_moving
	_touches[index] = pos
	_max_fingers = maxi(_max_fingers, _touches.size())


func touch_move(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		return
	_touches[index] = pos
	if _max_fingers == 1:
		_max_move = maxf(_max_move, pos.distance_to(_down_pos))


# Returns {} while fingers remain down. When the last finger lifts, returns
# {"tap": bool, "down_pos": Vector2, "up_pos": Vector2}.
func touch_up(index: int, pos: Vector2, t_ms: int) -> Dictionary:
	if not _touches.has(index):
		return {}
	touch_move(index, pos)
	_touches.erase(index)
	if not _touches.is_empty():
		return {}
	_in_session = false
	if _max_fingers >= 2:
		_last_multi_end_ms = t_ms
		return {"tap": false, "down_pos": _down_pos, "up_pos": pos}
	var is_tap := (_max_move <= tap_slop
		and t_ms - _down_ms <= tap_max_ms
		and not _started_while_moving
		and _down_ms - _last_multi_end_ms >= multi_touch_cooldown_ms)
	return {"tap": is_tap, "down_pos": _down_pos, "up_pos": pos}


# Cancels the session (e.g. the app lost focus); no tap is produced.
func cancel(t_ms: int) -> void:
	if _in_session and _max_fingers >= 2:
		_last_multi_end_ms = t_ms
	_touches.clear()
	_in_session = false
