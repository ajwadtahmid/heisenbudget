"""Makes every app icon from the logo vector assets/logos/logo.svg. Run:
python3 tools/make_icon_from_logo.py <project_dir>
(needs Pillow and ImageMagick's `magick`, which draws the SVG).

Writes:
- iOS: every size in AppIcon.appiconset/Contents.json (opaque, as the App
  Store requires).
- Android: the legacy square icons, the adaptive foreground and background
  colour, and the monochrome layer for Android 13 themed icons.
- assets/logos/google_play_icon_512.png, the 512 px icon Google Play asks for.

The SVG must hold exactly three paths, in this order: the liquid, the glass
outline, the dollar sign. The first element's fill (a <rect>) is the icon's
ground colour. The SVG is drawn at each size, so the small icons stay crisp.

(tools/make_icon.py draws the earlier flask-and-coin icon; it stays so that
icon can be restored.)
"""
import json
import os
import re
import subprocess
import sys
import tempfile

from PIL import Image, ImageChops, ImageDraw

# iOS and the old square Android icons show the flask this big (share of height).
FLASK_SHARE = 0.72
# Adaptive icons: the flask must stay inside the 66dp circle of a 108dp icon.
SAFE_RADIUS = 0.30  # of the canvas side (66/108 / 2 = 0.305, with a hair spare)
# The SVG is drawn this big, then scaled down to every size.
DRAW = 2508
# Themed icons: a hairline gap between the glass and the liquid, in SVG units.
MONO_GAP = 14


def draw(svg, size):
    """The SVG text as an RGBA image [size] pixels square."""
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "in.svg")
        out = os.path.join(tmp, "out.png")
        with open(src, "w") as f:
            f.write(svg)
        subprocess.run(
            ["magick", "-background", "none", "-density", "300", src,
             "-resize", f"{size}x{size}", out],
            check=True,
        )
        return Image.open(out).convert("RGBA").copy()


def parse(svg):
    head = re.search(r"<svg[^>]*>", svg).group(0)
    box = [float(v) for v in re.search(r'viewBox="([^"]+)"', head).group(1).split()]
    paths = []
    for m in re.finditer(r"<path\b([^>]*)/>", svg, re.S):
        attrs = dict(re.findall(r"([\w-]+)=\"([^\"]*)\"", m.group(1)))
        paths.append(attrs)
    if len(paths) != 3:
        sys.exit("logo.svg must hold exactly three paths: liquid, outline, dollar")
    ground = re.search(r'<rect[^>]*fill="(#[0-9A-Fa-f]{6})"', svg)
    if not ground:
        sys.exit("logo.svg must start with a <rect> holding the ground colour")
    return head, box, paths, ground.group(1)


def layer(head, paths, fill, extra=""):
    body = "".join(
        f'<path d="{p["d"]}" fill="{fill}" fill-rule="{p.get("fill-rule", "nonzero")}"/>'
        for p in paths
    )
    return head + body + extra + "</svg>"


def alpha_of(svg):
    return draw(svg, DRAW).getchannel("A")


def rgb(hex_colour):
    h = hex_colour.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


