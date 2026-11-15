#!/usr/bin/env python3
"""Draws the TubeMini app icons (Icon-72.png, Icon-144.png) with the standard library only.

Blue square with a white play triangle, 4x supersampled for smooth edges.
iOS 6 rounds the corners itself; UIPrerenderedIcon=true in Info.plist disables the gloss.

    python scripts/make-icons.py            # writes into ios/TubeMini/Resources/
"""
import struct
import sys
import zlib
from pathlib import Path

BG_TOP = (30, 110, 220)
BG_BOTTOM = (13, 71, 161)
FG = (255, 255, 255)
SS = 4  # supersampling factor


def inside_triangle(x, y, a, b, c):
    def side(p, q, r):
        return (r[0] - q[0]) * (p[1] - q[1]) - (r[1] - q[1]) * (p[0] - q[0])

    d1, d2, d3 = side((x, y), a, b), side((x, y), b, c), side((x, y), c, a)
    neg = d1 < 0 or d2 < 0 or d3 < 0
    pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (neg and pos)


def render(size):
    n = size * SS
    # Play triangle, optically centred (shifted right a little)
    a = (n * 0.36, n * 0.27)
    b = (n * 0.36, n * 0.73)
    c = (n * 0.76, n * 0.50)
    rows = []
    for py in range(size):
        t = py / max(size - 1, 1)
        bg = tuple(round(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3))
        row = bytearray([0])  # filter type: none
        for px in range(size):
            hits = 0
            for sy in range(SS):
                for sx in range(SS):
                    if inside_triangle(px * SS + sx + 0.5, py * SS + sy + 0.5, a, b, c):
                        hits += 1
            f = hits / (SS * SS)
            row += bytes(round(bg[i] * (1 - f) + FG[i] * f) for i in range(3))
        rows.append(bytes(row))
    return b"".join(rows)


def png(size, raw):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)  # 8-bit RGB
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "ios/TubeMini/Resources"
    for size in (72, 144):
        path = out / f"Icon-{size}.png"
        path.write_bytes(png(size, render(size)))
        print(path)


if __name__ == "__main__":
    main()
