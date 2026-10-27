# "Gỡ hạt" (bead sort) mode, modelled on the reference video: the picture is complete except that some patches
# carry a cover of wrong-coloured beads on top, and some cells are empty (hollow) placeholders.
#
#   tap a cover cluster  -> its beads lift off; each goes to a visible empty cell of its colour if one exists,
#                           the rest go to the trays (6 trays x 9 slots). Not enough tray room -> nothing moves.
#   tap an empty cluster -> beads of that colour fly from the trays into it.
#   done when every cell shows its correct bead.
#
# Pure logic; moves are returned so the view can animate them.
extends RefCounted

const TRAY_COUNT := 6
const TRAY_SLOTS := 9
const CAPACITY := TRAY_COUNT * TRAY_SLOTS

const NONE := -1

var level
var filled: PackedByteArray        # 1 = the correct bead sits in this cell (possibly under a cover)
var cover: PackedInt32Array        # colour of the wrong bead on top, or NONE
var tray: Array[int] = []          # colours in arrival order, at most CAPACITY


func _init(lvl) -> void:
	level = lvl
	filled.resize(level.cell_count())
	cover.resize(level.cell_count())
	for i in level.cell_count():
		filled[i] = 1 if level.cells[i] >= 0 else 0
		cover[i] = NONE


func duplicate_state():
	var s = get_script().new(level)
	s.filled = filled.duplicate()
	s.cover = cover.duplicate()
	s.tray = tray.duplicate()
	return s


func playable_count() -> int:
	var n := 0
	for c in level.cells:
		if c >= 0:
			n += 1
	return n


func is_correct(i: int) -> bool:
	return level.cells[i] >= 0 and filled[i] == 1 and cover[i] == NONE


func is_visible_empty(i: int) -> bool:
	return level.cells[i] >= 0 and filled[i] == 0 and cover[i] == NONE


func progress() -> float:
	var ok := 0
	var total := 0
	for i in level.cell_count():
		if level.cells[i] >= 0:
			total += 1
			if is_correct(i):
				ok += 1
	return float(ok) / maxf(total, 1)


func completed() -> bool:
	for i in level.cell_count():
		if level.cells[i] >= 0 and not is_correct(i):
			return false
	return true


# Every colour has exactly as many loose beads (covers + tray) as empty cells waiting for it.
func check_invariants() -> bool:
	var loose := {}
	var holes := {}
	for i in level.cell_count():
		var t: int = level.cells[i]
		if t < 0:
			if filled[i] != 0 or cover[i] != NONE:
				return false
			continue
		if cover[i] != NONE:
			if cover[i] == t:
				return false
			loose[cover[i]] = int(loose.get(cover[i], 0)) + 1
		if filled[i] == 0:
			holes[t] = int(holes.get(t, 0)) + 1
	for c in tray:
		loose[c] = int(loose.get(c, 0)) + 1
	if tray.size() > CAPACITY:
		return false
	for c in level.color_count():
		if int(loose.get(c, 0)) != int(holes.get(c, 0)):
			return false
	return true


func tray_free() -> int:
	return CAPACITY - tray.size()


func tray_count(color: int) -> int:
	var n := 0
	for c in tray:
		if c == color:
			n += 1
	return n


# Connected (4-neighbour) cells from `start` that satisfy `pred`.
func cluster(start: int, pred: Callable) -> PackedInt32Array:
	var out := PackedInt32Array()
	if start < 0 or start >= level.cell_count() or not pred.call(start):
		return out
	var seen := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var i: int = queue.pop_front()
		out.append(i)
		var x: int = level.cell_x(i)
		var y: int = level.cell_y(i)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx < 0 or ny < 0 or nx >= level.width or ny >= level.height:
				continue
			var j: int = ny * level.width + nx
			if not seen.has(j) and pred.call(j):
				seen[j] = true
				queue.append(j)
	return out


