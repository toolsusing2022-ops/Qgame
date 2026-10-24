#!/usr/bin/env python3
"""Level schema v1 validator. The contract itself is documented in LEVEL_SCHEMA.md.

Usage:
    python3 validate_level.py <level.json>... [--strict]

Exit code is 1 if any file has errors (or warnings, with --strict).
"""
import argparse
import json
import math
import re
import sys
from dataclasses import dataclass

SCHEMA_VERSION = 1
EMPTY_CELL = -1
DIFFICULTIES = ("easy", "relax", "challenge")
MODES = ("journey", "zen")
MAX_SIDE = 128

REQUIRED_FIELDS = ("schema_version", "id", "title", "difficulty", "modes", "width", "height", "palette", "cells")
OPTIONAL_FIELDS = ("mask",)
PALETTE_REQUIRED = ("id", "hex", "count")
PALETTE_OPTIONAL = ("name",)

ID_RE = re.compile(r"^[a-z0-9][a-z0-9_]*$")
HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")

# CIEDE2000 thresholds. ~1 is a just-noticeable difference side by side; beads are
# small, seen one at a time against a tray swatch, so the bar for "clearly different"
# is set much higher than print/colour-management tolerances.
NEAR_DUPLICATE_DE = 3.0
SIMILAR_DE = 10.0

MAX_POSITIONS_SHOWN = 5


@dataclass(frozen=True)
class Issue:
    severity: str  # "error" | "warning"
    code: str
    message: str

    def __str__(self):
        return f"[{self.severity.upper()}] {self.code}: {self.message}"


def is_int(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def hex_to_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def srgb_to_lab(rgb: tuple[int, int, int]) -> tuple[float, float, float]:
    """sRGB (0-255) -> CIE L*a*b*, D65 white point."""

    def lin(c):
        c = c / 255.0
        return ((c + 0.055) / 1.055) ** 2.4 if c > 0.04045 else c / 12.92

    r, g, b = (lin(c) for c in rgb)
    x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
    y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
    z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883

    def f(t):
        return t ** (1 / 3) if t > (6 / 29) ** 3 else t / (3 * (6 / 29) ** 2) + 4 / 29

    fx, fy, fz = f(x), f(y), f(z)
    return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)


def ciede2000(lab1, lab2) -> float:
    L1, a1, b1 = lab1
    L2, a2, b2 = lab2
    c_bar = (math.hypot(a1, b1) + math.hypot(a2, b2)) / 2
    g = 0.5 * (1 - math.sqrt(c_bar**7 / (c_bar**7 + 25**7)))
    a1p, a2p = (1 + g) * a1, (1 + g) * a2
    c1p, c2p = math.hypot(a1p, b1), math.hypot(a2p, b2)
    h1p = math.degrees(math.atan2(b1, a1p)) % 360 if c1p else 0.0
    h2p = math.degrees(math.atan2(b2, a2p)) % 360 if c2p else 0.0

    dl = L2 - L1
    dc = c2p - c1p
    if c1p * c2p == 0:
        dh = 0.0
    else:
        dh = h2p - h1p
        if dh > 180:
            dh -= 360
        elif dh < -180:
            dh += 360
    d_big_h = 2 * math.sqrt(c1p * c2p) * math.sin(math.radians(dh / 2))

    l_bar = (L1 + L2) / 2
    cp_bar = (c1p + c2p) / 2
    if c1p * c2p == 0:
        h_bar = h1p + h2p
    elif abs(h1p - h2p) <= 180:
        h_bar = (h1p + h2p) / 2
    elif h1p + h2p < 360:
        h_bar = (h1p + h2p + 360) / 2
    else:
        h_bar = (h1p + h2p - 360) / 2

    t = (
        1
        - 0.17 * math.cos(math.radians(h_bar - 30))
        + 0.24 * math.cos(math.radians(2 * h_bar))
        + 0.32 * math.cos(math.radians(3 * h_bar + 6))
        - 0.20 * math.cos(math.radians(4 * h_bar - 63))
    )
    d_theta = 30 * math.exp(-(((h_bar - 275) / 25) ** 2))
    r_c = 2 * math.sqrt(cp_bar**7 / (cp_bar**7 + 25**7))
    s_l = 1 + 0.015 * (l_bar - 50) ** 2 / math.sqrt(20 + (l_bar - 50) ** 2)
    s_c = 1 + 0.045 * cp_bar
    s_h = 1 + 0.015 * cp_bar * t
    r_t = -math.sin(math.radians(2 * d_theta)) * r_c
    return math.sqrt(
        (dl / s_l) ** 2 + (dc / s_c) ** 2 + (d_big_h / s_h) ** 2 + r_t * (dc / s_c) * (d_big_h / s_h)
    )


def delta_e_hex(h1: str, h2: str) -> float:
    return ciede2000(srgb_to_lab(hex_to_rgb(h1)), srgb_to_lab(hex_to_rgb(h2)))


