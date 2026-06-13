#!/usr/bin/env python3
import math
import os
import struct
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
ICONSET = ROOT / "NimbleScholar.iconset"
APP_RESOURCES = ROOT / "Nimble Scholar.app" / "Contents" / "Resources"
EXTENSION = ROOT / "extension"


def clamp(value):
    return max(0, min(255, int(round(value))))


def mix(a, b, t):
    return tuple(clamp(a[i] * (1 - t) + b[i] * t) for i in range(4))


def over(dst, src):
    sa = src[3] / 255
    da = dst[3] / 255
    out_a = sa + da * (1 - sa)
    if out_a == 0:
        return (0, 0, 0, 0)
    out = []
    for i in range(3):
        out.append(clamp((src[i] * sa + dst[i] * da * (1 - sa)) / out_a))
    out.append(clamp(out_a * 255))
    return tuple(out)


def rounded_rect_alpha(x, y, w, h, r):
    px = min(max(x, 0), w)
    py = min(max(y, 0), h)
    dx = max(r - px, 0, px - (w - r))
    dy = max(r - py, 0, py - (h - r))
    if dx == 0 and dy == 0:
        return 1.0
    distance = math.hypot(dx, dy)
    return max(0.0, min(1.0, r + 0.5 - distance))


def draw_round_rect(img, size, x, y, w, h, r, color):
    for yy in range(max(0, y), min(size, y + h)):
        for xx in range(max(0, x), min(size, x + w)):
            alpha = rounded_rect_alpha(xx - x + 0.5, yy - y + 0.5, w, h, r)
            if alpha <= 0:
                continue
            src = (color[0], color[1], color[2], clamp(color[3] * alpha))
            img[yy][xx] = over(img[yy][xx], src)


def draw_circle(img, size, cx, cy, r, color):
    for yy in range(max(0, int(cy - r - 1)), min(size, int(cy + r + 2))):
        for xx in range(max(0, int(cx - r - 1)), min(size, int(cx + r + 2))):
            distance = math.hypot(xx + 0.5 - cx, yy + 0.5 - cy)
            alpha = max(0.0, min(1.0, r + 0.5 - distance))
            if alpha <= 0:
                continue
            src = (color[0], color[1], color[2], clamp(color[3] * alpha))
            img[yy][xx] = over(img[yy][xx], src)


def write_png(path, pixels):
    height = len(pixels)
    width = len(pixels[0])
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for pixel in row:
            raw.extend(bytes(pixel))

    def chunk(kind, data):
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    png = bytearray(b"\x89PNG\r\n\x1a\n")
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def downsample(high, scale):
    if scale == 1:
        return high
    h = len(high) // scale
    w = len(high[0]) // scale
    out = []
    area = scale * scale
    for y in range(h):
        row = []
        for x in range(w):
            sums = [0, 0, 0, 0]
            for yy in range(scale):
                for xx in range(scale):
                    pixel = high[y * scale + yy][x * scale + xx]
                    for i in range(4):
                        sums[i] += pixel[i]
            row.append(tuple(clamp(value / area) for value in sums))
        out.append(row)
    return out


def render_icon(size):
    scale = 3 if size <= 512 else 2
    canvas = size * scale
    img = [[(0, 0, 0, 0) for _ in range(canvas)] for _ in range(canvas)]

    c1 = (238, 245, 255, 255)
    c2 = (213, 229, 255, 255)
    c3 = (246, 241, 255, 255)
    for y in range(canvas):
        for x in range(canvas):
            t = (x + y) / (2 * canvas)
            base = mix(c1, c2, t)
            glow = max(0, 1 - math.hypot(x - canvas * 0.76, y - canvas * 0.22) / (canvas * 0.75))
            img[y][x] = mix(base, c3, glow * 0.42)

    s = scale
    draw_round_rect(img, canvas, 72 * s, 72 * s, 880 * s, 880 * s, 210 * s, (255, 255, 255, 38))
    draw_round_rect(img, canvas, 235 * s, 210 * s, 470 * s, 565 * s, 54 * s, (170, 184, 210, 82))
    draw_round_rect(img, canvas, 286 * s, 171 * s, 470 * s, 565 * s, 54 * s, (255, 255, 255, 245))
    draw_round_rect(img, canvas, 334 * s, 229 * s, 274 * s, 32 * s, 16 * s, (79, 134, 214, 255))
    draw_round_rect(img, canvas, 334 * s, 315 * s, 315 * s, 22 * s, 11 * s, (176, 190, 214, 210))
    draw_round_rect(img, canvas, 334 * s, 374 * s, 346 * s, 22 * s, 11 * s, (176, 190, 214, 185))
    draw_round_rect(img, canvas, 334 * s, 433 * s, 290 * s, 22 * s, 11 * s, (176, 190, 214, 165))
    draw_round_rect(img, canvas, 458 * s, 515 * s, 176 * s, 50 * s, 25 * s, (236, 244, 255, 255))
    draw_circle(img, canvas, 500 * s, 540 * s, 13 * s, (91, 137, 212, 255))
    draw_circle(img, canvas, 548 * s, 540 * s, 13 * s, (117, 174, 134, 255))
    draw_circle(img, canvas, 596 * s, 540 * s, 13 * s, (199, 142, 191, 255))
    draw_round_rect(img, canvas, 394 * s, 640 * s, 340 * s, 64 * s, 32 * s, (240, 248, 245, 255))
    draw_circle(img, canvas, 440 * s, 672 * s, 15 * s, (102, 171, 157, 255))
    draw_round_rect(img, canvas, 470 * s, 658 * s, 190 * s, 18 * s, 9 * s, (80, 124, 118, 220))

    return downsample(img, scale)


def main():
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    ASSETS.mkdir(exist_ok=True)
    ICONSET.mkdir(exist_ok=True)
    for name, size in sizes.items():
        pixels = render_icon(size)
        write_png(ICONSET / name, pixels)
    write_png(ASSETS / "nimble-scholar-1024.png", render_icon(1024))
    for size in [16, 32, 48, 128]:
        pixels = render_icon(size)
        write_png(EXTENSION / f"icon-{size}.png", pixels)


if __name__ == "__main__":
    main()
