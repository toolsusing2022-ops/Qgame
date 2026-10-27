# Puzzle generator for the "Gỡ hạt" mode. Deterministic for a given (level, seed).
#
# 1. Holes: for a few colours, blob-shaped patches of their cells become empty placeholders.
# 2. Trays: part of the loose beads start in the trays (tray_start of the capacity), as in the reference video.
# 3. Covers: for every remaining hole of colour B, one bead of colour B is laid on top of a cell whose target is not B,
#    in blob-shaped patches. A share of the patches (hide_fraction) is laid over other colours' holes, so those
#    holes are hidden at first and the player has to park beads in the trays to uncover them.
# 4. Solvability: a greedy player (place into holes whenever possible, otherwise park the smallest cover cluster
#    in the trays) must finish within the tray capacity; otherwise retry with another seed and gentler parameters.
extends RefCounted

const SortState := preload("res://game/core/sort_state.gd")

const DEFAULTS := {"hole_fraction": 0.3, "min_patch": 6, "max_patch": 18, "max_cluster": 30, "hide_fraction": 0.9,
	"tray_start": 0.6}


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
		# Never empty a whole colour: some of it must stay visible as a hint. Skip crumbs (squeezed-in patches).
		if int(holes_per_color.get(c, 0)) + patch.size() > cells.size() * 0.6:
			continue
		if patch.size() < mini(int(p["min_patch"]), size) and guard < 300:
			continue
		for j in patch:
			st.filled[j] = 0
		holes_per_color[c] = int(holes_per_color.get(c, 0)) + patch.size()
		made += patch.size()
	# 2. some loose beads start in the trays (at most half of a colour's), one colour after another
	var in_tray := {}
	var slot := 0
	var tray_colors := holes_per_color.keys()
	tray_colors.sort()
	for k in range(tray_colors.size() - 1, 0, -1):      # deterministic shuffle
		var r := rng.randi_range(0, k)
		var tmp = tray_colors[k]
		tray_colors[k] = tray_colors[r]
		tray_colors[r] = tmp
	for c in tray_colors:
		var take := mini(int(holes_per_color[c]) / 2, int(SortState.CAPACITY * float(p["tray_start"])) - slot)
		for k in maxi(take, 0):
			st.tray[slot] = c
			slot += 1
		in_tray[c] = maxi(take, 0)
	# 3. covers: the remaining loose beads, laid in patches on cells of other colours
	for c in holes_per_color:
		var need: int = holes_per_color[c] - int(in_tray[c])
		var tries := 0
		while need > 0 and tries < 400:
			tries += 1
			var start := rng.randi_range(0, n - 1)
			var on_holes := rng.randf() < float(p["hide_fraction"])
			if on_holes:
				var hidden_ok := func(j: int) -> bool:
					return st.filled[j] == 0 and level.cells[j] != c and st.cover[j] == SortState.NONE
				for k in n:              # first free hole of another colour at or after the random start
					if hidden_ok.call((start + k) % n):
						start = (start + k) % n
						break
			if level.cells[start] < 0 or level.cells[start] == c or st.cover[start] != SortState.NONE:
				continue
			var size := mini(rng.randi_range(int(p["min_patch"]), int(p["max_patch"])), need)
			var patch := _blob(st, start, size, rng, func(j: int) -> bool:
				return (level.cells[j] >= 0 and level.cells[j] != c and st.cover[j] == SortState.NONE
					and (not on_holes or st.filled[j] == 0)))
			if patch.size() < mini(int(p["min_patch"]), need) and tries < 300:
				continue           # a crumb: one- or two-bead clusters make the game fiddly
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


# Greedy solver used as a solvability check (and for a hint). Mutates st; plays through the same two-tap API.
static func solve(st, max_steps := 5000) -> Dictionary:
	var steps := 0
	st.clear_selection()
	while not st.completed() and steps < max_steps:
		steps += 1
		var m := best_move(st)
		if m.is_empty():
			return {"solved": false, "steps": steps}
		if not play(st, m):
			return {"solved": false, "steps": steps}
	return {"solved": st.completed(), "steps": steps}


# Applies a move from best_move() as two taps. Returns false if the taps did not move anything.
static func play(st, m: Dictionary) -> bool:
	st.clear_selection()
	var r1: Dictionary = st.tap_cell(m["src"]) if m["src_kind"] == "cell" else st.tap_slot(m["src"])
	if r1["kind"] != "select" and r1["kind"] != "select_tray":
		return false
	var r2: Dictionary = st.tap_cell(m["dst"]) if m["dst_kind"] == "cell" else st.tap_slot(m["dst"])
	st.clear_selection()
	return not r2["moves"].is_empty()


# A good next move {src_kind, src, dst_kind, dst} ("cell" | "slot"), or {} if stuck:
#   1. tray beads into a visible hole of their colour
#   2. a cover cluster into a visible hole of its colour
#   3. the cover cluster that needs the least tray room into the trays
static func best_move(st) -> Dictionary:
	var n: int = st.level.cell_count()
	var hole_of := {}                      # colour -> some visible empty cell
	for i in n:
		if st.is_visible_empty(i) and not hole_of.has(st.level.cells[i]):
			hole_of[st.level.cells[i]] = i
	for s in SortState.CAPACITY:
		var c: int = st.tray[s]
		if c != SortState.NONE and hole_of.has(c):
			return {"src_kind": "slot", "src": s, "dst_kind": "cell", "dst": hole_of[c]}
	var best := -1
	var best_size := 1 << 30
	var seen := {}
	for i in n:
		if st.cover[i] == SortState.NONE or seen.has(i):
			continue
		var cells: PackedInt32Array = st.cover_cluster(i)
		for j in cells:
			seen[j] = true
		if hole_of.has(st.cover[i]):
			return {"src_kind": "cell", "src": i, "dst_kind": "cell", "dst": hole_of[st.cover[i]]}
		if cells.size() < best_size:
			best = i
			best_size = cells.size()
	var free: int = st.tray_free()
	if best < 0 or free == 0:
		return {}
	var first_free: int = st.tray.find(SortState.NONE)
	return {"src_kind": "cell", "src": best, "dst_kind": "slot", "dst": first_free}
