# Integration tests (level I) for the play screen with simulated touches: sections 5, 6, 8, 9, 10, 11.
extends "res://game/tests/test_case.gd"

const Play := preload("res://game/scenes/play.gd")
const Config := preload("res://game/core/config.gd")
const BoardState := preload("res://game/core/board_state.gd")


func _open(rel: String):
	tree.root.size = Vector2i(390, 844)
	var p = Play.new()
	add_to_tree(p)
	assert_true(p.load_level_file(repo_path(rel)), rel)
	await frames(6)
	p.board.reset_view(false)
	await frames(2)
	return p


func _cell_pos(p, i: int) -> Vector2:
	var lvl = p.state.level
	return p.board.grid_to_view(Vector2(lvl.cell_x(i) + 0.5, lvl.cell_y(i) + 0.5))


# Touches are injected in board-local coordinates through the same entry point _input uses. Going through
# Input.parse_input_event is unreliable headless because the window and viewport sizes differ.
func _touch(p, local: Vector2, pressed: bool, index := 0) -> void:
	p.board.handle_touch(index, local, pressed)


func _tap(p, local: Vector2) -> void:
	_touch(p, local, true)
	_touch(p, local, false)
	await frames(1)


func _wait_camera(p) -> void:
	for k in 120:
		if not p.board.is_animating():
			return
		await frames(1)


func test_tc_5_17_overview_tap_zooms_without_placing() -> void:
	var p = await _open("content/levels/squid_relax_01.json")
	assert_true(p.board.cell_size < Config.MIN_PLACE_CELL, "Relax overview is below MIN_PLACE_CELL")
	var i: int = p.state.valid_cells(p.state.selected)[0]
	var wrong_before: int = p.state.wrong_streak
	await _tap(p, _cell_pos(p, i))
	assert_eq(p.state.placed[i], 0, "no placement")
	assert_eq(p.state.last_placed, BoardState.NONE)
	assert_eq(p.state.wrong_streak, wrong_before)
	assert_eq(p._hint.text, p.HINT_ZOOM)
	await _wait_camera(p)
	assert_true(absf(p.board.cell_size - Config.PLACE_ZOOM_CELL) < 0.01, "zoomed to PLACE_ZOOM_CELL")
	assert_eq(p.feedback.sound_requests.size(), 0, "silent")


func test_tc_5_18_zoom_hint_once_per_session() -> void:
	var p = await _open("content/levels/squid_relax_01.json")
	await _tap(p, p.board.size * 0.5)
	p._hint.text = ""
	await _wait_camera(p)
	p.board.reset_view(false)
	await frames(1)
	await _tap(p, p.board.size * 0.5)
	assert_eq(p._hint.text, "", "hint not shown again")


func test_tc_5_20_and_5_21_placing_needs_new_tap_and_f1_places_directly() -> void:
	var p = await _open("tests/fixtures/levels/F1.json")
	assert_true(p.board.cell_size >= Config.MIN_PLACE_CELL)
	await _tap(p, _cell_pos(p, 0))
	assert_eq(p.state.placed[0], 1, "F1 overview tap places immediately")


func test_tc_6_1_and_11_9_haptic_only_on_success() -> void:
	var p = await _open("tests/fixtures/levels/F1.json")
	await _tap(p, _cell_pos(p, 0))        # place
	await _tap(p, _cell_pos(p, 1))        # wrong
	await _tap(p, _cell_pos(p, 0))        # already placed
	await _tap(p, _cell_pos(p, 3))        # empty
	p._on_undo()
	assert_eq(p.feedback.haptic_requests, 1)
	assert_eq(int(p.feedback.sound_requests.get("place", 0)), 1)
	assert_eq(int(p.feedback.sound_requests.get("wrong", 0)), 1)
	assert_eq(int(p.feedback.sound_requests.get("lift", 0)), 1)


func test_tc_8_1_tray_count_updates() -> void:
	var p = await _open("tests/fixtures/levels/F1.json")
	await _tap(p, _cell_pos(p, 0))
	assert_eq(p._swatches[0].remaining, 1)
	p._on_undo()
	assert_eq(p._swatches[0].remaining, 2)


func test_tc_8_3_disabled_buttons() -> void:
	var p = await _open("tests/fixtures/levels/F1.json")
	assert_true(p._btn_undo.disabled, "undo disabled before any placement")
	assert_false(p._btn_find.disabled)
	await _tap(p, _cell_pos(p, 0))
	assert_false(p._btn_undo.disabled)


func test_tc_9_4_find_then_tap_target() -> void:
	var p = await _open("content/levels/squid_relax_01.json")
	p._on_find()
	await _wait_camera(p)
	assert_true(p.board.cell_size >= Config.PLACE_ZOOM_CELL - 0.01)
	var visited: Dictionary = p.state.find_visited[p.state.selected]
	assert_eq(visited.size(), 1)
	var target: int = visited.keys()[0]
	await _tap(p, _cell_pos(p, target))
	assert_eq(p.state.placed[target], 1, "tap on the found cell places it")


func test_tc_9_6_touch_during_find_animation_stops_it_without_placing() -> void:
	var p = await _open("content/levels/squid_relax_01.json")
	p._on_find()
	await frames(2)
	assert_true(p.board.is_animating())
	var target: int = p.state.find_visited[p.state.selected].keys()[0]
	await _tap(p, _cell_pos(p, target))
	assert_false(p.board.is_animating(), "animation stopped")
	assert_eq(p.state.placed[target], 0, "no placement")


func test_tc_5_11_session_ending_outside_board_is_not_a_tap() -> void:
	var p = await _open("tests/fixtures/levels/F1.json")
	_touch(p, _cell_pos(p, 0), true)
	_touch(p, Vector2(_cell_pos(p, 0).x, p.board.size.y + 5), false)
	await frames(1)
	assert_eq(p.state.placed[0], 0)


func test_tc_10_9_undo_offscreen_shows_hint() -> void:
	var p = await _open("content/levels/squid_relax_01.json")
	var i: int = p.state.valid_cells(p.state.selected)[0]
	p.board.zoom_to(Config.PLACE_ZOOM_CELL, Vector2(p.state.level.cell_x(i) + 0.5, p.state.level.cell_y(i) + 0.5), false)
	await frames(1)
	await _tap(p, _cell_pos(p, i))
	assert_eq(p.state.placed[i], 1)
	p.board.zoom_to(Config.PLACE_ZOOM_CELL, Vector2(p.state.level.width, p.state.level.height), false)
	var center_before: Vector2 = p.board.center
	p._on_undo()
	assert_eq(p._hint.text, p.HINT_UNDO_OFFSCREEN)
	assert_eq(p.board.center, center_before, "camera does not move")


func test_tc_4_6_complete_level_shows_overlay_and_locks() -> void:
	var p = await _open("tests/fixtures/levels/F1.json")
	for step in [[0, 0], [0, 4], [1, 1], [1, 5], [2, 2]]:
		p._on_swatch_picked(step[0])
		await _tap(p, _cell_pos(p, step[1]))
	assert_true(p.state.completed)
	assert_true(p._overlay.visible)
	assert_true(p._btn_undo.disabled and p._btn_find.disabled)
	assert_eq(int(p.feedback.sound_requests.get("level_complete", 0)), 1)
