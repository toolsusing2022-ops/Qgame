# Headless unit-test runner.
#   godot --headless --path . -s res://game/tests/run_unit.gd [-- <name filter>]
# Runs every test_* method of every res://game/tests/unit/test_*.gd script. Exit code 0 = all passed.
extends SceneTree

const UNIT_DIR := "res://game/tests/unit"


func _init() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		filter = args[0]
	var files := PackedStringArray()
	for name in DirAccess.get_files_at(UNIT_DIR):
		if name.begins_with("test_") and name.ends_with(".gd"):
			files.append(name)
	files.sort()

	var passed := 0
	var failed := 0
	for name in files:
		var script: GDScript = load(UNIT_DIR.path_join(name))
		if script == null:
			print("FAIL %s: script failed to load" % name)
			failed += 1
			continue
		var methods := PackedStringArray()
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if mname.begins_with("test_") and not methods.has(mname):
				methods.append(mname)
		for mname in methods:
			var label := "%s::%s" % [name.get_basename(), mname]
			if filter != "" and not label.contains(filter):
				continue
			var t = script.new()
			t.call(mname)
			if t.failures.is_empty():
				passed += 1
				print("PASS ", label)
			else:
				failed += 1
				for f in t.failures:
					print("FAIL %s: %s" % [label, f])
	print("\n%d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 and passed > 0 else 1)
