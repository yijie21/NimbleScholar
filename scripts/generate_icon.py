#!/usr/bin/env python3
"""Generate the Nimble Scholar macOS app icon (squircle + paper & highlighter)
and the full AppIcon.appiconset. Run with any Python that has Pillow."""
import os, json
from PIL import Image, ImageDraw, ImageFilter

OUT_ASSET = os.path.join(os.path.dirname(__file__), "..", "NimbleScholar", "Assets.xcassets", "AppIcon.appiconset")
MASTER = 1024
SS = 2  # supersample for smooth edges
N = MASTER * SS


def lerp(a, b, t):
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(len(a)))


def make_master():
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))

    # Vertical gradient (indigo -> blue).
    grad = Image.new("RGBA", (N, N))
    gd = ImageDraw.Draw(grad)
    top, bot = (124, 154, 255, 255), (60, 88, 216, 255)
    for y in range(N):
        gd.line([(0, y), (N, y)], fill=lerp(top, bot, y / (N - 1)))

    # Rounded-rect (squircle) mask, inset like a real macOS icon.
    margin = int(0.085 * N)
    rect = [margin, margin, N - margin, N - margin]
    radius = int(0.2235 * (N - 2 * margin))
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle(rect, radius=radius, fill=255)
    img.paste(grad, (0, 0), mask)

    # Soft top highlight for depth.
    hi = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(hi).rounded_rectangle([margin, margin, N - margin, int(N * 0.52)],
                                         radius=radius, fill=(255, 255, 255, 32))
    img = Image.alpha_composite(img, Image.composite(hi, Image.new("RGBA", (N, N), (0, 0, 0, 0)), mask))

    cx, cy = N / 2, N / 2
    R = N - 2 * margin
    WHITE = (255, 255, 255, 255)
    ink = (150, 170, 235, 255)
    fold_tint = (206, 216, 250, 255)
    amber = (255, 196, 64, 255)

    pw, ph = 0.42 * R, 0.54 * R
    x0, y0 = cx - pw / 2, cy - ph / 2
    fold = 0.135 * R
    pr = 0.035 * R

    # Soft drop shadow under the page.
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [x0 + 0.02 * R, y0 + 0.04 * R, x0 + pw + 0.02 * R, y0 + ph + 0.04 * R],
        radius=pr, fill=(10, 18, 60, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(0.03 * N))
    img = Image.alpha_composite(img, shadow)

    # Page body (rounded rect) with the top-right corner clipped out for the fold.
    page = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(page).rounded_rectangle([x0, y0, x0 + pw, y0 + ph], radius=pr, fill=WHITE)
    cut = Image.new("L", (N, N), 0)
    ImageDraw.Draw(cut).polygon(
        [(x0 + pw - fold, y0 - 2), (x0 + pw + 2, y0 + fold), (x0 + pw + 2, y0 - 2)], fill=255)
    page.putalpha(Image.composite(Image.new("L", (N, N), 0), page.split()[3], cut))
    img = Image.alpha_composite(img, page)

    d = ImageDraw.Draw(img)
    # Folded corner flap.
    d.polygon([(x0 + pw - fold, y0), (x0 + pw - fold, y0 + fold), (x0 + pw, y0 + fold)], fill=fold_tint)

    # Text lines; amber highlighter band behind the 3rd line.
    lines_y = [y0 + 0.16 * ph, y0 + 0.32 * ph, y0 + 0.48 * ph, y0 + 0.64 * ph, y0 + 0.80 * ph]
    hy = lines_y[2]
    d.rounded_rectangle([x0 + 0.10 * pw, hy - 0.052 * ph, x0 + 0.93 * pw, hy + 0.052 * ph],
                        radius=0.045 * ph, fill=amber)
    lw = int(0.018 * ph)
    for i, yy in enumerate(lines_y):
        x_end = 0.62 if i == 0 else (0.50 if i == len(lines_y) - 1 else 0.84)
        d.line([(x0 + 0.13 * pw, yy), (x0 + x_end * pw, yy)], fill=ink, width=lw)

    return img.resize((MASTER, MASTER), Image.LANCZOS)


def main():
    os.makedirs(OUT_ASSET, exist_ok=True)
    master = make_master()
    master.save(os.path.join(os.path.dirname(__file__), "..", "assets", "nimble-scholar-icon-1024.png"))

    specs = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
    images = []
    for pt, scale in specs:
        px = pt * scale
        fname = f"icon_{pt}x{pt}@{scale}x.png" if scale == 2 else f"icon_{pt}x{pt}.png"
        master.resize((px, px), Image.LANCZOS).save(os.path.join(OUT_ASSET, fname))
        images.append({"size": f"{pt}x{pt}", "idiom": "mac", "filename": fname, "scale": f"{scale}x"})

    contents = {"images": images, "info": {"version": 1, "author": "xcode"}}
    with open(os.path.join(OUT_ASSET, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
    print("Wrote", OUT_ASSET)


if __name__ == "__main__":
    main()
