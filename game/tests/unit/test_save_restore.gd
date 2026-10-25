# Sections 12-14: write protocol (WE/WK rows), restore (E0-E3), events. Logic simulation on the model backend;
# none of this is evidence about real device storage (GS-12.9).
extends "res://game/tests/test_case.gd"

const Fault := preload("res://game/storage/fault_backend.gd")
const SB := preload("res://game/storage/storage_backend.gd")
const LevelLoader := preload("res://game/core/level_loader.gd")
const Session := preload("res://game/save/progress_session.gd")
const EventStore := preload("res://game/events/event_store.gd")
const Dispatcher := preload("res://game/events/dispatcher.gd")
const Restore := preload("res://game/save/restore.gd")
const PendingScan := preload("res://game/save/pending_scan.gd")
const Codec := preload("res://game/save/progress_codec.gd")
const ColorMath := preload("res://game/core/color_math.gd")

const DIR := "mem/progress"
const EVENTS := "mem/events/events.jsonl"
const MAIN := "mem/progress/fixture_f1.json"
const BAK := "mem/progress/fixture_f1.json.bak"

var now_ms := 1_000_000


func _clock() -> int:
	return now_ms


func _level(rel := "tests/fixtures/levels/F1.json"):
	return LevelLoader.load_file(repo_path(rel))["level"]


func _f1_variant(edit: Callable):
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(repo_path("tests/fixtures/levels/F1.json")))
	edit.call(d)
	var r := LevelLoader.validate(d)
	assert_true(r["ok"], str(r["errors"]))
	return r["level"]


# A "process": backend + store + dispatcher + session for one level.
func _session(fs, level = null, entry := {"content_version": 1}):
	var store = EventStore.new(fs, EVENTS)
	var disp = Dispatcher.new(store)
	var s = Session.new(fs, disp, level if level != null else _level(), entry, DIR, "install-1")
	s.set_clock(_clock)
	return s


func _open(fs, level = null, entry := {"content_version": 1}):
	var s = _session(fs, level, entry)
	s.open()
	return s


func _place(s, cell: int) -> Dictionary:
	var c: int = s.level.cells[cell]
	s.board.select_color(c)
	var r: Dictionary = s.board.tap(cell)
	s.on_tap_result(r)
	now_ms += 100
	return r


func _committed_state(fs, level = null) -> Dictionary:
	var s = _open(_clone(fs), level)
	return {"placed": s.board.placed, "source": s.restore_result["source"], "outcome": s.restore_result["outcome"]}


func _clone(fs):
	var n = Fault.new()
	n.load_image(fs.image())
	return n


# --- commit protocol -------------------------------------------------------------------------------------------

func test_first_play_writes_main_without_bak() -> void:
	var fs = Fault.new()
	var s = _open(fs)
	assert_eq(s.restore_result["outcome"], "fresh_first_play")
	assert_true(fs.files.has(MAIN))
	assert_false(fs.files.has(BAK), "first write has nothing to rotate")


func test_tc_12_6_write_then_read_back() -> void:
	var fs = Fault.new()
	var s = _open(fs)
	_place(s, 0)
	assert_true(s.flush()["committed"])
	s.board.undo()
	s.on_undo_result({"ok": true, "cell": 0, "color": 0})
	assert_true(s.flush()["committed"])
	var st := _committed_state(fs)
	assert_eq(st["placed"], PackedByteArray([0, 0, 0, 0, 0, 0]))
	var d: Dictionary = JSON.parse_string(fs.files[MAIN].get_string_from_utf8())
	for k in Codec.REQUIRED:
		assert_true(d.has(k), k)
	assert_true(fs.files.has(BAK), "second commit rotates .bak")


func test_tc_12_15_we_1a_write_fails() -> void:
	var fs = Fault.new()
	var s = _open(fs)
	var main_before: PackedByteArray = fs.files[MAIN]
	_place(s, 0)
	fs.fail("write", "fixture_f1.json.tmp", 1)
	var r: Dictionary = s.flush()
	assert_false(r["committed"])
	assert_eq(r["row"], "WE-1a")
	assert_eq(fs.files[MAIN], main_before, "L.json untouched")
	assert_false(fs.files.has(MAIN + ".tmp"), "tmp removed")
	assert_true(s.flush()["committed"], "next attempt commits")
	assert_eq(_committed_state(fs)["placed"][0], 1)


