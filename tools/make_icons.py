#!/usr/bin/env python3
"""
Build the app icons from the supplied TreeMapper artwork.

Inputs : tools/source_icon.png  (white glyph on the brand green square)
Outputs: resources/drawables/launcher_icon.png  128x128, as supplied
         resources/drawables/mark_w{64,96,130}.png  glyph only, white on transparent

The app draws the white glyph, since every screen is black. Three fixed sizes
are shipped rather than one scaled resource: the resource compiler's scaleX
attribute takes a pixel format, not a fraction of the screen, so Layout.mc picks
the right size at runtime from the screen width instead.
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "resources", "drawables")
SRC = os.path.join(HERE, "source_icon.png")

BRAND = (0x00, 0x7A, 0x49)


def glyph_alpha(img):
    """Return an alpha mask where the white artwork is opaque.

    The source is a white glyph on a solid green field, so whiteness is a
    clean proxy for coverage and it keeps the anti aliased edges intact.
    """
    rgb = img.convert("RGB")
    w, h = rgb.size
    alpha = Image.new("L", (w, h))
    src = rgb.load()
    dst = alpha.load()
    for y in range(h):
        for x in range(w):
            r, g, b = src[x, y]
            # distance from the brand green toward white, 0..1
            t = min(r, g, b) / 255.0
            # push the midpoint so the field stays fully transparent
            v = (t - 0.10) / 0.90
            dst[x, y] = max(0, min(255, int(v * 255)))
    return alpha


def tint(alpha, colour, size):
    out = Image.new("RGBA", alpha.size, colour + (0,))
    out.putalpha(alpha)
    return out.resize((size, size), Image.LANCZOS)


def main():
    if not os.path.exists(SRC):
        raise SystemExit("missing %s" % SRC)

    src = Image.open(SRC)
    # square it, in case the export carried a stray column
    side = min(src.size)
    src = src.crop((0, 0, side, side))

    src.convert("RGB").resize((128, 128), Image.LANCZOS).save(
        os.path.join(OUT, "launcher_icon.png"))

    a = glyph_alpha(src)
    # Roughly 30 percent of screen width for the three screen size bands.
    for size in (64, 96, 130):
        tint(a, (255, 255, 255), size).save(
            os.path.join(OUT, "mark_w%d.png" % size))
    # Kept full size for the preview renderer.
    tint(a, (255, 255, 255), 320).save(os.path.join(OUT, "..", "..",
                                                    "tools", "mark_full.png"))
    print("icons written")


if __name__ == "__main__":
    main()
