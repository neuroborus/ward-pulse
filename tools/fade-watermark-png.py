#!/usr/bin/env python3
"""Apply a bottom-weighted alpha dissolve to the mono watermark PNG.

The fade is relative to the opaque content bounds (not the full canvas),
so the pulse softens toward the strip stack on the watch face.

Depends only on Pillow (no numpy).
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image


def fade_bottom(path: Path, *, keep_top: float = 0.28, floor: float = 0.06) -> None:
    im = Image.open(path).convert("RGBA")
    width, height = im.size
    px = im.load()
    assert px is not None

    y0, y1 = None, None
    for y in range(height):
        if any(px[x, y][3] > 12 for x in range(width)):
            if y0 is None:
                y0 = y
            y1 = y
    if y0 is None or y1 is None:
        raise SystemExit(f"no opaque content in {path}")

    span = max(1, y1 - y0)
    for y in range(y0, y1 + 1):
        t = (y - y0) / span
        if t <= keep_top:
            factor = 1.0
        else:
            u = (t - keep_top) / (1.0 - keep_top)
            u = u * u * (3.0 - 2.0 * u)  # smoothstep
            factor = 1.0 - u * (1.0 - floor)
        for x in range(width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (r, g, b, max(0, min(255, int(a * factor))))

    im.save(path)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("usage: fade-watermark-png.py <png> [keep_top] [floor]")
    keep = float(sys.argv[2]) if len(sys.argv) > 2 else 0.28
    floor = float(sys.argv[3]) if len(sys.argv) > 3 else 0.06
    fade_bottom(Path(sys.argv[1]), keep_top=keep, floor=floor)
    print(f"faded {sys.argv[1]} keep_top={keep} floor={floor}")
