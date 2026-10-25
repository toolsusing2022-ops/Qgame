# One level session: restore, outbox of durable events, coalesced saving and event dispatch
# (gameplay spec GS-4.5, 12.1, 13.4 E3, 14.3, 14.4).
extends RefCounted

const Config := preload("res://game/core/config.gd")
const BoardState := preload("res://game/core/board_state.gd")
const Codec := preload("res://game/save/progress_codec.gd")
const Restore := preload("res://game/save/restore.gd")
const ProgressWriter := preload("res://game/save/progress_writer.gd")
const LevelHash := preload("res://game/core/level_hash.gd")

var backend
var dispatcher
var level
var catalog_entry: Dictionary
var progress_dir: String
var install_id: String
var mode := "zen"

var board
var writer
var outbox: Array = []            # in-memory outbox (committed + not yet committed entries)
var restore_result: Dictionary = {}
var dirty := false
var opened := false

var _layout_hash := ""
var _content_hash := ""
var _last_place_ms := -1
var _clock := Callable(Time, "get_ticks_msec")


func _init(storage_backend, event_dispatcher, lvl, entry: Dictionary, dir: String, inst_id: String) -> void:
	backend = storage_backend
	dispatcher = event_dispatcher
	level = lvl
	catalog_entry = entry
	progress_dir = dir
	install_id = inst_id
	_layout_hash = LevelHash.layout_hash(level)
	_content_hash = LevelHash.content_hash(level)


func set_clock(clock: Callable) -> void:
	_clock = clock


# Returns the restore result. When outcome is archive_failed the level must not be opened.
func open() -> Dictionary:
	var now: int = _clock.call()
	restore_result = Restore.run({"backend": backend, "dispatcher": dispatcher, "level": level,
		"catalog_entry": catalog_entry, "progress_dir": progress_dir, "now_ms": now})
	if restore_result["outcome"] == "archive_failed":
		return restore_result
	board = restore_result["board"]
	board.enter_level()
	outbox = (restore_result["restore_outbox"] as Array).duplicate(true)
	writer = ProgressWriter.new(backend, progress_dir, level.id)
	writer.h_commit = restore_result["h_commit"]
	writer.needs_reconcile = restore_result["needs_reconcile"]
	writer.on_committed_outbox = _on_committed_outbox
	opened = true
	# E3.4: dispatch the restored source's outbox (E_read), then write when required.
	_on_committed_outbox(restore_result["restore_outbox"], "startup")
	if restore_result["needs_write"]:
		dirty = true
		flush(true)
	record_best_effort("restore_result", {"source": restore_result["source"],
		"candidates": restore_result["candidates"], "outcome": restore_result["outcome"],
		"archived": restore_result["archived"], "bak_notice": restore_result["bak_notice"]})
	record_best_effort("level_start", {"level_id": level.id, "mode": mode,
		"restore_result": restore_result["outcome"]})
	return restore_result


# --- durable events (outbox, GS-14.3) -----------------------------------------------------------------------

func on_tap_result(r: Dictionary) -> void:
	if r.get("kind", "") != BoardState.TAP_PLACED:
		return
	var now: int = _clock.call()
	_add("bead_placed", {"cell": r["cell"], "color": r["color"],
		"ms_since_prev": now - _last_place_ms if _last_place_ms >= 0 else -1})
	_last_place_ms = now
	if r["color_completed"]:
		_add("color_complete", {"color": r["color"], "occurrence": r["occurrence"]})
	if r["level_completed"]:
		# GS-14.7: deterministic id is the second line of defence against duplicates.
		_add("level_complete", {"level_id": level.id, "mode": mode}, "lc:%s:%s" % [install_id, level.id])
	request_save()


func on_undo_result(r: Dictionary) -> void:
	if not r.get("ok", false):
		return
	var now: int = _clock.call()
	_add("undo_used", {"cell": r["cell"], "color": r["color"],
		"ms_since_place": now - _last_place_ms if _last_place_ms >= 0 else -1})
	request_save()


func record_best_effort(type: String, payload: Dictionary) -> void:
	dispatcher.record_best_effort({"event_id": new_uuid(), "type": type, "payload": payload,
		"ts": _clock.call()})


func _add(type: String, payload: Dictionary, event_id := "") -> void:
	outbox.append({"event_id": event_id if event_id != "" else new_uuid(), "type": type, "payload": payload,
		"ts": _clock.call()})


# --- saving (GS-12.1) ---------------------------------------------------------------------------------------

func request_save() -> void:
	dirty = true


# Writes at most once per call. forced = app going to background / leaving the level.
func flush(forced := false) -> Dictionary:
	if not opened or not dirty:
		return {}
	var now: int = _clock.call()
	if not writer.may_attempt(now, forced):
		return {}
	var bytes := Codec.encode(level, board, int(catalog_entry.get("content_version", 1)), _layout_hash,
		_content_hash, outbox)
	var res: Dictionary = writer.write(bytes, now)
	if res["committed"]:
		dirty = false
	return res


func is_save_blocked() -> bool:
	return writer != null and writer.save_blocked


func _on_committed_outbox(entries: Array, context := "commit") -> void:
	if entries.is_empty():
		return
	dispatcher.dispatch(entries, context, _clock.call())
	# Confirmed entries leave the in-memory outbox; the file drops them with the next commit (GS-14.4).
	var kept := []
	for e in outbox:
		if not dispatcher.is_confirmed(e["event_id"]):
			kept.append(e)
	outbox = kept


static func new_uuid() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]
