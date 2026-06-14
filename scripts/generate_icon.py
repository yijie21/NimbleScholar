#!/usr/bin/env python3
"""Generate the Nimble Scholar macOS app icon (squircle + graduation cap) and the
full AppIcon.appiconset. Run with any Python that has Pillow."""
import os, json
from PIL import Image, ImageDraw

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
    top, bot = (122, 152, 255, 255), (58, 86, 214, 255)
    for y in range(N):
        gd.line([(0, y), (N, y)], fill=lerp(top, bot, y / (N - 1)))

    # Rounded-rect (squircle) mask, inset like a real macOS icon.
    margin = int(0.085 * N)
    rect = [margin, margin, N - margin, N - margin]
    radius = int(0.2235 * (N - 2 * margin))
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle(rect, radius=radius, fill=255)
    img.paste(grad, (0, 0), mask)

    d = ImageDraw.Draw(img)

    # Soft top highlight for depth.
    hi = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hi)
    hd.rounded_rectangle([margin, margin, N - margin, int(N * 0.5)], radius=radius,
                         fill=(255, 255, 255, 38))
    img = Image.alpha_composite(img, Image.composite(hi, Image.new("RGBA", (N, N), (0, 0, 0, 0)), mask))
    d = ImageDraw.Draw(img)

    cx, cy = N / 2, N / 2
    R = (N - 2 * margin)
    white = (255, 255, 255, 255)
    shadow = (20, 30, 80, 70)

    # --- Graduation cap ---
    # Cap base (the part on the head): rounded trapezoid below center.
    bw_top, bw_bot = 0.165 * R, 0.135 * R
    by0, by1 = cy + 0.015 * R, cy + 0.205 * R
    base = [(cx - bw_top, by0), (cx + bw_top, by0), (cx + bw_bot, by1), (cx - bw_bot, by1)]
    d.polygon(base, fill=white)
    d.ellipse([cx - bw_bot, by1 - 0.05 * R, cx + bw_bot, by1 + 0.05 * R], fill=white)

    # Mortarboard (flat diamond) on top, with a subtle shadow under it.
    hw, hh = 0.34 * R, 0.115 * R
    yb = cy - 0.03 * R
    d.polygon([(cx, yb - hh - 0.04 * R), (cx + hw, yb), (cx, yb + hh - 0.04 * R), (cx - hw, yb)],
              fill=(0, 0, 0, 0))
    sh = [(cx, yb - hh - 0.02 * R), (cx + hw, yb + 0.02 * R), (cx, yb + hh), (cx - hw, yb + 0.02 * R)]
    d.polygon(sh, fill=shadow)
    board = [(cx, yb - hh - 0.04 * R), (cx + hw, yb), (cx, yb + hh - 0.04 * R), (cx - hw, yb)]
    d.polygon(board, fill=white)

    # Tassel: from the board center to the right edge, then hanging down (drawn first).
    bcx, bcy = cx, yb - 0.04 * R
    tx, ty = cx + hw - 0.02 * R, yb
    d.line([(bcx, bcy), (tx, ty)], fill=white, width=int(0.014 * R))
    d.line([(tx, ty), (tx, ty + 0.20 * R)], fill=white, width=int(0.014 * R))
    d.ellipse([tx - 0.028 * R, ty + 0.20 * R, tx + 0.028 * R, ty + 0.26 * R], fill=(120, 220, 255, 255))

    # Center button on top, so it stays a clean dot.
    br = 0.026 * R
    d.ellipse([bcx - br, bcy - br, bcx + br, bcy + br], fill=(58, 86, 214, 255))

    return img.resize((MASTER, MASTER), Image.LANCZOS)


def main():
    os.makedirs(OUT_ASSET, exist_ok=True)
    master = make_master()
    # Keep a master preview outside the iconset (Xcode warns about unreferenced files).
    master.save(os.path.join(os.path.dirname(__file__), "..", "assets", "nimble-scholar-icon-1024.png"))

    # macOS AppIcon sizes: (pt, scale) -> pixels
    specs = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
    images = []
    written = {}
    for pt, scale in specs:
        px = pt * scale
        fname = f"icon_{pt}x{pt}@{scale}x.png" if scale == 2 else f"icon_{pt}x{pt}.png"
        if px not in written:
            master.resize((px, px), Image.LANCZOS).save(os.path.join(OUT_ASSET, fname))
            written[px] = fname
        images.append({
            "size": f"{pt}x{pt}",
            "idiom": "mac",
            "filename": written[px] if written[px].endswith(".png") else fname,
            "scale": f"{scale}x",
        })
        # ensure file exists under this exact name (Contents references per-entry name)
        if not os.path.exists(os.path.join(OUT_ASSET, fname)):
            master.resize((px, px), Image.LANCZOS).save(os.path.join(OUT_ASSET, fname))
        images[-1]["filename"] = fname

    contents = {"images": images, "info": {"version": 1, "author": "xcode"}}
    with open(os.path.join(OUT_ASSET, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
    print("Wrote", OUT_ASSET)


if __name__ == "__main__":
    main()
