# Restore for one level (gameplay spec GS-13.3 .. 13.15 as of v0.4.9).
#
# E0  delete leftover L.json.tmp / L.json.bak.tmp (never used as progress, GS-13.13)
# E1  evaluate [L.json, L.json.bak] in memory through phases A-D; each candidate is read exactly once
#     (B_read / H_read / E_read)
# E2  source = first restorable candidate
# E3  archive every non-chosen candidate (drain outbox first when required, pending on store failure,
#     rename_noreplace, never overwrite); abort with archive_failed if a rename cannot be completed
extends RefCounted

const Config := preload("res://game/core/config.gd")
const StorageBackend := preload("res://game/storage/storage_backend.gd")
const BoardState := preload("res://game/core/board_state.gd")
const Codec := preload("res://game/save/progress_codec.gd")
const ColorMath := preload("res://game/core/color_math.gd")
const LevelHash := preload("res://game/core/level_hash.gd")

const KIND_RESTORABLE := "restorable"
const KIND_INCOMPATIBLE := "incompatible"
const KIND_BROKEN := "broken"
const KIND_MISSING := "missing"
const KIND_IO_ERROR := "io_error"

const MESSAGES := {
	"stale": "Tranh đã được cập nhật, bắt đầu lại",
	"corrupt_fresh": "Không đọc được tiến độ cũ, bắt đầu lại",
	"restored_hex_changed": "Màu của tranh vừa được cập nhật",
	"archive_failed": "Không thể mở tiến độ do lỗi bộ nhớ. Hãy thử lại sau.",
	"fresh_after_archive": "Không khôi phục được tiến độ cũ, bắt đầu lại.",
	"bak": "Đã khôi phục bản lưu gần nhất; một số thao tác gần đây có thể chưa được lưu.",
}


# ctx: {backend, dispatcher, level, catalog_entry, progress_dir, now_ms, utc}
static func run(ctx: Dictionary) -> Dictionary:
	var backend = ctx["backend"]
	var level = ctx["level"]
	var main_path: String = ctx["progress_dir"].path_join(level.id + ".json")
	var paths := [main_path, main_path + ".bak"]

	# E0
	for tmp in [main_path + ".tmp", main_path + ".bak.tmp"]:
		if backend.exists(tmp) == StorageBackend.EXISTS:
			backend.delete(tmp)

	# E1
	var cands := []
	for p in paths:
		cands.append(evaluate(backend, p, level, ctx["catalog_entry"]))

	# E2
	var source := -1
	for i in cands.size():
		if cands[i]["kind"] == KIND_RESTORABLE:
			source = i
			break

	# E3.1
	var archived := []
	for i in cands.size():
		if i == source:
			continue
		var c: Dictionary = cands[i]
		if c["kind"] in [KIND_MISSING, KIND_IO_ERROR]:
			continue
		var a := archive(backend, ctx["dispatcher"], c, ctx.get("utc", _utc()), ctx["now_ms"])
		if not a["ok"]:
			return _result("archive_failed", "none", null, cands, archived, ctx, level)
		archived.append({"file": c["path"].get_file(), "as": a["as"]})

	var out: Dictionary
	if source >= 0:
		var s: Dictionary = cands[source]
		out = _result(s["result"], "main" if source == 0 else "bak", s["board"], cands, archived, ctx, level)
		out["restore_outbox"] = s["outbox"]
		out["h_commit"] = s["h_read"] if source == 0 else ""
		out["needs_write"] = source == 1 or s["result"] == "restored_hex_changed"
	else:
		var outcome := ""
		for c in cands:
			if c["kind"] == KIND_INCOMPATIBLE:
				outcome = c["result"]
				break
			if c["kind"] in [KIND_BROKEN, KIND_IO_ERROR]:
				outcome = "corrupt_fresh"
				break
		if outcome == "":
			outcome = "fresh_after_archive" if has_archives(backend, ctx["progress_dir"], level.id) \
				else "fresh_first_play"
		var board = BoardState.new(level)
		out = _result(outcome, "none", board, cands, archived, ctx, level)
		out["restore_outbox"] = []
		out["h_commit"] = ""
		out["needs_write"] = true
	out["needs_reconcile"] = cands[0]["kind"] == KIND_IO_ERROR
	return out


