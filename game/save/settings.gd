# App settings, stored separately from progress (gameplay spec GS-11.6, GS-12.6): install_id, sound, haptic.
# A broken settings file never affects progress, and vice versa; on failure defaults are used.
extends RefCounted

const StorageBackend := preload("res://game/storage/storage_backend.gd")
const ProgressSession := preload("res://game/save/progress_session.gd")

const PATH := "user://settings.json"

var backend
var path := PATH
var install_id := ""
var sfx_enabled := true
var haptic_enabled := true
var ambient := "sea"              # off | sea | rain (GS-11.3)


func _init(storage_backend, settings_path := PATH) -> void:
	backend = storage_backend
	path = settings_path


func load_or_create() -> void:
	var rd: Dictionary = backend.read_file(path)
	var d = JSON.parse_string((rd["bytes"] as PackedByteArray).get_string_from_utf8()) if rd["ok"] else null
	if typeof(d) == TYPE_DICTIONARY:
		install_id = String(d.get("install_id", ""))
		sfx_enabled = bool(d.get("sfx", true))
		haptic_enabled = bool(d.get("haptic", true))
		ambient = String(d.get("ambient", "sea"))
	if install_id == "":
		install_id = ProgressSession.new_uuid()
		save()


func save() -> bool:
	var bytes := JSON.stringify({"install_id": install_id, "sfx": sfx_enabled, "haptic": haptic_enabled, "ambient": ambient},
		"", true).to_utf8_buffer()
	var tmp := path + ".tmp"
	if not backend.write_file(tmp, bytes)["ok"]:
		return false
	return backend.rename_replace(tmp, path, StorageBackend.sha256(bytes))["ok"]