func test_tc_12_16_we_1b_sync_fails() -> void:
	var fs = Fault.new()
	var s = _open(fs)
	_place(s, 0)
	var renames_before: int = fs.count("rename", "fixture_f1.json")
	fs.fail("sync_file", "fixture_f1.json.tmp", 1)
	var r: Dictionary = s.flush()
	assert_eq(r["row"], "WE-1b")
	assert_eq(fs.count("rename", "fixture_f1.json"), renames_before, "tmp never renamed")


func test_tc_12_17_we_2a_bak_tmp_write_fails() -> void:
	var fs = Fault.new()
	var s = _open(fs)
	_place(s, 0)
	s.flush()
	var main_before: PackedByteArray = fs.files[MAIN]
	var bak_before: PackedByteArray = fs.files[BAK] if fs.files.has(BAK) else PackedByteArray()
	_place(s, 4)
	fs.fail("write", ".bak.tmp", 1)
	var r: Dictionary = s.flush()
	assert_eq(r["row"], "WE-2a")
	assert_eq(fs.files[MAIN], main_before)
	assert_eq(fs.files.get(BAK, PackedByteArray()), bak_before)
	assert_false(fs.files.has(MAIN + ".tmp") or fs.files.has(BAK + ".tmp"))


func test_tc_12_18_we_2b_bak_rename_fails_unchanged() -> void:
	var fs = Fault.new()
	var s = _open(fs)
	_place(s, 0)
	s.flush()
	_place(s, 4)
	s.flush()
	var bak_before: PackedByteArray = fs.files[BAK]
	_place(s, 1)
	fs.fail("rename", ".bak", 1)
	var r: Dictionary = s.flush()
	assert_eq(r["row"], "WE-2b")
	assert_eq(fs.files[BAK], bak_before)
	assert_false(s.writer.needs_reconcile, "state has evidence")


func test_tc_12_19_we_3_bak_already_replaced() -> void:
	var fs = Fault.new()
	var s = _open(fs)
	_place(s, 0)
	s.flush()
	var main_n: PackedByteArray = fs.files[MAIN]
	_place(s, 4)
	fs.fail("rename", "fixture_f1.json", 1)
	var r: Dictionary = s.flush()
	assert_eq(r["row"], "WE-3")
	assert_eq(fs.files[MAIN], main_n, "L.json = N")
	assert_eq(fs.files[BAK], main_n, ".bak WAS changed: it is now a copy of N")
	var st := _committed_state(fs)
	assert_eq(st["source"], "main")
	assert_eq(st["placed"][4], 0)
	assert_true(s.flush()["committed"])
	assert_eq(fs.files[BAK], main_n)


func test_tc_12_20_dir_sync_unsupported_and_failed_still_commit() -> void:
	var fs = Fault.new()
	var s = _open(fs)
	_place(s, 0)
	var r: Dictionary = s.flush()
	assert_eq(r["dir_sync"], "unsupported")
	assert_eq(r["level"], "written")
	_place(s, 4)
	fs.durable_mode = true
	fs.fail("sync_dir", "progress", 1)
	var r2: Dictionary = s.flush()
	assert_true(r2["committed"])
	assert_eq(r2["dir_sync"], "failed")
	assert_eq(r2["level"], "written", "not durable without a successful dir sync")
	for line in fs.log_lines:
		if line.begins_with("commit "):
			assert_false(line.contains("level=durable"), line)


func test_tc_12_33_we_3r_commit_reported_failed_but_replaced() -> void:
	var fs = Fault.new()
	var s = _open(fs)
	_place(s, 0)
	fs.fail_after_effect("rename", "fixture_f1.json")
	var r: Dictionary = s.flush()
	assert_true(r["committed"])
	assert_eq(r["row"], "WE-3r")