def _positions(indices, width):
    shown = ", ".join(f"(x={i % width}, y={i // width})" for i in indices[:MAX_POSITIONS_SHOWN])
    more = f" … và {len(indices) - MAX_POSITIONS_SHOWN} ô khác" if len(indices) > MAX_POSITIONS_SHOWN else ""
    return shown + more


def validate(data) -> list[Issue]:
    issues: list[Issue] = []

    def err(code, msg):
        issues.append(Issue("error", code, msg))

    def warn(code, msg):
        issues.append(Issue("warning", code, msg))

    if not isinstance(data, dict):
        err("bad_type", f"gốc của level phải là object JSON, nhận được {type(data).__name__}")
        return issues

    if ("cols" in data or "rows" in data) and "width" not in data:
        err("legacy_format", "định dạng cũ (cols/rows, cells 2D) — cần chuyển sang schema v1 (width/height, cells phẳng)")
    for k in REQUIRED_FIELDS:
        if k not in data:
            err("missing_field", f"thiếu trường bắt buộc '{k}'")
    for k in data:
        if k not in REQUIRED_FIELDS and k not in OPTIONAL_FIELDS:
            warn("unknown_field", f"trường không có trong schema v1: '{k}'")

    # --- metadata
    if "schema_version" in data and not (is_int(data["schema_version"]) and data["schema_version"] == SCHEMA_VERSION):
        err("bad_schema_version", f"schema_version phải là {SCHEMA_VERSION}, nhận được {data['schema_version']!r}")
    if "id" in data and not (isinstance(data["id"], str) and ID_RE.match(data["id"])):
        err("bad_id", f"id phải khớp {ID_RE.pattern} (chữ thường, số, gạch dưới), nhận được {data['id']!r}")
    if "title" in data and not (isinstance(data["title"], str) and data["title"].strip()):
        err("bad_title", "title phải là chuỗi không rỗng")
    if "difficulty" in data and data["difficulty"] not in DIFFICULTIES:
        err("bad_difficulty", f"difficulty phải là một trong {DIFFICULTIES}, nhận được {data['difficulty']!r}")
    if "modes" in data:
        modes = data["modes"]
        if not isinstance(modes, list) or not modes:
            err("bad_modes", f"modes phải là mảng không rỗng con của {MODES}")
        else:
            bad = [m for m in modes if m not in MODES]
            if bad:
                err("bad_modes", f"mode không hợp lệ {bad!r}; cho phép {MODES}")
            if len(set(map(str, modes))) != len(modes):
                err("bad_modes", "modes có phần tử trùng lặp")

    # --- grid size
    size_ok = True
    for k in ("width", "height"):
        if k in data:
            v = data[k]
            if not (is_int(v) and 1 <= v <= MAX_SIDE):
                err("grid_size", f"{k} phải là số nguyên 1..{MAX_SIDE}, nhận được {v!r}")
                size_ok = False
        else:
            size_ok = False
    width = data.get("width") if size_ok else None
    total = data["width"] * data["height"] if size_ok else None

    # --- palette
    palette_ok = False
    palette_hex: dict[int, str] = {}
    if "palette" in data:
        pal = data["palette"]
        if not isinstance(pal, list) or not pal:
            err("bad_palette", "palette phải là mảng không rỗng")
        else:
            palette_ok = True
            for i, entry in enumerate(pal):
                where = f"palette[{i}]"
                if not isinstance(entry, dict):
                    err("bad_palette", f"{where} phải là object")
                    palette_ok = False
                    continue
                for k in PALETTE_REQUIRED:
                    if k not in entry:
                        err("missing_field", f"{where} thiếu trường '{k}'")
                        palette_ok = False
                for k in entry:
                    if k not in PALETTE_REQUIRED and k not in PALETTE_OPTIONAL:
                        warn("unknown_field", f"{where} có trường lạ '{k}'")
                if "id" in entry and not (is_int(entry["id"]) and entry["id"] == i):
                    err("palette_id", f"{where}.id phải bằng vị trí trong mảng ({i}), nhận được {entry['id']!r}")
                    palette_ok = False
                if "hex" in entry:
                    if isinstance(entry["hex"], str) and HEX_RE.match(entry["hex"]):
                        palette_hex[i] = entry["hex"].lower()
                    else:
                        err("bad_hex", f"{where}.hex phải có dạng #rrggbb, nhận được {entry['hex']!r}")
                        palette_ok = False
                if "count" in entry and not (is_int(entry["count"]) and entry["count"] >= 0):
                    err("bad_count", f"{where}.count phải là số nguyên ≥ 0, nhận được {entry['count']!r}")
                    palette_ok = False

            ids = sorted(palette_hex)
            for ai, a in enumerate(ids):
                for b in ids[ai + 1 :]:
                    ha, hb = palette_hex[a], palette_hex[b]
                    if ha == hb:
                        err("duplicate_color", f"màu {a} và {b} cùng mã {ha}")
                        continue
                    de = delta_e_hex(ha, hb)
                    if de < NEAR_DUPLICATE_DE:
                        warn("near_duplicate_color", f"màu {a} {ha} và {b} {hb} gần như không phân biệt được (ΔE00={de:.1f} < {NEAR_DUPLICATE_DE})")
                    elif de < SIMILAR_DE:
                        warn("similar_color", f"màu {a} {ha} và {b} {hb} khó phân biệt trên hạt nhỏ (ΔE00={de:.1f} < {SIMILAR_DE})")

    # --- cells
    cells_ok = False
    cells = data.get("cells")
    if "cells" in data:
        if not isinstance(cells, list):
            err("bad_cells", f"cells phải là mảng số nguyên, nhận được {type(cells).__name__}")
        elif cells and all(isinstance(r, list) for r in cells):
            err("cells_not_flat", "cells là mảng 2D — schema v1 yêu cầu mảng phẳng theo hàng (index = y*width + x)")
        elif total is not None and len(cells) != total:
            err("grid_size", f"cells có {len(cells)} phần tử, cần width*height = {total}")
        elif total is not None:
            bad_value = [i for i, v in enumerate(cells) if not is_int(v)]
            if bad_value:
                err("bad_cell_value", f"{len(bad_value)} ô thiếu dữ liệu hoặc không phải số nguyên: {_positions(bad_value, width)}")
            else:
                cells_ok = True
                if all(v == EMPTY_CELL for v in cells):
                    err("no_playable_cells", "không có ô nào để đính")
                if palette_ok:
                    unknown = [i for i, v in enumerate(cells) if v != EMPTY_CELL and v not in palette_hex]
                    if unknown:
                        vals = sorted({cells[i] for i in unknown})
                        err("unknown_color", f"{len(unknown)} ô tham chiếu mã màu không có trong palette {vals}: {_positions(unknown, width)}")

    if cells_ok and palette_ok:
        actual = {i: 0 for i in palette_hex}
        for v in cells:
            if v in actual:
                actual[v] += 1
        for i, entry in enumerate(data["palette"]):
            if actual.get(i, 0) == 0:
                err("unused_color", f"màu {i} {palette_hex.get(i)} có trong palette nhưng không ô nào dùng")
            elif entry["count"] != actual[i]:
                err("count_mismatch", f"palette[{i}].count = {entry['count']} nhưng có {actual[i]} ô dùng màu {i}")

    # --- optional subject mask
    if "mask" in data:
        mask = data["mask"]
        if not isinstance(mask, list):
            err("mask_type", f"mask phải là mảng 0/1, nhận được {type(mask).__name__}")
        elif total is not None and len(mask) != total:
            err("mask_size", f"mask có {len(mask)} phần tử, cần width*height = {total}")
        elif total is not None:
            bad = [i for i, v in enumerate(mask) if not (is_int(v) and v in (0, 1))]
            if bad:
                err("mask_value", f"{len(bad)} phần tử mask không phải 0/1: {_positions(bad, width)}")
            else:
                if not any(mask):
                    err("mask_empty", "mask không đánh dấu ô nào thuộc chủ thể")
                elif all(mask):
                    warn("mask_full", "mask đánh dấu toàn bộ lưới là chủ thể — có thể bỏ mask")
                if cells_ok:
                    on_empty = [i for i, v in enumerate(mask) if v == 1 and cells[i] == EMPTY_CELL]
                    if on_empty:
                        err("mask_on_empty", f"{len(on_empty)} ô chủ thể nằm trên ô trống: {_positions(on_empty, width)}")

    return issues


