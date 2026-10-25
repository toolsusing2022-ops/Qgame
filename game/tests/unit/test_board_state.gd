# Sections 3, 4, 6, 9, 10: gameplay rules on BoardState.
extends "res://game/tests/test_case.gd"

const LevelLoader := preload("res://game/core/level_loader.gd")
const BoardState := preload("res://game/core/board_state.gd")

# F1: 3x2, cells [0,1,2,-1,0,1], counts [2,2,1].


func _board(rel := "tests/fixtures/levels/F1.json"):
	var r := LevelLoader.load_file(repo_path(rel))
	assert_true(r["ok"], str(r["errors"]))
	var b = BoardState.new(r["level"])
	b.enter_level()
	return b


func _all_in_view(_i: int) -> bool:
	return true


func test_tc_2_1_remaining_counted_and_invariants() -> void:
	var b = _board()
	assert_eq(b.remaining, PackedInt32Array([2, 2, 1]))
	assert_true(b.check_invariants())


func test_tc_4_1_default_color_and_undo_disabled() -> void:
	var b = _board()
	assert_eq(b.selected, 0, "largest remaining, lowest id on tie (D-1)")
	assert_false(b.can_undo())


func test_tc_4_2_tie_goes_to_lowest_id() -> void:
	var b = _board("tests/fixtures/levels/F11_tie.json")
	assert_eq(b.selected, 2, "colour 2 has the most cells")
	b.tap(0)
	b.tap(3)
	assert_true(b.is_color_done(2))
	b.enter_level()
	assert_eq(b.selected, 0, "colours 0 and 1 tie with 1 cell each -> lowest id")


func test_tc_4_3_saved_done_color_is_replaced() -> void:
	var b = _board()
	b.select_color(2)
	b.tap(2)
	assert_true(b.is_color_done(2))
	b.enter_level()
	assert_eq(b.selected, 0)


func test_tc_6_1_place_valid_cell() -> void:
	var b = _board()
	var r: Dictionary = b.tap(0)
	assert_eq(r["kind"], BoardState.TAP_PLACED)
	assert_eq(b.placed[0], 1)
	assert_eq(b.remaining[0], 1)
	assert_eq(b.last_placed, 0)
	assert_true(b.check_invariants())


func test_tc_6_2_wrong_cell() -> void:
	var b = _board()
	b.tap(0)
	var r: Dictionary = b.tap(1)
	assert_eq(r["kind"], BoardState.TAP_WRONG)
	assert_eq(b.placed[1], 0)
	assert_eq(b.last_placed, 0, "wrong tap keeps last_placed")
	assert_eq(b.wrong_streak, 1)


func test_tc_6_3_already_placed_is_silent_and_keeps_undo() -> void:
	var b = _board()
	b.tap(0)
	assert_eq(b.tap(0)["kind"], BoardState.TAP_ALREADY)
	assert_eq(b.last_placed, 0)
	var u: Dictionary = b.undo()
	assert_true(u["ok"])
	assert_eq(u["cell"], 0)


func test_tc_6_4_empty_and_outside() -> void:
	var b = _board()
	assert_eq(b.tap(3)["kind"], BoardState.TAP_EMPTY)
	assert_eq(b.tap(-1)["kind"], BoardState.TAP_EMPTY)
	assert_eq(b.tap(99)["kind"], BoardState.TAP_EMPTY)
	assert_eq(b.remaining, PackedInt32Array([2, 2, 1]))


func test_tc_6_5_no_selection_or_done_color() -> void:
	var b = _board()
	b.selected = BoardState.NONE
	assert_eq(b.tap(0)["kind"], BoardState.TAP_NO_SELECTION)
	b.select_color(2)
	b.tap(2)
	assert_eq(b.tap(0)["kind"], BoardState.TAP_NO_SELECTION, "selected colour already done")


func test_tc_6_6_wrong_streak_resets() -> void:
	var b = _board()
	for i in 3:
		var r: Dictionary = b.tap(1)
		assert_eq(r["show_hint"], i == 2)
	b.tap(0)
	assert_eq(b.wrong_streak, 0, "reset by a successful placement")
	b.tap(1)
	b.undo()
	assert_eq(b.wrong_streak, 0, "reset by undo")
	b.tap(1)
	b.select_color(1)
	assert_eq(b.wrong_streak, 0, "reset by colour change")


func test_tc_4_5_color_complete_keeps_selection() -> void:
	var b = _board()
	b.select_color(2)
	var r: Dictionary = b.tap(2)
	assert_true(r["color_completed"])
	assert_eq(r["occurrence"], "first")
	assert_eq(b.selected, 2, "no auto switch (H2 off)")


func test_tc_4_6_and_10_5_complete_locks_everything() -> void:
	var b = _board()
	var order := [[0, 0], [0, 4], [1, 1], [1, 5], [2, 2]]
	var last: Dictionary = {}
	for step in order:
		b.select_color(step[0])
		last = b.tap(step[1])
	assert_true(last["level_completed"])
	assert_true(b.completed)
	assert_false(b.can_undo())
	assert_false(b.undo()["ok"])
	assert_false(b.can_find())
	assert_eq(b.tap(0)["kind"], BoardState.TAP_LOCKED)
	assert_true(b.check_invariants())