func test_tc_12_34_we_3i_postcheck_fails_then_r12() -> void:
	var fs = Fault.new()
	var s = _open(fs)
	_place(s, 0)
	s.flush()
	_place(s, 4)
	# Reads of L.json in this write: step 2a, step-3 pre-check, step-3 post-check -> fail the third.
	fs.fail("read", "progress/fixture_f1.json", 1, 2)
	var r: Dictionary = s.flush()
	assert_eq(r["row"], "WE-3i")
	assert_false(r["committed"], "indeterminate is never a commit")
	assert_true(s.writer.needs_reconcile)
	_place(s, 1)
	var r2: Dictionary = s.flush()
	assert_true(r2["committed"])
	var log := "\n".join(fs.log_lines)
	assert_true(log.contains("commit_reconciled"), "R12: L.json held the indeterminate write")
	assert_true(log.contains("reconcile R12"))
	assert_eq(_committed_state(fs)["placed"][1], 1)


func test_tc_12_34_r0_after_restore_from_bak() -> void:
	var fs = Fault.new()
	var s = _open(fs)
	_place(s, 0)
	s.flush()
	_place(s, 4)
	s.flush()
	fs.files[MAIN] = "garbage".to_utf8_buffer()
	var s2 = _open(fs)                          # source bak, L.json archived, first write created L.json
	fs.files.erase(MAIN)                        # pretend that first write never landed
	s2.writer.h_commit = ""
	s2.writer.needs_reconcile = true
	_place(s2, 1)
	var r: Dictionary = s2.flush()
	assert_true(r["committed"])
	assert_true("\n".join(fs.log_lines).contains("reconcile R0"))


func test_tc_12_34_r3_unknown_main_skips_rotation() -> void:
	var fs = Fault.new()
	var s = _open(fs)
	_place(s, 0)
	s.flush()
	_place(s, 4)
	s.flush()
	var bak_before: PackedByteArray = fs.files[BAK]
	fs.files[MAIN] = "{\"unknown\":true}".to_utf8_buffer()
	s.writer.needs_reconcile = true
	_place(s, 1)
	var r: Dictionary = s.flush()
	assert_true(r["committed"])
	assert_true("\n".join(fs.log_lines).contains("reconcile_unknown_main"))
	assert_eq(fs.files[BAK], bak_before, "R3 does not rotate .bak")


func test_tc_12_42_we_2b_i_then_reconcile_and_rotate() -> void:
	var fs = Fault.new()
	var s = _open(fs)
	_place(s, 0)
	s.flush()
	_place(s, 4)
	fs.fail("exists", ".bak", 1)               # pre-check of .bak cannot determine presence -> WE-2b-p
	var r: Dictionary = s.flush()
	assert_true(r["row"] in ["WE-2b-p", "WE-2b-i"], r["row"])
	assert_true(s.writer.needs_reconcile)
	var r2: Dictionary = s.flush()
	assert_true(r2["committed"])
	assert_false(s.writer.needs_reconcile)
	assert_true("reconcile R12" in "\n".join(fs.log_lines))


func test_tc_12_49_r0_keeps_bak_untouched() -> void:
	var fs = Fault.new()
	var s = _open(fs)
	_place(s, 0)
	s.flush()
	_place(s, 4)
	s.flush()                                   # L.json = {0,4}, .bak = {0}
	fs.files[MAIN] = "garbage".to_utf8_buffer()
	var s2 = _open(fs)                          # main unreadable -> source bak, L.json archived
	assert_eq(s2.restore_result["source"], "bak")
	assert_true(s2.restore_result["bak_notice"])
	var bak_before: PackedByteArray = fs.files[BAK]
	assert_eq(s2.board.placed[0], 1, "restored state, not empty")
	assert_true(fs.files.has(MAIN), "first write after restore created L.json")
	assert_eq(fs.files[BAK], bak_before, ".bak untouched by the first write")


