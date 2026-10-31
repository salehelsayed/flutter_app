#!/usr/bin/env python3
"""Draw stock-style test photos (no real photos) for filling a test Orbit with Thoughts.
   python3 docker-ws/orbit_fill_images.py <out-dir>"""
import math
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1]
random.seed(7)


def grad(w, h, stops):
    im = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = y / (h - 1)
        for i in range(len(stops) - 1):
            p0, c0 = stops[i]
            p1, c1 = stops[i + 1]
            if p0 <= t <= p1:
                k = (t - p0) / (p1 - p0)
                d.line([(0, y), (w, y)], fill=tuple(int(c0[j] + (c1[j] - c0[j]) * k) for j in range(3)))
                break
    return im


def glow(im, cx, cy, r, color, alpha=160):
    layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse([cx - r * 2.2, cy - r * 2.2, cx + r * 2.2, cy + r * 2.2], fill=color + (alpha // 2,))
    layer = layer.filter(ImageFilter.GaussianBlur(r))
    im.paste(layer, (0, 0), layer)
    ImageDraw.Draw(im).ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)


def ridge(d, w, h, base, amp, color, seed, step=8):
    rnd = random.Random(seed)
    ph = [rnd.uniform(0, 6.28) for _ in range(3)]
    pts = [(0, h)]
    for x in range(0, w + step, step):
        y = base + amp * (0.55 * math.sin(x / w * 3.1 + ph[0]) + 0.3 * math.sin(x / w * 7.3 + ph[1])
                          + 0.15 * math.sin(x / w * 17 + ph[2]))
        pts.append((x, y))
    pts.append((w, h))
    d.polygon(pts, fill=color)


def sunset(w, h):
    im = grad(w, h, [(0, (38, 32, 92)), (0.45, (238, 110, 90)), (0.7, (255, 196, 120)), (1, (255, 214, 150))])
    glow(im, w * 0.62, h * 0.58, min(w, h) * 0.09, (255, 236, 180))
    d = ImageDraw.Draw(im)
    ridge(d, w, h, h * 0.66, h * 0.05, (120, 64, 96), 1)
    ridge(d, w, h, h * 0.74, h * 0.05, (78, 40, 76), 2)
    ridge(d, w, h, h * 0.84, h * 0.04, (40, 22, 48), 3)
    return im


def sea(w, h):
    im = grad(w, h, [(0, (90, 170, 230)), (0.55, (200, 230, 250)), (0.56, (30, 110, 160)), (1, (10, 60, 100))])
    glow(im, w * 0.25, h * 0.2, min(w, h) * 0.06, (255, 252, 230), 200)
    d = ImageDraw.Draw(im)
    for i in range(140):
        y = h * 0.57 + (h * 0.43) * (i / 140) ** 1.6
        x = random.uniform(0, w)
        ln = random.uniform(20, 90) * (1 + i / 60)
        d.line([(x, y), (x + ln, y)], fill=(170, 215, 240), width=max(1, int(i / 50)))
    for cx, cy, s in [(0.6, 0.15, 1), (0.8, 0.25, 0.7), (0.4, 0.32, 0.8)]:
        for k in range(5):
            r = 50 * s + k * 9
            d.ellipse([w * cx + k * 45 * s - r, h * cy - r * 0.6, w * cx + k * 45 * s + r, h * cy + r * 0.6], fill=(250, 252, 255))
    return im


def skyline(w, h):
    im = grad(w, h, [(0, (14, 18, 48)), (0.6, (70, 50, 120)), (1, (230, 120, 110))])
    d = ImageDraw.Draw(im)
    for _ in range(120):
        x, y = random.uniform(0, w), random.uniform(0, h * 0.5)
        d.point((x, y), fill=(255, 255, 255))
    glow(im, w * 0.8, h * 0.18, min(w, h) * 0.05, (245, 240, 220), 120)
    d = ImageDraw.Draw(im)
    x = 0
    while x < w:
        bw = random.randint(int(w * 0.04), int(w * 0.09))
        bh = random.uniform(h * 0.18, h * 0.55)
        top = h - bh
        d.rectangle([x, top, x + bw, h], fill=(18, 16, 34))
        for wy in range(int(top) + 16, h - 10, 26):
            for wx in range(x + 8, x + bw - 8, 18):
                if random.random() < 0.35:
                    d.rectangle([wx, wy, wx + 7, wy + 11], fill=(255, 214, 120))
        x += bw + random.randint(2, 10)
    return im


def mountains(w, h):
    im = grad(w, h, [(0, (150, 180, 210)), (0.6, (225, 232, 238)), (1, (205, 215, 225))])
    d = ImageDraw.Draw(im)
    for i, (base, col) in enumerate([(0.45, (120, 135, 160)), (0.55, (90, 105, 130)), (0.68, (60, 75, 95)), (0.82, (35, 50, 60))]):
        ridge(d, w, h, h * base, h * 0.12, col, 10 + i, step=4)
    fog = Image.new("RGBA", im.size, (0, 0, 0, 0))
    fd = ImageDraw.Draw(fog)
    for i in range(6):
        y = h * (0.5 + i * 0.06)
        fd.rectangle([0, y, w, y + h * 0.03], fill=(240, 244, 248, 90))
    fog = fog.filter(ImageFilter.GaussianBlur(30))
    im.paste(fog, (0, 0), fog)
    return im


def colorfield(w, h):
    im = grad(w, h, [(0, (250, 120, 140)), (0.5, (250, 190, 120)), (1, (110, 190, 210))])
    layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    for col in [(120, 80, 220, 140), (255, 240, 160, 130), (40, 170, 160, 130), (255, 110, 90, 120)]:
        cx, cy, r = random.uniform(0, w), random.uniform(0, h), random.uniform(0.25, 0.45) * min(w, h)
        ld.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
    layer = layer.filter(ImageFilter.GaussianBlur(min(w, h) * 0.08))
    im.paste(layer, (0, 0), layer)
    return im


def desk(w, h):
    im = grad(w, h, [(0, (196, 160, 120)), (1, (150, 110, 78))])
    d = ImageDraw.Draw(im)
    for i in range(0, h, 9):
        d.line([(0, i), (w, i + random.randint(-6, 6))], fill=(170, 130, 95), width=2)
    s = min(w, h)
    # book
    bx, by = w * 0.12, h * 0.55
    d.rounded_rectangle([bx, by, bx + s * 0.42, by + s * 0.3], 12, fill=(240, 236, 226))
    d.line([(bx + s * 0.21, by), (bx + s * 0.21, by + s * 0.3)], fill=(190, 180, 170), width=4)
    for k in range(6):
        y = by + s * 0.05 + k * s * 0.035
        d.line([(bx + 20, y), (bx + s * 0.19, y)], fill=(170, 170, 170), width=3)
        d.line([(bx + s * 0.23, y), (bx + s * 0.4, y)], fill=(170, 170, 170), width=3)
    # cup
    cx, cy, r = w * 0.68, h * 0.42, s * 0.14
    d.ellipse([cx - r * 1.6, cy - r * 1.6, cx + r * 1.6, cy + r * 1.6], fill=(245, 245, 245))
    d.ellipse([cx + r * 1.3, cy - r * 0.35, cx + r * 2.1, cy + r * 0.35], outline=(235, 235, 235), width=int(r * 0.2))
    d.ellipse([cx - r * 1.2, cy - r * 1.2, cx + r * 1.2, cy + r * 1.2], fill=(232, 232, 232))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(110, 62, 34))
    d.ellipse([cx - r * 0.45, cy - r * 0.3, cx + r * 0.45, cy + r * 0.3], fill=(200, 150, 110))
    # plant
    px, py = w * 0.82, h * 0.78
    d.ellipse([px - s * 0.08, py - s * 0.08, px + s * 0.08, py + s * 0.08], fill=(200, 110, 80))
    for a in range(0, 360, 40):
        ex, ey = px + math.cos(math.radians(a)) * s * 0.12, py + math.sin(math.radians(a)) * s * 0.12
        d.ellipse([ex - s * 0.04, ey - s * 0.04, ex + s * 0.04, ey + s * 0.04], fill=(70, 140, 80))
    return im


