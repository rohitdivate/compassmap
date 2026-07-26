#!/usr/bin/env python3
"""Draw Tradewind's app icon.

The mark is the same dart the app uses for its arrow — `ArrowShape` in
`Shared/DesignSystem/CompassRose.swift` — over Tropical Spritz's Sunset Wash, inside a ring of
compass ticks. Generated rather than hand-drawn so the icon and the in-app arrow can never
drift apart.

An app icon is the one place the "one gradient per screen" rule cannot apply — there is no
screen, and a flat cream tile would vanish on a home screen. So it uses the mood's hero
gradient, which is the gradient that mood does sanction.

    pip install pillow
    python3 Tools/make_appicon.py

Writes Tradewind/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png.
"""

from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(
    ROOT, "Tradewind", "Resources", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png"
)

SIZE = 1024
SUPERSAMPLE = 4  # draw large, downscale once: cheap anti-aliasing for the whole composition

# Tropical Spritz — the default theme. Sunset Wash runs coral to Paloma Pink to a violet, and
# the dart is the cream canvas so it reads as paper cut out of the sunset.
DEEP = (0xB0, 0x6A, 0xB3)   # Sunset Wash, far end
MID = (0xFF, 0x6B, 0x8B)    # Paloma Pink
TOP = (0xFF, 0x8C, 0x42)    # Sunset Coral
ACCENT = (0xB8, 0xE6, 0x2E) # Margarita Lime, for the tick ring
ARROW_LOW = (0xFF, 0xE3, 0xC8)
ARROW_HIGH = (0xFF, 0xF6, 0xE9)  # Piña Cream


def lerp(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size: int) -> Image.Image:
    """Three-stop vertical gradient, deepest at the bottom."""
    image = Image.new("RGB", (1, size))
    pixels = image.load()
    for y in range(size):
        t = y / (size - 1)
        # Stops at 0.0 / 0.55 / 1.0, top to bottom.
        if t < 0.55:
            colour = lerp(TOP, MID, t / 0.55)
        else:
            colour = lerp(MID, DEEP, (t - 0.55) / 0.45)
        pixels[0, y] = colour
    return image.resize((size, size), Image.BILINEAR)


def radial_glow(size: int, centre: tuple[float, float], radius: float) -> Image.Image:
    """A soft light source, built as an alpha mask and blurred."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    steps = 42
    for step in range(steps, 0, -1):
        t = step / steps
        r = radius * t
        alpha = int(150 * (1 - t) ** 1.6)
        draw.ellipse(
            [centre[0] - r, centre[1] - r, centre[0] + r, centre[1] + r],
            fill=alpha,
        )
    return mask.filter(ImageFilter.GaussianBlur(radius * 0.10))


def quad_bezier(p0, p1, p2, steps: int = 48):
    """Samples a quadratic curve, so the icon's silhouette matches ArrowShape exactly."""
    points = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        points.append(
            (
                u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
                u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1],
            )
        )
    return points


def arrow_polygon(box: tuple[float, float, float, float]) -> list[tuple[float, float]]:
    """The dart from ArrowShape, mapped into `box` (x, y, width, height)."""
    x, y, w, h = box

    def p(fx: float, fy: float) -> tuple[float, float]:
        return (x + fx * w, y + fy * h)

    points: list[tuple[float, float]] = []
    points += quad_bezier(p(0.5, 0.0), p(0.74, 0.42), p(0.94, 0.88))
    points += quad_bezier(p(0.94, 0.88), p(0.68, 0.80), p(0.5, 0.66))
    points += quad_bezier(p(0.5, 0.66), p(0.32, 0.80), p(0.06, 0.88))
    points += quad_bezier(p(0.06, 0.88), p(0.26, 0.42), p(0.5, 0.0))
    return points


def vertical_gradient_fill(size: tuple[int, int], low, high) -> Image.Image:
    """Gradient used to fill the arrow, brightest at the tip."""
    width, height = size
    image = Image.new("RGB", (1, height))
    pixels = image.load()
    for y in range(height):
        pixels[0, y] = lerp(high, low, y / max(1, height - 1))
    return image.resize((width, height), Image.BILINEAR)


def compass_ticks(draw: ImageDraw.ImageDraw, size: int) -> None:
    """A ring of ticks, longer at the cardinals — the app's compass rose, abbreviated."""
    centre = size / 2
    radius = size * 0.415
    for degrees in range(0, 360, 15):
        is_cardinal = degrees % 90 == 0
        length = size * (0.055 if is_cardinal else 0.032)
        width = max(1, int(size * (0.010 if is_cardinal else 0.006)))
        alpha = 235 if is_cardinal else 120
        radians = math.radians(degrees - 90)
        outer = (centre + math.cos(radians) * radius, centre + math.sin(radians) * radius)
        inner = (
            centre + math.cos(radians) * (radius - length),
            centre + math.sin(radians) * (radius - length),
        )
        draw.line([inner, outer], fill=ACCENT + (alpha,), width=width)


def tint(size: int, colour: tuple[int, int, int], mask: Image.Image, strength: float) -> Image.Image:
    """An RGBA layer of `colour`, using `mask` as its alpha, ready to composite."""
    layer = Image.new("RGBA", (size, size), colour + (0,))
    layer.putalpha(mask.point(lambda v: min(255, int(v * strength))))
    return layer


def build() -> Image.Image:
    size = SIZE * SUPERSAMPLE
    canvas = gradient(size).convert("RGBA")

    # Light coming from the upper right, as it does on every screen in the app. Composited as a
    # translucent layer rather than a hard mask, so the gradient underneath survives.
    glow = radial_glow(size, (size * 0.80, size * 0.14), size * 0.66)
    canvas = Image.alpha_composite(canvas, tint(size, ACCENT, glow, 0.85))

    ticks = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    compass_ticks(ImageDraw.Draw(ticks), size)
    canvas = Image.alpha_composite(canvas, ticks)

    # The arrow: a gradient fill clipped to the dart, with a halo behind it.
    arrow_box = (size * 0.30, size * 0.165, size * 0.40, size * 0.67)
    polygon = arrow_polygon(arrow_box)

    shape_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(shape_mask).polygon(polygon, fill=255)

    halo = shape_mask.filter(ImageFilter.GaussianBlur(size * 0.030))
    canvas = Image.alpha_composite(canvas, tint(size, ARROW_HIGH, halo, 0.55))

    arrow_fill = vertical_gradient_fill((size, size), ARROW_LOW, ARROW_HIGH).convert("RGBA")
    canvas = Image.composite(arrow_fill, canvas, shape_mask).convert("RGBA")

    # A hairline highlight along the edge lifts it off the background.
    edge = shape_mask.filter(ImageFilter.FIND_EDGES).filter(
        ImageFilter.GaussianBlur(size * 0.0020)
    )
    canvas = Image.alpha_composite(canvas, tint(size, (255, 255, 255), edge, 0.5))

    return canvas.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")


def main() -> int:
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    build().save(OUTPUT, "PNG")
    print(f"wrote {os.path.relpath(OUTPUT, ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
