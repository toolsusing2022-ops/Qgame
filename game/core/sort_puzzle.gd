# Puzzle generator for the "Gỡ hạt" mode. Deterministic for a given (level, seed).
#
# 1. Holes: for a few colours, blob-shaped patches of their cells become empty placeholders.
# 2. Covers: for every hole of colour B, one bead of colour B is laid on top of a cell whose target is not B,
#    in blob-shaped patches (which may sit on other colours' holes, so some holes are hidden at first).
# 3. Solvability: a greedy player (fill whenever possible, otherwise lift the cluster that needs the least tray
#    room) must finish within the tray capacity; otherwise retry with another seed and gentler parameters.
extends RefCounted

const SortState := preload("res://game/core/sort_state.gd")

const DEFAULTS := {"hole_fraction": 0.25, "min_patch": 4, "max_patch": 14, "max_cluster": 24}


static func generate(level, seed_value: int, params := {}) -> Dictionary:
	var p := DEFAULTS.duplicate()
	p.merge(params, true)
	for attempt in 12:
		var st = _build(level, seed_value + attempt * 7919, p)
		if st != null and st.check_invariants() and solve(st.duplicate_state()).get("solved", false):
			return {"state": st, "seed": seed_value + attempt * 7919, "attempts": attempt + 1}
		p["hole_fraction"] = maxf(0.05, p["hole_fraction"] * 0.8)
		p["max_cluster"] = maxi(8, int(p["max_cluster"] * 0.8))
	return {"state": SortState.new(level), "seed": seed_value, "attempts": 12}   # trivially solved fallback


static func _build(level, seed_value: int, p: Dictionary):
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st = SortState.new(level)
	var n: int = level.cell_count()
	var by_color := {}
	for i in n:
		var c: int = level.cells[i]
		if c >= 0:
			if not by_color.has(c):
				by_color[c] = []
			by_color[c].append(i)
	var target_holes := int(st.playable_count() * float(p["hole_fraction"]))
	if target_holes == 0:
		return st
	# 1. holes, spread over colours proportionally to their size (at least one patch for big colours)
	var holes_per_color := {}
	var colors := by_color.keys()
	colors.sort()
	var made := 0
	var guard := 0
	while made < target_holes and guard < 400:
		guard += 1
		var c: int = colors[rng.randi_range(0, colors.size() - 1)]
		var cells: Array = by_color[c]
		if cells.size() < 6:
			continue
		var start: int = cells[rng.randi_range(0, cells.size() - 1)]
		if st.filled[start] == 0:
			continue
		var size := mini(rng.randi_range(int(p["min_patch"]), int(p["max_patch"])), target_holes - made)
		var patch := _blob(st, start, size, rng, func(j: int) -> bool:
			return level.cells[j] == c and st.filled[j] == 1)
		# Never empty a whole colour: some of it must stay visible as a hint.
		if int(holes_per_color.get(c, 0)) + patch.size() > cells.size() * 0.6:
			continue
		for j in patch:
			st.filled[j] = 0
		holes_per_color[c] = int(holes_per_color.get(c, 0)) + patch.size()
		made += patch.size()
	# 2. covers: one loose bead per hole, laid in patches on cells of other colours
	for c in holes_per_color:
		var need: int = holes_per_color[c]
		var tries := 0
		while need > 0 and tries < 400:
			tries += 1
			var start := rng.randi_range(0, n - 1)
			if level.cells[start] < 0 or level.cells[start] == c or st.cover[start] != SortState.NONE:
				continue
			var size := mini(rng.randi_range(int(p["min_patch"]), int(p["max_patch"])), need)
			var patch := _blob(st, start, size, rng, func(j: int) -> bool:
				return level.cells[j] >= 0 and level.cells[j] != c and st.cover[j] == SortState.NONE)
			for j in patch:
				st.cover[j] = c
			need -= patch.size()
		if need > 0:
			return null
	# Clusters must fit the trays comfortably.
	for i in n:
		if st.cover[i] != SortState.NONE and st.cover_cluster(i).size() > int(p["max_cluster"]):
			return null
	return st


# Random 4-connected blob of up to `size` cells grown from `start` through cells accepted by `ok`.
static func _blob(st, start: int, size: int, rng: RandomNumberGenerator, ok: Callable) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not ok.call(start):
		return out
	var lvl = st.level
	var seen := {start: true}
	var frontier := [start]
	while not frontier.is_empty() and out.size() < size:
		var k := rng.randi_range(0, frontier.size() - 1)
		var i: int = frontier[k]
		frontier.remove_at(k)
		out.append(i)
		var x: int = lvl.cell_x(i)
		var y: int = lvl.cell_y(i)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx < 0 or ny < 0 or nx >= lvl.width or ny >= lvl.height:
				continue
			var j: int = ny * lvl.width + nx
			if not seen.has(j) and ok.call(j):
				seen[j] = true
				frontier.append(j)
	return out


# Greedy solver used as a solvability check (and for a hint). Mutates st.
static func solve(st, max_steps := 5000) -> Dictionary:
	var steps := 0
	while not st.completed() and steps < max_steps:
		steps += 1
		var move := best_move(st)
		if move < 0:
			return {"solved": false, "steps": steps}
		var r: Dictionary = st.tap(move)
		if r["kind"] != "lift" and r["kind"] != "fill":
			return {"solved": false, "steps": steps}
	return {"solved": st.completed(), "steps": steps}


# A good next tap: any fill that can use tray beads, else the lift needing the least tray room. -1 if stuck.
static func best_move(st) -> int:
	var n: int = st.level.cell_count()
	for i in n:
		if st.is_visible_empty(i) and st.tray_count(st.level.cells[i]) > 0:
			return i
	var best := -1
	var best_overflow := 1 << 30
	var seen := {}
	for i in n:
		if st.cover[i] == SortState.NONE or seen.has(i):
			continue
		var cells: PackedInt32Array = st.cover_cluster(i)
		for j in cells:
			seen[j] = true
		var color: int = st.cover[i]
		var holes := 0
		for j in n:
			if st.is_visible_empty(j) and st.level.cells[j] == color:
				holes += 1
		var overflow := maxi(0, cells.size() - holes)
		if overflow <= st.tray_free() and overflow < best_overflow:
			best = i
			best_overflow = overflow
	return best
