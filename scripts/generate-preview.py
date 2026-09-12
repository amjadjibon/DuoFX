#!/usr/bin/env python3
"""Create a technical orientation fixture without replacing the bundled desktop art."""
from pathlib import Path
import math
import struct
import zlib

w, h = 960, 600
rows = bytearray()
for y in range(h):
    rows.append(0)
    for x in range(w):
        u, v = x / w, y / h
        glow = math.exp(-((u - 0.65) ** 2 + (v - 0.35) ** 2) * 8)
        r, g, b = 14 + 20 * glow, 28 + 115 * glow, 43 + 105 * glow
        if x % 80 < 2 or y % 75 < 2:
            r, g, b = r + 20, g + 20, b + 20
        if 70 < x < 430 and 110 < y < 460:
            r, g, b = 31, 49, 66
            if y < 142:
                r, g, b = 43, 66, 81
            if 100 < x < 390 and any(start < y < start + 9 for start in (180, 215, 250, 320, 355)):
                r, g, b = 83, 151, 166
        if 515 < x < 860 and 230 < y < 495:
            r, g, b = 28, 72, 81
            if y > 460 - (x - 545) * 0.55 and 545 < x < 830 and y < 463:
                r, g, b = 92, 203, 184
        # Four different corner colors expose inverted UVs and cropping.
        if x < 24 and y < 24: r, g, b = 255, 64, 64
        if x > w - 25 and y < 24: r, g, b = 64, 255, 64
        if x < 24 and y > h - 25: r, g, b = 64, 64, 255
        if x > w - 25 and y > h - 25: r, g, b = 255, 255, 64
        rows.extend((int(r), int(g), int(b), 255))


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")
out = Path(__file__).resolve().parent.parent / "build/fixtures/Orientation.png"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_bytes(png)
