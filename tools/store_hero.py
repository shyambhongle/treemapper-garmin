#!/usr/bin/env python3
"""
Render the 1440x720 Connect IQ store hero image.

Reuses the screen renderer in preview.py so the watch face in the banner is the
same drawing maths as the app itself.

    python3 tools/store_hero.py   ->  store/store-hero-1440x720.png
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from PIL import Image, ImageDraw  # noqa: E402

import preview as P  # noqa: E402

OUT = os.path.join(REPO, "store")

W, H = 1440, 720
WATCH = 430                  # diameter of the watch face in the banner
WATCH_CX, WATCH_CY = 1090, 360
TEXT_X = 120


def glow(size, radius, colour, peak):
    """Soft radial falloff, drawn as concentric rings so no blur import."""
    layer = Image.new("RGB", (size, size), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    steps = 90
    for i in range(steps, 0, -1):
        t = i / steps
        r = radius * t
        a = peak * (1.0 - t) ** 2
        c = tuple(int(v * a) for v in colour)
        d.ellipse([size / 2 - r, size / 2 - r, size / 2 + r, size / 2 + r], fill=c)
    return layer


def build():
    img = Image.new("RGB", (W, H), (0, 0, 0))

    # Green bloom behind the watch, so the right half does not read as a hole.
    g = glow(1000, 480, P.GREEN, 0.85)
    img.paste(g, (WATCH_CX - 500, WATCH_CY - 500), Image.new("L", g.size, 255))

    # The watch face: the real capture screen at a good fix. Masked tight to
    # the ring so the renderer's own dark surround does not add a second edge.
    face = P.capture(WATCH, q=4).render().convert("RGB")
    inner = int(WATCH * 0.955)
    face = face.crop(((WATCH - inner) // 2, (WATCH - inner) // 2,
                      (WATCH + inner) // 2, (WATCH + inner) // 2))
    mask = Image.new("L", (inner, inner), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, inner - 1, inner - 1], fill=255)
    img.paste(face, (WATCH_CX - inner // 2, WATCH_CY - inner // 2), mask)

    d = ImageDraw.Draw(img)

    # The mark, white, as it is drawn on the watch.
    mark = Image.open(os.path.join(HERE, "mark_full.png")).convert("RGBA")
    mark = mark.crop(mark.split()[3].getbbox())
    mh = 68
    mark = mark.resize((int(mark.width * mh / mark.height), mh), Image.LANCZOS)
    img.paste(mark, (TEXT_X, 198), mark)

    d.text((TEXT_X, 296), "TreeMapper GPS",
           font=P.font(62, bold=True), fill=P.TEXT)
    d.text((TEXT_X, 388), "High accuracy GPS for mapping trees",
           font=P.font(30), fill=P.GREEN_LIGHT)
    d.line([TEXT_X, 452, TEXT_X + 210, 452], fill=P.HAIRLINE, width=2)
    d.text((TEXT_X, 478), "Every fix goes straight to the TreeMapper app",
           font=P.font(23), fill=P.TEXT_DIM)

    return img


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    hero = build()
    path = os.path.join(OUT, "store-hero-1440x720.png")
    hero.save(path, "PNG", optimize=True)
    print(f"{path}  {hero.size[0]}x{hero.size[1]}  "
          f"{os.path.getsize(path)/1024:.1f} KB  mode={hero.mode}")
