"""Draws the three launcher-shortcut icons (original artwork: an up arrow, a
down arrow and a bolt) and writes the Android and iOS files.

  Android: android/app/src/main/res/drawable-*dpi/ic_shortcut_*.png
           (full colour, on a dark disc)
  iOS:     ios/Runner/Assets.xcassets/ic_shortcut_*.imageset
           (black on transparent: iOS tints template images itself)

Run: python3 tools/make_shortcut_icons.py <project_dir>   (needs Pillow)
"""
import json, os, sys
from PIL import Image, ImageDraw

M = 1024  # master canvas; shapes are drawn on this grid
DISC = (14, 21, 19, 255)          # ink black with a faint green cast
AMBER = (255, 181, 71, 255)       # Spent
GREEN = (62, 224, 143, 255)       # Received
TEAL = (47, 214, 192, 255)        # accent


def up_arrow():
    return [
        [(512, 250), (790, 540), (610, 540), (610, 790), (414, 790), (414, 540), (234, 540)],
    ]


def down_arrow():
    return [[(x, M - y) for x, y in poly] for poly in up_arrow()]


def bolt():
    return [[(580, 200), (330, 560), (500, 560), (440, 830), (700, 440), (530, 440)]]


ICONS = {
    "ic_shortcut_expense": (up_arrow(), AMBER),
    "ic_shortcut_income": (down_arrow(), GREEN),
    "ic_shortcut_favorite": (bolt(), TEAL),
}


def render(polys, color, size, disc):
    big = Image.new("RGBA", (M, M), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    if disc:
        d.ellipse([0, 0, M - 1, M - 1], fill=DISC)
    for poly in polys:
        d.polygon(poly, fill=color)
    return big.resize((size, size), Image.LANCZOS)


def main(root):
    densities = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    res = os.path.join(root, "android/app/src/main/res")
    for name, (polys, color) in ICONS.items():
        for density, px in densities.items():
            folder = os.path.join(res, f"drawable-{density}")
            os.makedirs(folder, exist_ok=True)
            render(polys, color, px, disc=True).save(os.path.join(folder, f"{name}.png"))

        folder = os.path.join(root, "ios/Runner/Assets.xcassets", f"{name}.imageset")
        os.makedirs(folder, exist_ok=True)
        images = []
        for scale, px in ((1, 35), (2, 70), (3, 105)):
            fname = f"{name}@{scale}x.png" if scale > 1 else f"{name}.png"
            render(polys, (0, 0, 0, 255), px, disc=False).save(os.path.join(folder, fname))
            images.append({"idiom": "universal", "filename": fname, "scale": f"{scale}x"})
        with open(os.path.join(folder, "Contents.json"), "w") as f:
            json.dump(
                {
                    "images": images,
                    "info": {"author": "xcode", "version": 1},
                    "properties": {"template-rendering-intent": "template"},
                },
                f,
                indent=2,
            )

    # Keep the icons when release builds shrink resources: the plugin finds
    # them by name at run time, which the shrinker cannot see.
    raw = os.path.join(res, "raw")
    os.makedirs(raw, exist_ok=True)
    with open(os.path.join(raw, "keep.xml"), "w") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<resources xmlns:tools="http://schemas.android.com/tools"\n'
            '    tools:keep="@drawable/ic_shortcut_*" />\n'
        )


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
