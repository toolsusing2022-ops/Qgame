# "Gỡ hạt" (bead sort) mode, modelled on the reference video: the picture is complete except that some patches
# carry a cover of wrong-coloured beads on top, and some cells are empty (hollow) placeholders.
#
# Every move takes two taps: pick a source, then a destination.
#   source       a cover cluster on the board (its beads lift up), or a tray bead (selects every tray bead of
#                that colour)
#   destination  an empty cell of the same colour (beads fill its cluster nearest first, then the colour's other
#                visible holes), or a tray (board beads only; they fill free slots from that tray onwards).
#                Whatever does not fit stays selected.
#   done when every cell shows its correct bead.
#
# Pure logic; moves are returned so the view can animate them. The selection is transient and never saved.
extends RefCounted

const TRAY_COUNT := 6
const TRAY_SLOTS := 9
const CAPACITY := TRAY_COUNT * TRAY_SLOTS

const NONE := -1

var level
var filled: PackedByteArray        # 1 = the correct bead sits in this cell (possibly under a cover)
var cover: PackedInt32Array        # colour of the wrong bead on top, or NONE
var tray: PackedInt32Array         # CAPACITY slots (tray t owns slots t*TRAY_SLOTS ..), colour or NONE

var sel_kind := ""                 # "" | "board" | "tray"
var sel_cells := PackedInt32Array()   # board selection: covered cells still waiting to move
var sel_color := NONE


func _init(lvl) -> void:
	level = lvl
	filled.resize(level.cell_count())
	cover.resize(level.cell_count())
	tray.resize(CAPACITY)
	tray.fill(NONE)
	for i in level.cell_count():
		filled[i] = 1 if level.cells[i] >= 0 else 0
		cover[i] = NONE


func duplicate_state():
	var s = get_script().new(level)
	s.filled = filled.duplicate()
	s.cover = cover.duplicate()
	s.tray = tray.duplicate()
	return s       # the selection is not copied


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
	if tray.size() != CAPACITY:
		return false
	for c in tray:
		if c != NONE:
			loose[c] = int(loose.get(c, 0)) + 1
	for c in level.color_count():
		if int(loose.get(c, 0)) != int(holes.get(c, 0)):
			return false
	return true


func tray_free() -> int:
	return tray.count(NONE)


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


func has_selection() -> bool:
	return sel_kind != ""


func clear_selection() -> void:
	sel_kind = ""
	sel_cells = PackedInt32Array()
	sel_color = NONE


