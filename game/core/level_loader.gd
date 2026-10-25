# Level loader (gameplay spec GS-2). Mirrors the error checks of tools/validate_level.py so that both give the
# same accept/reject decision and the same error codes on the shared fixtures (GS-2.6, TC-2.10).
#
# Known divergences, both caused by Godot's JSON parser and both stricter on the Python side, which runs first
# in the content pipeline:
# - Godot parses every number as float, so "1" and "1.0" are indistinguishable here. 1.0 is accepted (GS-2.2),
#   while validate_level.py rejects it.
# - Duplicate JSON keys are rejected by validate_level.py; Godot keeps the last value.
extends RefCounted

const LevelData := preload("res://game/core/level_data.gd")

const SCHEMA_VERSION := 1
const MAX_SIDE := 128
const DIFFICULTIES := ["easy", "relax", "challenge"]
const MODES := ["journey", "zen"]
const REQUIRED_FIELDS := ["schema_version", "id", "title", "difficulty", "modes", "width", "height", "palette", "cells"]
const PALETTE_REQUIRED := ["id", "hex", "count"]


static func load_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _result(PackedStringArray(["invalid_json"]), null)
	var text := f.get_as_text()
	f.close()
	return parse_text(text)


# Returns {ok: bool, errors: PackedStringArray (sorted, unique), level: LevelData or null}.
static func parse_text(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return _result(PackedStringArray(["invalid_json"]), null)
	return validate(json.data)


static func validate(data: Variant) -> Dictionary:
	var errors := {}
	if typeof(data) != TYPE_DICTIONARY:
		errors["bad_type"] = true
		return _result(_codes(errors), null)
	var d: Dictionary = data

	if (d.has("cols") or d.has("rows")) and not d.has("width"):
		errors["legacy_format"] = true
	for k in REQUIRED_FIELDS:
		if not d.has(k):
			errors["missing_field"] = true

	# --- metadata
	if d.has("schema_version") and not (_is_int(d["schema_version"]) and int(d["schema_version"]) == SCHEMA_VERSION):
		errors["bad_schema_version"] = true
	if d.has("id") and not (typeof(d["id"]) == TYPE_STRING and _valid_id(d["id"])):
		errors["bad_id"] = true
	if d.has("title") and not (typeof(d["title"]) == TYPE_STRING and String(d["title"]).strip_edges() != ""):
		errors["bad_title"] = true
	if d.has("difficulty") and not (typeof(d["difficulty"]) == TYPE_STRING and d["difficulty"] in DIFFICULTIES):
		errors["bad_difficulty"] = true
	if d.has("modes"):
		var modes = d["modes"]
		if typeof(modes) != TYPE_ARRAY or modes.is_empty():
			errors["bad_modes"] = true
		else:
			var seen := {}
			for m in modes:
				if not (typeof(m) == TYPE_STRING and m in MODES):
					errors["bad_modes"] = true
				seen[str(m)] = true
			if seen.size() != modes.size():
				errors["bad_modes"] = true

	# --- grid size
	var size_ok := true
	for k in ["width", "height"]:
		if d.has(k):
			var v = d[k]
			if not (_is_int(v) and int(v) >= 1 and int(v) <= MAX_SIDE):
				errors["grid_size"] = true
				size_ok = false
		else:
			size_ok = false
	var total := int(d["width"]) * int(d["height"]) if size_ok else -1

	# --- palette
	var palette_ok := false
	var palette_hex := {}
	if d.has("palette"):
		var pal = d["palette"]
		if typeof(pal) != TYPE_ARRAY or pal.is_empty():
			errors["bad_palette"] = true
		else:
			palette_ok = true
			for i in pal.size():
				var entry = pal[i]
				if typeof(entry) != TYPE_DICTIONARY:
					errors["bad_palette"] = true
					palette_ok = false
					continue
				for k in PALETTE_REQUIRED:
					if not entry.has(k):
						errors["missing_field"] = true
						palette_ok = false
				if entry.has("id") and not (_is_int(entry["id"]) and int(entry["id"]) == i):
					errors["palette_id"] = true
					palette_ok = false
				if entry.has("hex"):
					if typeof(entry["hex"]) == TYPE_STRING and _valid_hex(entry["hex"]):
						palette_hex[i] = String(entry["hex"]).to_lower()
					else:
						errors["bad_hex"] = true
						palette_ok = false
				if entry.has("count") and not (_is_int(entry["count"]) and int(entry["count"]) >= 0):
					errors["bad_count"] = true
					palette_ok = false
			var ids := palette_hex.keys()
			ids.sort()
			for ai in ids.size():
				for bi in range(ai + 1, ids.size()):
					if palette_hex[ids[ai]] == palette_hex[ids[bi]]:
						errors["duplicate_color"] = true

	# --- cells
	var cells_ok := false
	var cells_int := PackedInt32Array()
	if d.has("cells"):
		var cells = d["cells"]
		if typeof(cells) != TYPE_ARRAY:
			errors["bad_cells"] = true
		elif not cells.is_empty() and _all_arrays(cells):
			errors["cells_not_flat"] = true
		elif total >= 0 and cells.size() != total:
			errors["grid_size"] = true
		elif total >= 0:
			var bad_value := false
			for v in cells:
				if not _is_int(v):
					bad_value = true
					break
			if bad_value:
				errors["bad_cell_value"] = true
			else:
				cells_ok = true
				cells_int.resize(cells.size())
				var all_empty := true
				for idx in cells.size():
					cells_int[idx] = int(cells[idx])
					if cells_int[idx] != LevelData.EMPTY_CELL:
						all_empty = false
				if all_empty:
					errors["no_playable_cells"] = true
				if palette_ok:
					for v in cells_int:
						if v != LevelData.EMPTY_CELL and not palette_hex.has(v):
							errors["unknown_color"] = true
							break

	var actual := {}
	if cells_ok and palette_ok:
		for i in palette_hex:
			actual[i] = 0
		for v in cells_int:
			if actual.has(v):
				actual[v] += 1
		var pal: Array = d["palette"]
		for i in pal.size():
			if int(actual.get(i, 0)) == 0:
				errors["unused_color"] = true
			elif int(pal[i]["count"]) != int(actual[i]):
				errors["count_mismatch"] = true

	# --- optional subject mask (gameplay ignores it, but it must be well formed)
	if d.has("mask"):
		var mask = d["mask"]
		if typeof(mask) != TYPE_ARRAY:
			errors["mask_type"] = true
		elif total >= 0 and mask.size() != total:
			errors["mask_size"] = true
		elif total >= 0:
			var bad_mask := false
			for v in mask:
				if not (_is_int(v) and (int(v) == 0 or int(v) == 1)):
					bad_mask = true
					break
			if bad_mask:
				errors["mask_value"] = true
			else:
				var any_set := false
				for v in mask:
					if int(v) == 1:
						any_set = true
						break
				if not any_set:
					errors["mask_empty"] = true
				if cells_ok:
					for idx in mask.size():
						if int(mask[idx]) == 1 and cells_int[idx] == LevelData.EMPTY_CELL:
							errors["mask_on_empty"] = true
							break

	if not errors.is_empty():
		return _result(_codes(errors), null)

	var level := LevelData.new()
	level.schema_version = int(d["schema_version"])
	level.id = d["id"]
	level.title = d["title"]
	level.difficulty = d["difficulty"]
	level.modes = PackedStringArray(d["modes"])
	level.width = int(d["width"])
	level.height = int(d["height"])
	var pal_arr: Array = d["palette"]
	level.hexes.resize(pal_arr.size())
	level.counts.resize(pal_arr.size())
	level.names.resize(pal_arr.size())
	for i in pal_arr.size():
		level.hexes[i] = palette_hex[i]
		level.colors.append(Color.html(palette_hex[i]))
		level.counts[i] = int(pal_arr[i]["count"])
		var nm = pal_arr[i].get("name", "")
		level.names[i] = nm if typeof(nm) == TYPE_STRING else ""
	level.cells = cells_int
	return _result(PackedStringArray(), level)


static func _result(errors: PackedStringArray, level) -> Dictionary:
	return {"ok": errors.is_empty(), "errors": errors, "level": level}


static func _codes(errors: Dictionary) -> PackedStringArray:
	var keys := errors.keys()
	keys.sort()
	return PackedStringArray(keys)


static func _is_int(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		return is_finite(v) and v == floorf(v) and absf(v) <= 2147483647.0
	return false


static func _all_arrays(a: Array) -> bool:
	for r in a:
		if typeof(r) != TYPE_ARRAY:
			return false
	return true


static func _valid_id(s: String) -> bool:
	if s.is_empty():
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		var is_lower := c >= 97 and c <= 122
		var is_digit := c >= 48 and c <= 57
		if i == 0 and not (is_lower or is_digit):
			return false
		if not (is_lower or is_digit or c == 95):
			return false
	return true


static func _valid_hex(s: String) -> bool:
	if s.length() != 7 or s[0] != "#":
		return false
	for i in range(1, 7):
		var c := s.unicode_at(i)
		var ok := (c >= 48 and c <= 57) or (c >= 97 and c <= 102) or (c >= 65 and c <= 70)
		if not ok:
			return false
	return true