func test_tc_10_1_and_10_2_single_step_undo() -> void:
	var b = _board()
	b.tap(0)
	var u: Dictionary = b.undo()
	assert_true(u["ok"])
	assert_eq(b.placed[0], 0)
	assert_eq(b.remaining, PackedInt32Array([2, 2, 1]))
	assert_false(b.can_undo())
	assert_false(b.undo()["ok"], "second undo does nothing")


func test_tc_10_3_reopen_and_repeat_occurrence() -> void:
	var b = _board()
	b.select_color(2)
	assert_eq(b.tap(2)["occurrence"], "first")
	var u: Dictionary = b.undo()
	assert_true(u["color_reopened"])
	assert_false(b.is_color_done(2))
	assert_eq(b.colors_ever_completed[2], 1, "colors_ever_completed is not cleared")
	assert_eq(b.tap(2)["occurrence"], "repeat")


func test_tc_10_4_non_placing_actions_keep_last_placed() -> void:
	var b = _board()
	b.tap(0)
	b.tap(1)            # wrong
	b.tap(0)            # already placed
	b.tap(3)            # empty
	b.select_color(1)   # colour change
	b.find_target(Vector2(1.5, 1.0), Callable(self, "_all_in_view"))
	assert_eq(b.last_placed, 0)
	assert_eq(b.undo()["cell"], 0)


func test_tc_10_6_leaving_clears_last_placed() -> void:
	var b = _board()
	b.tap(0)
	b.leave_level()
	b.enter_level()
	assert_false(b.can_undo())


func test_tc_9_1_find_prefers_unvisited_off_screen_then_clears() -> void:
	var b = _board("content/levels/squid_relax_01.json")
	var c: int = b.selected
	var cells: PackedInt32Array = b.valid_cells(c)
	assert_true(cells.size() >= 4)
	var visible := {cells[0]: true}
	var in_view := func(i: int) -> bool: return visible.has(i)
	var seen := {}
	for k in cells.size() - 1:
		var t: int = b.find_target(Vector2(0, 0), in_view)
		assert_false(visible.has(t), "off-screen cells first")
		assert_false(seen.has(t), "no repeats before all visited")
		seen[t] = true
	assert_eq(b.find_target(Vector2(0, 0), in_view), cells[0], "then the on-screen unvisited cell")
	var again: int = b.find_target(Vector2(0, 0), in_view)
	assert_true(again in cells, "after all visited the set is cleared")
	assert_eq(b.last_placed, BoardState.NONE)
	assert_eq(b.selected, c, "find never changes selection")


func test_tc_9_3_tie_lowest_index() -> void:
	var b = _board()
	# Colour 0 valid cells: 0 (0.5,0.5) and 4 (1.5,1.5). Centre (1,1) is equidistant.
	assert_eq(b.find_target(Vector2(1, 1), Callable(self, "_all_in_view")), 0)


func test_tc_9_8_undo_removes_cell_from_visited() -> void:
	var b = _board()
	var t: int = b.find_target(Vector2(0, 0), Callable(self, "_all_in_view"))
	assert_eq(t, 0)
	b.tap(t)
	b.undo()
	assert_false(b.find_visited[0].has(0))


func test_tc_6_10_random_operations_keep_invariants() -> void:
	var b = _board("content/trials/squid_easy_01.json")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var n: int = b.level.cell_count()
	for step in 10000:
		var op := rng.randi_range(0, 9)
		var before_last: int = b.last_placed
		if op <= 5:
			var i := rng.randi_range(-2, n + 1)
			var expected_color: int = b.level.cells[i] if i >= 0 and i < n else -9
			var r: Dictionary = b.tap(i)
			if r["kind"] == BoardState.TAP_PLACED:
				assert_eq(expected_color, r["color"])
			elif b.last_placed != before_last:
				fail("last_placed changed without placement at step %d" % step)
		elif op == 6:
			b.undo()
		elif op == 7:
			b.select_color(rng.randi_range(0, b.level.color_count() - 1))
			if b.last_placed != before_last:
				fail("colour change moved last_placed")
		elif op == 8:
			b.find_target(Vector2(rng.randf() * 20, rng.randf() * 15), Callable(self, "_all_in_view"))
			if b.last_placed != before_last:
				fail("find moved last_placed")
		else:
			if b.completed:
				break
		if not b.check_invariants():
			fail("invariant broken at step %d" % step)
			return


func test_tc_6_9_full_replay_of_relax_level() -> void:
	var b = _board("content/levels/squid_relax_01.json")
	for c in b.level.color_count():
		b.select_color(c)
		for i in b.valid_cells(c):
			b.tap(i)
			if not b.check_invariants():
				fail("invariant broken")
				return
	assert_true(b.completed)


func test_apply_saved_rejects_inconsistent_data() -> void:
	var b = _board()
	var placed := PackedByteArray([0, 0, 0, 1, 0, 0])   # cell 3 is -1
	assert_false(b.apply_saved(placed, 0, false, PackedByteArray([0, 0, 0])))
	assert_eq(b.remaining, PackedInt32Array([2, 2, 1]), "state untouched")
	var ok_placed := PackedByteArray([0, 0, 1, 0, 0, 0])
	assert_false(b.apply_saved(ok_placed, 0, true, PackedByteArray([0, 0, 1])), "completed flag mismatch")
	assert_true(b.apply_saved(ok_placed, 0, false, PackedByteArray([0, 0, 0])))
	assert_eq(b.colors_ever_completed[2], 1, "TC-13.16: missing completed colour is added")
