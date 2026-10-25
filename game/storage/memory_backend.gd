# In-memory file system used by unit tests (logic simulation only, never evidence about real storage; TC-12.24).
#
# Two layers: `files` is what the OS would show (written), `durable_files` is what survives power loss.
# With durable_mode off (like GodotFileBackend) nothing ever becomes durable, so power_loss() reverts to the
# initial image. crash() keeps the written layer (process death, page cache survives).
extends "res://game/storage/storage_backend.gd"

var files := {}            # path -> PackedByteArray
var dirs := {}             # path -> true (explicit directories, only used for dst_is_dir tests)
var durable_files := {}
var durable_mode := false


func capabilities() -> Dictionary:
	var caps := super.capabilities()
	if durable_mode:
		caps["file_sync"] = {"value": "durable", "evidence": "assumed"}
		caps["dir_sync"] = {"value": "durable", "evidence": "assumed"}
	return caps


func load_image(image: Dictionary) -> void:
	files = image.duplicate(true)
	durable_files = image.duplicate(true)


func image() -> Dictionary:
	return files.duplicate(true)


# Power loss: everything not durable is lost.
func power_loss() -> void:
	files = durable_files.duplicate(true)


func _p_exists(path: String) -> int:
	return EXISTS if files.has(path) or dirs.has(path) else ABSENT


func _p_is_dir(path: String) -> bool:
	return dirs.has(path)


func _p_read(path: String) -> Dictionary:
	if not files.has(path):
		return {"ok": false, "bytes": PackedByteArray()}
	return {"ok": true, "bytes": (files[path] as PackedByteArray).duplicate()}


func _p_write(path: String, bytes: PackedByteArray) -> bool:
	files[path] = bytes.duplicate()
	return true


func _p_append(path: String, bytes: PackedByteArray) -> bool:
	var cur: PackedByteArray = files.get(path, PackedByteArray())
	cur.append_array(bytes)
	files[path] = cur
	return true


func _p_rename(src: String, dst: String) -> bool:
	if not files.has(src) or dirs.has(dst):
		return false
	files[dst] = files[src]
	files.erase(src)
	return true


func _p_delete(path: String) -> bool:
	return files.erase(path)


func _p_list(dir: String) -> Dictionary:
	var names := PackedStringArray()
	var prefix := dir.trim_suffix("/") + "/"
	for p in files:
		var s: String = p
		if s.begins_with(prefix) and not s.substr(prefix.length()).contains("/"):
			names.append(s.substr(prefix.length()))
	names.sort()
	return {"ok": true, "names": names}


func _p_sync_file(path: String) -> String:
	if not files.has(path):
		return "failed"
	if durable_mode:
		durable_files[path] = (files[path] as PackedByteArray).duplicate()
		return "durable"
	return "written"


func _p_sync_dir(_dir: String) -> String:
	if not durable_mode:
		return "unsupported"
	# Directory entries become durable: drop names that no longer exist, keep durable data for the rest.
	var snapshot := {}
	for p in files:
		snapshot[p] = durable_files.get(p, files[p])
	durable_files = snapshot
	return "durable"
