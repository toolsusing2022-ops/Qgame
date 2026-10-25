# GS-12.8 rename contract on the fault-injecting model backend (logic simulation, not storage evidence).
extends "res://game/tests/test_case.gd"

const Fault := preload("res://game/storage/fault_backend.gd")
const SB := preload("res://game/storage/storage_backend.gd")

const SRC := "mem/p/L.json.tmp"
const DST := "mem/p/L.json"


func _fs(src := "new", dst: Variant = "old"):
	var fs = Fault.new()
	fs.files[SRC] = String(src).to_utf8_buffer()
	if dst != null:
		fs.files[DST] = String(dst).to_utf8_buffer()
	return fs


func _h(s: String) -> String:
	return SB.sha256(s.to_utf8_buffer())


func _consistent(fs, r: Dictionary, old: Variant) -> bool:
	# Two-way consistency (v0.4.7 P1-4): replaced <=> dst new and src gone; unchanged <=> dst old and src present.
	var dst_bytes = fs.files.get(DST)
	if r["state_after"] == SB.STATE_REPLACED:
		return not fs.files.has(SRC) and dst_bytes == "new".to_utf8_buffer()
	if r["state_after"] == SB.STATE_UNCHANGED:
		var dst_ok: bool = (old == null and dst_bytes == null) or (old != null and dst_bytes == String(old).to_utf8_buffer())
		return fs.files.has(SRC) and dst_ok
	return true


func test_tc_12_38_a_replace_existing_destination() -> void:
	var fs = _fs()
	var r: Dictionary = fs.rename_replace(SRC, DST, _h("new"))
	assert_eq(r["state_after"], SB.STATE_REPLACED)
	assert_true(r["ok"])
	assert_true(_consistent(fs, r, "old"))


func test_tc_12_38_b_destination_absent() -> void:
	var fs = _fs("new", null)
	var r: Dictionary = fs.rename_replace(SRC, DST, _h("new"))
	assert_eq(r["state_after"], SB.STATE_REPLACED)


func test_tc_12_38_c_source_missing_is_indeterminate() -> void:
	var fs = _fs()
	fs.files.erase(SRC)
	var r: Dictionary = fs.rename_replace(SRC, DST, _h("new"))
	assert_eq(r["err"], "src_missing")
	assert_eq(r["operation_effect"], "none")
	assert_eq(r["state_after"], SB.STATE_INDETERMINATE)


func test_tc_12_38_d_destination_is_directory() -> void:
	var fs = _fs("new", null)
	fs.dirs[DST] = true
	var r: Dictionary = fs.rename_replace(SRC, DST, _h("new"))
	assert_eq(r["err"], "dst_is_dir")
	assert_eq(r["state_after"], SB.STATE_UNCHANGED)
	assert_eq(fs.count("rename", DST), 0, "primitive not called")


func test_tc_12_41_same_content_decided_by_source_presence() -> void:
	var fs = _fs("same", "same")
	fs.fail("rename", "L.json")
	var r: Dictionary = fs.rename_replace(SRC, DST, _h("same"))
	assert_eq(r["state_after"], SB.STATE_UNCHANGED, "src still present -> unchanged, not replaced")


func test_tc_12_38_f_error_before_effect() -> void:
	var fs = _fs()
	fs.fail("rename", "L.json")
	var r: Dictionary = fs.rename_replace(SRC, DST, _h("new"))
	assert_eq(r["primitive_result"], "error")
	assert_eq(r["state_after"], SB.STATE_UNCHANGED)
	assert_true(_consistent(fs, r, "old"))


func test_tc_12_33_error_after_effect_is_replaced() -> void:
	var fs = _fs()
	fs.fail_after_effect("rename", "L.json")
	var r: Dictionary = fs.rename_replace(SRC, DST, _h("new"))
	assert_eq(r["state_after"], SB.STATE_REPLACED)
	assert_true(r["ok"])
	assert_true("rename_failed_but_replaced" in "\n".join(fs.log_lines))


