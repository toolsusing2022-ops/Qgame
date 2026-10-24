#!/usr/bin/env python3
"""Converts a source image into a bead/pixel grid level definition for the game.

Usage:
    python3 image_to_beadgrid.py <source.png> <output.json> --id ID --title TITLE --difficulty easy|relax|challenge
        [--modes journey,zen] [--cols N] [--colors K] [--preview out.png]

Output follows level schema v1 (LEVEL_SCHEMA.md) and is validated before it is written.
"""
import argparse
import json
import sys
from pathlib import Path

from PIL import Image

from validate_level import DIFFICULTIES, EMPTY_CELL, MODES, SCHEMA_VERSION, hex_to_rgb, validate


def crop_to_content(im: Image.Image, bg_tolerance: int = 30) -> Image.Image:
    arr = im.convert("RGB")
    import numpy as np

    a = np.array(arr).astype(int)
    bg = a[2, 2]
    diff = np.abs(a - bg).sum(axis=2)
    mask = diff > bg_tolerance
    ys, xs = np.where(mask)
    y0, y1 = ys.min(), ys.max()
    x0, x1 = xs.min(), xs.max()
    return arr.crop((x0, y0, x1 + 1, y1 + 1))


def isolate_subject(im: Image.Image, warm_thresh: int = 70, dilate_px: int = 18) -> Image.Image:
    """Keeps only the largest warm-colored connected blob (the subject) and flattens
    everything else (background clutter like coral that shares the subject's hue) to
    a representative background color. Used to keep low-res tiers legible."""
    import numpy as np
    from collections import deque

    W, H = im.size
    N = 200
    small = im.resize((N, N), Image.Resampling.BOX)
    arr = np.array(small).astype(int)
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
    mask = (r - b) > warm_thresh

    visited = np.zeros_like(mask, dtype=bool)
    best_pts: list[tuple[int, int]] = []
    h, w = mask.shape
    for i in range(h):
        for j in range(w):
            if mask[i, j] and not visited[i, j]:
                q = deque([(i, j)])
                visited[i, j] = True
                pts = []
                while q:
                    y, x = q.popleft()
                    pts.append((y, x))
                    for dy, dx in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)]:
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not visited[ny, nx]:
                            visited[ny, nx] = True
                            q.append((ny, nx))
                if len(pts) > len(best_pts):
                    best_pts = pts

    subject = np.zeros((h, w), dtype=bool)
    for y, x in best_pts:
        subject[y, x] = True

    # fill small holes (eyes, sucker rings) and cover anti-aliased edges via dilation
    dilate_iters = max(1, round(dilate_px * N / W))
    for _ in range(dilate_iters):
        shifted = (
            subject
            | np.roll(subject, 1, axis=0)
            | np.roll(subject, -1, axis=0)
            | np.roll(subject, 1, axis=1)
            | np.roll(subject, -1, axis=1)
        )
        subject = shifted

    subject_full = np.array(
        Image.fromarray((subject * 255).astype("uint8")).resize((W, H), Image.Resampling.NEAREST)
    ) > 127

    full_arr = np.array(im).astype(int)
    cool = (full_arr[:, :, 0] - full_arr[:, :, 2]) <= 0
    if cool.sum() > 0:
        bg_color = full_arr[cool].mean(axis=0).astype("uint8")
    else:
        bg_color = np.array([40, 110, 160], dtype="uint8")

    out = np.array(im).copy()
    out[~subject_full] = bg_color
    return Image.fromarray(out)


def merge_small_colors(index_grid, palette, min_frac: float):
    """Merges palette colors below min_frac of total cells into their nearest
    remaining neighbor, so quantization noise (muddy anti-aliased edge colors)
    doesn't become its own playable color."""
    import numpy as np

    total = len(index_grid)
    counts = {}
    for idx in index_grid:
        counts[idx] = counts.get(idx, 0) + 1

    keep = {i for i, c in counts.items() if c / total >= min_frac}
    if not keep:
        keep = set(counts.keys())

    def nearest_keep(i):
        if i in keep:
            return i
        pi = np.array(palette[i])
        best, best_d = None, 1e18
        for k in keep:
            d = float(np.sum((pi - np.array(palette[k])) ** 2))
            if d < best_d:
                best, best_d = k, d
        return best

    remap_old = {i: nearest_keep(i) for i in counts}
    new_grid = [remap_old[i] for i in index_grid]
    return new_grid


