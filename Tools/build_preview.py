#!/usr/bin/env python3
"""Assemble the self-contained design preview.

Inlines two things into `docs/preview/template.html` and writes `docs/preview/index.html`:

* the painted placeholder images, from `images.json`; and
* the bundled typefaces, subset to the glyphs the preview actually sets and encoded as woff2.

The fonts matter. Both moods in the design specify real families, and a preview set in a
substitute face is not a preview of this design — but the full twelve faces come to 1.1 MB of
base64, so they are subset first, which brings it to about 120 KB.

    python3 Tools/make_preview_images.py   # once, or after changing the paintings
    python3 Tools/build_preview.py
"""

from __future__ import annotations

import base64
import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "docs" / "preview" / "template.html"
IMAGES = ROOT / "docs" / "preview" / "images.json"
FONT_DIR = ROOT / "Tradewind" / "Resources" / "Fonts"
OUTPUT = ROOT / "docs" / "preview" / "index.html"

IMAGE_PLACEHOLDER = "__IMAGES__"
FONT_PLACEHOLDER = "/* __FONTS__ */"

# Latin text, digits, punctuation and the few symbols the mockup sets.
SUBSET = (
    "U+0020-007E,U+00A0,U+00B0,U+00B7,U+00D7,U+2013,U+2014,U+2018-201D,U+2022,U+2026,"
    "U+2212,U+00B1,U+2191,U+2192,U+2197,U+2713,U+25AE,U+21BB,U+25CF,U+25C6,U+25CB,U+2299"
)

# PostScript stem -> (CSS family, weight). Mirrors Shared/DesignSystem/Fonts.swift.
FACES = {
    "InstrumentSerif-Regular": ("Instrument Serif", 400),
    "DMSans-Regular": ("DM Sans", 400),
    "DMSans-Medium": ("DM Sans", 500),
    "DMSans-Bold": ("DM Sans", 700),
    "DMMono-Regular": ("DM Mono", 400),
    "DMMono-Medium": ("DM Mono", 500),
    "SpaceGrotesk-Regular": ("Space Grotesk", 400),
    "SpaceGrotesk-Medium": ("Space Grotesk", 500),
    "SpaceGrotesk-Bold": ("Space Grotesk", 700),
    "JetBrainsMono-Regular": ("JetBrains Mono", 400),
    "JetBrainsMono-Medium": ("JetBrains Mono", 500),
    "JetBrainsMono-Bold": ("JetBrains Mono", 700),
}


def inline_fonts() -> str:
    """Subset each bundled face and return the @font-face rules, or a comment if tooling is absent."""
    if not FONT_DIR.is_dir():
        return "/* fonts not bundled */"
    try:
        subprocess.run(["pyftsubset", "--help"], capture_output=True, check=True)
    except (OSError, subprocess.CalledProcessError):
        print(
            "  ! pyftsubset unavailable (pip install fonttools brotli) — the preview will fall "
            "back to system faces",
            file=sys.stderr,
        )
        return "/* pyftsubset unavailable at build time; using fallback faces */"

    rules, binary = [], 0
    with tempfile.TemporaryDirectory() as tmp:
        for stem, (family, weight) in FACES.items():
            source = FONT_DIR / f"{stem}.ttf"
            if not source.exists():
                print(f"  ! missing {source.name}", file=sys.stderr)
                continue
            target = os.path.join(tmp, f"{stem}.woff2")
            subprocess.run(
                [
                    "pyftsubset", str(source), f"--unicodes={SUBSET}", "--flavor=woff2",
                    "--layout-features=kern,liga", f"--output-file={target}",
                ],
                check=True, capture_output=True,
            )
            blob = pathlib.Path(target).read_bytes()
            binary += len(blob)
            rules.append(
                "@font-face{font-family:'%s';font-style:normal;font-weight:%d;"
                "font-display:block;src:url(data:font/woff2;base64,%s) format('woff2')}"
                % (family, weight, base64.b64encode(blob).decode("ascii"))
            )
    print(f"  fonts: {len(rules)} faces, {binary // 1024} KB subset")
    return "\n".join(rules)


def main() -> int:
    if not IMAGES.exists():
        sys.exit("docs/preview/images.json is missing — run Tools/make_preview_images.py first")

    template = TEMPLATE.read_text(encoding="utf-8")
    if IMAGE_PLACEHOLDER not in template or FONT_PLACEHOLDER not in template:
        sys.exit("template is missing a placeholder — expected __IMAGES__ and /* __FONTS__ */")

    images = json.loads(IMAGES.read_text(encoding="utf-8"))
    # No characters that could end the surrounding <script> element early.
    payload = json.dumps(images, separators=(",", ":")).replace("</", "<\\/")

    page = template.replace(FONT_PLACEHOLDER, inline_fonts())
    page = page.replace(IMAGE_PLACEHOLDER, payload)

    OUTPUT.write_text(page, encoding="utf-8")
    print(f"wrote {OUTPUT.relative_to(ROOT)} ({len(page) // 1024} KB, {len(images)} images)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