func test_tc_12_55_save_blocked_and_recovery() -> void:
	var fs = Fault.new()
	var s = _open(fs)
	_place(s, 0)
	fs.fail("read", "fixture_f1.json.tmp", -1)  # pre-check of step 3 can never read src -> WE-3p
	for k in 3:
		var r: Dictionary = s.flush(true)
		assert_eq(r["row"], "WE-3p")
	assert_true(s.is_save_blocked())
	assert_eq(s.flush(), {}, "throttled while blocked")
	assert_eq(int(s.writer.k_failures), 3)
	fs.clear_rules()
	now_ms += 31_000
	var ok: Dictionary = s.flush()
	assert_true(ok["committed"])
	assert_false(s.is_save_blocked())
	assert_eq(_committed_state(fs)["placed"][0], 1)


func test_tc_12_55_b_path_u_replaces_unreadable_main() -> void:
	var fs = Fault.new()
	var s = _open(fs)
	_place(s, 0)
	s.flush()
	var bak_before: Variant = fs.files.get(BAK)
	fs.fail("read", "progress/fixture_f1.json", 2)   # step 2a read fails, then step R read fails
	_place(s, 4)
	var r1: Dictionary = s.flush()
	assert_eq(r1["row"], "WE-2a-read")
	var r2: Dictionary = s.flush()
	assert_true(r2["committed"], "path U: no rotation, step 3 with pre_dst unreadable")
	assert_eq(fs.files.get(BAK), bak_before, ".bak untouched on path U")
	assert_eq(_committed_state(fs)["placed"][4], 1)


# --- crash points (WK) -----------------------------------------------------------------------------------------

func _crash_case(op: String, suffix: String, nth: int) -> Dictionary:
	var fs = Fault.new()
	var s = _open(fs)
	_place(s, 0)
	s.flush()
	_place(s, 4)
	fs.crash_before(op, suffix, nth)
	s.flush()
	assert_true(fs.dead, "crash point reached: %s %s" % [op, suffix])
	var after = Fault.new()
	after.load_image(fs.crash_image)
	var s2 = _open(after)
	return {"placed": s2.board.placed, "source": s2.restore_result["source"], "fs": after}


func test_tc_12_7_wk_1_during_tmp_write() -> void:
	var r := _crash_case("write", "fixture_f1.json.tmp", 1)
	assert_eq(r["placed"][4], 0, "N restored")
	assert_eq(r["source"], "main")


func test_tc_12_21_wk_3_after_bak_tmp() -> void:
	var r := _crash_case("rename", ".bak", 1)
	assert_eq(r["placed"][4], 0)
	assert_false(r["fs"].files.has(MAIN + ".bak.tmp"), "E0 removed bak.tmp")


func test_tc_12_12_wk_4_after_bak_rotated() -> void:
	var r := _crash_case("rename", "progress/fixture_f1.json", 1)
	assert_eq(r["placed"][4], 0)
	assert_eq(r["source"], "main", "no .bak notice when L.json is fine")
	assert_false(r["fs"].files.has(MAIN + ".tmp"))


func test_tc_12_14_wk_5_after_commit() -> void:
	var r := _crash_case("sync_dir", "progress", 1)
	assert_eq(r["placed"][4], 1, "N+1 restored")


func test_tc_12_13_tmp_never_used_even_if_newer() -> void:
	var fs = Fault.new()
	var s = _open(fs)
	_place(s, 0)
	s.flush()
	_place(s, 4)
	s.flush()
	fs.files[MAIN + ".tmp"] = fs.files[MAIN]
	fs.files[MAIN] = "{broken".to_utf8_buffer()
	var s2 = _open(fs)
	assert_eq(s2.restore_result["source"], "bak")
	assert_eq(s2.board.placed[4], 0, "bak (N) not tmp (N+1)")
	assert_true(s2.restore_result["bak_notice"])


# --- restore --------------------------------------------------------------------------------------------------

func _saved_f1(placed_cells: Array, entry := {"content_version": 1}):
	var fs = Fault.new()
	var s = _open(fs, null, entry)
	for c in placed_cells:
		_place(s, c)
	s.flush()
	return fs


func test_tc_13_4_restored() -> void:
	var fs = _saved_f1([0])
	var s = _open(fs)
	assert_eq(s.restore_result["outcome"], "restored")
	assert_eq(s.board.placed[0], 1)
	assert_eq(s.board.last_placed, -1, "TC-13.14")


