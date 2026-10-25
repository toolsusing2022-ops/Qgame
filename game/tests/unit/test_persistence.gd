# Persistence through the play screen and through GodotFileBackend on real files.
# Real-file tests run on the machine executing the suite (Linux in CI/container): they exercise the Godot API
# path, but they are NOT evidence for iOS (GS-12.8, GS-12.10).
extends "res://game/tests/test_case.gd"

const Play := preload("res://game/scenes/play.gd")
const MemoryBackend := preload("res://game/storage/memory_backend.gd")
const GodotFileBackend := preload("res://game/storage/godot_file_backend.gd")
const EventStore := preload("res://game/events/event_store.gd")
const Dispatcher := preload("res://game/events/dispatcher.gd")
const Session := preload("res://game/save/progress_session.gd")
const LevelLoader := preload("res://game/core/level_loader.gd")
const SB := preload("res://game/storage/storage_backend.gd")


func _open_play(backend, dir: String):
	var p = Play.new()
	add_to_tree(p)
	var disp = Dispatcher.new(EventStore.new(backend, dir.path_join("../events/events.jsonl").simplify_path()))
	var r: Dictionary = p.open_level(repo_path("tests/fixtures/levels/F1.json"), {"content_version": 1}, backend,
		disp, null, dir)
	assert_true(r["ok"], str(r))
	await frames(3)
	return p


func test_progress_survives_leaving_and_reopening_the_level() -> void:
	var mem = MemoryBackend.new()
	var p = await _open_play(mem, "mem/progress")
	p.state.select_color(0)
	p._on_cell_tapped(0)
	await frames(1)                              # _process flushes
	p._on_back()
	var p2 = await _open_play(mem, "mem/progress")
	assert_eq(p2.state.placed[0], 1, "placed bead restored")
	assert_false(p2.state.can_undo(), "D-8: undo not restored")
	assert_eq(p2.session.restore_result["outcome"], "restored")


func test_save_blocked_banner_visible_then_cleared() -> void:
	var fault = preload("res://game/storage/fault_backend.gd").new()
	var p = await _open_play(fault, "mem/progress")
	fault.fail("read", "fixture_f1.json.tmp", -1)
	for k in 3:
		p.state.select_color(0)
		p._on_cell_tapped([0, 4, 0][k])
		p.session.flush(true)
	await frames(1)
	assert_true(p._banner.visible, "KT-7 banner shown")
	assert_false(p.state.completed)
	fault.clear_rules()
	p.session.flush(true)
	await frames(1)
	assert_false(p._banner.visible, "removed after a replaced write")


func _tmp_dir() -> String:
	return "user://test_tmp_%d" % (Time.get_ticks_usec() % 1000000000)


func _rm_tree(dir: String) -> void:
	for sub in ["progress", "events", ""]:
		var d := dir.path_join(sub)
		if DirAccess.dir_exists_absolute(d):
			for f in DirAccess.get_files_at(d):
				DirAccess.remove_absolute(d.path_join(f))
			DirAccess.remove_absolute(d)


func test_godot_backend_rename_replace_on_real_files() -> void:
	var dir := _tmp_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var fs = GodotFileBackend.new()
	assert_true(fs.write_file(dir.path_join("a.tmp"), "new".to_utf8_buffer())["ok"])
	assert_true(fs.write_file(dir.path_join("a"), "old".to_utf8_buffer())["ok"])
	var r: Dictionary = fs.rename_replace(dir.path_join("a.tmp"), dir.path_join("a"), SB.sha256("new".to_utf8_buffer()))
	assert_eq(r["state_after"], SB.STATE_REPLACED)
	assert_eq(FileAccess.get_file_as_string(dir.path_join("a")), "new")
	assert_false(FileAccess.file_exists(dir.path_join("a.tmp")))
	var r2: Dictionary = fs.rename_noreplace(dir.path_join("a"), dir.path_join("a"), SB.sha256("new".to_utf8_buffer()))
	assert_eq(r2["err"], "dst_exists")
	assert_eq(fs.capabilities()["file_sync"]["value"], "written")
	assert_eq(fs.capabilities()["file_sync"]["evidence"], "assumed")
	_rm_tree(dir)


func test_godot_backend_full_session_round_trip() -> void:
	var dir := _tmp_dir()
	var fs = GodotFileBackend.new()
	var level = LevelLoader.load_file(repo_path("tests/fixtures/levels/F1.json"))["level"]
	var store = EventStore.new(fs, dir.path_join("events/events.jsonl"))
	var s = Session.new(fs, Dispatcher.new(store), level, {"content_version": 1}, dir.path_join("progress"), "i")
	s.open()
	s.board.select_color(0)
	s.on_tap_result(s.board.tap(0))
	assert_true(s.flush()["committed"])
	s.board.select_color(1)
	s.on_tap_result(s.board.tap(1))
	assert_true(s.flush()["committed"])
	assert_true(FileAccess.file_exists(dir.path_join("progress/fixture_f1.json.bak")))
	var s2 = Session.new(fs, Dispatcher.new(EventStore.new(fs, dir.path_join("events/events.jsonl"))), level,
		{"content_version": 1}, dir.path_join("progress"), "i")
	s2.open()
	assert_eq(s2.restore_result["outcome"], "restored")
	assert_eq(s2.board.placed, PackedByteArray([1, 1, 0, 0, 0, 0]))
	assert_eq(store.count_logical("bead_placed"), 2)
	_rm_tree(dir)
