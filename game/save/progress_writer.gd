# Progress write protocol for one level (gameplay spec GS-12.2 / GS-12.7, as of v0.4.9).
#
#   1  write L.json.tmp (truncate) + sync_file                         H_pending = sha256(B_new)
#   2a read L.json -> B_old, H_bak; write L.json.bak.tmp              (skipped when L.json is absent, R0, path U)
#   2b rename_replace(.bak.tmp -> .bak, H_bak)
#   3  rename_replace(.tmp -> L.json, H_pending)                       commit point: state_after == replaced
#   4  sync_dir                                                         durable | unsupported | failed (log only)
#
# Step R runs before a write while needs_reconcile is set (same session only; after a restart restore decides).
# H_pending / H_bak live for one write; H_commit lives for the session ("" = none). Decisions only use bytes and
# file presence, never commit order (invariant I-H).
extends RefCounted

const Config := preload("res://game/core/config.gd")
const StorageBackend := preload("res://game/storage/storage_backend.gd")

var backend
var main_path: String
var tmp_path: String
var bak_path: String
var bak_tmp_path: String

var h_commit := ""                # "" means none
var needs_reconcile := false
var k_failures := 0
var save_blocked := false
var last_attempt_ms := -1
var _h_prev_pending := ""

# Called with the outbox list parsed from committed bytes (B_new after replaced, B_disk in R12).
var on_committed_outbox: Callable


func _init(storage_backend, progress_dir: String, level_id: String) -> void:
	backend = storage_backend
	main_path = progress_dir.path_join(level_id + ".json")
	tmp_path = main_path + ".tmp"
	bak_path = main_path + ".bak"
	bak_tmp_path = main_path + ".bak.tmp"


# In save_blocked only one full attempt per SAVE_BLOCKED_RETRY_INTERVAL_S (plus forced attempts on background).
func may_attempt(now_ms: int, forced := false) -> bool:
	if not save_blocked or forced:
		return true
	return last_attempt_ms < 0 or now_ms - last_attempt_ms >= Config.SAVE_BLOCKED_RETRY_INTERVAL_S * 1000


# Returns {committed: bool, row: String, level: String, dir_sync: String}.
func write(b_new: PackedByteArray, now_ms := 0) -> Dictionary:
	last_attempt_ms = now_ms
	var h_pending := StorageBackend.sha256(b_new)
	var rotate := true

	# --- step R
	if needs_reconcile:
		var r := _reconcile()
		if r == "R0" or r == "R3":
			rotate = false
		backend.diag("reconcile %s" % r)

	# --- step 1
	var w1: Dictionary = backend.write_file(tmp_path, b_new)
	if not w1["ok"]:
		backend.delete(tmp_path)
		return _fail("WE-1a" if w1["err"] == "io_failed" else "WE-1b", false, h_pending)

	# --- step 2
	if rotate and backend.exists(main_path) == StorageBackend.EXISTS:
		var rd: Dictionary = backend.read_file(main_path)
		if not rd["ok"]:
			backend.delete(tmp_path)
			return _fail("WE-2a-read", true, h_pending)
		var b_old: PackedByteArray = rd["bytes"]
		var h_bak := StorageBackend.sha256(b_old)
		var w2: Dictionary = backend.write_file(bak_tmp_path, b_old)
		if not w2["ok"]:
			backend.delete(bak_tmp_path)
			backend.delete(tmp_path)
			return _fail("WE-2a", false, h_pending)
		var r2: Dictionary = backend.rename_replace(bak_tmp_path, bak_path, h_bak)
		if r2["state_after"] != StorageBackend.STATE_REPLACED:
			backend.delete(bak_tmp_path)
			backend.delete(tmp_path)
			if r2["state_after"] == StorageBackend.STATE_UNCHANGED:
				return _fail("WE-2b-v" if r2["primitive_result"] == "ok" else "WE-2b", false, h_pending)
			return _fail("WE-2b-p" if r2["operation_effect"] == "none" else "WE-2b-i", true, h_pending)
	elif rotate and backend.exists(main_path) == StorageBackend.UNKNOWN:
		backend.delete(tmp_path)
		return _fail("WE-2a-read", true, h_pending)

	# --- step 3 (commit point)
	var r3: Dictionary = backend.rename_replace(tmp_path, main_path, h_pending)
	if r3["state_after"] != StorageBackend.STATE_REPLACED:
		backend.delete(tmp_path)
		if r3["state_after"] == StorageBackend.STATE_UNCHANGED:
			if r3["err"] == "replace_not_atomic":
				backend.diag("storage_capability_unavailable")
				return _fail("WE-R", false, h_pending)
			return _fail("WE-3v" if r3["primitive_result"] == "ok" else "WE-3", false, h_pending)
		return _fail("WE-3p" if r3["operation_effect"] == "none" else "WE-3i", true, h_pending)

	# --- committed
	h_commit = h_pending
	needs_reconcile = false
	k_failures = 0
	save_blocked = false
	var level: String = backend.capabilities()["file_sync"]["value"]
	var ds: String = backend.sync_dir(main_path.get_base_dir())
	if ds != "durable":
		level = "written"
	backend.diag("commit level=%s dir_sync=%s%s" % [level, ds, " (WE-3r)" if r3["primitive_result"] == "error" else ""])
	_dispatch_bytes(b_new)
	return {"committed": true, "row": "WE-3r" if r3["primitive_result"] == "error" else "", "level": level,
		"dir_sync": ds}


# Step R. Returns "R12", "R0" or "R3".
func _reconcile() -> String:
	var ex: int = backend.exists(main_path)
	if ex == StorageBackend.ABSENT:
		return "R0" if h_commit == "" else "R3"
	if ex == StorageBackend.UNKNOWN:
		return "R3"
	var rd: Dictionary = backend.read_file(main_path)
	if not rd["ok"]:
		return "R3"
	var h_disk := StorageBackend.sha256(rd["bytes"])
	if h_disk == _h_prev_pending or (h_commit != "" and h_disk == h_commit):
		if h_disk == _h_prev_pending:
			backend.diag("commit_reconciled")
		h_commit = h_disk
		# Only the outbox parsed from B_disk is dispatched; memory-only entries wait for a real commit.
		_dispatch_bytes(rd["bytes"])
		return "R12"
	backend.diag("reconcile_unknown_main")
	return "R3"


func _dispatch_bytes(bytes: PackedByteArray) -> void:
	if not on_committed_outbox.is_valid():
		return
	var d = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(d) == TYPE_DICTIONARY and typeof(d.get("outbox")) == TYPE_ARRAY:
		on_committed_outbox.call(d["outbox"])


func _fail(row: String, set_reconcile: bool, h_pending: String) -> Dictionary:
	if set_reconcile:
		needs_reconcile = true
	_h_prev_pending = h_pending
	k_failures += 1
	if k_failures >= Config.SAVE_BLOCK_AFTER_FAILURES:
		save_blocked = true
	backend.diag("commit_attempt failed row=%s" % row)
	return {"committed": false, "row": row, "level": "", "dir_sync": ""}
