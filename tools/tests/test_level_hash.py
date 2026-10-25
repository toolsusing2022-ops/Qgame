import copy
import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from build_catalog import build, dump  # noqa: E402
from level_hash import content_hash, content_string, layout_hash, layout_string  # noqa: E402
from validate_level import load_level, validate  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
FIXTURES = os.path.join(ROOT, "tests", "fixtures", "levels")

F1 = {
    "schema_version": 1,
    "id": "fixture_f1",
    "title": "F1",
    "difficulty": "easy",
    "modes": ["journey", "zen"],
    "width": 3,
    "height": 2,
    "palette": [
        {"id": 0, "hex": "#2f86b8", "count": 2},
        {"id": 1, "hex": "#e2553d", "count": 2},
        {"id": 2, "hex": "#f3dcd2", "count": 1},
    ],
    "cells": [0, 1, 2, -1, 0, 1],
}

F1_LAYOUT = "b09305c9fea477ff6a5ba10b4f13a255ab9892d484f27d7b40d1bf9f3910f8aa"
F1_CONTENT = "dc70ea18d4a5edfd1dcf79ac21a466ca6b417ddc8b6b97ebcdd453542e0c7a14"
F9_CONTENT = "5206fe955572afbe7e8fed4d516fc98aa36c5bce1df98c6eaf4a29c8ea9a38ca"
F10_LAYOUT = "910660ec8fccc6ff44459b418df8e86c241d31aee0e8f36db33b5195cd9cc4c8"
F10_CONTENT = "24c69fac36cfbf754ad12182b949bfca8c00c3568386c0f231aee71c25db0581"


class ReferenceHashes(unittest.TestCase):
    """TC-13.1: reference values from GS-13.2."""

    def test_f1(self):
        self.assertEqual(layout_hash(F1), F1_LAYOUT)
        self.assertEqual(content_hash(F1), F1_CONTENT)

    def test_f9_only_hex_changed(self):
        f9 = copy.deepcopy(F1)
        f9["palette"][1]["hex"] = "#c9362f"
        self.assertEqual(layout_hash(f9), F1_LAYOUT)
        self.assertEqual(content_hash(f9), F9_CONTENT)

    def test_f10_layout_changed(self):
        f10 = copy.deepcopy(F1)
        f10["cells"][5] = 0
        f10["palette"][0]["count"] = 3
        f10["palette"][1]["count"] = 1
        self.assertEqual(layout_hash(f10), F10_LAYOUT)
        self.assertEqual(content_hash(f10), F10_CONTENT)

    def test_canonical_strings(self):
        self.assertEqual(layout_string(F1), "pbart-layout-1|w=3|h=2|n=3|cells=0,1,2,-1,0,1")
        self.assertEqual(
            content_string(F1),
            "pbart-content-1|schema=1|w=3|h=2|palette=0:#2f86b8,1:#e2553d,2:#f3dcd2|cells=0,1,2,-1,0,1",
        )


class CanonicalInvariance(unittest.TestCase):
    """TC-13.3: key order and hex case do not change the hash; non-hashed fields are ignored."""

    def test_key_order_and_hex_case(self):
        shuffled = json.loads(json.dumps(F1, sort_keys=True))
        shuffled["palette"] = [dict(reversed(list(e.items()))) for e in shuffled["palette"]]
        shuffled["palette"][0]["hex"] = "#2F86B8"
        self.assertEqual(layout_hash(shuffled), F1_LAYOUT)
        self.assertEqual(content_hash(shuffled), F1_CONTENT)

    def test_palette_order_in_file_does_not_matter(self):
        reordered = copy.deepcopy(F1)
        reordered["palette"] = list(reversed(reordered["palette"]))
        self.assertEqual(content_hash(reordered), F1_CONTENT)

    def test_non_hashed_fields(self):
        other = copy.deepcopy(F1)
        other.update(title="khác", id="other_id", difficulty="relax", modes=["zen"], mask=[0, 1, 1, 0, 0, 1])
        other["palette"][0]["name"] = "water"
        self.assertEqual(layout_hash(other), F1_LAYOUT)
        self.assertEqual(content_hash(other), F1_CONTENT)


