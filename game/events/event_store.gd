# Event store events/events.jsonl (gameplay spec GS-14.5 as of v0.4.2).
#
# One JSON object per line: {event_id, type, payload, ts, crc32}; crc32 covers the canonical JSON of the other
# four fields. Lines that are torn, not JSON or fail the CRC are skipped (and counted). The store may contain
# several lines with the same event_id (re-appends after restart, GS-14.4); the first valid line is the logical
# record and the others are duplicates. Every reader must use logical_records().
extends RefCounted

const PATH := "user://events/events.jsonl"

var backend
var path := PATH
var skipped_lines := 0
var payload_conflicts := 0


func _init(storage_backend, store_path := PATH) -> void:
	backend = storage_backend
	path = store_path


static func canonical(entry: Dictionary) -> String:
	return JSON.stringify({"event_id": entry["event_id"], "type": entry["type"], "payload": entry["payload"],
		"ts": entry["ts"]}, "", true)


# The entry is normalised through one JSON round trip first (numbers become floats, as they will be when read
# back), so the CRC computed at write time matches the one recomputed by valid_lines().
static func line_for(entry: Dictionary) -> PackedByteArray:
	var obj: Dictionary = JSON.parse_string(canonical(entry))
	obj["crc32"] = Crc32.of(canonical(obj).to_utf8_buffer())
	return (JSON.stringify(obj, "", true) + "\n").to_utf8_buffer()


# Appends one line. If the file does not end with "\n" (torn tail after a failed append), a newline goes first.
func append(entry: Dictionary) -> bool:
	var prefix := PackedByteArray()
	var r: Dictionary = backend.read_file(path)
	if r["ok"]:
		var b: PackedByteArray = r["bytes"]
		if not b.is_empty() and b[b.size() - 1] != 10:
			prefix.append(10)
	prefix.append_array(line_for(entry))
	return backend.append_line(path, prefix)


func sync() -> String:
	return backend.sync_file(path)


# All valid lines in file order.
func valid_lines() -> Array:
	skipped_lines = 0
	var out := []
	var r: Dictionary = backend.read_file(path)
	if not r["ok"]:
		return out
	var text: String = (r["bytes"] as PackedByteArray).get_string_from_utf8()
	var lines := text.split("\n")
	var complete := lines.size() - 1          # the last element is either "" or a torn tail
	for k in lines.size():
		var line := lines[k]
		if line == "":
			continue
		if k >= complete:
			skipped_lines += 1
			continue
		var obj = JSON.parse_string(line)
		if typeof(obj) != TYPE_DICTIONARY or not obj.has("crc32") or not obj.has("event_id"):
			skipped_lines += 1
			continue
		if Crc32.of(canonical(obj).to_utf8_buffer()) != int(obj["crc32"]):
			skipped_lines += 1
			continue
		out.append(obj)
	return out


# Logical records: first valid line per event_id (GS-14.5).
func logical_records() -> Array:
	payload_conflicts = 0
	var seen := {}
	var out := []
	for obj in valid_lines():
		var id: String = obj["event_id"]
		if seen.has(id):
			if canonical(seen[id]) != canonical(obj):
				payload_conflicts += 1
			continue
		seen[id] = obj
		out.append(obj)
	return out


func count_logical(type := "") -> int:
	var n := 0
	for obj in logical_records():
		if type == "" or obj["type"] == type:
			n += 1
	return n


class Crc32:
	static var _table := PackedInt64Array()

	static func of(bytes: PackedByteArray) -> int:
		if _table.is_empty():
			_table.resize(256)
			for n in 256:
				var c := n
				for k in 8:
					c = (0xEDB88320 ^ (c >> 1)) if (c & 1) else (c >> 1)
				_table[n] = c
		var crc := 0xFFFFFFFF
		for b in bytes:
			crc = _table[(crc ^ b) & 0xFF] ^ (crc >> 8)
		return crc ^ 0xFFFFFFFF
