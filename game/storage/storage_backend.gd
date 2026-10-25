# StorageBackend contract (gameplay spec GS-12.8, v0.4.4 .. v0.4.9).
#
# Gameplay, restore and the event dispatcher never call FileAccess/DirAccess directly; everything goes through a
# backend (TC-12.23). Subclasses implement the primitives (_p_*); the rename contract with pre/post checks and
# state_after classification lives here once, so every backend classifies results the same way.
#
# Levels used in results: "written" (handed to the OS) and "durable" (only with verified evidence). No backend in
# this repo reaches "durable"; capabilities() reports what the backend can actually claim (GS-12.9).
extends RefCounted

const EXISTS := 1
const ABSENT := 0
const UNKNOWN := -1

const STATE_REPLACED := "replaced"
const STATE_UNCHANGED := "unchanged"
const STATE_INDETERMINATE := "indeterminate"

# Diagnostics log (GS-12.11 commit log, rename_contract_violation, ...). Tests inspect it.
var log_lines: PackedStringArray = []


func capabilities() -> Dictionary:
	return {
		"file_sync": {"value": "written", "evidence": "assumed"},
		"dir_sync": {"value": "unsupported", "evidence": "assumed"},
		"atomic_replace": {"value": "available", "evidence": "assumed"},
		"noreplace": {"value": "check_then_rename", "evidence": "assumed"},
	}


func diag(line: String) -> void:
	log_lines.append(line)


# --- primitives (override) -----------------------------------------------------------------------------------

func _p_exists(_path: String) -> int:
	return UNKNOWN

func _p_is_dir(_path: String) -> bool:
	return false

func _p_read(_path: String) -> Dictionary:          # {ok, bytes}
	return {"ok": false, "bytes": PackedByteArray()}

func _p_write(_path: String, _bytes: PackedByteArray) -> bool:   # truncate + write + flush + close, all checked
	return false

func _p_append(_path: String, _bytes: PackedByteArray) -> bool:
	return false

func _p_rename(_src: String, _dst: String) -> bool:   # raw primitive, may replace dst
	return false

func _p_delete(_path: String) -> bool:
	return false

func _p_list(_dir: String) -> Dictionary:           # {ok, names}
	return {"ok": false, "names": PackedStringArray()}

func _p_sync_file(_path: String) -> String:          # "written" | "durable" | "failed"
	return "failed"

func _p_sync_dir(_dir: String) -> String:            # "durable" | "unsupported" | "failed"
	return "unsupported"


# --- public operations ---------------------------------------------------------------------------------------

func exists(path: String) -> int:
	return _p_exists(path)


func read_file(path: String) -> Dictionary:
	return _p_read(path)


# write_file: truncate, write, flush, sync_file at backend level, close (GS-12.8).
func write_file(path: String, bytes: PackedByteArray, verify := false) -> Dictionary:
	if not _p_write(path, bytes):
		return {"ok": false, "err": "io_failed"}
	var level := _p_sync_file(path)
	if level == "failed":
		return {"ok": false, "err": "sync_failed"}
	if verify:
		var r := _p_read(path)
		if not r["ok"] or r["bytes"] != bytes:
			return {"ok": false, "err": "verify_failed"}
	return {"ok": true, "level": level}


func append_line(path: String, bytes: PackedByteArray) -> bool:
	return _p_append(path, bytes)


func sync_file(path: String) -> String:
	return _p_sync_file(path)


func sync_dir(dir: String) -> String:
	return _p_sync_dir(dir)


func delete(path: String) -> bool:
	return _p_delete(path)


func list_dir(dir: String) -> Dictionary:
	return _p_list(dir)


