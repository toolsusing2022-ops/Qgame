import copy
import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from validate_level import (  # noqa: E402
    EMPTY_CELL,
    REQUIRED_FIELDS,
    ciede2000,
    main,
    validate,
    validate_file,
)


def valid_level():
    # 3x2 grid:  0 1 2
    #            0 0 1
    return {
        "schema_version": 1,
        "id": "test_squid_01",
        "title": "Mực thử nghiệm",
        "difficulty": "easy",
        "modes": ["journey", "zen"],
        "width": 3,
        "height": 2,
        "palette": [
            {"id": 0, "hex": "#2f86b8", "count": 3, "name": "water"},
            {"id": 1, "hex": "#e2553d", "count": 2},
            {"id": 2, "hex": "#f3dcd2", "count": 1},
        ],
        "cells": [0, 1, 2, 0, 0, 1],
    }


def codes(issues, severity=None):
    return [i.code for i in issues if severity is None or i.severity == severity]


class ValidLevelTests(unittest.TestCase):
    def test_valid_level_has_no_issues(self):
        self.assertEqual(validate(valid_level()), [])

    def test_valid_level_with_empty_cells_and_mask(self):
        lvl = valid_level()
        lvl["cells"] = [0, 1, 2, EMPTY_CELL, 0, 1]
        lvl["palette"][0]["count"] = 2
        lvl["mask"] = [0, 1, 1, 0, 0, 1]
        self.assertEqual(validate(lvl), [])

    def test_uppercase_hex_is_accepted(self):
        lvl = valid_level()
        lvl["palette"][1]["hex"] = "#E2553D"
        self.assertEqual(validate(lvl), [])

    def test_single_mode_is_accepted(self):
        lvl = valid_level()
        lvl["modes"] = ["zen"]
        self.assertEqual(validate(lvl), [])


class MissingAndMalformedTests(unittest.TestCase):
    def test_each_missing_required_field_is_an_error(self):
        for field in REQUIRED_FIELDS:
            with self.subTest(field=field):
                lvl = valid_level()
                del lvl[field]
                issues = validate(lvl)
                self.assertIn("missing_field", codes(issues, "error"))
                self.assertTrue(any(f"'{field}'" in i.message for i in issues))

    def test_missing_palette_field(self):
        lvl = valid_level()
        del lvl["palette"][1]["hex"]
        issues = validate(lvl)
        self.assertIn("missing_field", codes(issues, "error"))
        self.assertTrue(any("palette[1]" in i.message for i in issues))

    def test_legacy_format_is_rejected_with_hint(self):
        legacy = {
            "cols": 3,
            "rows": 2,
            "palette": [{"id": 0, "hex": "#2f86b8", "count": 4}, {"id": 1, "hex": "#e2553d", "count": 2}],
            "cells": [[0, 1, 0], [0, 0, 1]],
        }
        c = codes(validate(legacy), "error")
        self.assertIn("legacy_format", c)
        self.assertIn("cells_not_flat", c)
        self.assertIn("missing_field", c)

    def test_bad_metadata_values(self):
        cases = {
            "bad_schema_version": ("schema_version", 2),
            "bad_id": ("id", "Squid 01"),
            "bad_title": ("title", "   "),
            "bad_difficulty": ("difficulty", "hard"),
        }
        for code, (field, value) in cases.items():
            with self.subTest(code=code):
                lvl = valid_level()
                lvl[field] = value
                self.assertIn(code, codes(validate(lvl), "error"))

    def test_bad_modes(self):
        for modes in ([], ["arcade"], ["zen", "zen"], "zen", None):
            with self.subTest(modes=modes):
                lvl = valid_level()
                lvl["modes"] = modes
                self.assertIn("bad_modes", codes(validate(lvl), "error"))

    def test_bad_cell_values_are_missing_data(self):
        for bad in (None, "1", 1.0, True):
            with self.subTest(value=bad):
                lvl = valid_level()
                lvl["cells"][4] = bad
                issues = validate(lvl)
                self.assertIn("bad_cell_value", codes(issues, "error"))
                self.assertTrue(any("x=1, y=1" in i.message for i in issues))

    def test_unknown_field_is_only_a_warning(self):
        lvl = valid_level()
        lvl["colz"] = 3
        issues = validate(lvl)
        self.assertEqual(codes(issues, "error"), [])
        self.assertIn("unknown_field", codes(issues, "warning"))

    def test_garbage_input_never_raises(self):
        garbage = [
            None,
            [],
            "level",
            {"palette": "x", "cells": None, "width": "3", "height": None, "mask": 5},
            {**valid_level(), "palette": [None, 3, "a"]},
            {**valid_level(), "cells": [[0, 1, 2], [0]]},
            {**valid_level(), "modes": [{"a": 1}]},
        ]
        for g in garbage:
            with self.subTest(data=repr(g)[:60]):
                issues = validate(g)
                self.assertTrue(codes(issues, "error"))