func tray_slots_of(color: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for s in CAPACITY:
		if tray[s] == color:
			out.append(s)
	return out


# Can a tap on cell i do anything right now (used by the view to snap near misses)?
func cell_is_target(i: int) -> bool:
	if i < 0 or i >= level.cell_count() or level.cells[i] < 0:
		return false
	return cover[i] != NONE or filled[i] == 0


# Tap on board cell i. Returns {kind, ...}:
#   "select"      a cover cluster is now selected (cells, color)
#   "deselect"    the selection was dropped
#   "place"       beads moved into the empty cluster (moves: [{from_cell | from_slot, to_cell, color}])
#   "wrong_color" selection does not match the empty cell's colour (cells = that empty cluster)
#   "need_select" empty cell tapped with nothing selected
#   "none"
func tap_cell(i: int) -> Dictionary:
	if not cell_is_target(i):
		if has_selection():
			clear_selection()
			return {"kind": "deselect", "moves": []}
		return {"kind": "none", "moves": []}
	if cover[i] != NONE:
		if sel_kind == "board" and sel_cells.has(i):
			clear_selection()
			return {"kind": "deselect", "moves": []}
		clear_selection()
		sel_kind = "board"
		sel_cells = cover_cluster(i)
		sel_color = cover[i]
		return {"kind": "select", "moves": [], "cells": sel_cells, "color": sel_color}
	# visible empty cell
	var target: int = level.cells[i]
	if not has_selection():
		return {"kind": "need_select", "moves": [], "cells": empty_cluster(i), "color": target}
	if sel_color != target:
		return {"kind": "wrong_color", "moves": [], "cells": empty_cluster(i), "color": target, "selected": sel_color}
	# The tapped empty cluster first (BFS from i: nearest first), then other visible holes of the colour by distance.
	var dests := empty_cluster(i)
	var origin := Vector2(level.cell_x(i), level.cell_y(i))
	var others := []
	for j in level.cell_count():
		if is_visible_empty(j) and level.cells[j] == target and not dests.has(j):
			others.append(j)
	others.sort_custom(func(p, q): return _dist(p, origin) < _dist(q, origin))
	dests.append_array(PackedInt32Array(others))
	var moves := []
	if sel_kind == "board":
		var srcs := Array(sel_cells)
		srcs.sort_custom(func(p, q): return _dist(p, origin) < _dist(q, origin))
		var n := mini(srcs.size(), dests.size())
		for k in n:
			var src: int = srcs[k]
			cover[src] = NONE
			filled[dests[k]] = 1
			moves.append({"from_cell": src, "to_cell": dests[k], "color": target})
		sel_cells = PackedInt32Array(srcs.slice(n))
		if sel_cells.is_empty():
			clear_selection()
	else:
		var slots := tray_slots_of(target)
		var n := mini(slots.size(), dests.size())
		for k in n:
			var s: int = slots[slots.size() - 1 - k]      # take from the back so the front trays stay tidy
			tray[s] = NONE
			filled[dests[k]] = 1
			moves.append({"from_slot": s, "to_cell": dests[k], "color": target})
		if tray_slots_of(target).is_empty():
			clear_selection()
	return {"kind": "place", "moves": moves, "cells": dests, "color": target}


# Tap on tray slot s (any slot of a tray picks that tray as the destination). Returns {kind, ...}:
#   "to_tray"     board selection moved into free slots (moves: [{from_cell, to_slot, color}])
#   "tray_full"   no free slot at all
#   "select_tray" tray beads of the slot's colour are now selected (slots, color)
#   "deselect" | "none"
func tap_slot(s: int) -> Dictionary:
	if s < 0 or s >= CAPACITY:
		return {"kind": "none", "moves": []}
	if sel_kind == "board":
		var free := PackedInt32Array()
		var first := (s / TRAY_SLOTS) * TRAY_SLOTS
		for k in CAPACITY:
			var slot := (first + k) % CAPACITY
			if tray[slot] == NONE:
				free.append(slot)
		if free.is_empty():
			return {"kind": "tray_full", "moves": [], "cells": sel_cells}
		var n := mini(free.size(), sel_cells.size())
		var moves := []
		for k in n:
			var src: int = sel_cells[k]
			cover[src] = NONE
			tray[free[k]] = sel_color
			moves.append({"from_cell": src, "to_slot": free[k], "color": sel_color})
		var color := sel_color
		sel_cells = sel_cells.slice(n)
		if sel_cells.is_empty():
			clear_selection()
		return {"kind": "to_tray", "moves": moves, "color": color, "left": sel_cells.size()}
	var c: int = tray[s]
	if c == NONE or (sel_kind == "tray" and sel_color == c):
		if has_selection():
			clear_selection()
			return {"kind": "deselect", "moves": []}
		return {"kind": "none", "moves": []}
	clear_selection()
	sel_kind = "tray"
	sel_color = c
	return {"kind": "select_tray", "moves": [], "slots": tray_slots_of(c), "color": c}


func _dist(j: int, origin: Vector2) -> float:
	return Vector2(level.cell_x(j), level.cell_y(j)).distance_squared_to(origin)


# --- persistence ---------------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"filled": Marshalls.raw_to_base64(filled), "cover": Array(cover), "tray": Array(tray)}


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
	for c in tr:
		if int(c) < NONE or int(c) >= level.color_count():
			return false
	filled = f
	cover = PackedInt32Array(cv)
	tray.fill(NONE)
	for k in tr.size():          # older saves stored only the occupied slots, packed at the front
		tray[k] = int(tr[k])
	clear_selection()
	return true
