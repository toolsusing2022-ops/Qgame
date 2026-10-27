# "Gỡ hạt" mode: generator, lift / fill rules, trays, solvability, persistence.
extends "res://game/tests/test_case.gd"

const LevelLoader := preload("res://game/core/level_loader.gd")
const SortState := preload("res://game/core/sort_state.gd")
const SortPuzzle := preload("res://game/core/sort_puzzle.gd")


func _level(rel := "content/trials/squid_easy_01.json"):
	return LevelLoader.load_file(repo_path(rel))["level"]


# F1 (3x2, cells [0,1,2,-1,0,1]) with a hand-made puzzle:
#   cell 4 (target 0) is a hole; cell 1 (target 1) carries a cover of colour 0.
func _hand_made():
	var st = SortState.new(_level("tests/fixtures/levels/F1.json"))
	st.filled[4] = 0
	st.cover[1] = 0
	assert_true(st.check_invariants())
	return st


func test_lift_goes_straight_to_visible_hole() -> void:
	var st = _hand_made()
	assert_eq(st.action_at(1), "lift")
	var r: Dictionary = st.tap(1)
	assert_eq(r["kind"], "lift")
	assert_eq(r["moves"].size(), 1)
	assert_eq(r["moves"][0]["to_cell"], 4)
	assert_true(st.completed())
	assert_eq(st.tray.size(), 0)
	assert_true(st.check_invariants())


func test_lift_overflows_into_tray_then_fill_from_tray() -> void:
	var st = _hand_made()
	st.cover[0] = 2               # hide the hole... no: put a cover on cell 0 doesn't hide cell 4
	st.cover[0] = SortState.NONE
	st.cover[4] = 1               # the hole of colour 0 is now under a cover of colour 1 -> needs a colour-1 hole
	st.filled[5] = 0
	assert_true(st.check_invariants())
	var r: Dictionary = st.tap(1)  # cover 0 lifts, hole 4 is still covered -> into the tray
	assert_eq(r["kind"], "lift")
	assert_true(r["moves"][0].has("to_tray"))
	assert_eq(st.tray, [0])
	r = st.tap(4)                  # cover 1 lifts straight into hole 5, revealing hole 4
	assert_eq(r["moves"][0]["to_cell"], 5)
	assert_eq(st.action_at(4), "fill")
	r = st.tap(4)                  # fill from the tray
	assert_eq(r["kind"], "fill")
	assert_eq(st.tray.size(), 0)
	assert_true(st.completed())


func test_fill_without_beads_and_correct_cell_do_nothing() -> void:
	var st = _hand_made()
	assert_eq(st.tap(4)["kind"], "need_beads")
	assert_eq(st.tap(0)["kind"], "none")
	assert_eq(st.tap(3)["kind"], "none", "-1 cell")


func test_tray_full_blocks_the_whole_lift() -> void:
	var st = _hand_made()
	for k in SortState.CAPACITY:
		st.tray.append(2)
	st.filled[4] = 1               # no visible hole for colour 0 anymore -> lift must overflow
	var r: Dictionary = st.tap(1)
	assert_eq(r["kind"], "tray_full")
	assert_eq(st.cover[1], 0, "nothing moved")


func test_cover_cluster_is_connected_same_colour() -> void:
	var st = SortState.new(_level())
	st.cover[0] = 3
	st.cover[1] = 3
	st.cover[2] = 4
	assert_eq(st.cover_cluster(0), PackedInt32Array([0, 1]))
	assert_eq(st.cover_cluster(2), PackedInt32Array([2]))


func test_generator_is_deterministic_conserves_beads_and_is_solvable() -> void:
	for rel in ["content/trials/squid_easy_01.json", "content/levels/squid_relax_01.json"]:
		var lvl = _level(rel)
		var a: Dictionary = SortPuzzle.generate(lvl, 42)
		var b: Dictionary = SortPuzzle.generate(lvl, 42)
		assert_eq(a["state"].cover, b["state"].cover, rel + " deterministic")
		assert_eq(a["state"].filled, b["state"].filled)
		var st = a["state"]
		assert_true(st.check_invariants(), rel)
		var covers := 0
		var holes := 0
		for i in lvl.cell_count():
			if st.cover[i] != SortState.NONE:
				covers += 1
			if lvl.cells[i] >= 0 and st.filled[i] == 0:
				holes += 1
		assert_true(holes > 0, rel + " has holes")
		assert_eq(covers, holes, rel + " one loose bead per hole")
		assert_true(st.progress() < 1.0)
		var solved: Dictionary = SortPuzzle.solve(st.duplicate_state())
		assert_true(solved["solved"], rel + " greedy solve")


func test_random_play_keeps_invariants() -> void:
	var lvl = _level()
	var st = SortPuzzle.generate(lvl, 7)["state"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for step in 3000:
		st.tap(rng.randi_range(-1, lvl.cell_count()))
		if not st.check_invariants():
			fail("invariant broken at step %d" % step)
			return


func test_persistence_round_trip() -> void:
	var lvl = _level()
	var st = SortPuzzle.generate(lvl, 5)["state"]
	st.tap(SortPuzzle.best_move(st))
	var d: Dictionary = JSON.parse_string(JSON.stringify(st.to_dict()))
	var st2 = SortState.new(lvl)
	assert_true(st2.from_dict(d))
	assert_eq(st2.cover, st.cover)
	assert_eq(st2.filled, st.filled)
	assert_eq(st2.tray, st.tray)
	assert_false(SortState.new(lvl).from_dict({"filled": "", "cover": [], "tray": []}))