class GridSizeTests(unittest.TestCase):
    def test_invalid_dimensions(self):
        for value in (0, -1, 129, 2.5, True, "3"):
            with self.subTest(width=value):
                lvl = valid_level()
                lvl["width"] = value
                self.assertIn("grid_size", codes(validate(lvl), "error"))

    def test_cells_length_must_match_width_times_height(self):
        lvl = valid_level()
        lvl["height"] = 3
        issues = validate(lvl)
        self.assertIn("grid_size", codes(issues, "error"))
        self.assertTrue(any("cần width*height = 9" in i.message for i in issues))

    def test_cells_missing_one_value(self):
        lvl = valid_level()
        lvl["cells"].pop()
        self.assertIn("grid_size", codes(validate(lvl), "error"))

    def test_no_playable_cells(self):
        lvl = valid_level()
        lvl["cells"] = [EMPTY_CELL] * 6
        self.assertIn("no_playable_cells", codes(validate(lvl), "error"))


class PaletteTests(unittest.TestCase):
    def test_bad_hex_formats(self):
        for bad in ("#12345", "123456", "#12345g", "#1234567", "#abc", 0x123456, None):
            with self.subTest(hex=bad):
                lvl = valid_level()
                lvl["palette"][2]["hex"] = bad
                self.assertIn("bad_hex", codes(validate(lvl), "error"))

    def test_palette_ids_must_equal_their_index(self):
        for ids in ((0, 2, 1), (0, 1, 1), (1, 2, 3), (0, "1", 2)):
            with self.subTest(ids=ids):
                lvl = valid_level()
                for entry, i in zip(lvl["palette"], ids):
                    entry["id"] = i
                self.assertIn("palette_id", codes(validate(lvl), "error"))

    def test_cell_references_unknown_color(self):
        lvl = valid_level()
        lvl["cells"][2] = 9
        issues = validate(lvl)
        self.assertIn("unknown_color", codes(issues, "error"))
        self.assertTrue(any("[9]" in i.message and "x=2, y=0" in i.message for i in issues))

    def test_negative_ids_other_than_empty_are_unknown(self):
        lvl = valid_level()
        lvl["cells"][2] = -2
        self.assertIn("unknown_color", codes(validate(lvl), "error"))

    def test_unused_palette_color(self):
        lvl = valid_level()
        lvl["palette"].append({"id": 3, "hex": "#2a1f22", "count": 0})
        issues = validate(lvl)
        self.assertIn("unused_color", codes(issues, "error"))
        self.assertTrue(any("màu 3" in i.message for i in issues))

    def test_count_mismatch(self):
        lvl = valid_level()
        lvl["palette"][0]["count"] = 4
        self.assertIn("count_mismatch", codes(validate(lvl), "error"))

    def test_negative_count(self):
        lvl = valid_level()
        lvl["palette"][0]["count"] = -3
        self.assertIn("bad_count", codes(validate(lvl), "error"))

    def test_exact_duplicate_color_is_error_case_insensitive(self):
        lvl = valid_level()
        lvl["palette"][2]["hex"] = "#E2553D"
        self.assertIn("duplicate_color", codes(validate(lvl), "error"))

    def test_near_duplicate_color_is_warning_not_error(self):
        # the two blues that coexist in the current Easy level (ΔE00 ≈ 0.4)
        lvl = valid_level()
        lvl["palette"][0]["hex"] = "#267aa1"
        lvl["palette"][2]["hex"] = "#267ba2"
        issues = validate(lvl)
        self.assertEqual(codes(issues, "error"), [])
        self.assertEqual(codes(issues, "warning"), ["near_duplicate_color"])

    def test_similar_color_is_warning(self):
        # the two greys in the current Easy level (ΔE00 ≈ 9.3)
        lvl = valid_level()
        lvl["palette"][0]["hex"] = "#75838f"
        lvl["palette"][2]["hex"] = "#636d7f"
        issues = validate(lvl)
        self.assertEqual(codes(issues, "error"), [])
        self.assertEqual(codes(issues, "warning"), ["similar_color"])

    def test_validator_never_modifies_or_merges_palette(self):
        lvl = valid_level()
        lvl["palette"][2]["hex"] = "#e2563d"
        before = copy.deepcopy(lvl)
        validate(lvl)
        self.assertEqual(lvl, before)


