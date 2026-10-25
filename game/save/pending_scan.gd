# Startup scan of archived-but-undrained candidates (gameplay spec GS-14.9, GS-13.3 exception).
# For every progress/*.pending-{stale,corrupt}.<UTC>[-n] file, of any level, the dispatcher may only:
#   read that file's outbox, and rename that same file (pending-X -> X, or -> corrupt when unreadable).
extends RefCounted

const StorageBackend := preload("res://game/storage/storage_backend.gd")
const Codec := preload("res://game/save/progress_codec.gd")


static func run(backend, dispatcher, progress_dir: String, now_ms: int) -> Array:
	var report := []
	var lst: Dictionary = backend.list_dir(progress_dir)
	for name in lst.get("names", []):
		if not (name.contains(".pending-stale.") or name.contains(".pending-corrupt.")):
			continue
		var path := progress_dir.path_join(name)
		var rd: Dictionary = backend.read_file(path)
		if not rd["ok"]:
			backend.diag("pending_io_error %s" % name)          # keep, retry next scan
			report.append({"file": name, "action": "kept_io_error"})
			continue
		var h := StorageBackend.sha256(rd["bytes"])
		var dec := Codec.decode(rd["bytes"], "")
		var target := ""
		if not dec["outbox_valid"]:
			target = name.replace(".pending-stale.", ".corrupt.").replace(".pending-corrupt.", ".corrupt.")
		else:
			var r: Dictionary = dispatcher.dispatch(dec["outbox"], "pending", now_ms)
			if not r["all_confirmed"]:
				report.append({"file": name, "action": "kept_pending"})
				continue
			target = name.replace(".pending-stale.", ".stale.").replace(".pending-corrupt.", ".corrupt.")
		var done := false
		for n in 50:
			var dst := progress_dir.path_join(target + ("" if n == 0 else "-%d" % n))
			var rr: Dictionary = backend.rename_noreplace(path, dst, h)
			if rr["state_after"] == StorageBackend.STATE_REPLACED:
				report.append({"file": name, "action": "renamed", "to": dst.get_file()})
				done = true
				break
			if rr["err"] != "dst_exists":
				break
		if not done:
			report.append({"file": name, "action": "kept_rename_failed"})
	return report