def reach(mask, cx, cy):
    """The farthest any drawn pixel is from (cx, cy)."""
    step = 8
    small = mask.resize((mask.width // step, mask.height // step))
    px = small.load()
    far = 0.0
    for y in range(small.height):
        for x in range(small.width):
            if px[x, y] > 128:
                far = max(
                    far,
                    (((x + 0.5) * step - cx) ** 2 + ((y + 0.5) * step - cy) ** 2) ** 0.5,
                )
    return far


def square_around(img, fill, cx, cy, side):
    """A square of [side] pixels centred on (cx, cy), padded with [fill]."""
    side = int(round(side))
    canvas = Image.new(img.mode, (side, side), fill)
    canvas.paste(img, (int(round(side / 2 - cx)), int(round(side / 2 - cy))))
    return canvas


def main(project):
    with open(os.path.join(project, "assets/logos/logo.svg")) as f:
        svg = f.read()
    head, box, paths, ground = parse(svg)
    liquid, outline, dollar = paths
    bg = rgb(ground)

    art = draw(svg, DRAW).convert("RGB")
    glass = alpha_of(layer(head, [outline], "#000"))
    x0, y0, x1, y1 = glass.getbbox()
    cx, cy, flask_h = (x0 + x1) / 2, (y0 + y1) / 2, y1 - y0
    far = reach(glass, cx, cy)

    # iOS (opaque, every size in Contents.json) and the old square Android icons.
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
    legacy = [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]
    for folder, size in legacy:
        out = os.path.join(res, f"mipmap-{folder}/ic_launcher.png")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        full.resize((size, size), Image.LANCZOS).save(out)

    # Android adaptive icon: the flask on the ground colour, inside the safe circle.
    side = far / SAFE_RADIUS
    adaptive = square_around(art, bg, cx, cy, side)

    # Android 13 themed icon: one shape, the system tints it. The glass, the
    # liquid pulled in a little so the glass still reads as glass, and the
    # dollar sign cut out of the liquid. Same size and position as the
    # foreground, so it sits inside the same safe circle.
    w, h = box[2], box[3]
    inset = (
        head
        + f'<rect width="{w}" height="{h}" fill="#fff"/>'
        + f'<path d="{liquid["d"]}" fill="#000"/>'
        + f'<path d="{liquid["d"]}" fill="none" stroke="#fff" stroke-width="{MONO_GAP * 2}"/>'
        + "</svg>"
    )
    liquid_a = ImageChops.invert(draw(inset, DRAW).convert("L"))
    dollar_a = alpha_of(layer(head, [dollar], "#000"))
    shape = ImageChops.subtract(ImageChops.lighter(glass, liquid_a), dollar_a)
    mono = square_around(shape, 0, cx, cy, side)

    layers = [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)]
    for folder, size in layers:
        adaptive.resize((size, size), Image.LANCZOS).save(
            os.path.join(res, f"mipmap-{folder}/ic_launcher_foreground.png")
        )
        themed = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        themed.putalpha(mono.resize((size, size), Image.LANCZOS))
        themed.save(os.path.join(res, f"mipmap-{folder}/ic_launcher_monochrome.png"))
    with open(os.path.join(res, "values/ic_launcher_background.xml"), "w") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
            f'    <color name="ic_launcher_background">{ground.upper()}</color>\n</resources>\n'
        )
    with open(os.path.join(res, "mipmap-anydpi-v26/ic_launcher.xml"), "w") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
            "</adaptive-icon>\n"
        )

    # The 512 px icon Google Play asks for: square, opaque, no rounded corners
    # (Play rounds it itself).
    full.resize((512, 512), Image.LANCZOS).convert("RGBA").save(
        os.path.join(project, "assets/logos/google_play_icon_512.png")
    )

    preview(full, adaptive, mono)
    print("ground", ground, "flask height", flask_h, "reach", round(far))
    print("done; preview at /tmp/hb_icon/preview_from_logo.png")


def preview(full, adaptive, mono):
    """A contact sheet: the iOS icon, the adaptive icon in a circle, the
    themed icon tinted, then the smallest sizes enlarged."""
    os.makedirs("/tmp/hb_icon", exist_ok=True)
    tile = 256
    sheet = Image.new("RGB", (3 * (tile + 24) + 24, tile + 24 + 24 + 24 + 192), (60, 60, 60))
    ios = full.resize((tile, tile), Image.LANCZOS).convert("RGBA")
    rounded = Image.new("L", (tile, tile), 0)
    ImageDraw.Draw(rounded).rounded_rectangle((0, 0, tile - 1, tile - 1), 57, fill=255)
    sheet.paste(ios, (24, 24), rounded)

    visible = adaptive.resize((432, 432), Image.LANCZOS).crop((36, 36, 396, 396))
    visible = visible.resize((tile, tile), Image.LANCZOS)
    circle = Image.new("L", (tile, tile), 0)
    ImageDraw.Draw(circle).ellipse((0, 0, tile - 1, tile - 1), fill=255)
    sheet.paste(visible, (24 + (tile + 24), 24), circle)

    # A themed icon: the system's tint behind, the shape in a dark tone of it.
    themed = Image.new("RGB", (tile, tile), (178, 223, 219))
    shape = mono.resize((432, 432), Image.LANCZOS).crop((36, 36, 396, 396))
    shape = shape.resize((tile, tile), Image.LANCZOS)
    ink = Image.new("RGB", (tile, tile), (0, 59, 56))
    themed.paste(ink, (0, 0), shape)
    themed_round = Image.new("RGB", (tile, tile), (60, 60, 60))
    themed_round.paste(themed, (0, 0), circle)
    sheet.paste(themed_round, (24 + 2 * (tile + 24), 24))

    x = 24
    for s in (29, 40, 48, 60, 76):
        small = full.resize((s, s), Image.LANCZOS).convert("RGB")
        sheet.paste(small.resize((s * 3, s * 3), Image.NEAREST), (x, tile + 48))
        x += s * 3 + 12
    sheet.save("/tmp/hb_icon/preview_from_logo.png")


main(sys.argv[1])
