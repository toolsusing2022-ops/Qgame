# Board geometry helpers (gameplay spec GS-5.4, 5.9, 5.10).
extends RefCounted

const Config := preload("res://game/core/config.gd")


# Cell index under a point given in board-local units where one cell is cell_size wide.
# Cell (x, y) is the square [x, x+1) x [y, y+1): a point exactly on an edge belongs to the cell on the right or
# below. Returns -1 outside the grid.
static func cell_at(local: Vector2, cell_size: float, width: int, height: int) -> int:
	if cell_size <= 0.0:
		return -1
	var gx := floori(local.x / cell_size)
	var gy := floori(local.y / cell_size)
	if gx < 0 or gy < 0 or gx >= width or gy >= height:
		return -1
	return gy * width + gx


# Cell size (pt) that fits the whole grid into the area, with BOARD_SIDE_MARGIN on the left and right.
static func fit_cell_size(area: Vector2, width: int, height: int) -> float:
	var usable_w := maxf(area.x - 2.0 * Config.BOARD_SIDE_MARGIN, 1.0)
	return minf(usable_w / width, area.y / height)


static func clamp_cell_size(cell_size: float, fit: float) -> float:
	return clampf(cell_size, minf(fit, Config.MAX_ZOOM_CELL), maxf(fit, Config.MAX_ZOOM_CELL))


static func needs_zoom_to_place(cell_size: float) -> bool:
	return cell_size < Config.MIN_PLACE_CELL
