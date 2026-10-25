"""Draws the Heisenbudget icon (original artwork: a flask with a coin) and writes
the iOS and Android icon files. Run: python3 tools/make_icon.py <project_dir>  (needs Pillow)"""
import json, os, sys
from PIL import Image, ImageDraw

S = 2048  # master size; shapes are drawn on a 1024 grid and scaled x2
GREEN_TOP, GREEN_BOTTOM = (13, 20, 17), (5, 8, 7)   # ink black, faint green cast
AMBER, AMBER_DARK = (255, 179, 0), (204, 140, 0)
GLASS = (47, 214, 192)   # assay-teal outline


def p(points):
    return [(x * 2, y * 2) for x, y in points]


def flask_layer(with_background):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    if with_background:
        bg = Image.new("RGBA", (S, S))
        px = bg.load()
        for y in range(S):
            t = y / (S - 1)
            c = tuple(int(GREEN_TOP[i] + (GREEN_BOTTOM[i] - GREEN_TOP[i]) * t) for i in range(3))
            for x in range(S):
                px[x, y] = c + (255,)
        img = bg
    d = ImageDraw.Draw(img)

    # Flask outline (neck + conical body), drawn as one glass-white shape.
    body = p([(430, 200), (594, 200), (594, 400), (790, 760), (790, 800),
              (760, 840), (264, 840), (234, 800), (234, 760), (430, 400)])
    d.polygon(body, fill=GLASS)
    d.rounded_rectangle(p([(396, 168), (628, 232)]), radius=28, fill=GLASS)

    # Inner cavity (cut out), then amber liquid in the lower part.
    cavity = p([(466, 236), (558, 236), (558, 420), (740, 770), (740, 790),
                (724, 804), (300, 804), (284, 790), (284, 770), (466, 420)])
    liquid_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(liquid_mask).polygon(cavity, fill=255)
    cut = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bgfill = ImageDraw.Draw(cut)
    bgfill.polygon(cavity, fill=(0, 0, 0, 255))
    # Re-paint the cavity with the background so the glass reads as an outline.
    if with_background:
        inner = img.copy()
        # background colour inside the cavity: sample a gradient again
        for_y = Image.new("RGBA", (S, S))
        px = for_y.load()
        for y in range(S):
            t = y / (S - 1)
            c = tuple(int(GREEN_TOP[i] + (GREEN_BOTTOM[i] - GREEN_TOP[i]) * t) for i in range(3))
            for x in range(S):
                px[x, y] = c + (255,)
        img = Image.composite(for_y, img, liquid_mask)
    else:
        arr = img.load()
        m = liquid_mask.load()
        for y in range(S):
            for x in range(S):
                if m[x, y]:
                    arr[x, y] = (0, 0, 0, 0)
    d = ImageDraw.Draw(img)

    liquid = Image.new("L", (S, S), 0)
    ImageDraw.Draw(liquid).rectangle(p([(0, 600), (1024, 1024)]), fill=255)
    liquid_only = Image.new("L", (S, S), 0)
    liquid_only.paste(liquid_mask, mask=liquid)
    amber = Image.new("RGBA", (S, S), AMBER + (255,))
    img = Image.composite(amber, img, Image.composite(liquid_mask, Image.new("L", (S, S), 0), liquid))

    # The coin floating in the liquid.
    d = ImageDraw.Draw(img)
    cx, cy, r = 512, 690, 92
    d.ellipse(p([(cx - r, cy - r), (cx + r, cy + r)]), fill=(255, 236, 160), outline=AMBER_DARK, width=10)
    r2 = 62
    d.ellipse(p([(cx - r2, cy - r2), (cx + r2, cy + r2)]), outline=AMBER_DARK, width=8)
    # A simple "I" bar in the coin keeps it generic (no currency glyph needed).
    d.rounded_rectangle(p([(cx - 12, cy - 36), (cx + 12, cy + 36)]), radius=8, fill=AMBER_DARK)

    # Bubbles above the liquid line.
    for bx, by, br in [(500, 520, 20), (548, 470, 13), (520, 410, 9)]:
        d.ellipse(p([(bx - br, by - br), (bx + br, by + br)]), outline=(47, 214, 192), width=6)
    return img


def save(img, path, size, opaque=False):
    out = img.resize((size, size), Image.LANCZOS)
    if opaque:
        flat = Image.new("RGB", out.size, GREEN_BOTTOM)
        flat.paste(out, mask=out.split()[3])
        out = flat
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.save(path)


def main(project):
    full = flask_layer(with_background=True)
    fg = flask_layer(with_background=False)

    # iOS: every file named in Contents.json.
    ios_dir = os.path.join(project, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
    with open(os.path.join(ios_dir, "Contents.json")) as f:
        contents = json.load(f)
    for entry in contents["images"]:
        base = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].replace("x", ""))
        save(full, os.path.join(ios_dir, entry["filename"]), round(base * scale), opaque=True)

    # Android legacy launcher icons.
    res = os.path.join(project, "android/app/src/main/res")
    for folder, size in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
        save(full, os.path.join(res, f"mipmap-{folder}/ic_launcher.png"), size)

    # Android adaptive icon: foreground sits inside the 66% safe zone.
    for folder, size in [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)]:
        canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        shrunk = fg.resize((int(S * 0.62), int(S * 0.62)), Image.LANCZOS)
        off = (S - shrunk.size[0]) // 2
        canvas.paste(shrunk, (off, off), shrunk)
        save(canvas, os.path.join(res, f"mipmap-{folder}/ic_launcher_foreground.png"), size)

    os.makedirs(os.path.join(res, "mipmap-anydpi-v26"), exist_ok=True)
    with open(os.path.join(res, "mipmap-anydpi-v26/ic_launcher.xml"), "w") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@color/ic_launcher_background"/>\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '</adaptive-icon>\n')
    with open(os.path.join(res, "values/ic_launcher_background.xml"), "w") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
                '    <color name="ic_launcher_background">#070A09</color>\n</resources>\n')

    # A preview for a quick look.
    preview = os.path.join("/tmp/hb_icon", "preview.png")
    full.resize((512, 512), Image.LANCZOS).save(preview)
    print("done; preview at", preview)


main(sys.argv[1])
