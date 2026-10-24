#!/usr/bin/env python3
"""Produces a DRAFT subject mask plus an overlay for human review. A draft is never ground
truth: it becomes an approved mask only after someone has checked the overlay.

Steps: warm-colour classification -> drop yellow/tan reef and pale sand -> opening, keep the
largest blob, regrow it inside the warm area (thin tentacle tips survive, thin bridges to coral
do not) -> optionally attach strongly red parts hidden behind an outline -> fill enclosed holes
that are not open water (eyes, mouth, suckers) -> optional manual include ellipses.

Usage:
    python3 draft_mask.py SOURCE OUT_MASK.png --overlay OUT_OVERLAY.png [--attach-r 6]
        [--include-ellipse cx,cy,rx,ry ...]
"""
import argparse
from collections import deque

import numpy as np
from PIL import Image


def _shift_or(m, r):
    h, w = m.shape
    p = np.pad(m, r, constant_values=False)
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy <= r * r:
                out |= p[r + dy : r + dy + h, r + dx : r + dx + w]
    return out


def dilate(m, r):
    return _shift_or(m, r)


def erode(m, r):
    return ~_shift_or(~m, r)


def _components(m):
    h, w = m.shape
    seen = np.zeros_like(m)
    for y0, x0 in zip(*np.nonzero(m)):
        if seen[y0, x0]:
            continue
        q = deque([(y0, x0)])
        seen[y0, x0] = True
        pts = []
        while q:
            y, x = q.popleft()
            pts.append((y, x))
            for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    q.append((ny, nx))
        yield pts


def largest_component(m):
    out = np.zeros_like(m)
    best = max(_components(m), key=len, default=None)
    if best:
        ys, xs = map(list, zip(*best))
        out[ys, xs] = True
    return out


def reconstruct(marker, mask):
    cur = marker & mask
    while True:
        nxt = dilate(cur, 1) & mask
        if (nxt == cur).all():
            return cur
        cur = nxt


def fill_non_water_holes(m, r, b):
    border = np.zeros_like(m)
    border[0, :] = border[-1, :] = border[:, 0] = border[:, -1] = True
    outside = reconstruct(border & ~m, ~m)
    out = m.copy()
    for pts in _components(~m & ~outside):
        ys, xs = map(list, zip(*pts))
        if np.median(b[ys, xs] - r[ys, xs]) <= 15:
            out[ys, xs] = True
    return out


def draft_mask(
    src: str,
    scale: float = 0.5,
    warm_rb: float = 30,
    pale_rg: float = 20,
    yellow_gb: float = 40,
    open_r: int = 6,
    close_r: int = 3,
    attach_r: int = 0,
    include_ellipses=(),
):
    im = Image.open(src).convert("RGB")
    W, H = im.size
    a = np.array(im.resize((round(W * scale), round(H * scale)), Image.Resampling.BOX)).astype(int)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]

    warm = (r - b > warm_rb) & (r > 120)
    warm &= ~((r - g) < pale_rg)  # sand, yellow fish
    warm &= ~(((g - b) > yellow_gb) & ((r - g) < 60))  # yellow/tan reef rock

    core = largest_component(dilate(erode(warm, open_r), open_r))
    subject = reconstruct(core, warm)
    if attach_r:
        strict = (r - b > 80) & (r > 120)
        subject |= reconstruct(dilate(subject, attach_r) & strict, strict)
    subject = fill_non_water_holes(subject, r, b)
    subject = erode(dilate(subject, close_r), close_r)
    subject = fill_non_water_holes(subject, r, b)

    full = Image.fromarray((subject * 255).astype("uint8")).resize((W, H), Image.Resampling.BILINEAR)
    m = np.array(full) >= 128
    if include_ellipses:
        fa = np.array(im).astype(int)
        not_water = (fa[..., 2] - fa[..., 0]) <= 15
        yy, xx = np.mgrid[0:H, 0:W]
        for cx, cy, rx, ry in include_ellipses:
            ell = ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2 <= 1
            m |= ell & not_water
            # seal small notches (eyelid edge, reflections) inside the ellipse
            m |= erode(dilate(m, 8), 8) & ell
    return im, m


def overlay(im, m):
    src = np.array(im).astype(float)
    ov = src * 0.35
    ov[m] = src[m] * 0.85 + np.array([0, 255, 0]) * 0.15
    ov[m ^ erode(m, 2)] = [255, 255, 0]
    return Image.fromarray(ov.clip(0, 255).astype("uint8"))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("source")
    ap.add_argument("out_mask")
    ap.add_argument("--overlay", help="write a review overlay (yellow = mask outline, dimmed = background)")
    ap.add_argument("--warm-rb", type=float, default=30)
    ap.add_argument("--pale-rg", type=float, default=20)
    ap.add_argument("--yellow-gb", type=float, default=40)
    ap.add_argument("--open-r", type=int, default=6)
    ap.add_argument("--close-r", type=int, default=3)
    ap.add_argument("--attach-r", type=int, default=0, help="attach strongly red parts within R px (half-res) of the body")
    ap.add_argument("--include-ellipse", action="append", default=[], metavar="cx,cy,rx,ry",
                    help="manual fix: add non-water pixels inside this ellipse (source pixels)")
    args = ap.parse_args(argv)

    ellipses = [tuple(float(v) for v in e.split(",")) for e in args.include_ellipse]
    im, m = draft_mask(args.source, warm_rb=args.warm_rb, pale_rg=args.pale_rg, yellow_gb=args.yellow_gb,
                       open_r=args.open_r, close_r=args.close_r, attach_r=args.attach_r, include_ellipses=ellipses)
    Image.fromarray((m * 255).astype("uint8")).save(args.out_mask)
    print(f"wrote DRAFT mask {args.out_mask}: coverage {m.mean():.1%} (needs human review)")
    if args.overlay:
        overlay(im, m).save(args.overlay)
        print(f"wrote overlay {args.overlay}")


if __name__ == "__main__":
    main()
