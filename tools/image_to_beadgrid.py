#!/usr/bin/env python3
"""Converts a source image into a bead/pixel grid level definition for the game.

Usage (new levels — approved subject mask + designed palette):
    python3 image_to_beadgrid.py <source> <output.json> --mask MASK.png --palette PALETTE.json --cols N
        --id ID --title TITLE --difficulty easy|relax|challenge [--modes journey,zen]
        [--crop-to-mask MARGIN] [--subject-threshold 0.5] [--preview review.png] [--report report.txt]

Legacy usage (median-cut, no mask) is kept only to reproduce old levels: --colors K [--isolate].

Output follows level schema v1 (LEVEL_SCHEMA.md) and is validated before it is written.
"""
import argparse
import json
import sys
from pathlib import Path

from PIL import Image

from validate_level import DIFFICULTIES, EMPTY_CELL, HEX_RE, MODES, SCHEMA_VERSION, hex_to_rgb, validate


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


ROLES = ("subject", "background")
SAMPLES_PER_CELL = 12


def load_palette_spec(path: str) -> list[dict]:
    """Palette spec: {"colors": [{"name", "hex", "role": "subject"|"background",
    "min_share"?, "preserve_min_area"?}]}.
    min_share lets a small but meaningful colour (pupil, mouth) win a cell when it covers at
    least that share of the cell's subject pixels, instead of losing to the majority colour.
    preserve_min_area (source pixels, subject colours only) guarantees every connected region of
    that colour at least that large keeps one cell, even when it straddles several cells.
    preserve_regions ([[x0, y0, x1, y1], ...], source pixels) limits that guarantee to regions
    overlapping designer-marked boxes (e.g. the eyes and the mouth)."""
    with open(path, encoding="utf-8") as f:
        spec = json.load(f)
    colors = spec.get("colors") if isinstance(spec, dict) else None
    if not isinstance(colors, list) or not colors:
        raise ValueError(f"{path}: cần object có mảng 'colors' không rỗng")
    names, hexes = set(), set()
    for i, c in enumerate(colors):
        where = f"{path}: colors[{i}]"
        if not isinstance(c, dict):
            raise ValueError(f"{where} phải là object")
        unknown = set(c) - {"name", "hex", "role", "min_share", "preserve_min_area", "preserve_regions"}
        if unknown:
            raise ValueError(f"{where} có trường lạ {sorted(unknown)}")
        name, hx, role = c.get("name"), c.get("hex"), c.get("role")
        if not isinstance(name, str) or not name or name in names:
            raise ValueError(f"{where}.name phải là chuỗi không rỗng và không trùng")
        if not isinstance(hx, str) or not HEX_RE.match(hx) or hx.lower() in hexes:
            raise ValueError(f"{where}.hex phải có dạng #rrggbb và không trùng")
        if role not in ROLES:
            raise ValueError(f"{where}.role phải là một trong {ROLES}")
        ms = c.get("min_share")
        if ms is not None and not (isinstance(ms, (int, float)) and not isinstance(ms, bool) and 0 < ms <= 1):
            raise ValueError(f"{where}.min_share phải trong (0, 1]")
        pa = c.get("preserve_min_area")
        if pa is not None:
            if not (isinstance(pa, (int, float)) and not isinstance(pa, bool) and pa > 0):
                raise ValueError(f"{where}.preserve_min_area phải là số > 0 (pixel ảnh nguồn)")
            if role != "subject":
                raise ValueError(f"{where}.preserve_min_area chỉ dùng cho màu role 'subject'")
        regions = c.get("preserve_regions")
        if regions is not None:
            if pa is None:
                raise ValueError(f"{where}.preserve_regions cần đi kèm preserve_min_area")
            ok = isinstance(regions, list) and regions and all(
                isinstance(b, list) and len(b) == 4 and all(isinstance(v, int) and not isinstance(v, bool) for v in b)
                and b[0] < b[2] and b[1] < b[3]
                for b in regions
            )
            if not ok:
                raise ValueError(f"{where}.preserve_regions phải là mảng các hộp [x0, y0, x1, y1] (pixel ảnh nguồn)")
        names.add(name)
        hexes.add(hx.lower())
    for role in ROLES:
        if not any(c["role"] == role for c in colors):
            raise ValueError(f"{path}: palette cần ít nhất một màu role '{role}'")
    return [{**c, "hex": c["hex"].lower()} for c in colors]


