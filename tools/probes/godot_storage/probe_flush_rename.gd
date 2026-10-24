# Probe: what FileAccess.store/flush/close and DirAccess.rename_absolute do at the syscall level.
# Usage: godot --headless --path tools/probes/godot_storage -s probe_flush_rename.gd -- <empty_dir>
extends SceneTree

func _init():
	var args = OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: ... -- <empty_dir>")
		quit(2)
		return
	var base = args[0].trim_suffix("/") + "/"
	var f = FileAccess.open(base + "L.json.tmp", FileAccess.WRITE)
	print("MARK_STORE")
	var ok = f.store_string("{\"x\":1}")
	print("store ok=", ok, " err=", f.get_error())
	print("MARK_FLUSH")
	f.flush()
	print("flush err=", f.get_error())
	print("MARK_CLOSE")
	f.close()
	print("MARK_RENAME")
	print("rename err=", DirAccess.rename_absolute(base + "L.json.tmp", base + "L.json"))
	print("MARK_END")
	quit(0)