static func sha256(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


# rename_replace (GS-12.8): result {ok, err, operation_effect, primitive_result, postcheck, state_after}.
func rename_replace(src: String, dst: String, expected_src_hash: String) -> Dictionary:
	return _rename(src, dst, expected_src_hash, true)


# rename_noreplace: never overwrites an existing destination.
func rename_noreplace(src: String, dst: String, expected_src_hash: String) -> Dictionary:
	return _rename(src, dst, expected_src_hash, false)


func _rename(src: String, dst: String, expected: String, replace: bool) -> Dictionary:
	var res := {"ok": false, "err": "", "operation_effect": "none", "primitive_result": "not_called",
		"postcheck": "not_run", "state_after": STATE_INDETERMINATE}
	# 1. Pre-check: read src (hash must match) and determine dst presence; read dst content when possible.
	var src_state := _p_exists(src)
	if src_state == UNKNOWN:
		res["err"] = "precheck_failed"
		return res
	if src_state == ABSENT:
		res["err"] = "src_missing"           # indeterminate: `unchanged` needs src present (v0.4.7 P1-1)
		return res
	var src_read := _p_read(src)
	if not src_read["ok"] or sha256(src_read["bytes"]) != expected:
		res["err"] = "precheck_failed"
		return res
	var dst_state := _p_exists(dst)
	if dst_state == UNKNOWN:
		res["err"] = "precheck_failed"
		return res
	var pre_dst := "absent"
	if dst_state == EXISTS:
		if _p_is_dir(dst):
			res["err"] = "dst_is_dir"
			res["state_after"] = STATE_UNCHANGED
			return res
		var dst_read := _p_read(dst)
		pre_dst = sha256(dst_read["bytes"]) if dst_read["ok"] else "unreadable"
	# 2. Capability / noreplace decision, after the reads so `unchanged` has evidence.
	if replace and capabilities()["atomic_replace"]["value"] == "unavailable":
		res["err"] = "replace_not_atomic"
		res["state_after"] = STATE_UNCHANGED if pre_dst != "unreadable" else STATE_INDETERMINATE
		return res
	if not replace and dst_state == EXISTS:
		res["err"] = "dst_exists"
		res["state_after"] = STATE_UNCHANGED
		return res
	# 3. Primitive.
	res["operation_effect"] = "attempted"
	var prim_ok := _p_rename(src, dst)
	res["primitive_result"] = "ok" if prim_ok else "error"
	# 4. Post-check (always).
	var src_after := _p_exists(src)
	var dst_after := _p_exists(dst)
	if src_after == UNKNOWN or dst_after == UNKNOWN:
		res["postcheck"] = "failed"
		res["err"] = "postcheck_failed"
		return res
	var dst_hash := ""
	if dst_after == EXISTS:
		var d := _p_read(dst)
		if not d["ok"]:
			res["postcheck"] = "failed"
			res["err"] = "postcheck_failed"
			return res
		dst_hash = sha256(d["bytes"])
	var src_hash := ""
	if src_after == EXISTS:
		var s := _p_read(src)
		if not s["ok"]:
			res["postcheck"] = "failed"
			res["err"] = "postcheck_failed"
			return res
		src_hash = sha256(s["bytes"])
	res["postcheck"] = "ok"
	if src_after == ABSENT and dst_after == EXISTS and dst_hash == expected:
		res["state_after"] = STATE_REPLACED
	elif src_after == EXISTS and src_hash == expected and pre_dst != "unreadable" \
			and ((pre_dst == "absent" and dst_after == ABSENT) or (pre_dst != "absent" and dst_hash == pre_dst)):
		res["state_after"] = STATE_UNCHANGED
	else:
		res["state_after"] = STATE_INDETERMINATE
	res["ok"] = res["state_after"] == STATE_REPLACED
	if prim_ok and not res["ok"]:
		res["err"] = "reported_ok_but_unchanged" if res["state_after"] == STATE_UNCHANGED \
			else "reported_ok_but_inconsistent"
		diag("rename_contract_violation op=%s dst=%s state=%s" % ["replace" if replace else "noreplace",
			dst.get_file(), res["state_after"]])
	elif not prim_ok and res["ok"]:
		diag("rename_failed_but_replaced dst=%s" % dst.get_file())
	elif not prim_ok:
		res["err"] = "io_failed"
	return res