func test_tc_13_5_hex_changed_with_catalog_claim() -> void:
	var fs = _saved_f1([0])
	var f9 = _f1_variant(func(d): d["palette"][1]["hex"] = "#c9362f")
	var s = _open(fs, f9, {"content_version": 2, "palette_compat_from": 1})
	assert_eq(s.restore_result["outcome"], "restored_hex_changed")
	assert_eq(s.board.placed[0], 1)
	assert_true(Restore.MESSAGES["restored_hex_changed"] in s.restore_result["notices"])


func test_tc_13_5b_hex_changed_without_metadata() -> void:
	var fs = _saved_f1([0])
	var f9 = _f1_variant(func(d): d["palette"][1]["hex"] = "#c9362f")
	var s = _open(fs, f9, {"content_version": 2})
	assert_eq(s.restore_result["outcome"], "stale_palette_unverified")
	assert_eq(s.board.placed[0], 0, "fresh progress")


func test_tc_13_5c_swapped_colors_rejected() -> void:
	var fs = _saved_f1([0])
	var f15 = _f1_variant(func(d):
		d["palette"][0]["hex"] = "#e2553d"
		d["palette"][1]["hex"] = "#2f86b8")
	var s = _open(fs, f15, {"content_version": 2, "palette_compat_from": 1})
	assert_eq(s.restore_result["outcome"], "stale_palette_rejected")


func test_tc_13_5d_large_recolor_rejected_and_delta_e_reference() -> void:
	assert_true(absf(ColorMath.delta_e_hex("#e2553d", "#c9362f") - 9.5) < 0.1, "F9 ΔE00")
	assert_true(absf(ColorMath.delta_e_hex("#2f86b8", "#e2553d") - 49.0) < 0.1, "F15 ΔE00")
	assert_true(absf(ColorMath.delta_e_hex("#e2553d", "#f2a33a") - 28.0) < 0.1, "F17 ΔE00")
	var fs = _saved_f1([0])
	var f17 = _f1_variant(func(d): d["palette"][1]["hex"] = "#f2a33a")
	var s = _open(fs, f17, {"content_version": 2, "palette_compat_from": 1})
	assert_eq(s.restore_result["outcome"], "stale_palette_rejected")


func test_tc_13_5e_content_version_not_bumped() -> void:
	var fs = _saved_f1([0])
	var f9 = _f1_variant(func(d): d["palette"][1]["hex"] = "#c9362f")
	var s = _open(fs, f9, {"content_version": 1, "palette_compat_from": 1})
	assert_eq(s.restore_result["outcome"], "stale_palette_unverified")


func test_tc_13_6_layout_changed() -> void:
	var fs = _saved_f1([0])
	var f10 = _level("tests/fixtures/levels/F10_layout_changed.json")
	# F10 has a different level id; reuse F1's id so the same progress file is read.
	f10.id = "fixture_f1"
	var s = _open(fs, f10, {"content_version": 2})
	assert_eq(s.restore_result["outcome"], "stale_layout_changed")
	assert_true(Restore.MESSAGES["stale"] in s.restore_result["notices"])


func test_tc_13_12_both_unreadable() -> void:
	var fs = Fault.new()
	fs.files[MAIN] = "x".to_utf8_buffer()
	fs.files[BAK] = "y".to_utf8_buffer()
	var s = _open(fs)
	assert_eq(s.restore_result["outcome"], "corrupt_fresh")
	var names: PackedStringArray = fs.list_dir(DIR)["names"]
	var corrupt := 0
	for n in names:
		if n.contains(".corrupt."):
			corrupt += 1
	assert_eq(corrupt, 2)


func test_tc_13_13_bitset_wrong_length_uses_bak() -> void:
	var fs = _saved_f1([0])
	var s = _open(fs)
	_place(s, 4)
	s.flush()
	var d: Dictionary = JSON.parse_string(fs.files[MAIN].get_string_from_utf8())
	d["placed"] = Marshalls.raw_to_base64(PackedByteArray([1, 0, 0]))
	fs.files[MAIN] = JSON.stringify(d).to_utf8_buffer()
	var s2 = _open(fs)
	assert_eq(s2.restore_result["source"], "bak")
	assert_eq(s2.restore_result["candidates"][0]["result"], "invalid")


