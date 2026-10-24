# Probe: rename_absolute over an existing destination, and with a missing source.
# Usage: godot --headless --path tools/probes/godot_storage -s probe_rename_existing.gd -- <dir_with_L.json>
extends SceneTree

func _init():
	var args = OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: ... -- <dir_with_L.json>")
		quit(2)
		return
	var base = args[0].trim_suffix("/") + "/"
	var f = FileAccess.open(base + "L.json.tmp", FileAccess.WRITE)
	f.store_string("{\"x\":2}")
	f.close()
	print("MARK_RENAME_OVER_EXISTING")
	var e = DirAccess.rename_absolute(base + "L.json.tmp", base + "L.json")
	print("rename err=", e, " content=", FileAccess.get_file_as_string(base + "L.json"))
	print("MARK_RENAME_MISSING_SRC")
	print("rename missing err=", DirAccess.rename_absolute(base + "nope.tmp", base + "L.json"))
	print("MARK_DONE")
	quit(0)
