#!/usr/bin/env python3
"""
Build the 500x500 Connect IQ store icon from the TreeMapper mark.

Garmin store icon rules:
  - 500 x 500 px, sRGB
  - max 300 KB
  - solid background, no transparency, no black
  - artwork centred, not stretched or skewed, with padding to the edge
"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
MARK = os.path.join(HERE, "mark_full.png")
OUT = os.path.join(REPO, "store")

GREEN = (0x00, 0x7A, 0x49)   # Theme.GREEN, the TreeMapper brand colour
SIZE = 500
SS = 4                       # supersample, then downsample once at the end
MARK_HEIGHT = 0.60           # mark height as a fraction of the canvas


def build():
    mark = Image.open(MARK).convert("RGBA")
    bbox = mark.split()[3].getbbox()
    mark = mark.crop(bbox)

    canvas = SIZE * SS
    target_h = int(round(canvas * MARK_HEIGHT))
    target_w = int(round(mark.width * target_h / mark.height))
    mark = mark.resize((target_w, target_h), Image.LANCZOS)

    out = Image.new("RGB", (canvas, canvas), GREEN)
    out.paste(mark, ((canvas - target_w) // 2, (canvas - target_h) // 2), mark)
    out = out.resize((SIZE, SIZE), Image.LANCZOS)
    return out


if __name__ == "__main__":
    icon = build()
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "store-icon-500.png")
    icon.save(path, "PNG", optimize=True)
    kb = os.path.getsize(path) / 1024
    print(f"{path}  {icon.size[0]}x{icon.size[1]}  {kb:.1f} KB  mode={icon.mode}")
