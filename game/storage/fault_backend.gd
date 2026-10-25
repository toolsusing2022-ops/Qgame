# FaultInjectingBackend (GS-12.8, build-test only): an in-memory backend with injectable failures and crash points
# (WK / WE / EA / ES / AK in the spec) and an access log, so tests can assert "this file was never touched".
#
# Rules are matched on (op, path suffix). Ops: exists, read, write, append, rename, delete, sync_file, sync_dir.
#   fail(op, suffix, times)        -> the primitive reports failure without effect
#   fail_after_effect("rename", s) -> the rename happens but is reported as failed (WE-3r)
#   noop_ok("rename", s)           -> the rename reports success but does nothing (V-u)
#   crash_before(op, suffix, nth)  -> the process "dies" before the nth matching op: image is captured and every
#                                     later operation fails. A new process continues from crash_image.
extends "res://game/storage/memory_backend.gd"

var access_log: PackedStringArray = []
var crash_image := {}
var dead := false

var _rules: Array = []           # {op, suffix, kind, times}
var _crash: Dictionary = {}      # {op, suffix, nth, seen}


func fail(op: String, suffix: String, times := -1, skip := 0) -> void:
	_rules.append({"op": op, "suffix": suffix, "kind": "fail", "times": times, "skip": skip})


# Like fail(), but matches any path containing the fragment (e.g. archive names with a timestamp).
func fail_containing(op: String, fragment: String, times := -1) -> void:
	_rules.append({"op": op, "suffix": fragment, "kind": "fail", "times": times, "contains": true})


func fail_after_effect(op: String, suffix: String, times := 1) -> void:
	_rules.append({"op": op, "suffix": suffix, "kind": "after_effect", "times": times})


func noop_ok(op: String, suffix: String, times := 1) -> void:
	_rules.append({"op": op, "suffix": suffix, "kind": "noop_ok", "times": times})


func clear_rules() -> void:
	_rules.clear()


func crash_before(op: String, suffix: String, nth := 1) -> void:
	_crash = {"op": op, "suffix": suffix, "nth": nth, "seen": 0}


func touched(suffix: String, ops := ["write", "append", "rename", "delete"]) -> bool:
	for line in access_log:
		var parts := line.split(" ", false, 1)
		if parts.size() == 2 and parts[0] in ops and parts[1].ends_with(suffix):
			return true
	return false


func count(op: String, suffix: String) -> int:
	var n := 0
	for line in access_log:
		var parts := line.split(" ", false, 1)
		if parts.size() == 2 and parts[0] == op and parts[1].ends_with(suffix):
			n += 1
	return n


# Returns "" (no fault), "dead", or the rule kind.
func _check(op: String, path: String) -> String:
	if dead:
		return "dead"
	if not _crash.is_empty() and op == _crash["op"] and path.ends_with(_crash["suffix"]):
		_crash["seen"] += 1
		if _crash["seen"] == _crash["nth"]:
			crash_image = image()
			dead = true
			return "dead"
	access_log.append("%s %s" % [op, path])
	for r in _rules:
		var hit: bool = path.contains(r["suffix"]) if r.get("contains", false) else path.ends_with(r["suffix"])
		if r["op"] == op and hit and r.get("skip", 0) > 0:
			r["skip"] -= 1
			continue
		if r["op"] == op and hit and r["times"] != 0:
			if r["times"] > 0:
				r["times"] -= 1
			return r["kind"]
	return ""


func _p_exists(path: String) -> int:
	match _check("exists", path):
		"dead", "fail":
			return UNKNOWN
	return super._p_exists(path)


func _p_read(path: String) -> Dictionary:
	match _check("read", path):
		"dead", "fail":
			return {"ok": false, "bytes": PackedByteArray()}
	return super._p_read(path)


func _p_write(path: String, bytes: PackedByteArray) -> bool:
	match _check("write", path):
		"dead":
			return false
		"fail":
			# A failed write may leave a partial file behind (WE-1a).
			files[path] = bytes.slice(0, bytes.size() / 2)
			return false
	return super._p_write(path, bytes)


func _p_append(path: String, bytes: PackedByteArray) -> bool:
	match _check("append", path):
		"dead":
			return false
		"fail":
			# Partial line without newline (EA / torn tail).
			var cur: PackedByteArray = files.get(path, PackedByteArray())
			cur.append_array(bytes.slice(0, maxi(1, bytes.size() / 2)))
			files[path] = cur
			return false
	return super._p_append(path, bytes)


func _p_rename(src: String, dst: String) -> bool:
	match _check("rename", path_pair(src, dst)):
		"dead", "fail":
			return false
		"after_effect":
			super._p_rename(src, dst)
			return false
		"noop_ok":
			return true
	return super._p_rename(src, dst)


func _p_delete(path: String) -> bool:
	match _check("delete", path):
		"dead", "fail":
			return false
	return super._p_delete(path)


func _p_sync_file(path: String) -> String:
	match _check("sync_file", path):
		"dead", "fail":
			return "failed"
	return super._p_sync_file(path)


func _p_sync_dir(dir: String) -> String:
	match _check("sync_dir", dir):
		"dead", "fail":
			return "failed"
	return super._p_sync_dir(dir)


# Rename rules match on the destination path.
static func path_pair(_src: String, dst: String) -> String:
	return dst
