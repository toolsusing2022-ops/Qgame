# A validated level (schema v1). Built only by level_loader.gd.
extends RefCounted

const EMPTY_CELL := -1

var schema_version: int
var id: String
var title: String
var difficulty: String
var modes: PackedStringArray
var width: int
var height: int
var hexes: PackedStringArray      # lowercase "#rrggbb", index = palette id
var colors: Array[Color] = []
var counts: PackedInt32Array      # palette[].count, equal to the counted cells
var cells: PackedInt32Array       # row-major, cells[y * width + x]


func color_count() -> int:
	return hexes.size()


func cell_count() -> int:
	return cells.size()


func index_of(x: int, y: int) -> int:
	return y * width + x


func cell_x(i: int) -> int:
	return i % width


func cell_y(i: int) -> int:
	return i / width


func is_playable(i: int) -> bool:
	return i >= 0 and i < cells.size() and cells[i] >= 0
