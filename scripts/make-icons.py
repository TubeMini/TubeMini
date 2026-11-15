#!/usr/bin/env python3
"""Draws the TubeMini app icons with the standard library only (no Pillow, no SVG renderer).

The design, in iOS 6 style (real materials, bevels, a glossy finish):
  - a copper cog with rust patina and rivets (Rust),
  - a red rounded "tube" screen with a white play triangle in its bezel (a little YouTube),
  - a small CRT reflection on the glass and the classic iOS gloss arc over the whole icon.

Every shape is a signed distance field, so edges are anti-aliased analytically and each size is drawn
natively (no downscaling blur). The rounded corners are baked in (transparent outside): SpringBoard on
iOS 6 left the old icon of this /Applications app square. UIPrerenderedIcon=true in Info.plist keeps it
from adding its own gloss on top of ours.

    python scripts/make-icons.py                 # icons into ios/TubeMini/Resources/, docs/icon.png
    python scripts/make-icons.py --preview DIR   # also DIR/icon-preview.png (rounded, on dark linen)
"""
import math
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "ios" / "TubeMini" / "Resources"
SIZES = {
    "Icon-72.png": 72,  # iPad home screen
    "Icon-144.png": 144,  # iPad retina
    "Icon-Small-50.png": 50,  # Spotlight
    "Icon-Small-50@2x.png": 100,
    "Icon-Small.png": 29,  # Settings
    "Icon-Small@2x.png": 58,
}

# Light comes from the top left (unit vector pointing towards the light, y down)
LIGHT = (-0.55, -0.835)

# Cog: 12 teeth, tooth centred at the top
TEETH = 12
R_TIP, R_ROOT = 0.455, 0.383
A_TIP, A_BASE = math.radians(6.6), math.radians(10.2)  # half-angles of a tooth at tip / root
TIP = (R_TIP * math.cos(A_TIP), R_TIP * math.sin(A_TIP))
BASE = (R_ROOT * math.cos(A_BASE), R_ROOT * math.sin(A_BASE))
CROSS_CENTRE = (BASE[0] - TIP[0]) * (-TIP[1]) - (BASE[1] - TIP[1]) * (-TIP[0])

BEZEL = (0.5, 0.5, 0.292, 0.218, 0.075)  # cx, cy, half width, half height, corner radius
SCREEN = (0.5, 0.5, 0.252, 0.178, 0.05)
PLAY = ((0.468, 0.414), (0.468, 0.586), (0.582, 0.5))  # rounded by PLAY_ROUND
PLAY_ROUND = 0.016
RIVETS = [(0.5 + sx * 0.165, 0.5 + sy * 0.302) for sx in (-1, 1) for sy in (-1, 1)]
RIVET_R = 0.021


# ---------- small maths ----------

def clamp(x, lo=0.0, hi=1.0):
    return lo if x < lo else hi if x > hi else x


