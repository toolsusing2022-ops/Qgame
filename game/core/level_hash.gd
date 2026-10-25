# Canonical level fingerprints (gameplay spec GS-13.1). Must match tools/level_hash.py byte for byte.
extends RefCounted


static func layout_string(level) -> String:
	return "pbart-layout-1|w=%d|h=%d|n=%d|cells=%s" % [level.width, level.height, level.color_count(), _cells(level.cells)]


static func content_string(level) -> String:
	var parts := PackedStringArray()
	for i in level.hexes.size():
		parts.append("%d:%s" % [i, String(level.hexes[i]).to_lower()])
	return "pbart-content-1|schema=%d|w=%d|h=%d|palette=%s|cells=%s" % [
		level.schema_version, level.width, level.height, ",".join(parts), _cells(level.cells)]


static func layout_hash(level) -> String:
	return layout_string(level).sha256_text()


static func content_hash(level) -> String:
	return content_string(level).sha256_text()


static func _cells(cells: PackedInt32Array) -> String:
	var parts := PackedStringArray()
	parts.resize(cells.size())
	for i in cells.size():
		parts[i] = str(cells[i])
	return ",".join(parts)
