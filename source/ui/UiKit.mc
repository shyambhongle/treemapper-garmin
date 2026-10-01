import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! Reusable drawing primitives.
//!
//! Everything is drawn with Dc calls rather than bitmaps so it scales to any
//! screen size and costs almost no memory. Nothing here loads a resource, so
//! these are safe to call from onUpdate().
module UiKit {

    //! Turn on anti aliasing where the device has it. Guarded, because it
    //! arrived in API 3.2.0 and older products will throw Symbol Not Found.
    function smooth(dc as Graphics.Dc, on as Boolean) as Void {
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(on);
        }
    }

    function norm(deg as Number) as Number {
        var a = deg;
        while (a < 0) { a += 360; }
        while (a >= 360) { a -= 360; }
        return a;
    }

    //! Full circle track.
    function ringTrack(dc as Graphics.Dc, cx as Number, cy as Number,
                       radius as Number, width as Number, colour as Number) as Void {
        dc.setPenWidth(width);
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, radius);
    }

    //! Continuous progress arc, clockwise from twelve o'clock.
    //! fraction runs 0.0 to 1.0.
    function ringProgress(dc as Graphics.Dc, cx as Number, cy as Number,
                          radius as Number, width as Number,
                          colour as Number, fraction as Float) as Void {
        var f = Anim.clamp(fraction);
        if (f <= 0.005) { return; }

        dc.setPenWidth(width);
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);

        if (f >= 0.999) {
            dc.drawCircle(cx, cy, radius);
            return;
        }

        var sweep = (360.0 * f).toNumber();
        var start = 90;
        var end = norm(90 - sweep);
        dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, start, end);
    }

    //! Four segment ring. Quality is a discrete 0..4 value, so four separate
    //! segments read more honestly than a smooth gauge: the user sees steps,
    //! which is what the receiver actually reports.
    function ringSegments(dc as Graphics.Dc, cx as Number, cy as Number,
                          radius as Number, width as Number,
                          filled as Number, onColour as Number,
                          offColour as Number) as Void {
        var gap = 12;
        var span = 90 - gap;

        dc.setPenWidth(width);
        for (var i = 0; i < 4; i++) {
            var start = norm(90 - (i * 90) - (gap / 2));
            var end = norm(start - span);
            dc.setColor(i < filled ? onColour : offColour, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, start, end);
        }
    }

    //! A single sweeping arc used while searching for a fix. headDeg is the
    //! leading edge in degrees; the tail fades out behind it.
    function ringSweep(dc as Graphics.Dc, cx as Number, cy as Number,
                       radius as Number, width as Number,
                       colour as Number, headDeg as Number) as Void {
        dc.setPenWidth(width);
        var steps = 6;
        var tail = 12;   // degrees per step
        for (var i = 0; i < steps; i++) {
            var alpha = 1.0 - (i.toFloat() / steps.toFloat());
            var start = norm(headDeg - (i * tail));
            var end = norm(start - tail);
            dc.setColor(Theme.fade(colour, alpha * alpha), Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, start, end);
        }
    }

    //! Draw a loaded bitmap centred on a point. Used for the TreeMapper mark,
    //! which is a real asset rather than code art so it matches the phone app
    //! exactly. Load it in onLayout and keep it: loading a resource inside
    //! onUpdate is expensive.
    function bitmapCentred(dc as Graphics.Dc, cx as Number, cy as Number,
                           bmp as WatchUi.BitmapResource) as Void {
        dc.drawBitmap(cx - (bmp.getWidth() / 2), cy - (bmp.getHeight() / 2), bmp);
    }

    //! A short arc chasing its tail. Used while a point is in flight to the
    //! phone, which is fast but not instant over Bluetooth.
    function spinner(dc as Graphics.Dc, cx as Number, cy as Number,
                     radius as Number, width as Number,
                     colour as Number, phaseDeg as Number) as Void {
        dc.setPenWidth(width);
        var steps = 5;
        var tail = 16;
        for (var i = 0; i < steps; i++) {
            var alpha = 1.0 - (i.toFloat() / steps.toFloat());
            var start = norm(phaseDeg - (i * tail));
            var end = norm(start - tail);
            dc.setColor(Theme.fade(colour, alpha * alpha), Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, start, end);
        }
    }

    //! Small filled dot, used for status indicators.
    function dot(dc as Graphics.Dc, x as Number, y as Number,
                 radius as Number, colour as Number) as Void {
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, radius);
    }

    //! A status pill: a dot plus a short label, centred on cx.
    function statusPill(dc as Graphics.Dc, cx as Number, y as Number,
                        label as String, colour as Number,
                        font as Graphics.FontType) as Void {
        var textW = dc.getTextWidthInPixels(label, font);
        var dotR = 3;
        var spacing = 7;
        var totalW = (dotR * 2) + spacing + textW;
        var left = cx - (totalW / 2);

        dot(dc, left + dotR, y, dotR, colour);

        dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + (dotR * 2) + spacing, y, font, label,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Centred caption text.
    function caption(dc as Graphics.Dc, cx as Number, y as Number,
                     text as String, font as Graphics.FontType,
                     colour as Number) as Void {
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, font, text,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Animated tick. progress 0.0 to 1.0 draws the stroke on.
    function check(dc as Graphics.Dc, cx as Number, cy as Number,
                   size as Float, colour as Number, progress as Float) as Void {
        var p = Anim.clamp(progress);
        var s = size;

        var ax = cx - (s * 0.46);
        var ay = cy + (s * 0.04);
        var bx = cx - (s * 0.12);
        var by = cy + (s * 0.36);
        var dx = cx + (s * 0.48);
        var dy = cy - (s * 0.36);

        var pen = (s * 0.17).toNumber();
        if (pen < 3) { pen = 3; }
        dc.setPenWidth(pen);
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);

        // First 40 percent draws the short leg, the rest draws the long leg.
        if (p <= 0.4) {
            var t = p / 0.4;
            dc.drawLine(ax.toNumber(), ay.toNumber(),
                        (ax + (bx - ax) * t).toNumber(),
                        (ay + (by - ay) * t).toNumber());
        } else {
            var t2 = (p - 0.4) / 0.6;
            dc.drawLine(ax.toNumber(), ay.toNumber(), bx.toNumber(), by.toNumber());
            dc.drawLine(bx.toNumber(), by.toNumber(),
                        (bx + (dx - bx) * t2).toNumber(),
                        (by + (dy - by) * t2).toNumber());
        }
    }

    //! Animated cross, for a rejected capture.
    function cross(dc as Graphics.Dc, cx as Number, cy as Number,
                   size as Float, colour as Number, progress as Float) as Void {
        var p = Anim.clamp(progress);
        var s = size * 0.40;
        var pen = (size * 0.16).toNumber();
        if (pen < 3) { pen = 3; }
        dc.setPenWidth(pen);
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);

        if (p <= 0.5) {
            var t = p / 0.5;
            dc.drawLine((cx - s).toNumber(), (cy - s).toNumber(),
                        (cx - s + (2 * s * t)).toNumber(),
                        (cy - s + (2 * s * t)).toNumber());
        } else {
            var t2 = (p - 0.5) / 0.5;
            dc.drawLine((cx - s).toNumber(), (cy - s).toNumber(),
                        (cx + s).toNumber(), (cy + s).toNumber());
            dc.drawLine((cx + s).toNumber(), (cy - s).toNumber(),
                        (cx + s - (2 * s * t2)).toNumber(),
                        (cy - s + (2 * s * t2)).toNumber());
        }
    }

    //! Expanding rings radiating from a point. Used on capture.
    function ripple(dc as Graphics.Dc, cx as Number, cy as Number,
                    maxRadius as Number, colour as Number, progress as Float) as Void {
        var p = Anim.clamp(progress);
        var count = 3;
        for (var i = 0; i < count; i++) {
            var offset = i.toFloat() * 0.18;
            var t = p - offset;
            if (t <= 0.0 or t >= 1.0) { continue; }

            var eased = Anim.easeOut(t);
            var radius = (maxRadius * eased).toNumber();
            var alpha = (1.0 - t) * 0.85;
            var pen = (4.0 * (1.0 - t)).toNumber();
            if (pen < 1) { pen = 1; }

            dc.setPenWidth(pen);
            dc.setColor(Theme.fade(colour, alpha), Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(cx, cy, radius);
        }
    }

    //! Four ascending bars, filled to match quality. A compact alternative to
    //! the ring for places where the edge is already busy.
    function signalBars(dc as Graphics.Dc, cx as Number, baseY as Number,
                        unit as Number, filled as Number,
                        onColour as Number, offColour as Number) as Void {
        var barW = unit;
        var gap = (unit * 0.7).toNumber();
        if (gap < 2) { gap = 2; }
        var total = (4 * barW) + (3 * gap);
        var left = cx - (total / 2);

        for (var i = 0; i < 4; i++) {
            var barH = unit * (i + 1);
            var x = left + (i * (barW + gap));
            dc.setColor(i < filled ? onColour : offColour, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, baseY - barH, barW, barH, 1);
        }
    }

    //! A thin horizontal rule, used to separate a hint from the content above.
    function hairline(dc as Graphics.Dc, cx as Number, y as Number,
                      width as Number, colour as Number) as Void {
        dc.setPenWidth(1);
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - (width / 2), y, cx + (width / 2), y);
    }
}
