# Progress file format (gameplay spec GS-12.3 as of v0.4) and phase-A classification (GS-13.4).
#
# Ordering note: checks that depend on the current level layout (bitset length, placed on a -1 cell, selected in
# range) are only meaningful when layout_hash matches. They run in check_against_level(), after phase C has
# confirmed the layout, so an outdated save is reported as stale_layout_changed rather than invalid.
extends RefCounted

const Config := preload("res://game/core/config.gd")

const CLASS_OK := "ok"
const CLASS_UNREADABLE := "unreadable"
const CLASS_WRONG_LEVEL := "wrong_level"
const CLASS_INVALID := "invalid"

const REQUIRED := {
	"save_version": TYPE_FLOAT, "level_id": TYPE_STRING, "level_schema_version": TYPE_FLOAT,
	"content_version": TYPE_FLOAT, "layout_hash": TYPE_STRING, "content_hash": TYPE_STRING,
	"palette_snapshot": TYPE_ARRAY, "placed": TYPE_STRING, "selected": TYPE_FLOAT, "completed": TYPE_BOOL,
	"colors_ever_completed": TYPE_STRING, "outbox": TYPE_ARRAY, "updated_at": TYPE_STRING,
}


static func encode(level, board, content_version: int, layout_hash: String, content_hash: String,
		outbox: Array) -> PackedByteArray:
	var snapshot := []
	for i in level.color_count():
		var e := {"hex": level.hexes[i]}
		if level.names[i] != "":
			e["name"] = level.names[i]
		snapshot.append(e)
	var data := {
		"save_version": Config.SAVE_VERSION,
		"level_id": level.id,
		"level_schema_version": level.schema_version,
		"content_version": content_version,
		"layout_hash": layout_hash,
		"content_hash": content_hash,
		"palette_snapshot": snapshot,
		"placed": Marshalls.raw_to_base64(pack_bits(board.placed)),
		"selected": board.selected,
		"completed": board.completed,
		"colors_ever_completed": Marshalls.raw_to_base64(pack_bits(board.colors_ever_completed)),
		"outbox": outbox,
		"updated_at": Time.get_datetime_string_from_system(true) + "Z",
	}
	return JSON.stringify(data, "", true).to_utf8_buffer()


# Phase A (structure only). Returns {class, data, outbox, outbox_valid}.
static func decode(bytes: PackedByteArray, level_id: String) -> Dictionary:
	var out := {"class": CLASS_UNREADABLE, "data": {}, "outbox": [], "outbox_valid": false}
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return out
	var d: Dictionary = json.data
	out["data"] = d
	if d.has("outbox"):
		out["outbox_valid"] = outbox_is_valid(d["outbox"])
		if out["outbox_valid"]:
			out["outbox"] = d["outbox"]
	if typeof(d.get("level_id")) == TYPE_STRING and d["level_id"] != level_id:
		out["class"] = CLASS_WRONG_LEVEL
		return out
	out["class"] = CLASS_INVALID
	for k in REQUIRED:
		if not d.has(k) or typeof(d[k]) != REQUIRED[k]:
			return out
	for k in ["save_version", "level_schema_version", "content_version", "selected"]:
		if d[k] != floorf(d[k]):
			return out
	if Marshalls.base64_to_raw(d["placed"]).is_empty() and d["placed"] != "":
		return out
	if not out["outbox_valid"]:
		return out
	for e in d["palette_snapshot"]:
		if typeof(e) != TYPE_DICTIONARY or typeof(e.get("hex")) != TYPE_STRING:
			return out
	out["class"] = CLASS_OK
	return out


# Level-dependent checks, run once the layout hash matches. Returns "" or an error string.
static func check_against_level(d: Dictionary, level) -> String:
	var placed := unpack_bits(Marshalls.base64_to_raw(d["placed"]), level.cell_count())
	if placed.is_empty():
		return "placed_length"
	var ever := unpack_bits(Marshalls.base64_to_raw(d["colors_ever_completed"]), level.color_count())
	if ever.is_empty():
		return "colors_ever_length"
	for i in placed.size():
		if placed[i] != 0 and level.cells[i] < 0:
			return "placed_on_empty"
	var sel := int(d["selected"])
	if sel < -1 or sel >= level.color_count():
		return "selected_range"
	return ""


static func outbox_is_valid(outbox: Variant) -> bool:
	if typeof(outbox) != TYPE_ARRAY:
		return false
	var ids := {}
	for e in outbox:
		if typeof(e) != TYPE_DICTIONARY:
			return false
		if typeof(e.get("event_id")) != TYPE_STRING or typeof(e.get("type")) != TYPE_STRING:
			return false
		if typeof(e.get("payload")) != TYPE_DICTIONARY or not e.has("ts"):
			return false
		if ids.has(e["event_id"]):
			return false
		ids[e["event_id"]] = true
	return true


static func pack_bits(flags: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize((flags.size() + 7) / 8)
	out.fill(0)
	for i in flags.size():
		if flags[i] != 0:
			out[i / 8] |= 1 << (i % 8)
	return out


# Returns an empty array if the byte length or padding bits do not match n.
static func unpack_bits(bytes: PackedByteArray, n: int) -> PackedByteArray:
	var out := PackedByteArray()
	if bytes.size() != (n + 7) / 8:
		return out
	out.resize(n)
	for i in n:
		out[i] = 1 if (bytes[i / 8] >> (i % 8)) & 1 else 0
	for i in range(n, bytes.size() * 8):
		if (bytes[i / 8] >> (i % 8)) & 1:
			return PackedByteArray()
	return out
