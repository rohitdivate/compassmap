#!/usr/bin/env python3
"""Assemble the self-contained design preview.

Inlines the painted placeholder images into `docs/preview/template.html` and writes
`docs/preview/index.html`. One file, no external requests — which is both what the published
page's content policy requires and what makes the preview openable straight from a clone.

    python3 Tools/make_preview_images.py   # once, or after changing the paintings
    python3 Tools/build_preview.py
"""

from __future__ import annotations

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE = os.path.join(ROOT, "docs", "preview", "template.html")
IMAGES = os.path.join(ROOT, "docs", "preview", "images.json")
OUTPUT = os.path.join(ROOT, "docs", "preview", "index.html")

PLACEHOLDER = "__IMAGES__"


def main() -> int:
    if not os.path.exists(IMAGES):
        sys.exit("docs/preview/images.json is missing — run Tools/make_preview_images.py first")

    with open(TEMPLATE, encoding="utf-8") as handle:
        template = handle.read()
    with open(IMAGES, encoding="utf-8") as handle:
        images = json.load(handle)

    if PLACEHOLDER not in template:
        sys.exit(f"{PLACEHOLDER} not found in the template — nothing to inline")

    # Compact, and with no characters that could end the surrounding <script> element early.
    payload = json.dumps(images, separators=(",", ":")).replace("</", "<\\/")
    page = template.replace(PLACEHOLDER, payload)

    with open(OUTPUT, "w", encoding="utf-8") as handle:
        handle.write(page)

    print(f"wrote {os.path.relpath(OUTPUT, ROOT)} ({len(page) // 1024} KB, {len(images)} images)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
