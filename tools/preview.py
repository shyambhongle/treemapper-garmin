#!/usr/bin/env python3
"""
Render static previews of the TreeMapper GPS watch screens.

This mirrors the drawing maths in source/ui/UiKit.mc so the design can be
reviewed without launching the Connect IQ simulator. It is a review aid only:
the watch app itself draws everything in Monkey C.

    python3 tools/preview.py     ->  writes previews/*.png
"""
import os
from PIL import Image, ImageDraw, ImageFont

SS = 4  # supersample factor

# ---- mirrors source/ui/Theme.mc -----------------------------------------
GREEN       = (0x00, 0x7A, 0x49)
GREEN_LIGHT = (0x35, 0xA9, 0x7A)
GREEN_SOFT  = (0x00, 0x30, 0x1C)
BG         = (0x00, 0x00, 0x00)
SURFACE    = (0x10, 0x10, 0x10)
HAIRLINE   = (0x2A, 0x2A, 0x2A)
TEXT       = (0xFF, 0xFF, 0xFF)
TEXT_DIM   = (0x9A, 0x9A, 0x9A)
TEXT_FAINT = (0x5A, 0x5A, 0x5A)
Q_POOR     = (0xE0, 0x4A, 0x3C)
Q_USABLE   = (0xE8, 0xA3, 0x3D)
Q_GOOD     = (0x00, 0x9A, 0x5C)
OFFLINE    = (0xE0, 0x4A, 0x3C)
MARK_PNG   = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mark_full.png")

# DejaVu is the reference face, because its condensed cut is the closest free
# match to Garmin's own screen font. Where it is not installed, fall back
# through whatever the host does have: this is a review aid, and a slightly
# different face is far better than not rendering at all.
FONT_DIRS = [
    d for d in [
        os.environ.get("TM_FONT_DIR"),
        "/usr/share/fonts/truetype/dejavu",          # Debian, Ubuntu
        "/usr/share/fonts/dejavu",                   # Fedora, Arch
        "/opt/homebrew/share/fonts",                 # macOS, Homebrew
        "/Library/Fonts",
        "/System/Library/Fonts/Supplemental",        # macOS stock
        "/System/Library/Fonts",
    ] if d
]

# matplotlib bundles DejaVu, so use its copy when it is importable.
try:
    import matplotlib
    FONT_DIRS.insert(1, os.path.join(
        os.path.dirname(matplotlib.__file__), "mpl-data", "fonts", "ttf"))
except ImportError:
    pass


def _find_font(names):
    """First existing file among `names`, searched across FONT_DIRS."""
    for name in names:
        for d in FONT_DIRS:
            path = os.path.join(d, name)
            if os.path.exists(path):
                return path
    return None


def font(size, bold=False, condensed=True):
    stem = "DejaVuSansCondensed" if condensed else "DejaVuSans"
    suffix = "-Bold" if bold else ""
    candidates = [
        stem + suffix + ".ttf",
        "DejaVuSans" + suffix + ".ttf",
        "DejaVuSans.ttf",
        "HelveticaNeue.ttc" if not bold else "HelveticaNeue.ttc",
        "Helvetica.ttc",
        "Arial Unicode.ttf",
    ]
    path = _find_font(candidates)
    if path is None:
        raise SystemExit(
            "No usable font found. Searched:\n  "
            + "\n  ".join(FONT_DIRS)
            + "\nInstall DejaVu, or set TM_FONT_DIR to a directory holding it."
        )
    return ImageFont.truetype(path, max(6, int(size)))


