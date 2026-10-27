#!/usr/bin/env python3
"""Post-process a Godot web export for hosts that cap the size of a single file.

Splits <dir>/index.wasm into index.part0.wasm .. index.partN-1.wasm (each <= --max-mb) and, with --pck-alias,
renames index.pck to a served name. Both are written into index.html (WASM_PARTS, PCK_ALIAS), whose shell
(web_shell/shell.html) maps the engine's requests onto them. Hosts without such limits (GitHub Pages, itch.io,
a plain web server) can serve the export unchanged.

Usage: python3 tools/web/package_web.py build/web [--max-mb 14] [--pck-alias index.pck.wasm]
"""
import argparse
import os
import re
import sys


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--max-mb", type=float, default=14.0)
    ap.add_argument("--pck-alias", default="")
    args = ap.parse_args(argv)
    wasm = os.path.join(args.dir, "index.wasm")
    html = os.path.join(args.dir, "index.html")
    data = open(wasm, "rb").read()
    limit = int(args.max_mb * 1024 * 1024)
    parts = [data[i:i + limit] for i in range(0, len(data), limit)]
    for i, chunk in enumerate(parts):
        with open(os.path.join(args.dir, f"index.part{i}.wasm"), "wb") as f:
            f.write(chunk)
    text = open(html, encoding="utf-8").read()
    new, n = re.subn(r"const WASM_PARTS = \d+;", f"const WASM_PARTS = {len(parts)};", text)
    if n != 1:
        print("index.html has no WASM_PARTS constant (was it exported with web_shell/shell.html?)")
        return 1
    if args.pck_alias:
        new, n = re.subn(r'const PCK_ALIAS = "[^"]*";', f'const PCK_ALIAS = "{args.pck_alias}";', new)
        if n != 1:
            print("index.html has no PCK_ALIAS constant")
            return 1
        os.replace(os.path.join(args.dir, "index.pck"), os.path.join(args.dir, args.pck_alias))
    open(html, "w", encoding="utf-8").write(new)
    os.remove(wasm)
    print(f"{len(data)} bytes -> {len(parts)} parts of <= {limit} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