class FixtureManifest(unittest.TestCase):
    """TC-2.10 (Python side): fixtures produce exactly the error codes listed in the shared manifest.
    The Godot loader test reads the same manifest."""

    def test_manifest(self):
        with open(os.path.join(FIXTURES, "expected_errors.json"), encoding="utf-8") as f:
            manifest = json.load(f)
        self.assertGreaterEqual(len(manifest), 10)
        for name, expected in manifest.items():
            with self.subTest(name=name):
                data = load_level(os.path.join(FIXTURES, name))
                codes = sorted({i.code for i in validate(data) if i.severity == "error"})
                self.assertEqual(codes, expected)


def _write_level(dirpath, rel, data):
    path = os.path.join(dirpath, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f)


class Catalog(unittest.TestCase):
    """GS-13.8: content_version bookkeeping."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = self.tmp.name

    def test_new_level_starts_at_version_1(self):
        _write_level(self.dir, "levels/f1.json", F1)
        catalog, problems = build(self.dir, {})
        self.assertEqual(problems, [])
        (entry,) = catalog["levels"]
        self.assertEqual(entry["level_id"], "fixture_f1")
        self.assertEqual(entry["file"], "levels/f1.json")
        self.assertEqual(entry["content_version"], 1)
        self.assertEqual(entry["layout_hash"], F1_LAYOUT)
        self.assertEqual(entry["content_hash"], F1_CONTENT)
        self.assertNotIn("palette_compat_from", entry)

    def test_unchanged_level_keeps_version_and_compat(self):
        _write_level(self.dir, "levels/f1.json", F1)
        prev = {"levels": [{"level_id": "fixture_f1", "content_version": 4, "palette_compat_from": 3,
                            "content_hash": F1_CONTENT, "layout_hash": F1_LAYOUT, "file": "levels/f1.json"}]}
        catalog, _ = build(self.dir, prev)
        self.assertEqual(catalog["levels"][0]["content_version"], 4)
        self.assertEqual(catalog["levels"][0]["palette_compat_from"], 3)

    def test_changed_level_bumps_version_and_drops_compat(self):
        f9 = copy.deepcopy(F1)
        f9["palette"][1]["hex"] = "#c9362f"
        _write_level(self.dir, "levels/f1.json", f9)
        prev = {"levels": [{"level_id": "fixture_f1", "content_version": 4, "palette_compat_from": 3,
                            "content_hash": F1_CONTENT, "layout_hash": F1_LAYOUT, "file": "levels/f1.json"}]}
        catalog, _ = build(self.dir, prev)
        entry = catalog["levels"][0]
        self.assertEqual(entry["content_version"], 5)
        self.assertNotIn("palette_compat_from", entry)

    def test_invalid_or_warning_level_is_rejected(self):
        bad = copy.deepcopy(F1)
        bad["palette"][0]["count"] = 3
        _write_level(self.dir, "levels/bad.json", bad)
        catalog, problems = build(self.dir, {})
        self.assertEqual(catalog["levels"], [])
        self.assertEqual(len(problems), 1)
        self.assertIn("count_mismatch", problems[0])

    def test_duplicate_level_id_is_rejected(self):
        _write_level(self.dir, "levels/a.json", F1)
        _write_level(self.dir, "trials/b.json", F1)
        _, problems = build(self.dir, {})
        self.assertEqual(len(problems), 1)
        self.assertIn("trùng", problems[0])

    def test_repo_catalog_is_up_to_date(self):
        content = os.path.join(ROOT, "content")
        with open(os.path.join(content, "catalog.json"), encoding="utf-8") as f:
            current = f.read()
        catalog, problems = build(content, json.loads(current))
        self.assertEqual(problems, [])
        self.assertEqual(dump(catalog), current)


if __name__ == "__main__":
    unittest.main()
