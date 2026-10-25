# Default backend on Godot's FileAccess/DirAccess. On Godot 4.4.1 (observed on Linux, see
# tools/probes/godot_storage/README.md) flush() does not fsync and there is no directory sync, so this backend
# reports file_sync = written and dir_sync = unsupported, both only `assumed` until verified on iOS (GS-12.10).
extends "res://game/storage/storage_backend.gd"


func _p_exists(path: String) -> int:
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		return EXISTS
	return ABSENT


func _p_is_dir(path: String) -> bool:
	return DirAccess.dir_exists_absolute(path)


func _p_read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "bytes": PackedByteArray()}
	var bytes := f.get_buffer(f.get_length())
	var ok := f.get_error() == OK or f.get_error() == ERR_FILE_EOF
	f.close()
	return {"ok": ok, "bytes": bytes}


func _p_write(path: String, bytes: PackedByteArray) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	var ok := f.store_buffer(bytes)
	f.flush()
	ok = ok and f.get_error() == OK
	f.close()
	return ok


func _p_append(path: String, bytes: PackedByteArray) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.seek_end()
	var ok := f.store_buffer(bytes)
	f.flush()
	ok = ok and f.get_error() == OK
	f.close()
	return ok


func _p_rename(src: String, dst: String) -> bool:
	return DirAccess.rename_absolute(src, dst) == OK


func _p_delete(path: String) -> bool:
	return DirAccess.remove_absolute(path) == OK


func _p_list(dir: String) -> Dictionary:
	if not DirAccess.dir_exists_absolute(dir):
		return {"ok": true, "names": PackedStringArray()}
	return {"ok": true, "names": DirAccess.get_files_at(dir)}


# Godot exposes no fsync: the best this backend can claim is that flush/close succeeded.
func _p_sync_file(path: String) -> String:
	return "written" if FileAccess.file_exists(path) else "failed"


func _p_sync_dir(_dir: String) -> String:
	return "unsupported"
