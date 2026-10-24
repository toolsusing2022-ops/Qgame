"""Quality report and review sheet for levels built from an approved subject mask."""
from collections import deque

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from validate_level import delta_e_hex, hex_to_rgb

# subject/background neighbours closer than this make the silhouette edge hard to read
WEAK_EDGE_DE = 20.0


def relative_luminance(hex_color: str) -> float:
    def lin(c):
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (lin(v) for v in hex_to_rgb(hex_color))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(h1: str, h2: str) -> float:
    l1, l2 = sorted((relative_luminance(h1), relative_luminance(h2)), reverse=True)
    return (l1 + 0.05) / (l2 + 0.05)


def _components(m: np.ndarray, diagonal: bool = False):
    h, w = m.shape
    seen = np.zeros_like(m, dtype=bool)
    steps = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    if diagonal:
        steps += [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    comps = []
    for y0, x0 in zip(*np.nonzero(m)):
        if seen[y0, x0]:
            continue
        q = deque([(y0, x0)])
        seen[y0, x0] = True
        pts = []
        while q:
            y, x = q.popleft()
            pts.append((y, x))
            for dy, dx in steps:
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    q.append((ny, nx))
        comps.append(pts)
    comps.sort(key=len, reverse=True)
    return comps


def _dilate(m: np.ndarray, r: int) -> np.ndarray:
    h, w = m.shape
    p = np.pad(m, r)
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy <= r * r:
                out |= p[r + dy : r + dy + h, r + dx : r + dx + w]
    return out


def silhouette_report(level: dict, diag: dict) -> dict:
    """Compares the grid's subject cells with the source mask at sampling resolution."""
    w, h, s = level["width"], level["height"], diag["samples_per_cell"]
    subj_cells = np.array(level["mask"], dtype=bool).reshape(h, w)
    cov = diag["cell_coverage"]
    thr = diag["subject_threshold"]
    g = np.repeat(np.repeat(subj_cells, s, axis=0), s, axis=1)
    m = diag["work_mask"]

    inter, union = (g & m).sum(), (g | m).sum()
    cell_area = s * s
    sx, sy = diag["crop_box"][2] - diag["crop_box"][0], diag["crop_box"][3] - diag["crop_box"][1]
    scale_x, scale_y = sx / m.shape[1], sy / m.shape[0]

    def regions(sel, min_cells):
        out = []
        for pts in _components(sel):
            if len(pts) < min_cells * cell_area:
                continue
            ys, xs = zip(*pts)
            x0, x1, y0, y1 = int(min(xs)), int(max(xs)), int(min(ys)), int(max(ys))
            out.append(
                {
                    "cells": round(len(pts) / cell_area, 2),
                    "grid_x": (x0 // s, x1 // s),
                    "grid_y": (y0 // s, y1 // s),
                    "source_box": (
                        int(diag["crop_box"][0] + x0 * scale_x),
                        int(diag["crop_box"][1] + y0 * scale_y),
                        int(diag["crop_box"][0] + (x1 + 1) * scale_x),
                        int(diag["crop_box"][1] + (y1 + 1) * scale_y),
                    ),
                }
            )
        return out

    # mask parts further than half a cell from any subject cell = protrusions the grid dropped
    lost = m & ~_dilate(g, s // 2)
    gained = g & ~_dilate(m, s // 2)
    islands = [len(c) for c in _components(subj_cells, diagonal=True)]

    return {
        "subject_cells": int(subj_cells.sum()),
        "background_cells": int((~subj_cells).sum()),
        "partial_excluded": int(((cov > 0) & ~subj_cells).sum()),
        "partial_included": int((subj_cells & (cov < 1)).sum()),
        "promoted_below_threshold": int((subj_cells & (cov < thr)).sum()),
        "iou": inter / union if union else 0.0,
        "recall": inter / m.sum() if m.sum() else 0.0,
        "precision": inter / g.sum() if g.sum() else 0.0,
        "lost_regions": regions(lost, 0.25),
        "gained_regions": regions(gained, 0.25),
        "subject_islands": islands,
        "lost_map": lost,
        "gained_map": gained,
    }


def palette_report(level: dict) -> dict:
    w, h = level["width"], level["height"]
    cells = np.array(level["cells"]).reshape(h, w)
    subj = np.array(level["mask"], dtype=bool).reshape(h, w)
    pal = {p["id"]: p for p in level["palette"]}

    nearest = {}
    for a in pal:
        best = min(((delta_e_hex(pal[a]["hex"], pal[b]["hex"]), b) for b in pal if b != a), default=(None, None))
        nearest[a] = best

    adjacency = {}
    for dy, dx in ((0, 1), (1, 0)):
        a = cells[: h - dy, : w - dx]
        b = cells[dy:, dx:]
        sa = subj[: h - dy, : w - dx]
        sb = subj[dy:, dx:]
        for ca, cb, ea, eb in zip(a.ravel(), b.ravel(), sa.ravel(), sb.ravel()):
            if ca == cb:
                continue
            key = (min(ca, cb), max(ca, cb))
            entry = adjacency.setdefault(key, {"count": 0, "silhouette_edge": 0})
            entry["count"] += 1
            entry["silhouette_edge"] += int(ea != eb)

    pairs = []
    for (a, b), e in adjacency.items():
        pairs.append(
            {
                "a": a,
                "b": b,
                "count": e["count"],
                "silhouette_edge": e["silhouette_edge"],
                "delta_e": delta_e_hex(pal[a]["hex"], pal[b]["hex"]),
                "contrast": contrast_ratio(pal[a]["hex"], pal[b]["hex"]),
            }
        )
    pairs.sort(key=lambda p: p["delta_e"])
    weak_edges = [p for p in pairs if p["silhouette_edge"] and p["delta_e"] < WEAK_EDGE_DE]
    return {"nearest": nearest, "adjacent_pairs": pairs, "weak_silhouette_edges": weak_edges}


def format_report(level: dict, diag: dict, sil: dict, pal: dict) -> str:
    names = {p["id"]: p.get("name", str(p["id"])) for p in level["palette"]}
    roles = diag["roles"]
    lines = [
        f"level {level['id']}: {level['width']}x{level['height']} = {level['width'] * level['height']} ô, {len(level['palette'])} màu",
        f"crop nguồn {diag['crop_box']}, mask coverage: {diag['mask_coverage_source']:.1%} ảnh gốc, {diag['mask_coverage_crop']:.1%} vùng crop",
        f"ô chủ thể {sil['subject_cells']}, ô nền (mask loại khỏi chủ thể) {sil['background_cells']}",
        f"ô biên có chủ thể nhưng bị loại (coverage < {diag['subject_threshold']}): {sil['partial_excluded']}; "
        f"ô biên được nhận vào chủ thể dù có một phần nền: {sil['partial_included']}",
        f"silhouette: IoU {sil['iou']:.3f}, recall {sil['recall']:.3f} (phần mask được lưới phủ), precision {sil['precision']:.3f}",
        f"mảnh chủ thể rời nhau (8-kề): {len(sil['subject_islands'])} — kích thước {sil['subject_islands'][:8]}",
        f"ô đầu xúc tu được giữ (coverage < {diag['subject_threshold']} nhưng là phần nhô bị mất): "
        f"{len(diag.get('promoted_tips', []))} {diag.get('promoted_tips', [])}",
        "",
        "màu (id, tên, vai trò, hex, số ô, màu gần nhất ΔE00):",
    ]
    for p in level["palette"]:
        de, other = pal["nearest"][p["id"]]
        near = f"{de:5.1f} với {other}:{names[other]}" if other is not None else "-"
        lines.append(f"  {p['id']:2d} {p['name']:<14s} {roles[p['name']]:<10s} {p['hex']}  {p['count']:4d}  {near}")
    if diag["unused_palette"]:
        lines.append(f"  màu trong palette nhưng không ô nào dùng (đã bỏ khỏi level): {', '.join(diag['unused_palette'])}")

    if diag.get("preserved_features"):
        lines += ["", "chi tiết được bảo toàn (preserve_min_area):"]
        action_vn = {"already": "đã có", "forced": "đặt thêm", "blocked": "KHÔNG đặt được"}
        for f in diag["preserved_features"]:
            extra = f" (thay {f['replaced']})" if f.get("replaced") else ""
            lines.append(
                f"  {f['name']:<10s} vùng {f['area_px']}px tại ảnh gốc {f['source_box']}: "
                f"{action_vn[f['action']]} ô {f['cells']}{extra}"
            )

    lines += ["", "phần nhô của mask bị lưới làm mất (> 1/2 ô tính từ ô chủ thể gần nhất):"]
    if not sil["lost_regions"]:
        lines.append("  không có")
    for r in sil["lost_regions"]:
        lines.append(f"  ~{r['cells']} ô tại cột {r['grid_x']} hàng {r['grid_y']}, ảnh gốc {r['source_box']}")
    lines += ["nền bị nhận nhầm vào chủ thể (> 1/2 ô tính từ mask):"]
    if not sil["gained_regions"]:
        lines.append("  không có")
    for r in sil["gained_regions"]:
        lines.append(f"  ~{r['cells']} ô tại cột {r['grid_x']} hàng {r['grid_y']}, ảnh gốc {r['source_box']}")

    lines += ["", f"cặp màu nằm cạnh nhau có ΔE00 thấp nhất (viền chủ thể yếu nếu ΔE00 < {WEAK_EDGE_DE}):"]
    for p in pal["adjacent_pairs"][:6]:
        tag = " ← viền chủ thể" if p["silhouette_edge"] else ""
        lines.append(
            f"  {names[p['a']]} / {names[p['b']]}: ΔE00 {p['delta_e']:.1f}, tương phản sáng {p['contrast']:.2f}:1, "
            f"{p['count']} cạnh kề{tag}"
        )
    if pal["weak_silhouette_edges"]:
        lines.append(f"  CẢNH BÁO: {len(pal['weak_silhouette_edges'])} cặp màu ở viền chủ thể/nền có ΔE00 < {WEAK_EDGE_DE}")
    return "\n".join(lines)


FONT_CANDIDATES = (
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    "/Library/Fonts/Arial Unicode.ttf",
    "C:/Windows/Fonts/arial.ttf",
)


def thumbnails_96(level: dict, size: int = 96) -> tuple[Image.Image, Image.Image]:
    """Level-select sized thumbnails, letterboxed into size×size: flat cells and round beads."""
    w, h = level["width"], level["height"]
    colors = {p["id"]: hex_to_rgb(p["hex"]) for p in level["palette"]}
    cells = np.array(level["cells"]).reshape(h, w)
    cell = size / max(w, h)
    ox, oy = (size - w * cell) / 2, (size - h * cell) / 2
    ss = 8  # supersample, then downscale for honest anti-aliasing at the real size
    flat = Image.new("RGB", (size * ss, size * ss), (40, 40, 48))
    beads = Image.new("RGB", (size * ss, size * ss), (40, 40, 48))
    df, db = ImageDraw.Draw(flat), ImageDraw.Draw(beads)
    for y in range(h):
        for x in range(w):
            if cells[y, x] < 0:
                continue
            x0, y0 = (ox + x * cell) * ss, (oy + y * cell) * ss
            x1, y1 = x0 + cell * ss, y0 + cell * ss
            df.rectangle([x0, y0, x1, y1], fill=colors[cells[y, x]])
            db.ellipse([x0 + ss * 0.3, y0 + ss * 0.3, x1 - ss * 0.3, y1 - ss * 0.3], fill=colors[cells[y, x]])
    return (flat.resize((size, size), Image.Resampling.LANCZOS), beads.resize((size, size), Image.Resampling.LANCZOS))


def _font(size):
    # the built-in Pillow font has no Vietnamese diacritics
    for path in FONT_CANDIDATES:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default(size=size)


def render_review_sheet(level: dict, diag: dict, sil: dict, pal: dict, report_text: str) -> Image.Image:
    w, h = level["width"], level["height"]
    cells = np.array(level["cells"]).reshape(h, w)
    subj = np.array(level["mask"], dtype=bool).reshape(h, w)
    colors = {p["id"]: hex_to_rgb(p["hex"]) for p in level["palette"]}
    cp = max(18, min(40, 720 // w))
    gw, gh = w * cp, h * cp

    # 1. source crop + mask + losses
    src = diag["crop_image"].resize((gw, gh), Image.Resampling.LANCZOS)
    a = np.array(src).astype(float)
    m = np.array(Image.fromarray(diag["work_mask"].astype("uint8") * 255).resize((gw, gh))) > 127
    lost = np.array(Image.fromarray(sil["lost_map"].astype("uint8") * 255).resize((gw, gh))) > 127
    gained = np.array(Image.fromarray(sil["gained_map"].astype("uint8") * 255).resize((gw, gh))) > 127
    a[~m] *= 0.45
    a[lost] = a[lost] * 0.3 + np.array([255, 0, 0]) * 0.7
    a[gained] = a[gained] * 0.3 + np.array([0, 120, 255]) * 0.7
    p1 = Image.fromarray(a.clip(0, 255).astype("uint8"))
    d = ImageDraw.Draw(p1)
    for x in range(0, gw + 1, cp):
        d.line([(x, 0), (x, gh)], fill=(255, 255, 255, 60), width=1)
    for y in range(0, gh + 1, cp):
        d.line([(0, y), (gw, y)], fill=(255, 255, 255, 60), width=1)

    def outline(draw, ox, oy, color):
        for y in range(h):
            for x in range(w):
                if not subj[y, x]:
                    continue
                if y == 0 or not subj[y - 1, x]:
                    draw.line([(ox + x * cp, oy + y * cp), (ox + (x + 1) * cp, oy + y * cp)], fill=color, width=2)
                if y == h - 1 or not subj[y + 1, x]:
                    draw.line([(ox + x * cp, oy + (y + 1) * cp), (ox + (x + 1) * cp, oy + (y + 1) * cp)], fill=color, width=2)
                if x == 0 or not subj[y, x - 1]:
                    draw.line([(ox + x * cp, oy + y * cp), (ox + x * cp, oy + (y + 1) * cp)], fill=color, width=2)
                if x == w - 1 or not subj[y, x + 1]:
                    draw.line([(ox + (x + 1) * cp, oy + y * cp), (ox + (x + 1) * cp, oy + (y + 1) * cp)], fill=color, width=2)

    outline(d, 0, 0, (255, 230, 0))

    # 2. bead render
    # light board so very dark beads (pupils) stay visible
    p2 = Image.new("RGB", (gw, gh), (214, 214, 220))
    d2 = ImageDraw.Draw(p2)
    for y in range(h):
        for x in range(w):
            if cells[y, x] < 0:
                continue
            d2.ellipse([x * cp + 1, y * cp + 1, (x + 1) * cp - 2, (y + 1) * cp - 2], fill=colors[cells[y, x]])

    # 3. id grid
    p3 = Image.new("RGB", (gw, gh), "white")
    d3 = ImageDraw.Draw(p3)
    f = _font(max(9, cp // 2 - 1))
    for y in range(h):
        for x in range(w):
            c = cells[y, x]
            rgb = colors[c]
            tint = tuple(int(v * 0.35 + 255 * 0.65) for v in rgb)
            d3.rectangle([x * cp, y * cp, (x + 1) * cp - 1, (y + 1) * cp - 1], fill=tint, outline=(200, 200, 200))
            d3.text((x * cp + cp / 2, y * cp + cp / 2), str(c), fill=(20, 20, 20), font=f, anchor="mm")
    outline(d3, 0, 0, (230, 120, 0))

    # 4. palette + report text
    tf = _font(15)
    lines = report_text.split("\n")
    pal_h = 34 * len(level["palette"]) + 20
    p4 = Image.new("RGB", (gw, max(gh, pal_h + 22 * len(lines) + 20)), "white")
    d4 = ImageDraw.Draw(p4)
    for i, p in enumerate(level["palette"]):
        y = 10 + i * 34
        d4.ellipse([10, y, 38, y + 28], fill=hex_to_rgb(p["hex"]), outline=(80, 80, 80))
        d4.text((48, y + 6), f"{p['id']:>2}  {p['name']}  ({diag['roles'][p['name']]})  {p['hex']}  ×{p['count']}", fill=(0, 0, 0), font=_font(17))
    for i, line in enumerate(lines):
        d4.text((10, pal_h + i * 22), line, fill=(0, 0, 0), font=tf)

    # 5. 96x96 thumbnails (flat and beaded, letterboxed), each also shown 3x for inspection
    t1 = Image.new("RGB", (96 * 3 * 2 + 20, 96 * 3), (245, 245, 245))
    flat, beads = thumbnails_96(level)
    t1.paste(flat.resize((288, 288), Image.Resampling.NEAREST), (0, 0))
    t1.paste(beads.resize((288, 288), Image.Resampling.NEAREST), (308, 0))
    t2 = Image.new("RGB", (96 * 2 + 10, 96), (245, 245, 245))
    t2.paste(flat, (0, 0))
    t2.paste(beads, (106, 0))

    title_h = 40
    sheet = Image.new("RGB", (gw * 2 + 30, title_h + gh * 2 + 30 + max(p4.height - gh, 0) + t1.height + 40), (245, 245, 245))
    ds = ImageDraw.Draw(sheet)
    ds.text((10, 8), f"{level['id']} — {level['title']} ({level['difficulty']}) — PREVIEW CHỜ DUYỆT", fill=(0, 0, 0), font=_font(22))
    y0 = title_h
    sheet.paste(p1, (0, y0))
    sheet.paste(p2, (gw + 30, y0))
    sheet.paste(p3, (0, y0 + gh + 30))
    sheet.paste(p4, (gw + 30, y0 + gh + 30))
    yb = y0 + gh + 30 + max(gh, p4.height) + 10
    sheet.paste(t1, (10, yb))
    sheet.paste(t2, (t1.width + 30, yb))
    ds.text((t1.width + 30, yb + t2.height + 10), "thumbnail 96×96 px thật (phẳng | hạt);\nbên trái: cùng thumbnail phóng ×3 để soi",
            fill=(0, 0, 0), font=_font(15))
    ds.text((10, y0 - 18 + gh + 30), "id màu từng ô (viền cam = chủ thể)", fill=(0, 0, 0), font=_font(14))
    return sheet