def _reject_duplicate_keys(pairs):
    seen = {}
    for k, v in pairs:
        if k in seen:
            raise ValueError(f"khoá JSON bị trùng: '{k}'")
        seen[k] = v
    return seen


def _reject_constant(name):
    raise ValueError(f"giá trị JSON không hợp lệ: {name}")


def load_level(path: str):
    with open(path, encoding="utf-8") as f:
        return json.load(f, object_pairs_hook=_reject_duplicate_keys, parse_constant=_reject_constant)


def validate_file(path: str) -> list[Issue]:
    try:
        data = load_level(path)
    except (OSError, ValueError) as e:
        return [Issue("error", "invalid_json", str(e))]
    return validate(data)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Validate level JSON against schema v1.")
    ap.add_argument("files", nargs="+")
    ap.add_argument("--strict", action="store_true", help="treat warnings as failures")
    args = ap.parse_args(argv)

    failed = 0
    for path in args.files:
        issues = validate_file(path)
        errors = [i for i in issues if i.severity == "error"]
        warnings = [i for i in issues if i.severity == "warning"]
        bad = bool(errors) or (args.strict and bool(warnings))
        failed += bad
        print(f"{'FAIL' if bad else 'OK  '} {path}  ({len(errors)} lỗi, {len(warnings)} cảnh báo)")
        for i in issues:
            print(f"     {i}")
    print(f"\n{len(args.files) - failed}/{len(args.files)} file hợp lệ")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