def build_grid(
    source_path: str,
    cols: int,
    colors: int,
    manual_crop: tuple[int, int, int, int] | None = None,
    isolate: bool = False,
    min_color_frac: float = 0.0,
):
    im = Image.open(source_path).convert("RGB")
    if isolate:
        im = isolate_subject(im)
    if manual_crop:
        im = im.crop(manual_crop)
    else:
        im = crop_to_content(im)

    w, h = im.size
    rows = round(cols * h / w)

    small = im.resize((cols, rows), Image.Resampling.BOX)

    quant = small.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    palette_raw = quant.getpalette()[: colors * 3]
    palette = [tuple(palette_raw[i : i + 3]) for i in range(0, len(palette_raw), 3)]

    index_grid = list(quant.getdata())
    if min_color_frac > 0:
        index_grid = merge_small_colors(index_grid, palette, min_color_frac)
    grid = [index_grid[r * cols : (r + 1) * cols] for r in range(rows)]

    counts = [0] * colors
    for idx in index_grid:
        counts[idx] += 1

    used_ids = [i for i in range(colors) if counts[i] > 0]
    order = sorted(used_ids, key=lambda i: -counts[i])

    palette_entries = []
    for new_id, old_id in enumerate(order):
        r, g, b = palette[old_id]
        palette_entries.append(
            {
                "id": new_id,
                "hex": "#{:02x}{:02x}{:02x}".format(r, g, b),
                "count": counts[old_id],
            }
        )
    remap = {old_id: new_id for new_id, old_id in enumerate(order)}
    flat_cells = [remap[v] for row in grid for v in row]

    return {
        "width": cols,
        "height": rows,
        "palette": palette_entries,
        "cells": flat_cells,
    }, small


def render_preview(level: dict, cell_px: int = 20) -> Image.Image:
    width, height = level["width"], level["height"]
    palette = {p["id"]: p["hex"] for p in level["palette"]}
    out = Image.new("RGB", (width * cell_px, height * cell_px), "white")
    px = out.load()
    for i, color_id in enumerate(level["cells"]):
        if color_id == EMPTY_CELL:
            continue
        x, y = i % width, i // width
        rgb = hex_to_rgb(palette[color_id])
        for yy in range(cell_px):
            for xx in range(cell_px):
                px[x * cell_px + xx, y * cell_px + yy] = rgb
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("output")
    ap.add_argument("--cols", type=int, default=25)
    ap.add_argument("--colors", type=int, default=8)
    ap.add_argument("--preview")
    ap.add_argument("--crop", type=str, help="x0,y0,x1,y1")
    ap.add_argument("--isolate", action="store_true", help="isolate largest warm-colored subject from background clutter")
    ap.add_argument("--min-color-frac", type=float, default=0.0, help="merge palette colors smaller than this fraction of total cells into their nearest neighbor")
    ap.add_argument("--id", required=True, help="stable level id, e.g. squid_relax_01")
    ap.add_argument("--title", required=True)
    ap.add_argument("--difficulty", required=True, choices=DIFFICULTIES)
    ap.add_argument("--modes", default="journey,zen", help="comma-separated subset of: " + ",".join(MODES))
    args = ap.parse_args()

    manual_crop = None
    if args.crop:
        manual_crop = tuple(int(v) for v in args.crop.split(","))

    grid, _ = build_grid(args.source, args.cols, args.colors, manual_crop, args.isolate, args.min_color_frac)
    level = {
        "schema_version": SCHEMA_VERSION,
        "id": args.id,
        "title": args.title,
        "difficulty": args.difficulty,
        "modes": [m.strip() for m in args.modes.split(",") if m.strip()],
        **grid,
    }

    issues = validate(level)
    for issue in issues:
        print(f"  {issue}")
    if any(i.severity == "error" for i in issues):
        print(f"not writing {args.output}: level failed validation", file=sys.stderr)
        sys.exit(1)

    Path(args.output).write_text(json.dumps(level, ensure_ascii=False), encoding="utf-8")
    print(f"wrote {args.output}: {level['width']}x{level['height']} cells, {len(level['palette'])} colors")
    for p in level["palette"]:
        print(f"  color {p['id']}: {p['hex']} x{p['count']}")

    if args.preview:
        render_preview(level).save(args.preview)
        print(f"wrote preview {args.preview}")


if __name__ == "__main__":
    main()