def blend(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def fade(colour, alpha):
    return blend(BG, colour, alpha)


def qcolour(q):
    return {4: Q_GOOD, 3: Q_USABLE, 2: Q_POOR}.get(q, TEXT_FAINT)


def qlabel(q):
    return {4: "GOOD", 3: "USABLE", 2: "POOR", 1: "STALE"}.get(q, "NO FIX")


class Screen(object):
    """One watch screen, with helpers matching UiKit.mc."""

    def __init__(self, size):
        self.size = size
        self.W = size * SS
        self.img = Image.new("RGB", (self.W, self.W), BG)
        self.d = ImageDraw.Draw(self.img)
        self.cx = self.W // 2
        self.cy = self.W // 2
        self.r = self.W // 2
        self.track_inset = int(self.r * 0.055)
        self.ring_w = int(self.r * 0.075)
        self.ring_r = self.r - self.track_inset - self.ring_w // 2

    def fill(self, colour):
        self.d.rectangle([0, 0, self.W, self.W], fill=colour)

    # PIL arcs run clockwise from 3 o'clock; Connect IQ runs counter clockwise.
    def arc(self, radius, width, colour, start, end):
        box = [self.cx - radius, self.cy - radius,
               self.cx + radius, self.cy + radius]
        self.d.arc(box, -start, -end, fill=colour, width=int(width))

    def ring_track(self, colour):
        self.arc(self.ring_r, self.ring_w, colour, 0, 359.9)

    def ring_progress(self, colour, fraction, radius=None, width=None):
        radius = self.ring_r if radius is None else radius
        width = self.ring_w if width is None else width
        if fraction <= 0.005:
            return
        sweep = 360.0 * min(fraction, 1.0)
        self.arc(radius, width, colour, 90, 90 - sweep)

    def ring_segments(self, filled, on, off):
        gap, span = 12.0, 78.0
        for i in range(4):
            start = 90 - (i * 90) - gap / 2
            self.arc(self.ring_r, self.ring_w,
                     on if i < filled else off, start, start - span)

    def ring_sweep(self, colour, head):
        tail = 12.0
        for i in range(6):
            alpha = 1.0 - i / 6.0
            start = head - i * tail
            self.arc(self.ring_r, self.ring_w,
                     fade(colour, alpha * alpha), start, start - tail)

    def mark(self, cy, rel_width=0.30):
        """Paste the real TreeMapper mark, as the app does."""
        m = Image.open(MARK_PNG).convert("RGBA")
        w = int(self.W * rel_width)
        m = m.resize((w, w), Image.LANCZOS)
        self.img.paste(m, (self.cx - w // 2, int(cy) - w // 2), m)
        self.d = ImageDraw.Draw(self.img)

    def spinner(self, radius, width, colour, phase):
        tail = 16.0
        for i in range(5):
            alpha = 1.0 - i / 5.0
            start = phase - i * tail
            self.arc(radius, width, fade(colour, alpha * alpha), start, start - tail)

    def text(self, y, s, rel_size, colour, bold=False, condensed=True,
             tracking=0.0):
        f = font(rel_size * self.W, bold=bold, condensed=condensed)
        if tracking > 0 and len(s) > 1:
            gap = int(tracking * self.W)
            widths = [self.d.textlength(ch, font=f) for ch in s]
            total = sum(widths) + gap * (len(s) - 1)
            x = self.cx - total / 2
            bb = self.d.textbbox((0, 0), s, font=f)
            top = y - (bb[3] - bb[1]) / 2 - bb[1]
            for ch, w in zip(s, widths):
                self.d.text((x, top), ch, font=f, fill=colour)
                x += w + gap
            return
        bb = self.d.textbbox((0, 0), s, font=f)
        self.d.text((self.cx - (bb[2] - bb[0]) / 2 - bb[0],
                     y - (bb[3] - bb[1]) / 2 - bb[1]),
                    s, font=f, fill=colour)

    def check(self, cy, s, colour, progress=1.0):
        ax, ay = self.cx - s * 0.46, cy + s * 0.04
        bx, by = self.cx - s * 0.12, cy + s * 0.36
        dx, dy = self.cx + s * 0.48, cy - s * 0.36
        pen = max(3, int(s * 0.17))
        if progress <= 0.4:
            t = progress / 0.4
            self.d.line([ax, ay, ax + (bx - ax) * t, ay + (by - ay) * t],
                        fill=colour, width=pen)
        else:
            t = (progress - 0.4) / 0.6
            self.d.line([ax, ay, bx, by], fill=colour, width=pen)
            self.d.line([bx, by, bx + (dx - bx) * t, by + (dy - by) * t],
                        fill=colour, width=pen)

    def cross(self, cy, size, colour):
        s = size * 0.40
        pen = max(3, int(size * 0.16))
        self.d.line([self.cx - s, cy - s, self.cx + s, cy + s],
                    fill=colour, width=pen)
        self.d.line([self.cx + s, cy - s, self.cx - s, cy + s],
                    fill=colour, width=pen)

    def ripple(self, max_r, colour, progress):
        for i in range(3):
            t = progress - i * 0.18
            if t <= 0 or t >= 1:
                continue
            rad = max_r * (1 - (1 - t) ** 3)
            self.d.ellipse([self.cx - rad, self.cy - rad,
                            self.cx + rad, self.cy + rad],
                           outline=fade(colour, (1 - t) * 0.85),
                           width=max(1, int(4 * SS * (1 - t))))

    def bars(self, base_y, unit, filled, on, off):
        gap = max(2, int(unit * 0.7))
        total = 4 * unit + 3 * gap
        left = self.cx - total // 2
        for i in range(4):
            h = unit * (i + 1)
            x = left + i * (unit + gap)
            self.d.rounded_rectangle([x, base_y - h, x + unit, base_y],
                                     radius=2, fill=on if i < filled else off)

    def pill(self, y, label, colour):
        f = font(0.030 * self.W)
        bb = self.d.textbbox((0, 0), label, font=f)
        tw = bb[2] - bb[0]
        dot_r = int(0.009 * self.W)
        spacing = int(0.020 * self.W)
        total = dot_r * 2 + spacing + tw
        left = self.cx - total // 2
        self.d.ellipse([left, y - dot_r, left + dot_r * 2, y + dot_r], fill=colour)
        self.d.text((left + dot_r * 2 + spacing, y - (bb[3] - bb[1]) / 2 - bb[1]),
                    label, font=f, fill=TEXT_DIM)

    def hairline(self, y, width, colour):
        self.d.line([self.cx - width // 2, y, self.cx + width // 2, y],
                    fill=colour, width=max(1, SS // 2))

    def render(self):
        out = self.img.resize((self.size, self.size), Image.LANCZOS)
        mask = Image.new("L", (self.W, self.W), 0)
        ImageDraw.Draw(mask).ellipse([0, 0, self.W - 1, self.W - 1], fill=255)
        mask = mask.resize((self.size, self.size), Image.LANCZOS)
        framed = Image.new("RGB", (self.size, self.size), (16, 16, 18))
        framed.paste(out, (0, 0), mask)
        return framed


# ---- screens -------------------------------------------------------------

def home(size):
    s = Screen(size)
    halo = int(s.r * 0.48)
    hy = int(s.W * 0.355)
    s.d.ellipse([s.cx - halo, hy - halo, s.cx + halo, hy + halo],
                outline=blend(BG, GREEN, 0.60), width=max(2, SS))
    s.mark(hy, 0.30)
    s.text(int(s.W * 0.635), "TREEMAPPER", 0.058, TEXT, bold=True, tracking=0.006)
    s.text(int(s.W * 0.715), "GPS companion", 0.034, TEXT_FAINT)
    s.text(int(s.W * 0.835), "starting receiver", 0.034, GREEN_LIGHT)
    return s


def acquiring(size, q=2):
    s = Screen(size)
    s.ring_track(SURFACE)
    s.ring_sweep(qcolour(q) if q >= 2 else GREEN, 205)
    s.text(int(s.W * 0.20), "ACQUIRING", 0.033, TEXT_FAINT, tracking=0.008)
    s.bars(int(s.W * 0.50), int(s.r * 0.075), q, qcolour(q), SURFACE)
    s.text(int(s.W * 0.60), qlabel(q), 0.044, qcolour(q))
    s.text(int(s.W * 0.835), "6s", 0.034, TEXT_FAINT)
    return s


def capture(size, q=4, ready=True, warning=None):
    """The fix screen: one converged position, offered to the phone."""
    s = Screen(size)
    s.ring_segments(q, qcolour(q), SURFACE)
    s.text(int(s.W * 0.20), "GNSS FIX", 0.033, TEXT_FAINT, tracking=0.006)
    s.text(int(s.W * 0.42), qlabel(q), 0.060, qcolour(q), bold=True, tracking=0.006)
    if warning is not None:
        s.pill(int(s.W * 0.63), warning[0], warning[1])
    s.hairline(int(s.W * 0.705), int(s.W * 0.30), HAIRLINE)
    s.text(int(s.W * 0.78), "START  send" if ready else "no position yet",
           0.042, GREEN_LIGHT if ready else TEXT_FAINT)
    s.text(int(s.W * 0.855), "BACK  restart", 0.032, TEXT_FAINT)
    return s


def sending(size, q=4):
    s = Screen(size)
    s.ring_segments(q, qcolour(q), SURFACE)
    s.cy = int(s.W * 0.42)
    s.arc(int(s.r * 0.34), int(s.r * 0.055), SURFACE, 0, 359.9)
    s.spinner(int(s.r * 0.34), int(s.r * 0.055), GREEN_LIGHT, 140)
    s.cy = s.W // 2
    s.text(int(s.W * 0.62), "SENDING", 0.044, TEXT, tracking=0.008)
    s.text(int(s.W * 0.71), "requested by phone", 0.033, TEXT_FAINT)
    return s


def sent(size, countdown=0.62):
    """Only ever shown on success, then it returns to acquiring."""
    s = Screen(size)
    s.ring_progress(fade(GREEN_LIGHT, 0.55), countdown, width=s.ring_w // 2 + 1)
    s.cy = int(s.W * 0.40)
    s.ripple(int(s.r * 0.32), GREEN_LIGHT, 0.55)
    s.cy = s.W // 2
    s.check(int(s.W * 0.40), s.r * 0.30, GREEN_LIGHT, 1.0)
    s.text(int(s.W * 0.62), "SENT", 0.044, TEXT, bold=True, tracking=0.008)
    s.text(int(s.W * 0.70), "TreeMapper has it", 0.033, TEXT_FAINT)
    s.text(int(s.W * 0.83), "next tree", 0.032, GREEN_LIGHT)
    return s


def failed(size, q=4):
    """The fix is still in hand. Try the same one again, or start over."""
    s = Screen(size)
    s.ring_segments(q, qcolour(q), SURFACE)
    s.cross(int(s.W * 0.355), s.r * 0.30, OFFLINE)
    s.text(int(s.W * 0.545), "NOT SENT", 0.044, TEXT, bold=True, tracking=0.008)
    s.text(int(s.W * 0.625), "phone not in range", 0.033, OFFLINE)
    s.hairline(int(s.W * 0.705), int(s.W * 0.30), HAIRLINE)
    s.text(int(s.W * 0.78), "START  try again", 0.042, GREEN_LIGHT)
    s.text(int(s.W * 0.855), "BACK  restart", 0.032, TEXT_FAINT)
    return s


def rejected(size, q=0):
    """The receiver has no position at all. The only thing the watch refuses."""
    s = Screen(size)
    s.ring_segments(q, qcolour(q), SURFACE)
    s.cross(int(s.W * 0.43), s.r * 0.30, Q_USABLE)
    s.text(int(s.W * 0.66), "NOT SENT", 0.044, TEXT, bold=True, tracking=0.008)
    s.text(int(s.W * 0.755), "no position yet", 0.033, Q_USABLE)
    return s


def main():
    out = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "previews"))
    os.makedirs(out, exist_ok=True)
    size = 300

    shots = [
        ("1-home.png", home(size)),
        ("2-acquiring.png", acquiring(size, q=2)),
        ("3-capture.png", capture(size, q=4)),
        ("4-sending.png", sending(size)),
        ("5-sent.png", sent(size)),
        ("6-failed.png", failed(size)),
        ("7-waiting.png", capture(size, q=2, ready=False,
                                  warning=("Open TreeMapper on phone", Q_USABLE))),
        ("8-rejected.png", rejected(size)),
    ]

    frames = []
    for name, scr in shots:
        img = scr.render()
        img.save(os.path.join(out, name))
        frames.append(img)
        print("wrote", name)

    pad, cols = 16, 4
    rows = (len(frames) + cols - 1) // cols
    sheet = Image.new("RGB",
                      (cols * size + (cols + 1) * pad,
                       rows * size + (rows + 1) * pad),
                      (10, 10, 12))
    for i, f in enumerate(frames):
        sheet.paste(f, (pad + (i % cols) * (size + pad),
                        pad + (i // cols) * (size + pad)))
    sheet.save(os.path.join(out, "contact-sheet.png"))
    print("wrote contact-sheet.png")


if __name__ == "__main__":
    main()
