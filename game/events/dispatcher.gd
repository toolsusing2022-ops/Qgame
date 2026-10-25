# Event dispatcher (gameplay spec GS-14.4 as of v0.4.7/v0.4.8).
#
# - Sources are outbox lists parsed from committed bytes only (B_new of a replaced write, B_disk in step R12,
#   E_read of a restored or archived candidate). Never the in-memory outbox.
# - An entry is skipped only if its event_id is in confirmed_ids (this session). Presence of a line in the file
#   is never enough; after a restart everything still in a source is appended again (duplicates are fine,
#   GS-14.5 dedupes logically).
# - A line becomes confirmed@<level> when a later sync succeeds. Lines appended before a failed sync are never
#   confirmed in this session; their entries are re-appended on the next attempt.
# - After a store failure, commit-triggered runs wait OUTBOX_RETRY_MIN_INTERVAL_S (startup/archive runs do not).
extends RefCounted

const Config := preload("res://game/core/config.gd")

var store
var confirmed_ids := {}
var confirmed_level := "written"
var last_failure_ms := -1
var retry_interval_ms := Config.OUTBOX_RETRY_MIN_INTERVAL_S * 1000

var _appended_since_sync: PackedStringArray = []


func _init(event_store) -> void:
	store = event_store


func is_confirmed(event_id: String) -> bool:
	return confirmed_ids.has(event_id)


func all_confirmed(entries: Array) -> bool:
	for e in entries:
		if not confirmed_ids.has(e["event_id"]):
			return false
	return true


func throttled(now_ms: int) -> bool:
	return last_failure_ms >= 0 and now_ms - last_failure_ms < retry_interval_ms


# context: "startup" | "archive" | "pending" | "commit". Returns {ok, all_confirmed, throttled}.
func dispatch(entries: Array, context: String, now_ms: int) -> Dictionary:
	if context == "commit" and throttled(now_ms):
		return {"ok": false, "all_confirmed": all_confirmed(entries), "throttled": true}
	for e in entries:
		var id: String = e["event_id"]
		if confirmed_ids.has(id) or _appended_since_sync.has(id):
			continue
		if not store.append(e):
			_poison(now_ms)
			return {"ok": false, "all_confirmed": false, "throttled": false}
		_appended_since_sync.append(id)
	if not _appended_since_sync.is_empty():
		var level: String = store.sync()
		if level == "failed":
			_poison(now_ms)
			return {"ok": false, "all_confirmed": false, "throttled": false}
		confirmed_level = level
		for id in _appended_since_sync:
			confirmed_ids[id] = true
		_appended_since_sync.clear()
		last_failure_ms = -1
	return {"ok": true, "all_confirmed": all_confirmed(entries), "throttled": false}


# Best-effort events (GS-14.1): appended directly, never retried, never confirmed.
func record_best_effort(entry: Dictionary) -> void:
	store.append(entry)


func _poison(now_ms: int) -> void:
	_appended_since_sync.clear()       # never confirmed in this session; re-appended next time
	last_failure_ms = now_ms