func test_tc_13_17_wrong_level_main() -> void:
	var fs = _saved_f1([0])
	var s = _open(fs)
	_place(s, 4)
	s.flush()
	var d: Dictionary = JSON.parse_string(fs.files[MAIN].get_string_from_utf8())
	d["level_id"] = "other_01"
	fs.files[MAIN] = JSON.stringify(d).to_utf8_buffer()
	var s2 = _open(fs)
	assert_eq(s2.restore_result["candidates"][0]["result"], "wrong_level")
	assert_eq(s2.restore_result["source"], "bak")


func test_tc_13_22_incompatible_main_compatible_bak() -> void:
	var fs = _saved_f1([0])
	var s = _open(fs)
	_place(s, 4)
	s.flush()
	var d: Dictionary = JSON.parse_string(fs.files[MAIN].get_string_from_utf8())
	d["save_version"] = 99
	fs.files[MAIN] = JSON.stringify(d).to_utf8_buffer()
	var s2 = _open(fs)
	assert_eq(s2.restore_result["source"], "bak")
	assert_eq(s2.restore_result["outcome"], "restored")
	assert_eq(s2.restore_result["archived"][0]["as"], "stale")


func test_tc_13_24_both_incompatible() -> void:
	var fs = _saved_f1([0])
	var s = _open(fs)
	_place(s, 4)
	s.flush()
	var f10 = _level("tests/fixtures/levels/F10_layout_changed.json")
	f10.id = "fixture_f1"
	var s2 = _open(fs, f10, {"content_version": 2})
	assert_eq(s2.restore_result["outcome"], "stale_layout_changed")
	assert_eq(s2.restore_result["archived"].size(), 2)


func test_tc_13_28_archive_rename_failure_aborts_without_rollback() -> void:
	var fs = _saved_f1([0])
	var s = _open(fs)
	_place(s, 4)
	s.flush()
	var f10 = _level("tests/fixtures/levels/F10_layout_changed.json")
	f10.id = "fixture_f1"
	fs.fail_containing("rename", ".bak.stale.")
	fs.fail_containing("rename", ".bak.pending-stale.")
	var s2 = _session(fs, f10, {"content_version": 2})
	var r: Dictionary = s2.open()
	assert_eq(r["outcome"], "archive_failed")
	assert_true(fs.files.has(BAK), ".bak unchanged")
	assert_false(fs.files.has(MAIN), "L.json already archived (no rollback)")
	fs.clear_rules()
	var s3 = _open(fs, f10, {"content_version": 2})
	assert_eq(s3.restore_result["outcome"], "stale_layout_changed")


func test_tc_13_31_archive_name_collision() -> void:
	var fs = Fault.new()
	fs.files[MAIN] = "x".to_utf8_buffer()
	var store = EventStore.new(fs, EVENTS)
	var r: Dictionary = Restore.run({"backend": fs, "dispatcher": Dispatcher.new(store), "level": _level(),
		"catalog_entry": {"content_version": 1}, "progress_dir": DIR, "now_ms": 0, "utc": "T"})
	fs.files[MAIN] = "y".to_utf8_buffer()
	var r2: Dictionary = Restore.run({"backend": fs, "dispatcher": Dispatcher.new(store), "level": _level(),
		"catalog_entry": {"content_version": 1}, "progress_dir": DIR, "now_ms": 0, "utc": "T"})
	assert_eq(fs.files[MAIN + ".corrupt.T"], "x".to_utf8_buffer(), "first archive untouched")
	assert_eq(fs.files[MAIN + ".corrupt.T-1"], "y".to_utf8_buffer())


func test_tc_13_32_fresh_after_archive_vs_first_play() -> void:
	var fs = Fault.new()
	fs.files[MAIN + ".stale.T"] = "x".to_utf8_buffer()
	var s = _open(fs)
	assert_eq(s.restore_result["outcome"], "fresh_after_archive")
	var fs2 = Fault.new()
	assert_eq(_open(fs2).restore_result["outcome"], "fresh_first_play")


