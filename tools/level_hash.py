#!/usr/bin/env python3
"""Canonical level fingerprints (gameplay spec GS-13.1).

layout_hash  = sha256("pbart-layout-1|w=<w>|h=<h>|n=<colours>|cells=<c0>,<c1>,...")
content_hash = sha256("pbart-content-1|schema=<v>|w=<w>|h=<h>|palette=<id>:<hex>,...|cells=<c0>,...")

Integers are plain ASCII decimal, hex is lowercase "#rrggbb", palette is ordered by id,
no spaces or newlines. count, name, mask, title, id, difficulty and modes are not hashed.
The Godot side (game/core/level_hash.gd) must produce identical strings.

Usage:
    python3 level_hash.py <level.json>...
"""
import hashlib
import json
import sys


def _cells_str(cells) -> str:
    return ",".join(str(int(v)) for v in cells)


def _palette_sorted(data):
    return sorted(data["palette"], key=lambda e: int(e["id"]))


def layout_string(data) -> str:
    return (
        f"pbart-layout-1|w={int(data['width'])}|h={int(data['height'])}"
        f"|n={len(data['palette'])}|cells={_cells_str(data['cells'])}"
    )


def content_string(data) -> str:
    palette = ",".join(f"{int(e['id'])}:{e['hex'].lower()}" for e in _palette_sorted(data))
    return (
        f"pbart-content-1|schema={int(data['schema_version'])}|w={int(data['width'])}|h={int(data['height'])}"
        f"|palette={palette}|cells={_cells_str(data['cells'])}"
    )


def _sha256(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def layout_hash(data) -> str:
    return _sha256(layout_string(data))


def content_hash(data) -> str:
    return _sha256(content_string(data))


def main(argv=None) -> int:
    paths = sys.argv[1:] if argv is None else argv
    if not paths:
        print(__doc__.strip().splitlines()[-1].strip())
        return 2
    for path in paths:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        print(f"{path}\n  layout_hash  {layout_hash(data)}\n  content_hash {content_hash(data)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
