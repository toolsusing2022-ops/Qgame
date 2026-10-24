import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import image_to_beadgrid as ib  # noqa: E402
from draft_mask import draft_mask  # noqa: E402
from level_review import silhouette_report  # noqa: E402
from validate_level import validate  # noqa: E402

BLUE, DEEP, RED, DARK = (40, 140, 210), (10, 60, 100), (230, 80, 50), (32, 20, 26)
PALETTE = [
    {"name": "body", "hex": "#e65032", "role": "subject"},
    {"name": "eye", "hex": "#20141a", "role": "subject", "min_share": 0.12},
    {"name": "water", "hex": "#288cd2", "role": "background"},
    {"name": "deep", "hex": "#0a3c64", "role": "background"},
]
META = {"schema_version": 1, "id": "synthetic", "title": "Synthetic", "difficulty": "easy", "modes": ["zen"]}


def make_scene(tmp, thin_arm=False):
    """120x80 scene, 12 cols -> 10px cells. Subject: red block at cells x4-7, y2-5 with a 4x4 dark
    eye inside cell (5, 3). Coral: a SAME-red block outside the mask at cells x0-1, y6-7."""
    img = Image.new("RGB", (120, 80), BLUE)
    px = img.load()
    for x in range(120):
        for y in range(60, 80):
            px[x, y] = DEEP
    for x in range(40, 80):
        for y in range(20, 60):
            px[x, y] = RED
    for x in range(52, 56):
        for y in range(32, 36):
            px[x, y] = DARK
    for x in range(0, 20):
        for y in range(60, 80):
            px[x, y] = RED
    mask = Image.new("L", (120, 80), 0)
    mp = mask.load()
    for x in range(40, 80):
        for y in range(20, 60):
            mp[x, y] = 255
    if thin_arm:
        # 4px arm inside cell row 3: coverage 0.4 per cell, below the 0.5 subject threshold
        for x in range(80, 110):
            for y in range(33, 37):
                px[x, y] = RED
                mp[x, y] = 255
    src, msk = os.path.join(tmp, "src.png"), os.path.join(tmp, "mask.png")
    img.save(src)
    mask.save(msk)
    return src, msk


def write_palette(tmp, colors, name="pal.json"):
    path = os.path.join(tmp, name)
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"colors": colors}, f)
    return path


class MaskFlowTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.src, self.mask = make_scene(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def build(self, palette=PALETTE, **kw):
        grid, diag = ib.build_grid_from_mask(self.src, self.mask, 12, palette, **kw)
        return {**META, **grid}, diag

    def test_output_is_valid_schema_v1_with_mask(self):
        level, _ = self.build()
        self.assertEqual(validate(level), [])
        self.assertEqual((level["width"], level["height"]), (12, 8))
        self.assertEqual(sum(level["mask"]), 16)

    def test_roles_are_respected_and_same_hue_coral_stays_background(self):
        level, _ = self.build()
        names = {p["id"]: p["name"] for p in level["palette"]}
        roles = {c["name"]: c["role"] for c in PALETTE}
        for i, (cell, in_subject) in enumerate(zip(level["cells"], level["mask"])):
            expected = "subject" if in_subject else "background"
            self.assertEqual(roles[names[cell]], expected, f"cell {i}")
        coral_cells = [y * 12 + x for y in (6, 7) for x in (0, 1)]
        for i in coral_cells:
            self.assertEqual(roles[names[level["cells"][i]]], "background")

    def test_min_share_keeps_small_feature(self):
        level, _ = self.build()
        names = {p["id"]: p["name"] for p in level["palette"]}
        self.assertEqual(names[level["cells"][3 * 12 + 5]], "eye")

        no_priority = [dict(c) for c in PALETTE]
        no_priority[1].pop("min_share")
        level2, diag2 = self.build(no_priority)
        names2 = {p["id"]: p["name"] for p in level2["palette"]}
        self.assertEqual(names2[level2["cells"][3 * 12 + 5]], "body")
        self.assertEqual(diag2["unused_palette"], ["eye"])
        self.assertNotIn("eye", names2.values())
        self.assertEqual(validate({**level2}), [])

    def test_subject_threshold_controls_membership(self):
        tmp = self.tmp.name
        with Image.open(self.src) as img:
            size = img.size
        mask = Image.new("L", size, 0)
        mp = mask.load()
        for x in range(40, 77):  # last column of the block covered only 70%
            for y in range(20, 60):
                mp[x, y] = 255
        m2 = os.path.join(tmp, "mask70.png")
        mask.save(m2)
        g_half, _ = ib.build_grid_from_mask(self.src, m2, 12, PALETTE, subject_threshold=0.5)
        g_high, _ = ib.build_grid_from_mask(self.src, m2, 12, PALETTE, subject_threshold=0.9)
        self.assertEqual(sum(g_half["mask"]), 16)
        self.assertEqual(sum(g_high["mask"]), 12)

    def test_crop_to_mask(self):
        level, diag = self.build(crop_margin=0.0)
        self.assertEqual(diag["crop_box"], (40, 20, 80, 60))
        self.assertEqual(sum(level["mask"]), level["width"] * level["height"])

    def test_mask_size_mismatch_is_rejected(self):
        bad = os.path.join(self.tmp.name, "small.png")
        Image.new("L", (60, 40), 255).save(bad)
        with self.assertRaisesRegex(ValueError, "cùng kích thước"):
            ib.build_grid_from_mask(self.src, bad, 12, PALETTE)

    def test_empty_mask_is_rejected(self):
        empty = os.path.join(self.tmp.name, "empty.png")
        Image.new("L", (120, 80), 0).save(empty)
        with self.assertRaisesRegex(ValueError, "không có pixel"):
            ib.build_grid_from_mask(self.src, empty, 12, PALETTE)

    def test_no_colours_are_merged(self):
        # two close reds both stay available; the pipeline never merges palette colours itself
        palette = PALETTE + [{"name": "body2", "hex": "#e85535", "role": "subject"}]
        level, diag = self.build(palette)
        used = {p["name"] for p in level["palette"]} | set(diag["unused_palette"])
        self.assertEqual(used, {c["name"] for c in palette})


def make_corner_eye_scene(tmp, eyes=((60, 40),), white_right_of_eye=False):
    """Red block (cells x4-7, y2-5) with 6x6 dark eyes centred on cell corners, so every cell
    holds only ~9% eye — below any sensible min_share."""
    img = Image.new("RGB", (120, 80), BLUE)
    px = img.load()
    for x in range(40, 80):
        for y in range(20, 60):
            px[x, y] = RED
    for cx, cy in eyes:
        for x in range(cx - 3, cx + 3):
            for y in range(cy - 3, cy + 3):
                px[x, y] = DARK
        if white_right_of_eye:
            for x in range(cx + 3, cx + 7):
                for y in range(cy - 3, cy + 3):
                    px[x, y] = (255, 248, 236)
    mask = Image.new("L", (120, 80), 0)
    mp = mask.load()
    for x in range(40, 80):
        for y in range(20, 60):
            mp[x, y] = 255
    src, msk = os.path.join(tmp, "eye_src.png"), os.path.join(tmp, "eye_mask.png")
    img.save(src)
    mask.save(msk)
    return src, msk


def names_of(grid):
    n = {p["id"]: p["name"] for p in grid["palette"]}
    return [n[c] for c in grid["cells"]]


class FeaturePreservationTests(unittest.TestCase):
    BASE = [
        {"name": "body", "hex": "#e65032", "role": "subject"},
        {"name": "eye", "hex": "#20141a", "role": "subject", "min_share": 0.12},
        {"name": "water", "hex": "#288cd2", "role": "background"},
    ]

    def with_eye(self, **extra):
        pal = [dict(c) for c in self.BASE]
        pal[1].update(extra)
        return pal

    def test_feature_straddling_four_cells_is_lost_without_preserve(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, mask = make_corner_eye_scene(tmp)
            grid, diag = ib.build_grid_from_mask(src, mask, 12, self.BASE)
        self.assertNotIn("eye", names_of(grid))
        self.assertEqual(diag["unused_palette"], ["eye"])

    def test_preserve_places_exactly_one_cell_where_feature_is(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, mask = make_corner_eye_scene(tmp)
            grid, diag = ib.build_grid_from_mask(src, mask, 12, self.with_eye(preserve_min_area=20))
        cells = names_of(grid)
        eye_cells = [(i % 12, i // 12) for i, n in enumerate(cells) if n == "eye"]
        self.assertEqual(len(eye_cells), 1)
        self.assertIn(eye_cells[0], {(5, 3), (6, 3), (5, 4), (6, 4)})
        self.assertEqual([f["action"] for f in diag["preserved_features"]], ["forced"])
        self.assertEqual(validate({**META, **grid}), [])

    def test_min_area_filters_small_specks(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, mask = make_corner_eye_scene(tmp)
            grid, diag = ib.build_grid_from_mask(src, mask, 12, self.with_eye(preserve_min_area=500))
        self.assertNotIn("eye", names_of(grid))
        self.assertEqual(diag["preserved_features"], [])

    def test_preserve_regions_limit_which_features_are_guaranteed(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, mask = make_corner_eye_scene(tmp, eyes=((50, 30), (70, 50)))
            grid, diag = ib.build_grid_from_mask(
                src, mask, 12, self.with_eye(preserve_min_area=20, preserve_regions=[[44, 24, 56, 36]])
            )
        eye_cells = [(i % 12, i // 12) for i, n in enumerate(names_of(grid)) if n == "eye"]
        self.assertEqual(len(eye_cells), 1)
        self.assertIn(eye_cells[0], {(4, 2), (5, 2), (4, 3), (5, 3)})

    def test_earlier_preserved_colour_keeps_its_cell(self):
        pal = self.with_eye(preserve_min_area=20) + [
            {"name": "white", "hex": "#fff8ec", "role": "subject", "preserve_min_area": 10}
        ]
        with tempfile.TemporaryDirectory() as tmp:
            src, mask = make_corner_eye_scene(tmp, white_right_of_eye=True)
            grid, diag = ib.build_grid_from_mask(src, mask, 12, pal)
        cells = names_of(grid)
        self.assertEqual(cells.count("eye"), 1)
        self.assertEqual(cells.count("white"), 1)
        self.assertNotEqual(cells.index("eye"), cells.index("white"))

    def test_preserve_never_touches_background_cells(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, mask = make_corner_eye_scene(tmp)
            grid, _ = ib.build_grid_from_mask(src, mask, 12, self.with_eye(preserve_min_area=20))
        for name, in_subject in zip(names_of(grid), grid["mask"]):
            if not in_subject:
                self.assertEqual(name, "water")


class KeepTipsTests(unittest.TestCase):
    def test_thin_arm_is_kept_and_no_background_is_gained(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, mask = make_scene(tmp, thin_arm=True)
            plain, d0 = ib.build_grid_from_mask(src, mask, 12, PALETTE)
            kept, d1 = ib.build_grid_from_mask(src, mask, 12, PALETTE, keep_tips=0.15)
        self.assertEqual(d0["promoted_tips"], [])
        self.assertTrue(d1["promoted_tips"])
        self.assertEqual(sorted(d1["promoted_tips"]), [(8, 3), (9, 3), (10, 3)])
        sil0 = silhouette_report({**META, **plain}, d0)
        sil1 = silhouette_report({**META, **kept}, d1)
        self.assertEqual(len(sil0["lost_regions"]), 1)
        self.assertEqual(sil1["lost_regions"], [])
        self.assertEqual(sil1["gained_regions"], [])
        self.assertEqual(sil1["promoted_below_threshold"], len(d1["promoted_tips"]))
        self.assertEqual(validate({**META, **kept}), [])

    def test_threshold_above_arm_coverage_promotes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, mask = make_scene(tmp, thin_arm=True)
            _, diag = ib.build_grid_from_mask(src, mask, 12, PALETTE, keep_tips=0.45)
        self.assertEqual(diag["promoted_tips"], [])

    def test_no_effect_when_nothing_is_lost(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, mask = make_scene(tmp)
            a, _ = ib.build_grid_from_mask(src, mask, 12, PALETTE)
            b, diag = ib.build_grid_from_mask(src, mask, 12, PALETTE, keep_tips=0.1)
        self.assertEqual(a, b)
        self.assertEqual(diag["promoted_tips"], [])


class SilhouetteReportTests(unittest.TestCase):
    def test_aligned_block_has_perfect_overlap(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, mask = make_scene(tmp)
            grid, diag = ib.build_grid_from_mask(src, mask, 12, PALETTE)
        sil = silhouette_report({**META, **grid}, diag)
        self.assertAlmostEqual(sil["iou"], 1.0)
        self.assertEqual(sil["lost_regions"], [])
        self.assertEqual(sil["subject_islands"], [16])

    def test_thin_arm_lost_by_grid_is_reported_with_location(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, mask = make_scene(tmp, thin_arm=True)
            grid, diag = ib.build_grid_from_mask(src, mask, 12, PALETTE)
        sil = silhouette_report({**META, **grid}, diag)
        self.assertEqual(len(sil["lost_regions"]), 1)
        x0, y0, x1, y1 = sil["lost_regions"][0]["source_box"]
        self.assertGreaterEqual(x0, 80)
        self.assertLessEqual(x1, 112)
        self.assertTrue(32 <= y0 <= y1 <= 38)
        self.assertLess(sil["recall"], 1.0)


class PaletteSpecTests(unittest.TestCase):
    def check_rejected(self, colors, pattern):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, pattern):
                ib.load_palette_spec(write_palette(tmp, colors))

    def test_valid_spec_lowercases_hex(self):
        with tempfile.TemporaryDirectory() as tmp:
            spec = ib.load_palette_spec(write_palette(tmp, [{**PALETTE[0], "hex": "#E65032"}] + PALETTE[1:]))
        self.assertEqual(spec[0]["hex"], "#e65032")

    def test_rejections(self):
        cases = [
            (PALETTE + [{"name": "body", "hex": "#123456", "role": "subject"}], "name"),
            (PALETTE + [{"name": "x", "hex": "#E65032", "role": "subject"}], "hex"),
            (PALETTE + [{"name": "x", "hex": "#123456", "role": "coral"}], "role"),
            ([c for c in PALETTE if c["role"] == "subject"], "background"),
            (PALETTE + [{"name": "x", "hex": "#123456", "role": "subject", "min_share": 0}], "min_share"),
            (PALETTE + [{"name": "x", "hex": "#123456", "role": "subject", "min_share": True}], "min_share"),
            (PALETTE + [{"name": "x", "hex": "#123456", "role": "subject", "weight": 2}], "trường lạ"),
            ([], "colors"),
            (PALETTE + [{"name": "x", "hex": "#123456", "role": "background", "preserve_min_area": 10}], "subject"),
            (PALETTE + [{"name": "x", "hex": "#123456", "role": "subject", "preserve_min_area": -5}], "preserve_min_area"),
            (PALETTE + [{"name": "x", "hex": "#123456", "role": "subject", "preserve_regions": [[0, 0, 5, 5]]}],
             "đi kèm"),
            (PALETTE + [{"name": "x", "hex": "#123456", "role": "subject", "preserve_min_area": 5,
                         "preserve_regions": [[10, 0, 5, 5]]}], "preserve_regions"),
            (PALETTE + [{"name": "x", "hex": "#123456", "role": "subject", "preserve_min_area": 5,
                         "preserve_regions": [[0, 0, 5]]}], "preserve_regions"),
        ]
        for colors, pattern in cases:
            with self.subTest(pattern=pattern):
                self.check_rejected(colors, pattern)


class CliTests(unittest.TestCase):
    def run_main(self, args):
        out, err = io.StringIO(), io.StringIO()
        code = 0
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                ib.main(args)
            except SystemExit as e:
                code = e.code
        return code, out.getvalue(), err.getvalue()

    def test_count_based_merge_option_is_gone(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, _ = make_scene(tmp)
            code, _, err = self.run_main([src, os.path.join(tmp, "o.json"), "--id", "x", "--title", "x",
                                          "--difficulty", "easy", "--min-color-frac", "0.1"])
        self.assertNotEqual(code, 0)
        self.assertIn("--min-color-frac", err)
        self.assertFalse(hasattr(ib, "merge_small_colors"))

    def test_mask_requires_palette(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, mask = make_scene(tmp)
            code, _, err = self.run_main([src, os.path.join(tmp, "o.json"), "--id", "x", "--title", "x",
                                          "--difficulty", "easy", "--mask", mask])
        self.assertNotEqual(code, 0)
        self.assertIn("--palette", err)

    def test_legacy_flow_warns(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, _ = make_scene(tmp)
            code, _, err = self.run_main([src, os.path.join(tmp, "o.json"), "--id", "x", "--title", "x",
                                          "--difficulty", "easy", "--cols", "12", "--colors", "3", "--crop", "0,0,120,80"])
        self.assertEqual(code, 0)
        self.assertIn("legacy flow", err)

    def test_mask_flow_end_to_end(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, mask = make_scene(tmp)
            pal = write_palette(tmp, PALETTE)
            out, prev, rep = (os.path.join(tmp, n) for n in ("o.json", "review.png", "report.txt"))
            code, stdout, _ = self.run_main([src, out, "--mask", mask, "--palette", pal, "--cols", "12",
                                             "--id", "synthetic", "--title", "Thử", "--difficulty", "easy",
                                             "--preview", prev, "--report", rep])
            self.assertEqual(code, 0)
            with open(out, encoding="utf-8") as f:
                level = json.load(f)
            self.assertEqual(validate(level), [])
            self.assertEqual(level["title"], "Thử")
            self.assertTrue(os.path.getsize(prev) > 0)
            with open(rep, encoding="utf-8") as f:
                self.assertIn("IoU", f.read())


class DraftMaskTests(unittest.TestCase):
    def test_draft_keeps_eye_and_excludes_same_hue_coral(self):
        img = Image.new("RGB", (200, 160), BLUE)
        px = img.load()
        for x in range(200):
            for y in range(160):
                if (x - 100) ** 2 + (y - 70) ** 2 <= 45**2:
                    px[x, y] = RED
                if (x - 100) ** 2 + (y - 70) ** 2 <= 8**2:
                    px[x, y] = DARK  # eye inside the body
                if x < 30 and y > 120:
                    px[x, y] = RED  # coral, same hue, separate
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "s.png")
            img.save(src)
            _, m = draft_mask(src, open_r=2, close_r=1)
        self.assertTrue(m[70, 100], "eye must be inside the mask")
        self.assertTrue(m[70, 130])
        self.assertFalse(m[140, 10], "coral must be outside the mask")
        self.assertFalse(m[10, 10])


if __name__ == "__main__":
    unittest.main()