func test_tc_12_56_io_error_main_is_not_archived() -> void:
	var fs = _saved_f1([0])
	var s = _open(fs)
	_place(s, 4)
	s.flush()
	fs.fail("read", "progress/fixture_f1.json", 1)
	var s2 = _open(fs)
	assert_eq(s2.restore_result["source"], "bak")
	assert_true(fs.files.has(MAIN) or s2.writer.h_commit != "", "L.json not archived")
	assert_eq(fs.count("rename", ".corrupt."), 0)


# --- events -----------------------------------------------------------------------------------------------------

func _store(fs):
	return EventStore.new(fs, EVENTS)


func test_tc_4_6_and_14_2_complete_f1_single_level_complete() -> void:
	var fs = Fault.new()
	var s = _open(fs)
	for c in [0, 4, 1, 5, 2]:
		_place(s, c)
	assert_true(s.board.completed)
	s.flush()
	for k in 3:
		_open(fs)
	var store = _store(fs)
	assert_eq(store.count_logical("level_complete"), 1)
	assert_eq(store.count_logical("bead_placed"), 5)
	assert_eq(store.count_logical("color_complete"), 3, "TC-6.8")


func test_tc_14_4_logical_dedupe() -> void:
	var fs = Fault.new()
	var store = _store(fs)
	var e := {"event_id": "a", "type": "t", "payload": {"x": 1}, "ts": 5}
	store.append(e)
	store.append(e)
	assert_eq(store.valid_lines().size(), 2)
	assert_eq(store.count_logical(), 1)


func test_tc_14_9_and_14_24_torn_line_skipped_and_newline_inserted() -> void:
	var fs = Fault.new()
	var store = _store(fs)
	store.append({"event_id": "a", "type": "t", "payload": {}, "ts": 1})
	fs.files[EVENTS].append_array("{\"event_id\":\"b\"".to_utf8_buffer())   # torn tail
	store.append({"event_id": "c", "type": "t", "payload": {}, "ts": 2})
	var ids := []
	for o in store.logical_records():
		ids.append(o["event_id"])
	assert_eq(ids, ["a", "c"])
	assert_eq(store.skipped_lines, 1)


func test_tc_14_26_payload_conflict_first_wins() -> void:
	var fs = Fault.new()
	var store = _store(fs)
	store.append({"event_id": "a", "type": "t", "payload": {"v": 1}, "ts": 1})
	store.append({"event_id": "a", "type": "t", "payload": {"v": 2}, "ts": 1})
	var recs: Array = store.logical_records()
	assert_eq(recs.size(), 1)
	assert_eq(int(recs[0]["payload"]["v"]), 1)
	assert_eq(store.payload_conflicts, 1)


func test_tc_14_22_and_14_25_sync_failure_never_confirms_earlier_lines() -> void:
	var fs = Fault.new()
	var disp = Dispatcher.new(_store(fs))
	var e1 := {"event_id": "e1", "type": "t", "payload": {}, "ts": 1}
	fs.fail("sync_file", "events.jsonl", 1)
	var r: Dictionary = disp.dispatch([e1], "startup", 0)
	assert_false(r["ok"])
	assert_false(disp.is_confirmed("e1"), "line present but not confirmed")
	var e2 := {"event_id": "e2", "type": "t", "payload": {}, "ts": 2}
	disp.dispatch([e2], "startup", 1)
	assert_true(disp.is_confirmed("e2"))
	assert_false(disp.is_confirmed("e1"), "a later successful sync does not confirm e1")
	disp.dispatch([e1], "startup", 2)
	assert_true(disp.is_confirmed("e1"), "re-appended as a new line, then confirmed")
	assert_eq(_store(fs).count_logical(), 2)


