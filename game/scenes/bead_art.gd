# Shared bead drawing (GS-7.4 limits: highlight only in the upper-left quadrant, shadow only at r > 0.65).
extends RefCounted


static func bead(ci: CanvasItem, mid: Vector2, radius: float, col: Color, alpha := 1.0) -> void:
	ci.draw_circle(mid, radius, Color(col, alpha))
	ci.draw_arc(mid, radius * 0.84, 0, TAU, 24, Color(col.darkened(0.25), alpha), maxf(1.0, radius * 0.16))
	ci.draw_circle(mid + Vector2(-0.33, -0.33) * radius, radius * 0.18, Color(col.lightened(0.5), alpha * 0.9))


# Empty placeholder waiting for a bead of `col`.
static func hollow(ci: CanvasItem, mid: Vector2, radius: float, col: Color) -> void:
	ci.draw_circle(mid, radius * 0.92, Color(col.lerp(Color.WHITE, 0.72), 0.85))
	ci.draw_arc(mid, radius * 0.8, 0, TAU, 24, Color(col.darkened(0.1), 0.35), maxf(1.0, radius * 0.12))
