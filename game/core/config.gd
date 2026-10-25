# Gameplay parameters (gameplay spec section 0.2). All values are defaults to be tuned on a real iPhone (D-2).
extends RefCounted

const TAP_SLOP := 10.0                  # pt
const TAP_MAX_MS := 500
const MULTI_TOUCH_COOLDOWN_MS := 120
const NUMBER_VISIBLE_CELL := 18.0       # pt
const MIN_PLACE_CELL := 24.0            # pt
const PLACE_ZOOM_CELL := 32.0           # pt
const MAX_ZOOM_CELL := 72.0             # pt
const EDGE_GUARD := 0.0                 # pt, off
const WRONG_TAP_HINT_AFTER := 3
const SFX_VOICES_MAX := 4
const HAPTIC_MIN_INTERVAL_MS := 40
const FIND_ANIM_MS := 300
const AUTO_SWITCH_COLOR := false        # hypothesis H2
const SNAP_TO_NEAREST := false          # hypothesis H1

const BOARD_SIDE_MARGIN := 16.0         # pt

# Saving and events (sections 12-14, spec v0.4 .. v0.4.9).
const SAVE_VERSION := 1
const PALETTE_RECOLOR_MAX_DE := 20.0
const OUTBOX_RETRY_MIN_INTERVAL_S := 60
const SAVE_BLOCK_AFTER_FAILURES := 3
const SAVE_BLOCKED_RETRY_INTERVAL_S := 30


# Returns an empty array when the ordering constraint of section 0.2 holds (TC-5.23).
static func constraint_errors(number_visible := NUMBER_VISIBLE_CELL, min_place := MIN_PLACE_CELL,
		place_zoom := PLACE_ZOOM_CELL, max_zoom := MAX_ZOOM_CELL) -> PackedStringArray:
	var errors := PackedStringArray()
	if number_visible > min_place:
		errors.append("NUMBER_VISIBLE_CELL > MIN_PLACE_CELL")
	if min_place > place_zoom:
		errors.append("MIN_PLACE_CELL > PLACE_ZOOM_CELL")
	if place_zoom > max_zoom:
		errors.append("PLACE_ZOOM_CELL > MAX_ZOOM_CELL")
	return errors