class MaskTests(unittest.TestCase):
    def test_mask_wrong_size(self):
        lvl = valid_level()
        lvl["mask"] = [1, 0, 1]
        self.assertIn("mask_size", codes(validate(lvl), "error"))

    def test_mask_wrong_type(self):
        lvl = valid_level()
        lvl["mask"] = "101010"
        self.assertIn("mask_type", codes(validate(lvl), "error"))

    def test_mask_values_must_be_0_or_1(self):
        for bad in (2, -1, True, 0.5, None):
            with self.subTest(value=bad):
                lvl = valid_level()
                lvl["mask"] = [0, 1, 1, 0, 0, bad]
                self.assertIn("mask_value", codes(validate(lvl), "error"))

    def test_empty_mask(self):
        lvl = valid_level()
        lvl["mask"] = [0] * 6
        self.assertIn("mask_empty", codes(validate(lvl), "error"))

    def test_full_mask_is_warning(self):
        lvl = valid_level()
        lvl["mask"] = [1] * 6
        self.assertEqual(codes(validate(lvl)), ["mask_full"])

    def test_mask_on_empty_cell(self):
        lvl = valid_level()
        lvl["cells"][3] = EMPTY_CELL
        lvl["palette"][0]["count"] = 2
        lvl["mask"] = [0, 1, 1, 1, 0, 1]
        self.assertIn("mask_on_empty", codes(validate(lvl), "error"))

    def test_mask_is_optional(self):
        lvl = valid_level()
        self.assertNotIn("mask", lvl)
        self.assertEqual(validate(lvl), [])


class Ciede2000Tests(unittest.TestCase):
    # Sharma, Wu & Dalal (2005) reference data, incl. hue-wraparound pairs
    REFERENCE = [
        ((50.0, 2.6772, -79.7751), (50.0, 0.0, -82.7485), 2.0425),
        ((50.0, 3.1571, -77.2803), (50.0, 0.0, -82.7485), 2.8615),
        ((50.0, 0.0, 0.0), (50.0, -1.0, 2.0), 2.3669),
        ((50.0, 2.49, -0.001), (50.0, -2.49, 0.0009), 7.1792),
        ((50.0, 2.49, -0.001), (50.0, -2.49, 0.0011), 7.2195),
        ((50.0, 2.5, 0.0), (73.0, 25.0, -18.0), 27.1492),
        ((50.0, 2.5, 0.0), (61.0, -5.0, 29.0), 22.8977),
        ((50.0, 2.5, 0.0), (56.0, -27.0, -3.0), 31.9030),
        ((50.0, 2.5, 0.0), (58.0, 24.0, 15.0), 19.4535),
    ]

    def test_reference_values(self):
        for a, b, expected in self.REFERENCE:
            with self.subTest(a=a, b=b):
                self.assertAlmostEqual(ciede2000(a, b), expected, places=4)
                self.assertAlmostEqual(ciede2000(b, a), expected, places=4)

    def test_identical_is_zero(self):
        self.assertEqual(ciede2000((50, 10, -10), (50, 10, -10)), 0.0)


class FileAndCliTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name, text):
        path = os.path.join(self.tmp.name, name)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        return path

    def run_cli(self, *args):
        out = io.StringIO()
        with redirect_stdout(out):
            code = main(list(args))
        return code, out.getvalue()

    def test_duplicate_json_keys_are_rejected(self):
        text = json.dumps(valid_level())[:-1] + ', "width": 4}'
        self.assertEqual(codes(validate_file(self.write("dup.json", text))), ["invalid_json"])

    def test_nan_is_rejected(self):
        text = json.dumps(valid_level()).replace('"count": 1', '"count": NaN')
        self.assertEqual(codes(validate_file(self.write("nan.json", text))), ["invalid_json"])

    def test_malformed_json(self):
        self.assertEqual(codes(validate_file(self.write("bad.json", "{"))), ["invalid_json"])

    def test_missing_file(self):
        self.assertEqual(codes(validate_file(os.path.join(self.tmp.name, "nope.json"))), ["invalid_json"])

    def test_cli_exit_codes(self):
        ok = self.write("ok.json", json.dumps(valid_level()))
        broken = valid_level()
        del broken["id"]
        bad = self.write("bad.json", json.dumps(broken))
        warn_only = valid_level()
        warn_only["palette"][0]["hex"] = "#267aa1"
        warn_only["palette"][2]["hex"] = "#267ba2"
        warn = self.write("warn.json", json.dumps(warn_only))

        self.assertEqual(self.run_cli(ok)[0], 0)
        self.assertEqual(self.run_cli(bad)[0], 1)
        self.assertEqual(self.run_cli(ok, bad)[0], 1)
        self.assertEqual(self.run_cli(warn)[0], 0)
        self.assertEqual(self.run_cli(warn, "--strict")[0], 1)


class PipelineOutputTests(unittest.TestCase):
    def test_generator_output_conforms_to_schema(self):
        from PIL import Image

        from image_to_beadgrid import build_grid

        img = Image.new("RGB", (60, 40), (47, 134, 184))
        for x in range(20, 40):
            for y in range(10, 30):
                img.putpixel((x, y), (226, 85, 61))
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "src.png")
            img.save(path)
            grid, _ = build_grid(path, cols=6, colors=2, manual_crop=(0, 0, 60, 40))

        level = {"schema_version": 1, "id": "gen_test", "title": "Gen", "difficulty": "easy", "modes": ["zen"], **grid}
        self.assertEqual(validate(level), [])
        self.assertEqual((level["width"], level["height"]), (6, 4))
        self.assertEqual(len(level["cells"]), 24)


if __name__ == "__main__":
    unittest.main()
