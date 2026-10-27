# Shared bead drawing (GS-7.4 limits: highlight only in the upper-left quadrant, shadow only at r > 0.65).
extends RefCounted


static func bead(ci: CanvasItem, mid: Vector2, radius: float, col: Color, alpha := 1.0) -> void:
	ci.draw_circle(mid, radius, Color(col, alpha))
	ci.draw_arc(mid, radius * 0.84, 0, TAU, 24, Color(col.darkened(0.25), alpha), maxf(1.0, radius * 0.16))
	ci.draw_circle(mid + Vector2(-0.33, -0.33) * radius, radius * 0.18, Color(col.lightened(0.5), alpha * 0.9))


# Empty socket waiting for a bead of `col`: a recessed dimple with a ring of the target colour, so it reads as
# "empty" even next to pale beads.
static func hollow(ci: CanvasItem, mid: Vector2, radius: float, col: Color) -> void:
	ci.draw_circle(mid, radius * 0.86, Color(0, 0, 0, 0.07))
	ci.draw_arc(mid, radius * 0.66, 0, TAU, 20, col.darkened(0.08), maxf(1.2, radius * 0.3))
	ci.draw_arc(mid, radius * 0.86, PI * 1.05, PI * 1.75, 8, Color(0, 0, 0, 0.12), maxf(1.0, radius * 0.1))
