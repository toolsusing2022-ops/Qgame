# "Gỡ hạt" mode: generator, two-tap select -> destination rules, trays, solvability, persistence.
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


func test_first_tap_only_selects_second_tap_places() -> void:
	var st = _hand_made()
	var r: Dictionary = st.tap_cell(1)
	assert_eq(r["kind"], "select")
	assert_eq(r["cells"], PackedInt32Array([1]))
	assert_eq(st.cover[1], 0, "nothing moves on the first tap")
	assert_eq(st.filled[4], 0)
	r = st.tap_cell(4)
	assert_eq(r["kind"], "place")
	assert_eq(r["moves"], [{"from_cell": 1, "to_cell": 4, "color": 0}])
	assert_false(st.has_selection())
	assert_true(st.completed())
	assert_eq(st.tray_free(), SortState.CAPACITY)
	assert_true(st.check_invariants())


func test_tap_selected_again_or_correct_bead_deselects() -> void:
	var st = _hand_made()
	st.tap_cell(1)
	assert_eq(st.tap_cell(1)["kind"], "deselect")
	assert_false(st.has_selection())
	st.tap_cell(1)
	assert_eq(st.tap_cell(0)["kind"], "deselect", "tapping a finished bead drops the selection")
	assert_eq(st.tap_cell(0)["kind"], "none")
	assert_eq(st.tap_cell(3)["kind"], "none", "-1 cell")


func test_empty_cell_needs_a_matching_selection() -> void:
	var st = _hand_made()
	assert_eq(st.tap_cell(4)["kind"], "need_select")
	st.filled[5] = 0               # hole of colour 1 ...
	st.cover[0] = 1                # ... and its loose bead, so the invariant still holds
	assert_true(st.check_invariants())
	st.tap_cell(1)                 # colour-0 cover selected
	var r: Dictionary = st.tap_cell(5)
	assert_eq(r["kind"], "wrong_color")
	assert_eq(st.cover[1], 0, "nothing moved")
	assert_true(st.has_selection(), "selection survives a wrong target")


func test_park_in_tray_then_place_from_tray() -> void:
	var st = _hand_made()
	st.cover[4] = 1               # the colour-0 hole is now hidden under a colour-1 cover
	st.filled[5] = 0              # ... whose own hole is cell 5
	assert_true(st.check_invariants())
	st.tap_cell(1)
	var r: Dictionary = st.tap_slot(13)          # any slot of tray 1 -> fills from tray 1 onwards
	assert_eq(r["kind"], "to_tray")
	assert_eq(r["moves"], [{"from_cell": 1, "to_slot": 9, "color": 0}])
	assert_eq(st.tray[9], 0)
	assert_false(st.has_selection())
	st.tap_cell(4)
	assert_eq(st.tap_cell(5)["kind"], "place")   # colour-1 cover into its hole, revealing hole 4
	assert_eq(st.tap_slot(10)["kind"], "none", "empty slot, nothing selected")
	r = st.tap_slot(9)
	assert_eq(r["kind"], "select_tray")
	assert_eq(r["slots"], PackedInt32Array([9]))
	r = st.tap_cell(4)
	assert_eq(r["kind"], "place")
	assert_eq(r["moves"], [{"from_slot": 9, "to_cell": 4, "color": 0}])
	assert_true(st.completed())
	assert_true(st.check_invariants())


