#!/usr/bin/env python3
"""Mask the icon's squircle so anything outside becomes truly transparent.

The image generator bakes the transparency checkerboard into the PNG as
actual pixels. This script:
  1. Walks inward from each image edge along the center axis until it finds
     the squircle interior (luminance jumps from ~235 checker grey to ~245
     squircle off-white).
  2. Builds a rounded-rectangle mask matching those bounds with macOS's
     ~22.5%-of-side corner radius.
  3. Applies the mask as the alpha channel and writes the file back in place.

Usage: scripts/fix-icon-transparency.py [path/to/icon.png]
Default: docs/icon.png
"""

from __future__ import annotations

import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter


def detect_squircle_bounds(image: Image.Image) -> tuple[int, int, int, int]:
    """Return (left, top, right, bottom) of the squircle in image pixels.

    Detection: along the center axis, walk inward from each edge until we
    hit a pixel that's clearly *inside the squircle*. The transparency
    checkerboard tiles (grey ~236 and white ~254) are neutral - R, G, B are
    nearly equal. The squircle's off-white has a slight cool tint, so
    B - R >= 1 reliably separates squircle pixels from checker pixels.
    """
    rgb = image.convert("RGB")
    w, h = rgb.size
    cx, cy = w // 2, h // 2

    def is_squircle(px: tuple[int, int, int]) -> bool:
        r, g, b = px
        return b - r >= 2

    def walk(start: int, step: int, axis: str) -> int:
        i = start
        if axis == "y":
            while 0 <= i < h:
                if is_squircle(rgb.getpixel((cx, i))):
                    return i
                i += step
        else:
            while 0 <= i < w:
                if is_squircle(rgb.getpixel((i, cy))):
                    return i
                i += step
        return start + step * 20

    top = walk(0, 1, "y")
    bottom = walk(h - 1, -1, "y")
    left = walk(0, 1, "x")
    right = walk(w - 1, -1, "x")
    return left, top, right, bottom


def make_squircle_mask(size: tuple[int, int], bounds: tuple[int, int, int, int]) -> Image.Image:
    w, h = size
    left, top, right, bottom = bounds
    side = min(right - left, bottom - top)
    radius = int(side * 0.225)  # macOS Big Sur+ icon corner radius

    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([left, top, right, bottom], radius=radius, fill=255)
    # 1px Gaussian softens the alpha edge so the squircle doesn't look stepped.
    return mask.filter(ImageFilter.GaussianBlur(radius=1))


def main() -> int:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/icon.png")
    if not path.exists():
        print(f"icon not found: {path}", file=sys.stderr)
        return 1

    icon = Image.open(path).convert("RGBA")
    bounds = detect_squircle_bounds(icon)
    print(f"detected squircle bounds: {bounds} (image {icon.size})")

    mask = make_squircle_mask(icon.size, bounds)
    r, g, b, _ = icon.split()
    masked = Image.merge("RGBA", (r, g, b, mask))
    masked.save(path)
    print(f"wrote masked icon: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
