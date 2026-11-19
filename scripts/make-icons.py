#!/usr/bin/env python3
"""Builds every TubeMini icon from the master logo art/TubeMini-logo.png (needs Pillow).

The master is a glossy rounded square on a dark, unsaturated backdrop. The rounded square is a
superellipse |x/a|^n + |y/b|^n = 1 (n is about 5.5). The script:
  1. finds its outline (pixels that are saturated or bright) and fits a, b, the centre and n;
  2. resamples the logo into each size with premultiplied alpha (Pillow does that for RGBA), using a
     source mask set slightly inside the outline, so the dark backdrop and the anti-aliased rim
     pixels add no dark fringe;
  3. replaces the alpha with the same superellipse drawn natively at that size, so the corners are
     as crisp as an analytic shape can be.

Apps in /Applications on iOS 6 get no corner mask from SpringBoard, so the transparent corners have to
be in the PNG. UIPrerenderedIcon=true in Info.plist keeps iOS from adding its gloss over the logo's own.

    python scripts/make-icons.py                # app icons, launch image, README / site / Cydia icons
    python scripts/make-icons.py --preview DIR  # also DIR/icon-preview.png (sizes on a wallpaper-like gradient)
"""
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
MASTER = ROOT / "art" / "TubeMini-logo.png"
RES = ROOT / "ios" / "TubeMini" / "Resources"
SIZES = {
    RES / "Icon-57.png": 57,  # iPhone home screen
    RES / "Icon-114.png": 114,  # iPhone retina
    RES / "Icon-72.png": 72,  # iPad home screen
    RES / "Icon-144.png": 144,  # iPad retina
    RES / "Icon-Small-50.png": 50,  # Spotlight
    RES / "Icon-Small-50@2x.png": 100,
    RES / "Icon-Small.png": 29,  # Settings
    RES / "Icon-Small@2x.png": 58,
    RES / "LogoMark.png": 30,  # in-app header next to the "TubeMini" title
    RES / "LogoMark@2x.png": 60,
    ROOT / "docs" / "icon.png": 256,  # README
    ROOT / "site" / "img" / "icon.png": 256,  # site header
    ROOT / "site" / "apple-touch-icon.png": 144,
    ROOT / "site" / "cydia" / "icon.png": 64,  # package icon (control: Icon:) and site favicon
    ROOT / "site" / "cydia" / "CydiaIcon.png": 64,  # repository icon in Cydia's Sources
}

# Plain black launch image. Its only job: iOS 6 runs an app full height on a 4-inch iPhone only when
# the bundle has Default-568h@2x.png, otherwise letterboxed.
LAUNCH = {RES / "Default-568h@2x.png": (640, 1136)}

INSET = 1.5  # source pixels: the outermost rim pixels are blended with the backdrop


def is_logo(rgb):
    r, g, b = rgb
    return max(r, g, b) - min(r, g, b) > 45 or max(r, g, b) > 110


def fit_outline(img):
    """Returns (cx, cy, a, b, n) of the superellipse around the logo, in source pixels."""
    w, h = img.size
    data = img.tobytes()
    mask = [is_logo(data[i * 3:i * 3 + 3]) for i in range(w * h)]
    points = []
    for y in range(h):
        row = mask[y * w:(y + 1) * w]
        if any(row):
            left = row.index(True)
            right = w - 1 - row[::-1].index(True)
            points += [(left - 0.5, y), (right + 0.5, y)]
    for x in range(w):
        col = mask[x::w]
        if any(col):
            top = col.index(True)
            bottom = h - 1 - col[::-1].index(True)
            points += [(x, top - 0.5), (x, bottom + 0.5)]
    x0, x1 = min(p[0] for p in points), max(p[0] for p in points)
    y0, y1 = min(p[1] for p in points), max(p[1] for p in points)
    cx, cy, a, b = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2

    def error(n):
        total = 0.0
        for x, y in points:
            r = (abs((x - cx) / a) ** n + abs((y - cy) / b) ** n) ** (1 / n)
            total += ((r - 1) * min(a, b)) ** 2
        return total

    n = min((3 + i * 0.05 for i in range(81)), key=error)
    return cx, cy, a, b, n


