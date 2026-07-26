#!/usr/bin/env python3
"""Paint the placeholder images used by the design preview.

The preview needs something in the photo slots, and it must be self-contained — the published
page blocks every external request. These are deliberately painterly abstractions rather than
anything that could be mistaken for a real photograph of a real place: gradients, a light
source, and a few soft shapes.

    pip install pillow
    python3 Tools/make_preview_images.py

Writes base64 JPEGs to docs/preview/images.json, which build_preview.py inlines.
"""

from __future__ import annotations

import base64
import io
import json
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "docs", "preview", "images.json")

WIDTH, HEIGHT = 480, 360
SUPERSAMPLE = 2


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def sky(size, stops):
    """Vertical gradient through an arbitrary number of stops."""
    width, height = size
    strip = Image.new("RGB", (1, height))
    pixels = strip.load()
    for y in range(height):
        t = y / max(1, height - 1)
        # Find the pair of stops this row falls between.
        for i in range(len(stops) - 1):
            lo, hi = stops[i], stops[i + 1]
            if lo[0] <= t <= hi[0]:
                span = max(1e-6, hi[0] - lo[0])
                pixels[0, y] = lerp(lo[1], hi[1], (t - lo[0]) / span)
                break
        else:
            pixels[0, y] = stops[-1][1]
    return strip.resize((width, height), Image.BILINEAR)


def soft_shape(layer_size, drawer, blur):
    layer = Image.new("RGBA", layer_size, (0, 0, 0, 0))
    drawer(ImageDraw.Draw(layer))
    return layer.filter(ImageFilter.GaussianBlur(blur))


def grain(image, amount=6):
    """A little noise so the gradients do not read as flat vector art."""
    import random

    random.seed(7)
    noise = Image.new("L", image.size)
    noise.putdata([random.randint(128 - amount, 128 + amount) for _ in range(image.size[0] * image.size[1])])
    return Image.blend(image, Image.merge("RGB", (noise, noise, noise)), 0.06)


def waterfall(size):
    """Deep jungle, mist, and a pale streak of falling water."""
    width, height = size
    base = sky(size, [
        (0.0, (0x14, 0x3A, 0x2B)),
        (0.45, (0x1E, 0x5B, 0x3C)),
        (0.75, (0x38, 0x7A, 0x50)),
        (1.0, (0x14, 0x33, 0x28)),
    ])

    # Canopy shapes, dark against the light behind them.
    def canopy(draw):
        for i in range(9):
            x = width * (0.05 + i * 0.12)
            r = width * (0.16 + 0.05 * math.sin(i * 1.7))
            draw.ellipse([x - r, -r * 0.5, x + r, r * 1.2], fill=(0x08, 0x22, 0x18, 210))
        for i in range(6):
            x = width * (0.0 + i * 0.2)
            r = width * 0.2
            draw.ellipse([x - r, height - r, x + r, height + r * 0.9], fill=(0x06, 0x1C, 0x14, 190))

    base = Image.alpha_composite(base.convert("RGBA"), soft_shape(size, canopy, width * 0.02))

    # The fall itself: a bright vertical band with mist at its foot.
    def water(draw):
        cx = width * 0.52
        draw.polygon(
            [
                (cx - width * 0.045, height * 0.10),
                (cx + width * 0.045, height * 0.10),
                (cx + width * 0.085, height * 0.72),
                (cx - width * 0.085, height * 0.72),
            ],
            fill=(0xEC, 0xF7, 0xEF, 225),
        )

    base = Image.alpha_composite(base, soft_shape(size, water, width * 0.012))

    def mist(draw):
        draw.ellipse(
            [width * 0.30, height * 0.62, width * 0.74, height * 0.92],
            fill=(0xD8, 0xEE, 0xE2, 150),
        )

    return Image.alpha_composite(base, soft_shape(size, mist, width * 0.06)).convert("RGB")