def smoothstep(e0, e1, x):
    t = clamp((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def ramp(stops, t):
    """Colour at t (0–1) along [(position, colour), ...]."""
    t = clamp(t)
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        if t <= p1:
            return mix(c0, c1, (t - p0) / (p1 - p0) if p1 > p0 else 0)
    return stops[-1][1]


def scale(c, k):
    return (c[0] * k, c[1] * k, c[2] * k)


def hash2(ix, iy, seed=0):
    """Deterministic pseudo-random value in [0, 1) for a lattice point."""
    h = (ix * 374761393 + iy * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFFFF) / 0x1000000


def value_noise(x, y, seed):
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    ux, uy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = hash2(ix, iy, seed), hash2(ix + 1, iy, seed)
    c, d = hash2(ix, iy + 1, seed), hash2(ix + 1, iy + 1, seed)
    return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy


def fbm(x, y, seed, octaves=4):
    total, amp, norm = 0.0, 0.5, 0.0
    for _ in range(octaves):
        total += amp * value_noise(x, y, seed)
        norm += amp
        x, y, amp, seed = x * 2.03, y * 2.03, amp * 0.5, seed + 17
    return total / norm


# ---------- signed distances (negative inside) ----------

def sd_round_rect(x, y, box, dy=0.0):
    cx, cy, hx, hy, r = box
    qx = abs(x - cx) - (hx - r)
    qy = abs(y - cy - dy) - (hy - r)
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    return outside + min(max(qx, qy), 0.0) - r


def sd_segment(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    t = clamp(((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy))
    return math.hypot(px - ax - vx * t, py - ay - vy * t)


def sd_cog(x, y, dy=0.0):
    """Exact distance to the cog outline, using the symmetry of one tooth."""
    dx, ddy = x - 0.5, y - 0.5 - dy
    r = math.hypot(dx, ddy)
    sector = 2 * math.pi / TEETH
    t = abs((math.atan2(ddy, dx) + math.pi / 2 + sector / 2) % sector - sector / 2)
    px, py = r * math.cos(t), r * math.sin(t)
    d_tip = abs(r - R_TIP) if t <= A_TIP else math.hypot(px - TIP[0], py - TIP[1])
    d_root = abs(r - R_ROOT) if t >= A_BASE else math.hypot(px - BASE[0], py - BASE[1])
    d = min(d_tip, d_root, sd_segment(px, py, TIP[0], TIP[1], BASE[0], BASE[1]))
    if t <= A_TIP:
        inside = r < R_TIP
    elif t >= A_BASE:
        inside = r < R_ROOT
    else:
        cross = (BASE[0] - TIP[0]) * (py - TIP[1]) - (BASE[1] - TIP[1]) * (px - TIP[0])
        inside = (cross > 0) == (CROSS_CENTRE > 0)
    return -d if inside else d


def sd_triangle(x, y, tri, dy=0.0):
    (ax, ay), (bx, by), (cx, cy) = tri
    y -= dy
    d = min(sd_segment(x, y, ax, ay, bx, by), sd_segment(x, y, bx, by, cx, cy), sd_segment(x, y, cx, cy, ax, ay))

    def side(px, py, qx, qy, rx, ry):
        return (rx - qx) * (py - qy) - (ry - qy) * (px - qx)

    s1, s2, s3 = side(x, y, ax, ay, bx, by), side(x, y, bx, by, cx, cy), side(x, y, cx, cy, ax, ay)
    inside = (s1 >= 0 and s2 >= 0 and s3 >= 0) or (s1 <= 0 and s2 <= 0 and s3 <= 0)
    return -d if inside else d


def sd_ellipse(x, y, cx, cy, rx, ry):
    return (math.hypot((x - cx) / rx, (y - cy) / ry) - 1.0) * min(rx, ry)


def normal(sd, x, y, h=0.002):
    gx = sd(x + h, y) - sd(x - h, y)
    gy = sd(x, y + h) - sd(x, y - h)
    n = math.hypot(gx, gy) or 1.0
    return gx / n, gy / n


# ---------- shading ----------

def background(u, v):
    t = clamp(math.hypot(u - 0.28, v - 0.12) / 1.05)
    c = ramp([(0, (58, 84, 112)), (0.55, (24, 36, 52)), (1, (9, 13, 20))], t)
    return scale(c, 0.97 + 0.06 * hash2(int(u * 4096), int(v * 4096), 3))


def copper(u, v):
    """Turned copper with rust patina, before the bevel."""
    s = u * 0.45 + v * 0.55
    c = ramp([(0.12, (255, 200, 150)), (0.42, (222, 112, 50)), (0.7, (168, 66, 26)), (0.92, (84, 30, 10))], s)
    # Turned metal: bright lobe facing the light, a weaker one opposite, dark sides in between
    ang = math.atan2(v - 0.5, u - 0.5) - math.atan2(LIGHT[1], LIGHT[0])
    lobe = 0.55 * max(0.0, math.cos(ang)) ** 6 + 0.22 * max(0.0, -math.cos(ang)) ** 8
    c = mix(c, (255, 236, 205), lobe)
    c = scale(c, 1 - 0.18 * abs(math.sin(ang)) ** 4)
    # Rust: dark patches and orange flakes
    patch = smoothstep(0.50, 0.66, fbm(u * 6.5, v * 6.5, 11))
    c = mix(c, ramp([(0, (84, 30, 14)), (1, (126, 46, 18))], fbm(u * 14, v * 14, 5)), 0.7 * patch)
    flakes = smoothstep(0.62, 0.76, fbm(u * 24, v * 24, 29))
    c = mix(c, (214, 92, 30), 0.6 * flakes)
    return scale(c, 0.94 + 0.12 * hash2(int(u * 4096), int(v * 4096), 7))


def bevel(c, d, n, width, strength=0.6, highlight=(255, 232, 205)):
    """Lights the band just inside an edge according to the edge normal."""
    if d >= 0 or d < -width:
        return c
    e = (1 + d / width) ** 1.6
    lit = n[0] * LIGHT[0] + n[1] * LIGHT[1]
    if lit > 0:
        return mix(c, highlight, strength * lit * e)
    return scale(c, 1 + strength * 0.8 * lit * e)


CORNER = 10.0 / 57.0  # iOS 6 icon corner radius relative to the size


def render(size, rounded=True):
    """Rows of RGBA pixels (PNG filter byte first). `rounded` makes the corners transparent."""
    pw = 1.0 / size  # one pixel in icon units
    mask_box = (0.5, 0.5, 0.5, 0.5, CORNER)

    def cover(d, soft=1.0):
        return clamp(0.5 - d / (pw * soft))

    rows = []
    for py in range(size):
        row = bytearray([0])  # PNG filter: none
        v = (py + 0.5) / size
        for px in range(size):
            u = (px + 0.5) / size
            c = background(u, v)

            # Cog with its drop shadow
            c = mix(c, (0, 0, 0), 0.55 * (1 - smoothstep(-0.01, 0.05, sd_cog(u, v, 0.024))))
            d_cog = sd_cog(u, v)
            if d_cog < pw:
                m = copper(u, v)
                m = bevel(m, d_cog, normal(sd_cog, u, v), 0.03, 0.8)
                c = mix(c, m, cover(d_cog))

            # Rivets
            for rx, ry in RIVETS:
                d_r = math.hypot(u - rx, v - ry) - RIVET_R
                if d_r < 0.02:
                    c = mix(c, (40, 14, 4), 0.5 * (1 - smoothstep(-0.004, 0.012, math.hypot(u - rx, v - ry - 0.006) - RIVET_R)))
                    if d_r < pw:
                        k = clamp(math.hypot(u - rx + 0.35 * RIVET_R, v - ry + 0.45 * RIVET_R) / (1.6 * RIVET_R))
                        c = mix(c, ramp([(0, (255, 236, 214)), (0.5, (196, 112, 64)), (1, (92, 38, 16))], k), cover(d_r))

            # Bezel and its shadow on the cog
            c = mix(c, (0, 0, 0), 0.6 * (1 - smoothstep(-0.01, 0.045, sd_round_rect(u, v, BEZEL, 0.02))))
            d_bz = sd_round_rect(u, v, BEZEL)
            if d_bz < pw * 2:
                c = mix(c, (0, 0, 0), 0.5 * cover(d_bz - pw * 1.2, 1.5))  # thin dark outline
            if d_bz < pw:
                t = (v - (BEZEL[1] - BEZEL[3])) / (2 * BEZEL[3])
                m = ramp([(0, (92, 92, 98)), (0.5, (44, 44, 48)), (1, (18, 18, 20))], t)
                m = bevel(m, d_bz, normal(lambda a, b: sd_round_rect(a, b, BEZEL), u, v), 0.014, 0.7, (235, 235, 240))
                c = mix(c, m, cover(d_bz))

            # Screen: glowing red tube, darker at the edges, recessed under the bezel
            d_sc = sd_round_rect(u, v, SCREEN)
            if d_sc < pw:
                q = math.hypot((u - 0.5) / SCREEN[2], (v - 0.47) / SCREEN[3])
                m = ramp([(0, (255, 88, 70)), (0.55, (228, 32, 22)), (1.15, (124, 10, 6))], q / 1.15)
                depth = -d_sc
                if depth < 0.04:
                    m = scale(m, 1 - 0.45 * (1 - depth / 0.04) ** 2)
                c = mix(c, m, cover(d_sc))

                # Play triangle with a soft shadow
                c = mix(c, (60, 0, 0), 0.55 * (1 - smoothstep(-0.006, 0.022, sd_triangle(u, v, PLAY, 0.012) - PLAY_ROUND)) * cover(d_sc))
                d_pl = sd_triangle(u, v, PLAY) - PLAY_ROUND
                if d_pl < pw:
                    t = (v - 0.4) / 0.2
                    c = mix(c, ramp([(0, (255, 255, 255)), (1, (226, 226, 232))], t), cover(d_pl))

                # Reflection on the glass
                glass = cover(sd_round_rect(u, v, (0.5, 0.5, SCREEN[2] - 0.008, SCREEN[3] - 0.008, SCREEN[4] - 0.006)))
                refl = cover(sd_ellipse(u, v, 0.43, 0.335, 0.33, 0.155), 1.5)
                c = mix(c, (255, 255, 255), 0.30 * (1 - smoothstep(0.33, 0.47, v)) * glass * refl)

            # The iOS gloss arc over the whole icon
            g = cover(sd_ellipse(u, v, 0.5, -0.31, 1.02, 0.79), 1.2)
            if g > 0:
                c = mix(c, (255, 255, 255), g * (0.27 - 0.20 * clamp(v / 0.48)))

            alpha = cover(sd_round_rect(u, v, mask_box)) if rounded else 1.0
            row += bytes(int(clamp(ch / 255.0) * 255 + 0.5) for ch in c)
            row.append(int(alpha * 255 + 0.5))
        rows.append(bytes(row))
    return rows


# ---------- PNG + preview ----------

def write_png(path, width, height, rows, alpha=False):
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    colour_type = 6 if alpha else 2  # RGBA or RGB
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, colour_type, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
    png += chunk(b"IEND", b"")
    Path(path).write_bytes(png)


def preview(out_dir, big):
    """The icons as the iPad shows them, on a dark linen-like background."""
    sizes = [big, 144, 72]
    icons = {s: render(s) for s in sizes}
    pad = 40
    width = sum(sizes) + pad * (len(sizes) + 1)
    height = big + 2 * pad
    canvas = []
    for y in range(height):
        line = []
        for x in range(width):
            n = 0.85 + 0.15 * (hash2(x, y, 41) * 0.5 + 0.5 * (((x + y) % 3) == 0))
            line.append([int(46 * n), int(48 * n), int(52 * n)])
        canvas.append(line)
    x0 = pad
    for s in sizes:
        rows = icons[s]
        y0 = pad + (big - s) // 2
        for y in range(s):
            src = rows[y]
            for x in range(s):
                a = src[1 + x * 4 + 3] / 255.0
                if a <= 0:
                    continue
                px = canvas[y0 + y][x0 + x]
                for i in range(3):
                    px[i] = int(px[i] + (src[1 + x * 4 + i] - px[i]) * a)
        x0 += s + pad
    rows = [bytes([0]) + bytes(ch for px in line for ch in px) for line in canvas]
    write_png(Path(out_dir) / "icon-preview.png", width, height, rows)


def main():
    for name, size in SIZES.items():
        write_png(RES / name, size, size, render(size), alpha=True)
        print(f"{name}: {size}x{size}")
    write_png(ROOT / "docs" / "icon.png", 256, 256, render(256), alpha=True)
    print("docs/icon.png: 256x256")
    if "--preview" in sys.argv:
        out = sys.argv[sys.argv.index("--preview") + 1]
        preview(out, 384)
        print(f"{out}/icon-preview.png")


if __name__ == "__main__":
    main()
