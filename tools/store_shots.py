#!/usr/bin/env python3
"""
Render store screenshots at real device resolution using the preview renderer.

Garmin store screenshots: max 150 KB each. Rendered at the native pixel size of
the device so the store shows them without resampling.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import preview as P  # noqa: E402

OUT = os.path.join(REPO, "store", "screenshots")

# venu3 is the highest resolution round product in the manifest, so its frames
# downscale cleanly for every other device in the store listing.
SIZE = 454

SHOTS = [
    ("01-capture.png",   lambda: P.capture(SIZE, q=4)),
    ("02-acquiring.png", lambda: P.acquiring(SIZE, q=3)),
    ("03-sent.png",      lambda: P.sent(SIZE)),
    ("04-sending.png",   lambda: P.sending(SIZE)),
    ("05-home.png",      lambda: P.home(SIZE)),
    ("06-waiting.png",   lambda: P.capture(
        SIZE, q=2, ready=False,
        warning=("Open TreeMapper on phone", P.Q_USABLE))),
    ("07-notsent.png",   lambda: P.failed(SIZE)),
    ("08-rejected.png",  lambda: P.rejected(SIZE)),
]

LIMIT = 150 * 1024


def main():
    os.makedirs(OUT, exist_ok=True)
    print(f"font in use: {P.font(20).path}")
    for name, build in SHOTS:
        img = build().render()
        path = os.path.join(OUT, name)
        img.save(path, "PNG", optimize=True)
        n = os.path.getsize(path)
        flag = "OK " if n <= LIMIT else "OVER"
        print(f"{flag} {name:20s} {img.size[0]}x{img.size[1]}  {n/1024:6.1f} KB")


if __name__ == "__main__":
    main()
