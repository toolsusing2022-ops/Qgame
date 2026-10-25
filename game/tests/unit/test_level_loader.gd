# Section 2: level data (TC-2.1 .. TC-2.11).
extends "res://game/tests/test_case.gd"

const LevelLoader := preload("res://game/core/level_loader.gd")

const F1 := '{"schema_version":1,"id":"fixture_f1","title":"F1","difficulty":"easy","modes":["journey","zen"],"width":3,"height":2,"palette":[{"id":0,"hex":"#2f86b8","count":2},{"id":1,"hex":"#e2553d","count":2},{"id":2,"hex":"#f3dcd2","count":1}],"cells":[0,1,2,-1,0,1]}'


func _parse(text: String) -> Dictionary:
	return LevelLoader.parse_text(text)


func _f1_with(path: Array, value: Variant) -> String:
	var d: Dictionary = JSON.parse_string(F1)
	var node: Variant = d
	for k in path.slice(0, path.size() - 1):
		node = node[k]
	node[path[path.size() - 1]] = value
	return JSON.stringify(d)


func test_tc_2_1_load_f1_counts_remaining() -> void:
	var r := _parse(F1)
	assert_true(r["ok"], str(r["errors"]))
	var level = r["level"]
	assert_eq(level.width, 3)
	assert_eq(level.height, 2)
	assert_eq(level.cells, PackedInt32Array([0, 1, 2, -1, 0, 1]))
	assert_eq(level.counts, PackedInt32Array([2, 2, 1]))
	assert_eq(level.hexes, PackedStringArray(["#2f86b8", "#e2553d", "#f3dcd2"]))
	assert_eq(typeof(level.cells[0]), TYPE_INT)


func test_tc_2_3_integer_valued_float_accepted_fraction_rejected() -> void:
	assert_true(_parse(_f1_with(["width"], 3.0))["ok"], "3.0 accepted (GS-2.2)")
	var r := _parse(F1.replace("[0,1,2,-1,0,1]", "[0,1,2,-1,0,1.5]"))
	assert_false(r["ok"])
	assert_eq(r["errors"], PackedStringArray(["bad_cell_value"]))


func test_tc_2_10_shared_fixtures_match_python_manifest() -> void:
	var dir := repo_path("tests/fixtures/levels")
	var manifest_text := FileAccess.get_file_as_string(dir.path_join("expected_errors.json"))
	var manifest: Dictionary = JSON.parse_string(manifest_text)
	assert_true(manifest.size() >= 10, "manifest has fixtures")
	for name in manifest:
		var r := LevelLoader.load_file(dir.path_join(name))
		assert_eq(r["errors"], PackedStringArray(manifest[name]), name)
		assert_eq(r["ok"], (manifest[name] as Array).is_empty(), name)


func test_tc_2_2_rejects_without_partial_level() -> void:
	for text in ["[]", "not json", '{"schema_version":1}']:
		var r := _parse(text)
		assert_false(r["ok"], text)
		assert_eq(r["level"], null, text)


func test_legacy_format_rejected() -> void:
	var r := _parse('{"cols":2,"rows":1,"cells":[[0,0]]}')
	assert_true("legacy_format" in r["errors"])


func test_tc_2_11_internal_levels_load() -> void:
	for rel in ["content/levels/squid_relax_01.json", "content/trials/squid_easy_01.json"]:
		var r := LevelLoader.load_file(repo_path(rel))
		assert_true(r["ok"], "%s %s" % [rel, r["errors"]])