def lagoon(size):
    """Turquoise water, hot sand, a low sun."""
    width, height = size
    base = sky(size, [
        (0.0, (0xFF, 0xC9, 0x7A)),
        (0.30, (0x6E, 0xC8, 0xC8)),
        (0.62, (0x18, 0x8F, 0xA0)),
        (0.80, (0xE8, 0xD6, 0xAE)),
        (1.0, (0xC9, 0xA9, 0x76)),
    ])

    def sun(draw):
        cx, cy, r = width * 0.74, height * 0.16, width * 0.075
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(0xFF, 0xF4, 0xD2, 255))

    base = Image.alpha_composite(base.convert("RGBA"), soft_shape(size, sun, width * 0.03))

    # Sun glitter on the water, brightest directly below the sun.
    def shimmer(draw):
        for i in range(22):
            t = i / 21
            y = height * (0.34 + t * 0.42)
            spread = width * (0.03 + t * 0.20)
            cx = width * 0.74 - t * width * 0.06
            draw.line(
                [(cx - spread, y), (cx + spread, y)],
                fill=(0xFF, 0xF6, 0xDC, int(150 * (1 - t))),
                width=max(1, int(height * 0.006)),
            )

    base = Image.alpha_composite(base, soft_shape(size, shimmer, width * 0.006))

    # Two palm fronds cutting into the frame from the left.
    def frond(draw):
        for angle, length in ((-24, 0.42), (-6, 0.34), (14, 0.38)):
            rad = math.radians(angle)
            x0, y0 = -width * 0.04, height * 0.14
            x1 = x0 + math.cos(rad) * width * length
            y1 = y0 + math.sin(rad) * width * length
            draw.line([(x0, y0), (x1, y1)], fill=(0x0E, 0x33, 0x2A, 220), width=int(height * 0.035))

    return Image.alpha_composite(base, soft_shape(size, frond, width * 0.008)).convert("RGB")


def temple(size):
    """Violet dusk over a silhouetted roofline."""
    width, height = size
    base = sky(size, [
        (0.0, (0x2A, 0x11, 0x50)),
        (0.42, (0x83, 0x2B, 0x63)),
        (0.68, (0xE0, 0x6B, 0x4E)),
        (0.84, (0xFF, 0xB4, 0x5E)),
        (1.0, (0x3A, 0x1B, 0x3C)),
    ])

    def sun(draw):
        cx, cy, r = width * 0.30, height * 0.70, width * 0.10
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(0xFF, 0xE6, 0xA8, 240))

    base = Image.alpha_composite(base.convert("RGBA"), soft_shape(size, sun, width * 0.05))

    # A stepped roofline, the one recognisable shape in the picture.
    def roofline(draw):
        baseline = height * 0.86
        draw.polygon(
            [
                (width * 0.52, baseline),
                (width * 0.62, height * 0.44),
                (width * 0.66, height * 0.50),
                (width * 0.70, height * 0.36),
                (width * 0.76, height * 0.52),
                (width * 0.86, baseline),
            ],
            fill=(0x1C, 0x0C, 0x24, 255),
        )
        draw.rectangle([0, baseline, width, height], fill=(0x18, 0x0A, 0x20, 255))

    return Image.alpha_composite(base, soft_shape(size, roofline, width * 0.004)).convert("RGB")


def hills(size):
    """Tea-country ridgelines fading into haze."""
    width, height = size
    base = sky(size, [
        (0.0, (0xD8, 0xE3, 0xC9)),
        (0.35, (0x9F, 0xBE, 0x9A)),
        (0.70, (0x53, 0x7E, 0x54)),
        (1.0, (0x22, 0x40, 0x2C)),
    ])

    greens = [(0x7F, 0xA5, 0x7C), (0x5C, 0x86, 0x5E), (0x3E, 0x66, 0x47), (0x27, 0x48, 0x35)]
    for index, colour in enumerate(greens):
        t = index / (len(greens) - 1)
        top = height * (0.34 + t * 0.34)

        def ridge(draw, top=top, colour=colour, index=index):
            points = [(-10, height + 10)]
            for step in range(0, 41):
                x = width * step / 40
                wobble = math.sin(step * 0.55 + index * 2.1) * height * 0.045
                points.append((x, top + wobble))
            points.append((width + 10, height + 10))
            draw.polygon(points, fill=colour + (255,))

        base = Image.alpha_composite(base.convert("RGBA"), soft_shape(size, ridge, width * 0.006))

    return base.convert("RGB")


PAINTINGS = {
    "waterfall": waterfall,
    "lagoon": lagoon,
    "temple": temple,
    "hills": hills,
}


def encode(image: Image.Image) -> str:
    buffer = io.BytesIO()
    image.save(buffer, "JPEG", quality=74, optimize=True)
    return "data:image/jpeg;base64," + base64.b64encode(buffer.getvalue()).decode("ascii")


def main() -> int:
    size = (WIDTH * SUPERSAMPLE, HEIGHT * SUPERSAMPLE)
    payload = {}
    for name, painter in PAINTINGS.items():
        image = grain(painter(size)).resize((WIDTH, HEIGHT), Image.LANCZOS)
        payload[name] = encode(image)
        print(f"  {name}: {len(payload[name]) // 1024} KB")

    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=0)
        handle.write("\n")
    print(f"wrote {os.path.relpath(OUTPUT, ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
