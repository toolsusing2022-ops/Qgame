#!/usr/bin/env python3
"""Build or check content/catalog.json (gameplay spec GS-13.8).

One entry per level: level_id, file (relative to content/), content_version,
optional palette_compat_from, layout_hash, content_hash.

- New level: content_version 1.
- content_hash changed: content_version + 1 and palette_compat_from is dropped. This tool never
  sets palette_compat_from; that claim needs the (not yet built) content review tool.
- Every level must pass validate_level --strict before it is catalogued.

Usage:
    python3 build_catalog.py            # rewrite content/catalog.json
    python3 build_catalog.py --check    # exit 1 if the catalog is stale or invalid
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from level_hash import content_hash, layout_hash  # noqa: E402
from validate_level import load_level, validate  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONTENT = os.path.join(ROOT, "content")
LEVEL_DIRS = ("levels", "trials")
CATALOG_VERSION = 1


def find_level_files(content_dir: str) -> list[str]:
    out = []
    for sub in LEVEL_DIRS:
        d = os.path.join(content_dir, sub)
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            if name.endswith(".json"):
                out.append(f"{sub}/{name}")
    return out


def load_catalog(path: str) -> dict:
    if not os.path.exists(path):
        return {"catalog_version": CATALOG_VERSION, "levels": []}
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def build(content_dir: str, previous: dict) -> tuple[dict, list[str]]:
    """Return (catalog, problems). problems is non-empty if some level is not catalogable."""
    prev = {e["level_id"]: e for e in previous.get("levels", [])}
    problems = []
    entries = []
    seen_ids = {}
    for rel in find_level_files(content_dir):
        data = load_level(os.path.join(content_dir, rel))
        issues = validate(data)
        if issues:
            problems.append(f"{rel}: " + ", ".join(sorted({i.code for i in issues})))
            continue
        level_id = data["id"]
        if level_id in seen_ids:
            problems.append(f"{rel}: id '{level_id}' trùng với {seen_ids[level_id]}")
            continue
        seen_ids[level_id] = rel
        entry = {
            "level_id": level_id,
            "file": rel,
            "content_version": 1,
            "layout_hash": layout_hash(data),
            "content_hash": content_hash(data),
        }
        old = prev.get(level_id)
        if old is not None:
            if old["content_hash"] == entry["content_hash"]:
                entry["content_version"] = old["content_version"]
                if "palette_compat_from" in old:
                    entry["palette_compat_from"] = old["palette_compat_from"]
            else:
                entry["content_version"] = old["content_version"] + 1
        entries.append(entry)
    entries.sort(key=lambda e: e["level_id"])
    return {"catalog_version": CATALOG_VERSION, "levels": entries}, problems


def dump(catalog: dict) -> str:
    return json.dumps(catalog, ensure_ascii=False, indent=2) + "\n"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true", help="do not write; fail if catalog differs")
    ap.add_argument("--content", default=CONTENT)
    args = ap.parse_args(argv)

    path = os.path.join(args.content, "catalog.json")
    previous = load_catalog(path)
    catalog, problems = build(args.content, previous)
    for p in problems:
        print(f"FAIL {p}")
    if problems:
        return 1

    text = dump(catalog)
    if args.check:
        current = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
        if current != text:
            print(f"FAIL {path} không khớp với level hiện tại; chạy lại build_catalog.py")
            return 1
        print(f"OK   {path} ({len(catalog['levels'])} level)")
        return 0

    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"Đã ghi {path} ({len(catalog['levels'])} level)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