# Not a balanced puzzle: only the move mechanics are checked here.
func test_partial_moves_keep_the_rest_selected() -> void:
	var st = SortState.new(_level())
	var lvl = st.level
	var hole: int = Array(lvl.cells).find(0)
	var covers := []
	for i in lvl.cell_count():
		if lvl.cell_x(i) <= lvl.width - 3 and lvl.cells[i] > 0 and lvl.cells[i + 1] > 0 and lvl.cells[i + 2] > 0:
			covers = [i, i + 1, i + 2]
			break
	st.filled[hole] = 0
	for i in covers:
		st.cover[i] = 0
	assert_eq(st.tap_cell(covers[2])["kind"], "select")
	var r: Dictionary = st.tap_cell(hole)
	assert_eq(r["kind"], "place")
	assert_eq(r["moves"].size(), 1, "one hole, one bead")
	assert_eq(st.sel_cells.size(), 2, "the other two stay selected")
	for s in SortState.CAPACITY:
		st.tray[s] = 1
	st.tray[53] = SortState.NONE
	r = st.tap_slot(0)                 # searches forward from tray 0 to the only free slot
	assert_eq(r["kind"], "to_tray")
	assert_eq(r["moves"].size(), 1)
	assert_eq(r["moves"][0]["to_slot"], 53)
	assert_eq(st.sel_cells.size(), 1)
	assert_eq(st.tap_slot(0)["kind"], "tray_full")
	assert_eq(st.sel_cells.size(), 1, "nothing moved")


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
		var in_tray: int = SortState.CAPACITY - st.tray_free()
		assert_true(in_tray > 0, rel + " some beads start in the trays")
		assert_eq(covers + in_tray, holes, rel + " one loose bead per hole")
		assert_true(st.progress() < 1.0)
		var solved: Dictionary = SortPuzzle.solve(st.duplicate_state())
		assert_true(solved["solved"], rel + " greedy solve")


func test_random_play_keeps_invariants() -> void:
	var lvl = _level()
	var st = SortPuzzle.generate(lvl, 7)["state"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for step in 6000:
		if rng.randf() < 0.7:
			st.tap_cell(rng.randi_range(-1, lvl.cell_count()))
		else:
			st.tap_slot(rng.randi_range(-1, SortState.CAPACITY))
		if not st.check_invariants():
			fail("invariant broken at step %d" % step)
			return


func test_persistence_round_trip() -> void:
	var lvl = _level()
	var st = SortPuzzle.generate(lvl, 5)["state"]
	for k in 3:
		assert_true(SortPuzzle.play(st, SortPuzzle.best_move(st)))
	st.tap_cell(0)                 # a transient selection is not saved
	var d: Dictionary = JSON.parse_string(JSON.stringify(st.to_dict()))
	var st2 = SortState.new(lvl)
	assert_true(st2.from_dict(d))
	assert_eq(st2.cover, st.cover)
	assert_eq(st2.filled, st.filled)
	assert_eq(st2.tray, st.tray)
	assert_false(st2.has_selection())
	assert_false(SortState.new(lvl).from_dict({"filled": "", "cover": [], "tray": []}))
	# older saves stored only the occupied slots
	var old: Dictionary = st.to_dict()
	old["tray"] = [2, 3]
	assert_true(st2.from_dict(old))
	assert_eq(st2.tray[0], 2)
	assert_eq(st2.tray[1], 3)
	assert_eq(st2.tray[2], SortState.NONE)


# The play screen: a tap only selects, the second tap moves beads (animated), progress survives a reopen.
func test_play_screen_two_taps_then_restore() -> void:
	var SortPlay = load("res://game/scenes/sort_play.gd")
	var MemoryBackend = load("res://game/storage/memory_backend.gd")
	var backend = MemoryBackend.new()
	var path := repo_path("content/trials/squid_easy_01.json")
	var p = add_to_tree(SortPlay.new())
	p.size = Vector2(390, 844)
	assert_true(await p.open_level(path, backend, null, "user://sort_test"))
	var m: Dictionary = SortPuzzle.best_move(p.state.duplicate_state())
	var before: Dictionary = p.state.to_dict()
	var r1: Dictionary = p.apply_cell(m["src"]) if m["src_kind"] == "cell" else p.apply_slot(m["src"])
	assert_true(r1["kind"] == "select" or r1["kind"] == "select_tray")
	assert_eq(p.state.to_dict(), before, "first tap moves nothing")
	assert_true(p._flights.is_empty())
	var r2: Dictionary = p.apply_cell(m["dst"]) if m["dst_kind"] == "cell" else p.apply_slot(m["dst"])
	assert_false(r2["moves"].is_empty())
	assert_eq(p._flights.size(), r2["moves"].size(), "every moved bead flies")
	var after: Dictionary = p.state.to_dict()
	p._on_back()                                   # forced save
	p.queue_free()
	await frames(2)
	var q = add_to_tree(SortPlay.new())
	q.size = Vector2(390, 844)
	assert_true(await q.open_level(path, backend, null, "user://sort_test"))
	assert_eq(q.state.to_dict(), after, "restored from the save")