func cover_cluster(i: int) -> PackedInt32Array:
	if i < 0 or i >= level.cell_count() or cover[i] == NONE:
		return PackedInt32Array()
	var c := cover[i]
	return cluster(i, func(j: int) -> bool: return cover[j] == c)


func empty_cluster(i: int) -> PackedInt32Array:
	if i < 0 or i >= level.cell_count() or not is_visible_empty(i):
		return PackedInt32Array()
	var t: int = level.cells[i]
	return cluster(i, func(j: int) -> bool: return is_visible_empty(j) and level.cells[j] == t)


# What a tap on cell i would do, without changing anything.
func action_at(i: int) -> String:
	if i < 0 or i >= level.cell_count() or level.cells[i] < 0:
		return "none"
	if cover[i] != NONE:
		return "lift"
	if filled[i] == 0:
		return "fill"
	return "none"


# Returns {kind, moves: [{from_cell, to_cell | to_tray, color}], ...}.
# kind: "lift" | "fill" | "tray_full" | "need_beads" | "none".
func tap(i: int) -> Dictionary:
	match action_at(i):
		"lift":
			return _lift(i)
		"fill":
			return _fill(i)
	return {"kind": "none", "moves": []}


func _lift(i: int) -> Dictionary:
	var cells := cover_cluster(i)
	var color := cover[i]
	# Destinations: visible empty cells of this colour, nearest to the tapped cell first. Cells of the cluster
	# itself are still covered, so they are not destinations.
	var dests := []
	for j in level.cell_count():
		if is_visible_empty(j) and level.cells[j] == color:
			dests.append(j)
	var origin := Vector2(level.cell_x(i), level.cell_y(i))
	dests.sort_custom(func(a, b): return _dist(a, origin) < _dist(b, origin))
	var direct := mini(dests.size(), cells.size())
	var overflow := cells.size() - direct
	if overflow > tray_free():
		return {"kind": "tray_full", "moves": [], "cells": cells, "needed": overflow, "free": tray_free()}
	var moves := []
	for k in cells.size():
		var src: int = cells[k]
		cover[src] = NONE
		if k < direct:
			var dst: int = dests[k]
			filled[dst] = 1
			moves.append({"from_cell": src, "to_cell": dst, "color": color})
		else:
			tray.append(color)
			moves.append({"from_cell": src, "to_tray": tray.size() - 1, "color": color})
	return {"kind": "lift", "moves": moves, "cells": cells, "color": color}


func _fill(i: int) -> Dictionary:
	var cells := empty_cluster(i)
	var color: int = level.cells[i]
	var available := tray_count(color)
	if available == 0:
		return {"kind": "need_beads", "moves": [], "cells": cells, "color": color}
	var n := mini(available, cells.size())
	var moves := []
	for k in n:
		var slot := tray.rfind(color)
		tray.remove_at(slot)
		filled[cells[k]] = 1
		moves.append({"from_tray": slot, "to_cell": cells[k], "color": color})
	return {"kind": "fill", "moves": moves, "cells": cells, "color": color}


func _dist(j: int, origin: Vector2) -> float:
	return Vector2(level.cell_x(j), level.cell_y(j)).distance_squared_to(origin)


# --- persistence ---------------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"filled": Marshalls.raw_to_base64(filled), "cover": Array(cover), "tray": tray.duplicate()}


func from_dict(d: Dictionary) -> bool:
	var f := Marshalls.base64_to_raw(String(d.get("filled", "")))
	var cv: Array = d.get("cover", [])
	var tr: Array = d.get("tray", [])
	if f.size() != level.cell_count() or cv.size() != level.cell_count() or tr.size() > CAPACITY:
		return false
	for i in level.cell_count():
		var c := int(cv[i])
		if level.cells[i] < 0 and (f[i] != 0 or c != NONE):
			return false
		if c < NONE or c >= level.color_count():
			return false
	filled = f
	cover = PackedInt32Array(cv)
	tray.clear()
	for c in tr:
		tray.append(int(c))
	return true
