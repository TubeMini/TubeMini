#!/usr/bin/env python3
"""Draws the TubeMini app icons with the standard library only (no Pillow, no SVG renderer).

The design, in iOS 6 style (real materials, bevels, a glossy finish):
  - a copper cog with rust patina and rivets (Rust),
  - a red rounded "tube" screen with a white play triangle in its bezel (a little YouTube),
  - a small CRT reflection on the glass and the classic iOS gloss arc over the cog.

The background is transparent (the cog and its soft shadow float on the wallpaper; the user asked for
no dark frame). Every shape is a signed distance field, so edges are anti-aliased analytically and each
size is drawn natively (no downscaling blur). Layers are composited over black, which gives
premultiplied colour, then divided by the alpha. UIPrerenderedIcon=true in Info.plist keeps iOS from
adding its own gloss on top of ours.

    python scripts/make-icons.py                 # icons into ios/TubeMini/Resources/, docs/icon.png
    python scripts/make-icons.py --preview DIR   # also DIR/icon-preview.png (on a wallpaper-like gradient)
    python scripts/make-icons.py --background silver|sky   # opaque rounded square instead of transparent
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

def copper(u, v):
    """Turned copper with a light, broad patina, before the bevel. No speckles or per-pixel grain: at the
    72 px the iPad mini shows, they turn into noise (the user found the textured version "rỗ")."""
    s = u * 0.45 + v * 0.55
    c = ramp([(0.12, (255, 206, 160)), (0.42, (228, 120, 54)), (0.7, (176, 70, 28)), (0.92, (92, 34, 12))], s)
    # Turned metal: bright lobe facing the light, a weaker one opposite, dark sides in between
    ang = math.atan2(v - 0.5, u - 0.5) - math.atan2(LIGHT[1], LIGHT[0])
    lobe = 0.38 * max(0.0, math.cos(ang)) ** 6 + 0.16 * max(0.0, -math.cos(ang)) ** 8
    c = mix(c, (255, 236, 205), lobe)
    c = scale(c, 1 - 0.18 * abs(math.sin(ang)) ** 4)
    # Patina: a few large, soft, darker areas (rust, without the pitting)
    patch = smoothstep(0.52, 0.72, fbm(u * 3.0, v * 3.0, 11, octaves=2))
    return mix(c, (118, 46, 20), 0.32 * patch)


def bevel(c, d, n, width, strength=0.6, highlight=(255, 232, 205)):
    """Lights the band just inside an edge according to the edge normal."""
    if d >= 0 or d < -width:
        return c
    e = (1 + d / width) ** 1.6
    lit = n[0] * LIGHT[0] + n[1] * LIGHT[1]
    if lit > 0:
        return mix(c, highlight, strength * lit * e)
    return scale(c, 1 + strength * 0.8 * lit * e)


SCALE = 0.94  # artwork size within the image: leaves room for the cog's shadow
CORNER = 10.0 / 57.0  # iOS 6 icon corner radius relative to the size


def bg_silver(u, v):
    """Brushed aluminium, light (iOS 6 style): vertical gradient with horizontal grain."""
    c = ramp([(0, (242, 243, 245)), (0.55, (214, 217, 222)), (1, (170, 175, 184))], v)
    return scale(c, 0.97 + 0.05 * hash2(int(v * 1024), int(u * 24), 5))


def bg_sky(u, v):
    """iOS 6 blue: light top, deep bottom."""
    return ramp([(0, (142, 206, 250)), (0.5, (62, 146, 228)), (1, (22, 88, 186))], v)


BACKGROUNDS = {"transparent": None, "silver": bg_silver, "sky": bg_sky}


def render(size, background=None):
    """Rows of RGBA pixels (PNG filter byte first). `background(u, v)` gives an opaque rounded
    square; None = transparent (the cog and its shadow only)."""
    pw = 1.0 / (size * SCALE)  # one pixel in icon units

    def cover(d, soft=1.0):
        return clamp(0.5 - d / (pw * soft))

    rows = []
    for py in range(size):
        row = bytearray([0])  # PNG filter: none
        v = 0.5 + ((py + 0.5) / size - 0.5) / SCALE
        for px in range(size):
            u = 0.5 + ((px + 0.5) / size - 0.5) / SCALE
            # Over black the result is premultiplied colour (transparent); else over the background
            c = background(u, v) if background else (0.0, 0.0, 0.0)

            # Cog with its drop shadow (the shadow is all alpha: black adds nothing)
            shadow = 0.5 * (1 - smoothstep(-0.01, 0.04, sd_cog(u, v, 0.02)))
            d_cog = sd_cog(u, v)
            cog = cover(d_cog)
            # Thin dark outline just outside the cog: a crisp edge on any wallpaper
            shadow = max(shadow, 0.55 * cover(d_cog - pw))
            if background:
                c = mix(c, (0, 0, 0), shadow)
            if d_cog < pw:
                m = copper(u, v)
                m = bevel(m, d_cog, normal(sd_cog, u, v), 0.03, 0.8)
                c = mix(c, m, cover(d_cog))

            # Rivets: only where they are more than a dot (they read as pits at 72 px)
            for rx, ry in RIVETS if size >= 100 else ():
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

            # The iOS gloss arc, on the cog only
            g = cover(sd_ellipse(u, v, 0.5, -0.31, 1.02, 0.79), 1.2) * (1.0 if background else cog)
            if g > 0:
                c = mix(c, (255, 255, 255), g * (0.27 - 0.20 * clamp(v / 0.48)))

            if background:
                # Rounded corners in image space (the artwork is scaled, the icon square is not)
                iu, iv = (px + 0.5) / size, (py + 0.5) / size
                alpha = clamp(0.5 - sd_round_rect(iu, iv, (0.5, 0.5, 0.5, 0.5, CORNER)) * size)
            else:
                alpha = cog + shadow * (1 - cog)
                if alpha > 0.002:
                    c = scale(c, 1 / alpha)
            row += bytes(int(clamp(ch / 255.0) * 255 + 0.5) for ch in c)
            row.append(int(clamp(alpha) * 255 + 0.5))
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


def preview(out_dir, big, background=None):
    """The icons on a wallpaper-like gradient (sky to grass), to see the transparency."""
    sizes = [big, 144, 72]
    icons = {s: render(s, background) for s in sizes}
    pad = 40
    width = sum(sizes) + pad * (len(sizes) + 1)
    height = big + 2 * pad
    canvas = []
    for y in range(height):
        line = []
        for x in range(width):
            t = y / max(height - 1, 1)
            sky, grass = (96, 140, 196), (86, 140, 52)
            line.append([int(sky[i] + (grass[i] - sky[i]) * t) for i in range(3)])
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
    bg = BACKGROUNDS[sys.argv[sys.argv.index("--background") + 1]] if "--background" in sys.argv else None
    for name, size in SIZES.items():
        write_png(RES / name, size, size, render(size, bg), alpha=True)
        print(f"{name}: {size}x{size}")
    write_png(ROOT / "docs" / "icon.png", 256, 256, render(256, bg), alpha=True)
    print("docs/icon.png: 256x256")
    if "--preview" in sys.argv:
        out = sys.argv[sys.argv.index("--preview") + 1]
        preview(out, 384, bg)
        print(f"{out}/icon-preview.png")


if __name__ == "__main__":
    main()
