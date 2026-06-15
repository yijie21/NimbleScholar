#!/usr/bin/env python3
"""Generate the Chrome/Edge extension icons (16/32/48/128) from the Nimble Scholar
page+highlighter mark. Tighter margin than the macOS app icon so it reads on a
browser toolbar. Writes extension/icon-{16,32,48,128}.png."""
import os
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "extension")
SS = 4
BASE = 256
N = BASE * SS


def lerp(a, b, t):
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(len(a)))


def make_icon(margin_frac=0.045):
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    grad = Image.new("RGBA", (N, N))
    gd = ImageDraw.Draw(grad)
    top, bot = (124, 154, 255, 255), (60, 88, 216, 255)
    for y in range(N):
        gd.line([(0, y), (N, y)], fill=lerp(top, bot, y / (N - 1)))

    margin = int(margin_frac * N)
    radius = int(0.235 * (N - 2 * margin))
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle([margin, margin, N - margin, N - margin], radius=radius, fill=255)
    img.paste(grad, (0, 0), mask)

    hi = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(hi).rounded_rectangle([margin, margin, N - margin, int(N * 0.52)],
                                         radius=radius, fill=(255, 255, 255, 30))
    img = Image.alpha_composite(img, Image.composite(hi, Image.new("RGBA", (N, N), (0, 0, 0, 0)), mask))

    cx, cy = N / 2, N / 2
    R = N - 2 * margin
    WHITE = (255, 255, 255, 255)
    ink = (150, 170, 235, 255)
    fold_tint = (206, 216, 250, 255)
    amber = (255, 196, 64, 255)

    # Slightly larger page than the app icon so it reads at 16px.
    pw, ph = 0.46 * R, 0.58 * R
    x0, y0 = cx - pw / 2, cy - ph / 2
    fold = 0.15 * R
    pr = 0.04 * R

    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [x0 + 0.02 * R, y0 + 0.035 * R, x0 + pw + 0.02 * R, y0 + ph + 0.035 * R],
        radius=pr, fill=(10, 18, 60, 100))
    shadow = shadow.filter(ImageFilter.GaussianBlur(0.025 * N))
    img = Image.alpha_composite(img, shadow)

    page = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(page).rounded_rectangle([x0, y0, x0 + pw, y0 + ph], radius=pr, fill=WHITE)
    cut = Image.new("L", (N, N), 0)
    ImageDraw.Draw(cut).polygon(
        [(x0 + pw - fold, y0 - 2), (x0 + pw + 2, y0 + fold), (x0 + pw + 2, y0 - 2)], fill=255)
    page.putalpha(Image.composite(Image.new("L", (N, N), 0), page.split()[3], cut))
    img = Image.alpha_composite(img, page)

    d = ImageDraw.Draw(img)
    d.polygon([(x0 + pw - fold, y0), (x0 + pw - fold, y0 + fold), (x0 + pw, y0 + fold)], fill=fold_tint)

    lines_y = [y0 + 0.17 * ph, y0 + 0.34 * ph, y0 + 0.51 * ph, y0 + 0.68 * ph, y0 + 0.85 * ph]
    hy = lines_y[2]
    d.rounded_rectangle([x0 + 0.10 * pw, hy - 0.058 * ph, x0 + 0.93 * pw, hy + 0.058 * ph],
                        radius=0.05 * ph, fill=amber)
    lw = max(1, int(0.022 * ph))
    for i, yy in enumerate(lines_y):
        x_end = 0.62 if i == 0 else (0.50 if i == len(lines_y) - 1 else 0.84)
        d.line([(x0 + 0.13 * pw, yy), (x0 + x_end * pw, yy)], fill=ink, width=lw)

    return img.resize((BASE, BASE), Image.LANCZOS)


def main():
    master = make_icon()
    for size in (16, 32, 48, 128):
        master.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, f"icon-{size}.png"))
    print("Wrote extension/icon-{16,32,48,128}.png")


if __name__ == "__main__":
    main()
