# GS-13.1 / 13.2: canonical hashes (TC-13.1 .. TC-13.3).
extends "res://game/tests/test_case.gd"

const LevelLoader := preload("res://game/core/level_loader.gd")
const LevelHash := preload("res://game/core/level_hash.gd")


func _level(rel: String):
	var r := LevelLoader.load_file(repo_path(rel))
	assert_true(r["ok"], "%s %s" % [rel, r["errors"]])
	return r["level"]


func test_tc_13_1_reference_values() -> void:
	var f1 = _level("tests/fixtures/levels/F1.json")
	assert_eq(LevelHash.layout_hash(f1), "b09305c9fea477ff6a5ba10b4f13a255ab9892d484f27d7b40d1bf9f3910f8aa")
	assert_eq(LevelHash.content_hash(f1), "dc70ea18d4a5edfd1dcf79ac21a466ca6b417ddc8b6b97ebcdd453542e0c7a14")
	var f9 = _level("tests/fixtures/levels/F9_hex_changed.json")
	assert_eq(LevelHash.layout_hash(f9), "b09305c9fea477ff6a5ba10b4f13a255ab9892d484f27d7b40d1bf9f3910f8aa")
	assert_eq(LevelHash.content_hash(f9), "5206fe955572afbe7e8fed4d516fc98aa36c5bce1df98c6eaf4a29c8ea9a38ca")
	var f10 = _level("tests/fixtures/levels/F10_layout_changed.json")
	assert_eq(LevelHash.layout_hash(f10), "910660ec8fccc6ff44459b418df8e86c241d31aee0e8f36db33b5195cd9cc4c8")
	assert_eq(LevelHash.content_hash(f10), "24c69fac36cfbf754ad12182b949bfca8c00c3568386c0f231aee71c25db0581")


func test_tc_13_2_internal_levels_match_python_catalog() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(repo_path("content/catalog.json")))
	assert_eq((catalog["levels"] as Array).size(), 2)
	for entry in catalog["levels"]:
		var level = _level("content".path_join(entry["file"]))
		assert_eq(level.id, entry["level_id"])
		assert_eq(LevelHash.layout_hash(level), entry["layout_hash"], entry["level_id"])
		assert_eq(LevelHash.content_hash(level), entry["content_hash"], entry["level_id"])


func test_tc_13_3_key_order_and_hex_case() -> void:
	var text := '{"cells":[0,1,2,-1,0,1],"palette":[{"count":2,"hex":"#2F86B8","id":0},{"hex":"#E2553D","id":1,"count":2},{"id":2,"count":1,"hex":"#f3dcd2"}],"height":2,"width":3,"modes":["zen"],"difficulty":"relax","title":"x","id":"other","schema_version":1}'
	var r := LevelLoader.parse_text(text)
	assert_true(r["ok"], str(r["errors"]))
	assert_eq(LevelHash.content_hash(r["level"]), "dc70ea18d4a5edfd1dcf79ac21a466ca6b417ddc8b6b97ebcdd453542e0c7a14")
