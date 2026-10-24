# Level schema v1

Contract between the Python content pipeline (`image_to_beadgrid.py`, `validate_level.py`) and the Godot game.
`validate_level.py` is the executable form of this document; if they disagree, fix one of them.

## Example

```json
{
  "schema_version": 1,
  "id": "squid_easy_01",
  "title": "Mực đỏ",
  "difficulty": "easy",
  "modes": ["journey", "zen"],
  "width": 3,
  "height": 2,
  "palette": [
    {"id": 0, "hex": "#2f86b8", "count": 2, "name": "water"},
    {"id": 1, "hex": "#e2553d", "count": 2},
    {"id": 2, "hex": "#f3dcd2", "count": 1}
  ],
  "cells": [0, 1, 2, -1, 0, 1],
  "mask":  [0, 1, 1,  0, 0, 1]
}
```

## Fields

| Field | Type | Rule |
|---|---|---|
| `schema_version` | int | Must be `1`. |
| `id` | string | Stable, `^[a-z0-9][a-z0-9_]*$`. Save data is keyed by it — never rename a shipped id. |
| `title` | string | Non-empty. |
| `difficulty` | string | `easy` \| `relax` \| `challenge`. |
| `modes` | string[] | Non-empty, no duplicates, subset of `journey`, `zen`. |
| `width`, `height` | int | 1..128. |
| `palette` | object[] | Non-empty. Entry `i` has `id == i`. |
| `palette[].hex` | string | `#rrggbb` (case-insensitive). No two entries share a hex. |
| `palette[].count` | int | Exact number of cells using this colour; must be > 0 (no unused colours). |
| `palette[].name` | string | Optional, for tooling/debug. |
| `cells` | int[] | Flat, row-major, length `width*height`. |
| `mask` | int[] | Optional. Same shape as `cells`; `1` = cell belongs to the approved subject, `0` = background. |

## Cell encoding (Python and Godot must agree)

- `cells[y * width + x]` is the cell at column `x`, row `y`; `(0, 0)` is top-left.
  Reverse: `x = i % width`, `y = i / width` (integer division).
- Value `>= 0` is a palette id, and the palette id is also its index in `palette`.
- Value `-1` means no bead at this position (not playable, not drawn). Every other negative number is invalid.
- Values are JSON integers. **Godot's `JSON` parses every number as `float`** — the loader must convert with `int()`
  (store as `PackedInt32Array`). The validator rejects non-integer values such as `1.0`, so the conversion is lossless.
- Colours: Python writes lowercase `#rrggbb`; Godot reads with `Color.html(hex)`.
- `mask` is only consumed by tooling (silhouette checks) for now; the game must not require it.

## Validator

```
python3 tools/validate_level.py content/levels/*.json            # exit 1 on any error
python3 tools/validate_level.py --strict content/levels/*.json   # warnings also fail
python3 -m unittest discover -s tools/tests                       # validator tests
```

Errors make a level unshippable: missing/invalid fields, wrong grid size, malformed hex, palette id not equal to its
index, cells referencing a colour not in the palette, non-integer/missing cell values, unused palette colours,
`count` mismatches, identical colours, invalid mask (wrong size, values other than 0/1, empty, or marking a `-1` cell),
duplicate JSON keys, NaN/Infinity.

Warnings need a human decision; the validator never merges or edits colours:

- `near_duplicate_color` — CIEDE2000 ΔE00 < 3: practically indistinguishable.
- `similar_color` — ΔE00 < 10: hard to tell apart on a small bead next to the tray swatch.
- `unknown_field`, `mask_full`.

Merging similar colours is a content decision made in the pipeline, checked against the subject's silhouette — never
merge on ΔE or cell count alone.