def _lab_array(rgb: "np.ndarray") -> "np.ndarray":
    import numpy as np

    c = rgb.astype(float) / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    m = np.array([[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750], [0.0193339, 0.1191920, 0.9503041]])
    xyz = (c @ m.T) / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > (6 / 29) ** 3, np.cbrt(xyz), xyz / (3 * (6 / 29) ** 2) + 4 / 29)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], axis=-1)


def build_grid_from_mask(
    source_path: str,
    mask_path: str,
    cols: int,
    palette_spec: list[dict],
    crop_margin: float | None = None,
    subject_threshold: float = 0.5,
    keep_tips: float | None = None,
):
    """Builds a grid where subject cells (by the approved mask) may only use subject colours and
    background cells only background colours, so background that shares the subject's hue (coral)
    can never become part of the silhouette. Each cell takes the most common palette colour among
    its pixels of the matching role (with optional min_share priority). No colours are merged."""
    from collections import Counter

    import numpy as np

    from level_review import _components, _dilate

    im = Image.open(source_path).convert("RGB")
    mask_im = Image.open(mask_path).convert("L")
    if mask_im.size != im.size:
        raise ValueError(f"mask {mask_im.size} phải cùng kích thước với ảnh nguồn {im.size}")
    mask_full = np.array(mask_im) >= 128
    if not mask_full.any():
        raise ValueError("mask không có pixel chủ thể nào")

    W, H = im.size
    crop = (0, 0, W, H)
    if crop_margin is not None:
        ys, xs = np.nonzero(mask_full)
        pad = int(crop_margin * max(xs.max() - xs.min(), ys.max() - ys.min()))
        crop = (
            int(max(0, xs.min() - pad)),
            int(max(0, ys.min() - pad)),
            int(min(W, xs.max() + 1 + pad)),
            int(min(H, ys.max() + 1 + pad)),
        )
    im_c = im.crop(crop)
    mask_c = mask_im.crop(crop)

    cw, ch = im_c.size
    rows = max(1, round(cols * ch / cw))
    s = SAMPLES_PER_CELL
    work = (cols * s, rows * s)
    rgb = np.array(im_c.resize(work, Image.Resampling.BOX))
    cov_px = np.array(mask_c.point(lambda v: 255 if v >= 128 else 0).resize(work, Image.Resampling.BOX)) / 255.0
    subj_px = cov_px >= 0.5

    lab = _lab_array(rgb)
    pal_lab = _lab_array(np.array([hex_to_rgb(c["hex"]) for c in palette_spec]))
    dist = ((lab[:, :, None, :] - pal_lab[None, None, :, :]) ** 2).sum(axis=-1)
    is_subject_color = np.array([c["role"] == "subject" for c in palette_spec])
    lbl_subject = np.where(is_subject_color, dist, np.inf).argmin(axis=-1)
    lbl_background = np.where(~is_subject_color, dist, np.inf).argmin(axis=-1)

    n = len(palette_spec)

    def pick(r, c, is_subject):
        blk = (slice(r * s, (r + 1) * s), slice(c * s, (c + 1) * s))
        sel = subj_px[blk] if is_subject else ~subj_px[blk]
        labels = (lbl_subject if is_subject else lbl_background)[blk]
        picked = labels[sel] if sel.any() else labels.ravel()
        shares = np.bincount(picked, minlength=n) / picked.size
        priority = [i for i, spec in enumerate(palette_spec) if spec.get("min_share") and shares[i] >= spec["min_share"]]
        return max(priority, key=lambda i: shares[i]) if priority else int(shares.argmax())

    cell_cov = cov_px.reshape(rows, s, cols, s).mean(axis=(1, 3))
    subject_cells = cell_cov >= subject_threshold
    cell_idx = np.array([[pick(r, c, subject_cells[r, c]) for c in range(cols)] for r in range(rows)])

    # thin protrusions (tentacle tips) cover < subject_threshold of every cell they cross; promote
    # those cells when the mask still covers at least keep_tips of them
    promoted_tips = []
    if keep_tips is not None:
        g = np.repeat(np.repeat(subject_cells, s, axis=0), s, axis=1)
        lost = subj_px & ~_dilate(g, s // 2)
        for comp in _components(lost):
            if len(comp) < 0.1 * s * s:
                continue
            for r, c in sorted({(y // s, x // s) for y, x in comp}):
                if not subject_cells[r, c] and cell_cov[r, c] >= keep_tips:
                    subject_cells[r, c] = True
                    cell_idx[r, c] = pick(r, c, True)
                    promoted_tips.append((int(c), int(r)))

    # every sizeable region of a preserved colour (pupil, eye white, mouth) keeps at least one cell,
    # placed where that region covers the most pixels; earlier colours in the palette file win ties
    preserved = []
    locked = np.zeros_like(subject_cells)
    px_area = (cw / work[0]) * (ch / work[1])
    for i, spec in enumerate(palette_spec):
        min_area = spec.get("preserve_min_area")
        if not min_area:
            continue
        for comp in _components((lbl_subject == i) & subj_px):
            area = len(comp) * px_area
            if area < min_area:
                continue
            ys, xs = zip(*comp)
            where = (
                int(crop[0] + min(xs) * cw / work[0]),
                int(crop[1] + min(ys) * ch / work[1]),
                int(crop[0] + (max(xs) + 1) * cw / work[0]),
                int(crop[1] + (max(ys) + 1) * ch / work[1]),
            )
            regions = spec.get("preserve_regions")
            if regions and not any(
                where[0] < bx1 and bx0 < where[2] and where[1] < by1 and by0 < where[3]
                for bx0, by0, bx1, by1 in regions
            ):
                continue
            per_cell = Counter((y // s, x // s) for y, x in comp)
            cand = [(cnt, rc) for rc, cnt in per_cell.items() if subject_cells[rc]]
            have = [rc for _, rc in cand if cell_idx[rc] == i]
            entry = {"name": spec["name"], "area_px": int(area), "source_box": where}
            if have:
                for rc in have:
                    locked[rc] = True
                preserved.append({**entry, "action": "already", "cells": [(int(c), int(r)) for r, c in have]})
                continue
            free = [x for x in cand if not locked[x[1]]]
            if not free:
                preserved.append({**entry, "action": "blocked", "cells": []})
                continue
            _, (r, c) = max(free)
            replaced = palette_spec[cell_idx[r, c]]["name"]
            cell_idx[r, c] = i
            locked[r, c] = True
            preserved.append({**entry, "action": "forced", "cells": [(int(c), int(r))], "replaced": replaced})

    counts = np.bincount(cell_idx.ravel(), minlength=n)
    used = [i for i in range(n) if counts[i] > 0]
    order = sorted(used, key=lambda i: (-counts[i], i))
    remap = {old: new for new, old in enumerate(order)}
    palette = [
        {"id": remap[i], "hex": palette_spec[i]["hex"], "count": int(counts[i]), "name": palette_spec[i]["name"]}
        for i in order
    ]
    flat_cells = [remap[int(v)] for v in cell_idx.ravel()]

    grid = {
        "width": cols,
        "height": rows,
        "palette": palette,
        "cells": flat_cells,
        "mask": [int(v) for v in subject_cells.ravel()],
    }
    diag = {
        "crop_box": crop,
        "crop_image": im_c,
        "samples_per_cell": s,
        "subject_threshold": subject_threshold,
        "work_mask": subj_px,
        "cell_coverage": cell_cov,
        "mask_coverage_source": float(mask_full.mean()),
        "mask_coverage_crop": float(subj_px.mean()),
        "roles": {c["name"]: c["role"] for c in palette_spec},
        "unused_palette": [palette_spec[i]["name"] for i in range(n) if counts[i] == 0],
        "promoted_tips": promoted_tips,
        "preserved_features": preserved,
    }
    return grid, diag


def build_grid(
    source_path: str,
    cols: int,
    colors: int,
    manual_crop: tuple[int, int, int, int] | None = None,
    isolate: bool = False,
):
    """Legacy flow (median-cut over the whole image, no approved mask). Kept so existing
    levels stay reproducible; new levels should use build_grid_from_mask."""
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


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("output")
    ap.add_argument("--cols", type=int, default=25)
    ap.add_argument("--preview", help="review sheet (mask flow) or flat preview (legacy flow)")
    ap.add_argument("--id", required=True, help="stable level id, e.g. squid_relax_01")
    ap.add_argument("--title", required=True)
    ap.add_argument("--difficulty", required=True, choices=DIFFICULTIES)
    ap.add_argument("--modes", default="journey,zen", help="comma-separated subset of: " + ",".join(MODES))
    mask_flow = ap.add_argument_group("mask flow (new levels)")
    mask_flow.add_argument("--mask", help="approved subject mask, same size as source; white = subject")
    mask_flow.add_argument("--palette", help="palette spec JSON with subject/background roles")
    mask_flow.add_argument("--crop-to-mask", type=float, metavar="MARGIN", help="crop to the mask bbox plus MARGIN × its size")
    mask_flow.add_argument("--subject-threshold", type=float, default=0.5, help="min mask coverage for a subject cell")
    mask_flow.add_argument("--keep-tips", type=float, metavar="MIN_COV",
                           help="promote cells of thin protrusions the grid would drop when mask coverage >= MIN_COV")
    mask_flow.add_argument("--report", help="write the quality report to this text file")
    legacy = ap.add_argument_group("legacy flow (reproducing old levels only)")
    legacy.add_argument("--colors", type=int, default=8)
    legacy.add_argument("--crop", type=str, help="x0,y0,x1,y1")
    legacy.add_argument("--isolate", action="store_true", help="HEURISTIC subject guess by colour — not an approved mask")
    args = ap.parse_args(argv)

    if args.mask or args.palette:
        if not (args.mask and args.palette):
            ap.error("--mask và --palette phải dùng cùng nhau")
        if args.isolate or args.crop:
            ap.error("--isolate/--crop thuộc luồng cũ, không dùng chung với --mask")
        from level_review import format_report, palette_report, render_review_sheet, silhouette_report

        try:
            spec = load_palette_spec(args.palette)
            grid, diag = build_grid_from_mask(
                args.source, args.mask, args.cols, spec, args.crop_to_mask, args.subject_threshold, args.keep_tips
            )
        except ValueError as e:
            ap.error(str(e))
    else:
        print(
            "WARNING: legacy flow — median-cut over the whole image without an approved subject mask. "
            "Use --mask/--palette for new levels.",
            file=sys.stderr,
        )
        if args.isolate:
            print("WARNING: --isolate guesses the subject from colour; it is not an approved mask.", file=sys.stderr)
        manual_crop = tuple(int(v) for v in args.crop.split(",")) if args.crop else None
        grid, _ = build_grid(args.source, args.cols, args.colors, manual_crop, args.isolate)
        diag = None

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
    if diag is None:
        for p in level["palette"]:
            print(f"  color {p['id']}: {p['hex']} x{p['count']}")
        if args.preview:
            render_preview(level).save(args.preview)
            print(f"wrote preview {args.preview}")
        return

    sil = silhouette_report(level, diag)
    pal = palette_report(level)
    report = format_report(level, diag, sil, pal)
    print(report)
    if args.report:
        Path(args.report).write_text(report + "\n", encoding="utf-8")
        print(f"wrote report {args.report}")
    if args.preview:
        render_review_sheet(level, diag, sil, pal, report).save(args.preview)
        print(f"wrote preview {args.preview}")


if __name__ == "__main__":
    main()
