# Minimal test base for the headless runner (game/tests/run_unit.gd). Test scripts extend this file and define
# methods named test_*. Each failure is recorded; the runner reports them and sets the exit code.
extends RefCounted

var failures: PackedStringArray = []


func assert_true(cond: bool, msg := "") -> void:
	if not cond:
		failures.append("expected true" + (": " + msg if msg != "" else ""))


func assert_false(cond: bool, msg := "") -> void:
	if cond:
		failures.append("expected false" + (": " + msg if msg != "" else ""))


func assert_eq(actual: Variant, expected: Variant, msg := "") -> void:
	if not _equal(actual, expected):
		failures.append("expected %s, got %s%s" % [var_to_str(expected), var_to_str(actual),
			(": " + msg) if msg != "" else ""])


func fail(msg: String) -> void:
	failures.append(msg)


func repo_path(rel: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(rel)


const _PACKED := [TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_BYTE_ARRAY]
const _NUMERIC := [TYPE_INT, TYPE_FLOAT]


func _equal(a: Variant, b: Variant) -> bool:
	if typeof(a) in _PACKED or typeof(b) in _PACKED:
		return Array(a) == Array(b)
	if typeof(a) in _NUMERIC and typeof(b) in _NUMERIC:
		return a == b
	return typeof(a) == typeof(b) and a == b
