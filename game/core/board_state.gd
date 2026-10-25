# Gameplay state and rules of one level (gameplay spec sections 3, 4, 6, 9, 10). Pure logic: no nodes, no I/O,
# no audio. The play scene turns the returned results into feedback, saving and analytics.
extends RefCounted

const Config := preload("res://game/core/config.gd")

const NONE := -1

# Result kinds of tap() (GS-6.1 .. GS-6.5, GS-4.5).
const TAP_PLACED := "placed"
const TAP_WRONG := "wrong"
const TAP_ALREADY := "already"
const TAP_EMPTY := "empty"
const TAP_NO_SELECTION := "no_selection"
const TAP_LOCKED := "locked"

var level
var placed: PackedByteArray
var remaining: PackedInt32Array
var selected := NONE
var completed := false
var colors_ever_completed: PackedByteArray
var last_placed := NONE
var wrong_streak := 0
var find_visited: Array[Dictionary] = []


func _init(lvl) -> void:
	level = lvl
	placed.resize(level.cell_count())
	placed.fill(0)
	colors_ever_completed.resize(level.color_count())
	colors_ever_completed.fill(0)
	for c in level.color_count():
		find_visited.append({})
	_recompute_remaining()


# --- persistence hooks (used by restore, section 13) ---------------------------------------------------------

# Applies saved fields. Returns false (and leaves the state untouched) if the data breaks GS-3.1.
func apply_saved(saved_placed: PackedByteArray, saved_selected: int, saved_completed: bool,
		saved_colors_ever: PackedByteArray) -> bool:
	if saved_placed.size() != level.cell_count() or saved_colors_ever.size() != level.color_count():
		return false
	for i in saved_placed.size():
		if saved_placed[i] != 0 and level.cells[i] < 0:
			return false
	var backup := [placed, remaining, selected, completed, colors_ever_completed]
	placed = saved_placed.duplicate()
	colors_ever_completed = saved_colors_ever.duplicate()
	selected = saved_selected if saved_selected >= NONE and saved_selected < level.color_count() else NONE
	_recompute_remaining()
	completed = _total_remaining() == 0
	if completed != saved_completed:
		placed = backup[0]
		remaining = backup[1]
		selected = backup[2]
		completed = backup[3]
		colors_ever_completed = backup[4]
		return false
	# GS-13.7 (v0.4): add colours that are complete but missing from colors_ever_completed, without events.
	for c in level.color_count():
		if remaining[c] == 0:
			colors_ever_completed[c] = 1
	return check_invariants()


# --- level flow (section 4) ----------------------------------------------------------------------------------

func enter_level() -> void:
	last_placed = NONE
	wrong_streak = 0
	for c in find_visited.size():
		find_visited[c] = {}
	if completed:
		return
	if selected == NONE or is_color_done(selected):
		selected = default_color()


func leave_level() -> void:
	last_placed = NONE
	for c in find_visited.size():
		find_visited[c] = {}


# D-1: the unfinished colour with the most remaining cells; ties go to the lowest id.
func default_color() -> int:
	var best := NONE
	for c in level.color_count():
		if remaining[c] > 0 and (best == NONE or remaining[c] > remaining[best]):
			best = c
	return best


func select_color(c: int) -> Dictionary:
	if c < 0 or c >= level.color_count() or c == selected:
		return {"changed": false}
	selected = c
	wrong_streak = 0
	return {"changed": true}


# --- tap (section 6) -----------------------------------------------------------------------------------------

func tap(i: int) -> Dictionary:
	if completed:
		return {"kind": TAP_LOCKED, "cell": i}
	if not level.is_playable(i):
		return {"kind": TAP_EMPTY, "cell": i}
	if placed[i] != 0:
		return {"kind": TAP_ALREADY, "cell": i}
	if selected == NONE or is_color_done(selected):
		return {"kind": TAP_NO_SELECTION, "cell": i}
	var c: int = level.cells[i]
	if c != selected:
		wrong_streak += 1
		return {"kind": TAP_WRONG, "cell": i, "color": c,
			"show_hint": wrong_streak >= Config.WRONG_TAP_HINT_AFTER}
	placed[i] = 1
	remaining[c] -= 1
	last_placed = i
	wrong_streak = 0
	var result := {"kind": TAP_PLACED, "cell": i, "color": c, "color_completed": false,
		"occurrence": "", "level_completed": false}
	if remaining[c] == 0:
		result["color_completed"] = true
		result["occurrence"] = "repeat" if colors_ever_completed[c] != 0 else "first"
		colors_ever_completed[c] = 1
	if _total_remaining() == 0:
		completed = true
		last_placed = NONE
		result["level_completed"] = true
	return result


# --- undo (section 10) ---------------------------------------------------------------------------------------

func can_undo() -> bool:
	return last_placed != NONE and not completed


func undo() -> Dictionary:
	if not can_undo():
		return {"ok": false}
	var i := last_placed
	var c: int = level.cells[i]
	var was_done := remaining[c] == 0
	placed[i] = 0
	remaining[c] += 1
	last_placed = NONE
	wrong_streak = 0
	find_visited[c].erase(i)
	return {"ok": true, "cell": i, "color": c, "color_reopened": was_done}


# --- find (section 9) ----------------------------------------------------------------------------------------

func can_find() -> bool:
	return not completed and selected != NONE and not is_color_done(selected)


# view_center is in grid units (cell (x, y) spans [x, x+1) x [y, y+1)). in_view(i) tells whether cell i is visible.
func find_target(view_center: Vector2, in_view: Callable) -> int:
	if not can_find():
		return NONE
	var candidates := valid_cells(selected)
	var visited: Dictionary = find_visited[selected]
	var tier1 := PackedInt32Array()
	var tier2 := PackedInt32Array()
	for i in candidates:
		if not visited.has(i):
			tier2.append(i)
			if not in_view.call(i):
				tier1.append(i)
	var pool := tier1
	if pool.is_empty():
		pool = tier2
	if pool.is_empty():
		visited.clear()
		pool = candidates
	var best := NONE
	var best_d := INF
	for i in pool:
		var center := Vector2(level.cell_x(i) + 0.5, level.cell_y(i) + 0.5)
		var dist := center.distance_squared_to(view_center)
		if dist < best_d or (dist == best_d and i < best):
			best = i
			best_d = dist
	visited[best] = true
	return best


# --- queries -------------------------------------------------------------------------------------------------

func is_color_done(c: int) -> bool:
	return remaining[c] == 0


func is_valid_for(i: int, c: int) -> bool:
	return level.is_playable(i) and placed[i] == 0 and level.cells[i] == c


func valid_cells(c: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if c < 0:
		return out
	for i in level.cell_count():
		if level.cells[i] == c and placed[i] == 0:
			out.append(i)
	return out


# GS-3.1
func check_invariants() -> bool:
	var counted := PackedInt32Array()
	counted.resize(level.color_count())
	counted.fill(0)
	for i in level.cell_count():
		var c: int = level.cells[i]
		if placed[i] != 0 and c < 0:
			return false
		if c >= 0 and placed[i] == 0:
			counted[c] += 1
	for c in level.color_count():
		if counted[c] != remaining[c]:
			return false
		if remaining[c] == 0 and colors_ever_completed[c] == 0:
			return false
	return completed == (_total_remaining() == 0)


func _recompute_remaining() -> void:
	remaining.resize(level.color_count())
	remaining.fill(0)
	for i in level.cell_count():
		var c: int = level.cells[i]
		if c >= 0 and placed[i] == 0:
			remaining[c] += 1


func _total_remaining() -> int:
	var total := 0
	for r in remaining:
		total += r
	return total
