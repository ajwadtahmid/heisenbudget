"""Makes the iOS and Android launcher icons from the logo image
assets/logos/logo.png.  Run:  python3 tools/make_icon_from_logo.py <project_dir>
(needs Pillow).

The logo is a flask on a near-white background. The background colour is read
from the image's border and used for the Android adaptive icon's background, so
the foreground (the flask on that same colour) never shows an edge, whatever
shape the launcher masks it to.

(tools/make_icon.py draws the earlier flask-and-coin icon; it stays so that icon
can be restored.)
"""
import json
import os
import sys

from PIL import Image, ImageDraw

# iOS and the old square Android icons show the flask this big (share of height).
FLASK_SHARE = 0.72
# Adaptive icons: the flask must stay inside the 66dp circle of a 108dp icon.
SAFE_RADIUS = 0.30  # of the canvas side (66/108 / 2 = 0.305, with a hair spare)
# Pixels this close to the background colour are the background (cleans noise).
CLEAN = 14


def border_colour(img):
    w, h = img.size
    px = img.load()
    samples = []
    for i in range(0, w, 8):
        samples += [px[i, 3], px[i, h - 4]]
    for j in range(0, h, 8):
        samples += [px[3, j], px[w - 4, j]]
    return tuple(sorted(c[k] for c in samples)[len(samples) // 2] for k in range(3))


def cleaned(img, bg):
    out = img.copy()
    px = out.load()
    w, h = out.size
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if max(abs(r - bg[0]), abs(g - bg[1]), abs(b - bg[2])) <= CLEAN:
                px[x, y] = bg
    return out


def flask_geometry(img, bg):
    """Centre, height and farthest reach of everything that is not background."""
    w, h = img.size
    px = img.load()
    xs, ys = [], []
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            r, g, b = px[x, y]
            if max(abs(r - bg[0]), abs(g - bg[1]), abs(b - bg[2])) > 40:
                xs.append(x)
                ys.append(y)
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    far = max(((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 for x, y in zip(xs, ys))
    return cx, cy, y1 - y0, far


def square_around(img, bg, cx, cy, side):
    """A square of [side] pixels centred on (cx, cy), padded with the background."""
    side = int(round(side))
    canvas = Image.new("RGB", (side, side), bg)
    canvas.paste(img, (int(round(side / 2 - cx)), int(round(side / 2 - cy))))
    return canvas


def main(project):
    src = Image.open(os.path.join(project, "assets/logos/logo.png")).convert("RGB")
    bg = border_colour(src)
    art = cleaned(src, bg)
    cx, cy, flask_h, far = flask_geometry(art, bg)
    hex_bg = "#%02X%02X%02X" % bg

    # iOS (opaque, every size in Contents.json) and old square Android icons.
    full = square_around(art, bg, cx, cy, flask_h / FLASK_SHARE)
    ios_dir = os.path.join(project, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
    with open(os.path.join(ios_dir, "Contents.json")) as f:
        contents = json.load(f)
    for entry in contents["images"]:
        base = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].replace("x", ""))
        size = round(base * scale)
        full.resize((size, size), Image.LANCZOS).save(
            os.path.join(ios_dir, entry["filename"])
        )

    res = os.path.join(project, "android/app/src/main/res")
    for folder, size in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
        out = os.path.join(res, f"mipmap-{folder}/ic_launcher.png")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        full.resize((size, size), Image.LANCZOS).save(out)

    # Android adaptive icon: the flask, on the background colour, inside the
    # safe circle.
    adaptive = square_around(art, bg, cx, cy, far / SAFE_RADIUS)
    for folder, size in [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)]:
        adaptive.resize((size, size), Image.LANCZOS).save(
            os.path.join(res, f"mipmap-{folder}/ic_launcher_foreground.png")
        )
    with open(os.path.join(res, "values/ic_launcher_background.xml"), "w") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
            f'    <color name="ic_launcher_background">{hex_bg}</color>\n</resources>\n'
        )

    # A preview: the iOS icon, the adaptive icon, and it cut to a circle.
    os.makedirs("/tmp/hb_icon", exist_ok=True)
    sheet = Image.new("RGB", (3 * 360, 360), (60, 60, 60))
    sheet.paste(full.resize((320, 320), Image.LANCZOS), (20, 20))
    visible = adaptive.resize((432, 432), Image.LANCZOS).crop((36, 36, 396, 396))
    visible = visible.resize((320, 320), Image.LANCZOS)
    sheet.paste(visible, (380, 20))
    mask = Image.new("L", (320, 320), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, 319, 319), fill=255)
    sheet.paste(visible, (740, 20), mask)
    sheet.save("/tmp/hb_icon/preview_from_logo.png")
    print("background", hex_bg, "flask height", flask_h, "reach", round(far))
    print("done; preview at /tmp/hb_icon/preview_from_logo.png")


main(sys.argv[1])