def palms(w, h):
    im = grad(w, h, [(0, (255, 150, 110)), (0.6, (255, 205, 150)), (0.61, (60, 120, 170)), (1, (30, 70, 110))])
    glow(im, w * 0.5, h * 0.58, min(w, h) * 0.12, (255, 225, 150))
    d = ImageDraw.Draw(im)
    d.rectangle([0, h * 0.6, w, h], fill=(40, 90, 135))
    for i in range(60):
        y = h * 0.62 + i * (h * 0.38 / 60)
        hw = w * 0.12 * (1 - i / 80)
        d.line([(w * 0.5 - hw, y), (w * 0.5 + hw, y)], fill=(255, 200, 130), width=2)
    for bx, sc in [(0.15, 1.0), (0.85, 0.8)]:
        x0, y0 = w * bx, h
        tx, ty = x0 + 40 * sc, h * (0.62 - 0.25 * sc)
        d.line([(x0, y0), (tx, ty)], fill=(30, 20, 30), width=int(18 * sc))
        for a in range(-170, 10, 30):
            ex, ey = tx + math.cos(math.radians(a)) * 180 * sc, ty + math.sin(math.radians(a)) * 90 * sc + 60 * sc
            d.line([(tx, ty), (ex, ey)], fill=(30, 20, 30), width=int(14 * sc))
    return im


SCENES = [
    ("sunset_river_tall.jpg", sunset, 1080, 1920),
    ("beach_morning_wide.jpg", sea, 1920, 1080),
    ("city_night_square.jpg", skyline, 1080, 1080),
    ("misty_mountains_wide.jpg", mountains, 1920, 1440),
    ("coffee_book_square.jpg", desk, 1080, 1080),
    ("colour_field_tall.jpg", colorfield, 1080, 1440),
    ("palm_sunset_tall.jpg", palms, 1080, 1920),
    ("city_dusk_wide.jpg", skyline, 1920, 1080),
    ("sunset_hills_square.jpg", sunset, 1080, 1080),
    ("alps_morning_tall.jpg", mountains, 1080, 1440),
    ("sea_clouds_square.jpg", sea, 1080, 1080),
    ("coffee_desk_wide.jpg", desk, 1920, 1440),
]
for name, fn, w, h in SCENES:
    fn(w, h).save(f"{OUT}/{name}", quality=88)
    print(name, w, h)