# Phases A-D for one candidate.
static func evaluate(backend, path: String, level, entry: Dictionary) -> Dictionary:
	var c := {"path": path, "kind": KIND_MISSING, "result": "missing", "h_read": "", "outbox": [],
		"outbox_valid": false, "board": null}
	var ex: int = backend.exists(path)
	if ex == StorageBackend.ABSENT:
		return c
	var rd: Dictionary = backend.read_file(path) if ex == StorageBackend.EXISTS else {"ok": false}
	if not rd["ok"]:
		c["kind"] = KIND_IO_ERROR
		c["result"] = "io_error"
		return c
	c["h_read"] = StorageBackend.sha256(rd["bytes"])
	# A
	var dec := Codec.decode(rd["bytes"], level.id)
	c["outbox_valid"] = dec["outbox_valid"]
	c["outbox"] = dec["outbox"]
	if dec["class"] != Codec.CLASS_OK:
		c["kind"] = KIND_BROKEN
		c["result"] = dec["class"]
		return c
	var d: Dictionary = dec["data"]
	# B: no migrations are registered in the MVP.
	if int(d["save_version"]) != Config.SAVE_VERSION or int(d["level_schema_version"]) != level.schema_version:
		return _mark(c, KIND_INCOMPATIBLE, "stale_no_migration")
	# C
	var result := "restored"
	if d["layout_hash"] != LevelHash.layout_hash(level):
		return _mark(c, KIND_INCOMPATIBLE, "stale_layout_changed")
	if d["content_hash"] != LevelHash.content_hash(level):
		var compat := palette_compat(d, level, entry)
		if compat != "":
			return _mark(c, KIND_INCOMPATIBLE, compat)
		result = "restored_hex_changed"
	# A (level-dependent part) once the layout is known to match
	if Codec.check_against_level(d, level) != "":
		return _mark(c, KIND_BROKEN, "invalid")
	# D
	var board = BoardState.new(level)
	var placed := Codec.unpack_bits(Marshalls.base64_to_raw(d["placed"]), level.cell_count())
	var ever := Codec.unpack_bits(Marshalls.base64_to_raw(d["colors_ever_completed"]), level.color_count())
	if not board.apply_saved(placed, int(d["selected"]), d["completed"], ever):
		return _mark(c, KIND_BROKEN, "invariant_failed")
	c["board"] = board
	return _mark(c, KIND_RESTORABLE, result)


# GS-13.8 / 13.9. Returns "" when the recolour is proven compatible, else the stale result.
static func palette_compat(d: Dictionary, level, entry: Dictionary) -> String:
	var saved_cv := int(d["content_version"])
	var cur_cv := int(entry.get("content_version", 0))
	if saved_cv >= cur_cv:
		push_warning("content_version_not_bumped: %s" % level.id)
		return "stale_palette_unverified"
	if not entry.has("palette_compat_from"):
		return "stale_palette_unverified"
	var pcf := int(entry["palette_compat_from"])
	if not (pcf <= saved_cv and saved_cv < cur_cv):
		return "stale_palette_unverified"
	var snap: Array = d["palette_snapshot"]
	if snap.size() != level.color_count():
		return "stale_palette_rejected"
	for i in snap.size():
		var old_name: String = snap[i].get("name", "")
		if old_name != "" and level.names[i] != "" and old_name != level.names[i]:
			return "stale_palette_rejected"
		if ColorMath.delta_e_hex(snap[i]["hex"], level.hexes[i]) > Config.PALETTE_RECOLOR_MAX_DE:
			return "stale_palette_rejected"
	return ""


# GS-13.11 / 13.15: drain (when required), then rename_noreplace to the archive name.
static func archive(backend, dispatcher, c: Dictionary, utc: String, now_ms: int) -> Dictionary:
	var family := "stale" if c["kind"] == KIND_INCOMPATIBLE else "corrupt"
	var needs_drain: bool = (c["kind"] == KIND_INCOMPATIBLE or c["result"] in ["invalid", "invariant_failed"]) \
		and c["outbox_valid"] and not (c["outbox"] as Array).is_empty()
	var as_name := family
	if needs_drain:
		var r: Dictionary = dispatcher.dispatch(c["outbox"], "archive", now_ms)
		if not r["all_confirmed"]:
			as_name = "pending-" + family
	for n in 50:
		var dst := "%s.%s.%s%s" % [c["path"], as_name, utc, "" if n == 0 else "-%d" % n]
		var rr: Dictionary = backend.rename_noreplace(c["path"], dst, c["h_read"])
		if rr["state_after"] == StorageBackend.STATE_REPLACED:
			return {"ok": true, "as": as_name, "dst": dst}
		if rr["err"] != "dst_exists":
			return {"ok": false}
	return {"ok": false}


static func has_archives(backend, progress_dir: String, level_id: String) -> bool:
	var lst: Dictionary = backend.list_dir(progress_dir)
	for name in lst.get("names", []):
		if name.begins_with(level_id + ".json") and (name.contains(".stale.") or name.contains(".corrupt.")
				or name.contains(".pending-")):
			return true
	return false


static func message_for(outcome: String) -> String:
	if outcome.begins_with("stale_"):
		return MESSAGES["stale"]
	return MESSAGES.get(outcome, "")


static func _mark(c: Dictionary, kind: String, result: String) -> Dictionary:
	c["kind"] = kind
	c["result"] = result
	return c


static func _result(outcome: String, source: String, board, cands: Array, archived: Array, ctx: Dictionary,
		level) -> Dictionary:
	var summary := []
	for c in cands:
		summary.append({"file": (c["path"] as String).get_file(), "class": c["kind"], "result": c["result"]})
	var notices := PackedStringArray()
	if source == "bak":
		notices.append(MESSAGES["bak"])           # GS-13.14 / KT-4
	var msg := message_for(outcome)
	if msg != "":
		notices.append(msg)
	return {"outcome": outcome, "source": source, "board": board, "candidates": summary, "archived": archived,
		"bak_notice": source == "bak", "notices": notices, "restore_outbox": [], "h_commit": "",
		"needs_write": false, "needs_reconcile": false, "level_id": level.id}


static func _utc() -> String:
	return Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "") + "Z"
