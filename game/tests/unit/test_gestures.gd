# Section 5 (logic part): tap classification, cell lookup, parameter constraints.
extends "res://game/tests/test_case.gd"

const GestureTracker := preload("res://game/core/gesture_tracker.gd")
const ViewMath := preload("res://game/core/view_math.gd")
const Config := preload("res://game/core/config.gd")


func _single(move: float, duration: int, moving := false, start := 1000) -> Dictionary:
	var g = GestureTracker.new()
	g.touch_down(0, Vector2(100, 100), start, moving)
	g.touch_move(0, Vector2(100 + move, 100))
	return g.touch_up(0, Vector2(100 + move, 100), start + duration)


func test_tc_5_1_small_move_short_press_is_tap() -> void:
	assert_true(_single(6, 200)["tap"])


func test_tc_5_2_drag_is_not_tap() -> void:
	assert_false(_single(15, 200)["tap"])


func test_tc_5_3_long_press_is_not_tap() -> void:
	assert_false(_single(0, 700)["tap"])


func test_tc_5_6_touch_while_camera_moving_is_not_tap() -> void:
	assert_false(_single(0, 100, true)["tap"])


func test_tc_5_4_pinch_then_lift_is_not_tap() -> void:
	var g = GestureTracker.new()
	g.touch_down(0, Vector2(100, 100), 0, false)
	g.touch_down(1, Vector2(200, 200), 10, false)
	assert_eq(g.touch_up(0, Vector2(100, 100), 50), {})
	var r: Dictionary = g.touch_up(1, Vector2(200, 200), 350)
	assert_false(r["tap"])


func test_tc_5_5_cooldown_after_multi_touch() -> void:
	var g = GestureTracker.new()
	g.touch_down(0, Vector2(0, 0), 0, false)
	g.touch_down(1, Vector2(50, 0), 0, false)
	g.touch_up(0, Vector2(0, 0), 100)
	g.touch_up(1, Vector2(50, 0), 100)
	g.touch_down(0, Vector2(10, 10), 160, false)
	assert_false(g.touch_up(0, Vector2(10, 10), 200)["tap"], "60 ms after multi-touch")
	g.touch_down(0, Vector2(10, 10), 300, false)
	assert_true(g.touch_up(0, Vector2(10, 10), 340)["tap"], "200 ms after multi-touch")


func test_tc_5_8_down_position_is_reported() -> void:
	var r := _single(8, 100)
	assert_eq(r["down_pos"], Vector2(100, 100))


func test_tc_5_12_three_fingers_never_tap() -> void:
	var g = GestureTracker.new()
	for k in 3:
		g.touch_down(k, Vector2(10 * k, 0), 0, false)
	assert_eq(g.finger_count(), 3)
	g.touch_up(0, Vector2(0, 0), 10)
	g.touch_up(1, Vector2(10, 0), 10)
	assert_false(g.touch_up(2, Vector2(20, 0), 10)["tap"])


func test_tc_5_9_edge_belongs_to_right_and_below() -> void:
	for k in 1000:
		assert_eq(ViewMath.cell_at(Vector2(3.0, 2.0) * 10.0, 10.0, 5, 4), 2 * 5 + 3)
	assert_eq(ViewMath.cell_at(Vector2(-0.01, 0), 10.0, 5, 4), -1)
	assert_eq(ViewMath.cell_at(Vector2(50, 0), 10.0, 5, 4), -1, "x == width is outside")


func test_tc_5_14_corner_of_cell_hits_that_cell() -> void:
	assert_eq(ViewMath.cell_at(Vector2(19.9, 0.1), 10.0, 5, 4), 1)


func test_tc_5_23_parameter_constraints() -> void:
	assert_eq(Config.constraint_errors(), PackedStringArray(), "shipped defaults are consistent")
	assert_eq(Config.constraint_errors(18, 40, 32, 72), PackedStringArray(["MIN_PLACE_CELL > PLACE_ZOOM_CELL"]))


func test_internal_levels_need_zoom_on_overview() -> void:
	# Section 0.2 consequence: on a 390 pt wide screen both internal levels are below MIN_PLACE_CELL at overview.
	var area := Vector2(390, 560)
	assert_true(ViewMath.needs_zoom_to_place(ViewMath.fit_cell_size(area, 20, 15)))
	assert_true(ViewMath.needs_zoom_to_place(ViewMath.fit_cell_size(area, 32, 32)))
	assert_false(ViewMath.needs_zoom_to_place(ViewMath.fit_cell_size(area, 3, 2)), "F1 places directly (TC-5.21)")