func test_tc_14_23_restart_after_sync_failure() -> void:
	var fs = Fault.new()
	var s = _open(fs)
	_place(s, 0)
	fs.fail("sync_file", "events.jsonl", -1)
	s.flush()
	assert_eq(s.outbox.size(), 1, "entry stays in the outbox")
	fs.clear_rules()
	var s2 = _open(fs)                          # restart: everything still in a source is appended again
	assert_true(s2.dispatcher.is_confirmed(s2.restore_result["restore_outbox"][0]["event_id"]))
	assert_eq(_store(fs).count_logical("bead_placed"), 1)


func test_tc_14_27_throttle_after_store_failure() -> void:
	var fs = Fault.new()
	var disp = Dispatcher.new(_store(fs))
	fs.fail("append", "events.jsonl", 1)
	disp.dispatch([{"event_id": "a", "type": "t", "payload": {}, "ts": 1}], "commit", 1000)
	var r: Dictionary = disp.dispatch([{"event_id": "a", "type": "t", "payload": {}, "ts": 1}], "commit", 2000)
	assert_true(r["throttled"])
	var r2: Dictionary = disp.dispatch([{"event_id": "a", "type": "t", "payload": {}, "ts": 1}], "commit", 62_000)
	assert_true(r2["all_confirmed"])


func test_tc_14_15_archive_drain_failure_goes_pending_then_scan_completes() -> void:
	var fs = _saved_f1([0])
	var s = _open(fs)
	_place(s, 4)
	fs.fail("sync_file", "events.jsonl", -1)
	s.flush()
	var f10 = _level("tests/fixtures/levels/F10_layout_changed.json")
	f10.id = "fixture_f1"
	var s2 = _open(fs, f10, {"content_version": 2})
	var as_names := []
	for a in s2.restore_result["archived"]:
		as_names.append(a["as"])
	assert_true("pending-stale" in as_names, str(as_names))
	fs.clear_rules()
	var disp = Dispatcher.new(_store(fs))
	var report: Array = PendingScan.run(fs, disp, DIR, 0)
	var renamed := 0
	for rep in report:
		if rep["action"] == "renamed":
			renamed += 1
	assert_true(renamed >= 1)
	for n in fs.list_dir(DIR)["names"]:
		assert_false(n.contains(".pending-"), n)
	assert_eq(_store(fs).count_logical("bead_placed"), 2)


func test_tc_14_29_pending_of_other_level_only_that_file_touched() -> void:
	var fs = Fault.new()
	var other_main := DIR + "/other_01.json"
	fs.files[other_main] = "{}".to_utf8_buffer()
	fs.files[other_main + ".bak"] = "{}".to_utf8_buffer()
	var pending := {"level_id": "other_01", "outbox": [{"event_id": "o1", "type": "t", "payload": {}, "ts": 1}]}
	fs.files[other_main + ".pending-stale.T"] = JSON.stringify(pending).to_utf8_buffer()
	PendingScan.run(fs, Dispatcher.new(_store(fs)), DIR, 0)
	assert_true(fs.files.has(other_main + ".stale.T"))
	assert_false(fs.touched("other_01.json"))
	assert_false(fs.touched("other_01.json.bak"))
	assert_eq(fs.count("read", "other_01.json"), 0, "main file never read")


func test_tc_14_30_pending_io_error_kept() -> void:
	var fs = Fault.new()
	fs.files[DIR + "/x.json.pending-stale.T"] = "{}".to_utf8_buffer()
	fs.fail("read", "pending-stale.T", -1)
	var report: Array = PendingScan.run(fs, Dispatcher.new(_store(fs)), DIR, 0)
	assert_eq(report[0]["action"], "kept_io_error")
	assert_true(fs.files.has(DIR + "/x.json.pending-stale.T"))


# --- power loss on the model (TC-12.24 b): no guarantee, but a valid outcome --------------------------------------

func test_tc_12_24_b_power_loss_written_level_gives_valid_outcome() -> void:
	var fs = Fault.new()
	var s = _open(fs)
	_place(s, 0)
	s.flush()
	fs.power_loss()                              # nothing was ever durable at the written level
	var s2 = _open(fs)
	assert_true(s2.restore_result["outcome"] in ["fresh_first_play", "restored", "corrupt_fresh"])
	assert_true(s2.board.check_invariants())