func test_tc_12_38_h_postcheck_failure_is_indeterminate() -> void:
	var fs = _fs()
	fs.fail("rename", "L.json")
	fs.fail("exists", "L.json", -1)
	var r: Dictionary = fs.rename_replace(SRC, DST, _h("new"))
	# exists() on DST fails already in the pre-check.
	assert_eq(r["state_after"], SB.STATE_INDETERMINATE)
	var fs2 = _fs()
	fs2.fail_after_effect("rename", "L.json")
	fs2.fail("read", "L.json", -1)
	var r2: Dictionary = fs2.rename_replace(SRC, DST, _h("new"))
	assert_eq(r2["state_after"], SB.STATE_INDETERMINATE)


func test_tc_12_40_precheck_failure_never_unchanged() -> void:
	var fs = _fs()
	fs.fail("read", "L.json.tmp")
	var r: Dictionary = fs.rename_replace(SRC, DST, _h("new"))
	assert_eq(r["err"], "precheck_failed")
	assert_eq(r["operation_effect"], "none")
	assert_eq(r["state_after"], SB.STATE_INDETERMINATE)
	assert_eq(fs.count("rename", DST), 0)


func test_tc_12_38_l_and_12_54_reported_ok_but_nothing_happened() -> void:
	var fs = _fs()
	fs.noop_ok("rename", "L.json")
	var r: Dictionary = fs.rename_replace(SRC, DST, _h("new"))
	assert_eq(r["state_after"], SB.STATE_UNCHANGED)
	assert_eq(r["err"], "reported_ok_but_unchanged")
	assert_false(r["ok"])
	assert_true("rename_contract_violation" in "\n".join(fs.log_lines))


func test_tc_12_38_m_unreadable_destination_still_replaced() -> void:
	var fs = _fs()
	fs.fail("read", "L.json", 1)       # first read of DST (pre-check) fails
	var r: Dictionary = fs.rename_replace(SRC, DST, _h("new"))
	assert_eq(r["state_after"], SB.STATE_REPLACED)
	var fs2 = _fs()
	fs2.fail("read", "L.json", 1)
	fs2.fail("rename", "L.json")
	var r2: Dictionary = fs2.rename_replace(SRC, DST, _h("new"))
	assert_eq(r2["state_after"], SB.STATE_INDETERMINATE, "pre_dst unreadable: never unchanged")


func test_tc_12_59_noreplace_never_overwrites() -> void:
	var fs = _fs()
	var r: Dictionary = fs.rename_noreplace(SRC, DST, _h("new"))
	assert_eq(r["err"], "dst_exists")
	assert_eq(r["state_after"], SB.STATE_UNCHANGED)
	assert_eq(fs.files[DST], "old".to_utf8_buffer())
	var fs2 = _fs()
	fs2.fail("read", "L.json", 1)
	var r2: Dictionary = fs2.rename_noreplace(SRC, DST, _h("new"))
	assert_eq(r2["err"], "dst_exists", "unreadable destination is still never overwritten")
	assert_eq(fs2.count("rename", DST), 0)


func test_tc_12_35_replace_not_atomic() -> void:
	var fs = _fs()
	var caps_backend = AtomicUnavailable.new()
	caps_backend.files = fs.files
	var r: Dictionary = caps_backend.rename_replace(SRC, DST, _h("new"))
	assert_eq(r["err"], "replace_not_atomic")
	assert_eq(r["state_after"], SB.STATE_UNCHANGED)
	assert_eq(caps_backend.files[DST], "old".to_utf8_buffer())


class AtomicUnavailable extends "res://game/storage/memory_backend.gd":
	func capabilities() -> Dictionary:
		var c := super.capabilities()
		c["atomic_replace"] = {"value": "unavailable", "evidence": "assumed"}
		return c