def superellipse_alpha(width, height, cx, cy, a, b, n, x_range=None, y_range=None):
    """Coverage (0-255) of the superellipse, anti-aliased with an approximate signed distance."""
    out = bytearray(width * height)
    xs = x_range or range(width)
    ys = y_range or range(height)
    for y in ys:
        v = (y + 0.5 - cy) / b
        av = abs(v)
        for x in xs:
            u = (x + 0.5 - cx) / a
            au = abs(u)
            if au < 1e-9 and av < 1e-9:
                out[y * width + x] = 255
                continue
            f = (au ** n + av ** n) ** (1 / n)
            # gradient of f (homogeneous of degree 1), in 1/pixel
            k = f ** (1 - n)
            gx = k * au ** (n - 1) / a
            gy = k * av ** (n - 1) / b
            dist = (f - 1) / ((gx * gx + gy * gy) ** 0.5)  # pixels, > 0 outside
            cover = 0.5 - dist
            out[y * width + x] = 0 if cover <= 0 else 255 if cover >= 1 else int(cover * 255 + 0.5)
    return Image.frombytes("L", (width, height), bytes(out))


def build(master, fit, size):
    cx, cy, a, b, n = fit
    # Pillow resizes RGBA premultiplied, so the (masked-off) backdrop adds no colour.
    box = (cx - a, cy - b, cx + a, cy + b)
    icon = master.resize((size, size), Image.LANCZOS, box=box)
    scale = size / (2 * a)
    inset = INSET * scale
    half = size / 2
    alpha = superellipse_alpha(size, size, half, half, half - inset, half - inset * a / b, n)
    icon.putalpha(alpha)
    return icon


def preview(path, icons):
    """The icons on a wallpaper-like gradient (sky to grass)."""
    pad = 40
    big = max(i.size[0] for i in icons)
    width = sum(i.size[0] for i in icons) + pad * (len(icons) + 1)
    height = big + 2 * pad
    canvas = Image.new("RGB", (width, height))
    sky, grass = (96, 140, 196), (86, 140, 52)
    for y in range(height):
        t = y / (height - 1)
        colour = tuple(int(sky[i] + (grass[i] - sky[i]) * t) for i in range(3))
        canvas.paste(colour, (0, y, width, y + 1))
    x = pad
    for icon in icons:
        s = icon.size[0]
        canvas.paste(icon, (x, pad + (big - s) // 2), icon)
        x += s + pad
    canvas.save(path)


def main():
    rgb = Image.open(MASTER).convert("RGB")
    fit = fit_outline(rgb)
    cx, cy, a, b, n = fit
    print(f"outline: centre ({cx:.1f}, {cy:.1f}), half size {a:.1f} x {b:.1f}, n = {n:.2f}")

    # Source alpha: the superellipse moved INSET pixels inwards, only around the logo.
    w, h = rgb.size
    x_range = range(max(int(cx - a) - 2, 0), min(int(cx + a) + 3, w))
    y_range = range(max(int(cy - b) - 2, 0), min(int(cy + b) + 3, h))
    alpha = superellipse_alpha(w, h, cx, cy, a - INSET, b - INSET, n, x_range, y_range)
    master = rgb.convert("RGBA")
    master.putalpha(alpha)

    made = {}
    for path, size in SIZES.items():
        if size not in made:
            made[size] = build(master, fit, size)
        made[size].save(path, optimize=True)
        print(f"{path.relative_to(ROOT).as_posix()}: {size}x{size}")

    for path, (lw, lh) in LAUNCH.items():
        black = Image.new("RGB", (lw, lh))
        if path.exists():
            current = Image.open(path)
            if current.size == (lw, lh) and current.convert("RGB").getextrema() == ((0, 0),) * 3:
                continue
        black.save(path, optimize=True)
        print(f"{path.relative_to(ROOT).as_posix()}: {lw}x{lh}")

    if "--preview" in sys.argv:
        out = Path(sys.argv[sys.argv.index("--preview") + 1]) / "icon-preview.png"
        preview(out, [build(master, fit, 256), made[144], made[114], made[72], made[57], made[29]])
        print(out)


if __name__ == "__main__":
    main()
