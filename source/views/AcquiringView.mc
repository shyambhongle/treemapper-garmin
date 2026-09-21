import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! Satellite acquisition.
//!
//! This screen exists because a cold multi band fix genuinely takes tens of
//! seconds under canopy, and the person needs to see the difference between
//! slow and broken. The elapsed counter is there for exactly that.
//!
//! It advances as soon as the receiver reports a real 3D-capable fix, or after
//! a long wait with any position at all, so nobody is trapped here.
class AcquiringView extends WatchUi.View {

    //! Quality at which we stop waiting. POOR means a real 2D fix, which is
    //! enough to start working: the watch sends quality with every point and
    //! the phone decides what to keep.
    const ADVANCE_QUALITY = 2;

    //! After this long, move on with whatever exists rather than stare.
    const PATIENCE_MS = 90000;

    private var _layout as Layout or Null;
    private var _timer as Timer.Timer or Null;
    private var _lockedAtMs as Number or Null;
    private var _lockAnim as Anim.Timeline;

    function initialize() {
        View.initialize();
        _lockedAtMs = null;
        _lockAnim = new Anim.Timeline(700);
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _layout = new Layout(dc);
    }

    function onShow() as Void {
        _lockedAtMs = null;
        _lockAnim.reset();
        _timer = new Timer.Timer();
        _timer.start(method(:onFrame), 50, true);
    }

    function onHide() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    function onFrame() as Void {
        var session = $.gSession;
        if (session == null) { return; }

        session.tick();

        // The phone may ask for a point before the person has even looked at
        // the watch. Get out of the way and let the capture screen show it.
        if (session.isRemoteActive()) {
            toCapture();
            return;
        }

        var gps = session.gps();
        var settled = session.quality >= ADVANCE_QUALITY
            or (gps.hasPosition() and gps.warmupSeconds() * 1000 > PATIENCE_MS);

        if (_lockedAtMs == null and settled) {
            _lockedAtMs = System.getTimer();
            _lockAnim.start();
        }

        var locked = _lockedAtMs;
        if (locked != null and (System.getTimer() - locked) > 1100) {
            toCapture();
            return;
        }

        WatchUi.requestUpdate();
    }

    private function toCapture() as Void {
        var capture = new CaptureView();
        WatchUi.switchToView(capture, new CaptureDelegate(capture),
                             WatchUi.SLIDE_IMMEDIATE);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var L = _layout;
        var session = $.gSession;
        if (L == null or session == null) { return; }

        dc.setColor(Theme.BG, Theme.BG);
        dc.clear();
        UiKit.smooth(dc, true);

        UiKit.ringTrack(dc, L.cx, L.cy, L.ringRadius, L.ringWidth, Theme.SURFACE);

        if (_lockedAtMs != null) {
            drawLocked(dc, L, session);
        } else {
            drawSearching(dc, L, session);
        }
    }

    private function drawSearching(dc as Graphics.Dc, L as Layout,
                                   session as SessionState) as Void {
        var now = System.getTimer();

        // The sweep speeds up as the fix improves, which reads as progress
        // without needing a number nobody can interpret.
        var speed = 210 + (session.quality * 40);
        var head = ((now / 1000.0) * speed).toNumber() % 360;
        var colour = session.quality >= 2 ? Theme.quality(session.quality) : Theme.GREEN;

        UiKit.ringSweep(dc, L.cx, L.cy, L.ringRadius, L.ringWidth, colour, head);

        UiKit.caption(dc, L.cx, L.topLabelY, "ACQUIRING", L.fontLabel, Theme.TEXT_FAINT);

        UiKit.signalBars(dc, L.cx, (L.h * 0.50).toNumber(),
                         (L.r * 0.075).toNumber(), session.quality,
                         Theme.quality(session.quality), Theme.SURFACE);

        UiKit.caption(dc, L.cx, (L.h * 0.60).toNumber(),
                      Theme.qualityLabel(session.quality),
                      L.fontBody, Theme.quality(session.quality));

        // Elapsed, so slow is distinguishable from broken.
        UiKit.caption(dc, L.cx, L.bottomHintY,
                      session.gps().warmupSeconds().format("%d") + "s",
                      L.fontLabel, Theme.TEXT_FAINT);
    }

    private function drawLocked(dc as Graphics.Dc, L as Layout,
                                session as SessionState) as Void {
        var p = _lockAnim.progress();
        var eased = Anim.easeOut(p);

        UiKit.ringProgress(dc, L.cx, L.cy, L.ringRadius, L.ringWidth,
                           Theme.quality(session.quality), eased);

        UiKit.ripple(dc, L.cx, L.cy, (L.r * 0.34).toNumber(), Theme.GREEN_LIGHT, p);

        var size = (L.r * 0.30) * Anim.easeBack(Anim.clamp(p * 1.4));
        UiKit.check(dc, L.cx, (L.h * 0.44).toNumber(), size.toFloat(),
                    Theme.GREEN_LIGHT, Anim.clamp(p * 1.6));

        UiKit.caption(dc, L.cx, (L.h * 0.68).toNumber(), "FIX ACQUIRED",
                      L.fontBody, Theme.blend(Theme.BG, Theme.TEXT, eased));
    }
}

class AcquiringDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    //! Skip ahead. The capture screen refuses only when there is no position
    //! at all, so an impatient user cannot break anything here.
    function onSelect() as Boolean {
        var capture = new CaptureView();
        WatchUi.switchToView(capture, new CaptureDelegate(capture),
                             WatchUi.SLIDE_IMMEDIATE);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
