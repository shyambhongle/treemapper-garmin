import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! Satellite acquisition. A sweeping arc while searching, then a short
//! confirmation beat once the fix clears the quality floor.
//!
//! This screen exists because a cold multi band fix takes real time in the
//! field, and the user needs to see that something is happening rather than
//! guess whether the watch is working.
class AcquiringView extends WatchUi.View {
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

        if (_lockedAtMs == null and session.quality >= session.minQuality) {
            _lockedAtMs = System.getTimer();
            _lockAnim.start();
        }

        // Hold the confirmation briefly so the lock is legible, then move on.
        var locked = _lockedAtMs;
        if (locked != null and (System.getTimer() - locked) > 1100) {
            var capture = new CaptureView();
            WatchUi.switchToView(capture, new CaptureDelegate(capture),
                                 WatchUi.SLIDE_IMMEDIATE);
            return;
        }

        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var L = _layout;
        var session = $.gSession;
        if (L == null or session == null) { return; }

        dc.setColor(Theme.BG, Theme.BG);
        dc.clear();
        UiKit.smooth(dc, true);

        var now = System.getTimer();
        var isLocked = (_lockedAtMs != null);

        UiKit.ringTrack(dc, L.cx, L.cy, L.ringRadius, L.ringWidth, Theme.SURFACE);

        if (isLocked) {
            drawLocked(dc, L, session);
        } else {
            drawSearching(dc, L, session, now);
        }
    }

    private function drawSearching(dc as Graphics.Dc, L as Layout,
                                   session as SessionState, now as Number) as Void {
        // Sweep speeds up a little as the fix improves, which reads as progress
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

        var waited = session.elapsedSeconds();
        UiKit.caption(dc, L.cx, L.bottomHintY,
                      waited.format("%d") + "s", L.fontLabel, Theme.TEXT_FAINT);
    }

    private function drawLocked(dc as Graphics.Dc, L as Layout,
                                session as SessionState) as Void {
        var p = _lockAnim.progress();
        var eased = Anim.easeOut(p);

        // The ring snaps closed to say: settled.
        UiKit.ringProgress(dc, L.cx, L.cy, L.ringRadius, L.ringWidth,
                           Theme.quality(session.quality), eased);

        UiKit.ripple(dc, L.cx, L.cy, (L.r * 0.78).toNumber(), Theme.GREEN_LIGHT, p);

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

    //! Let an impatient user skip straight through. In the real app this would
    //! warn that the fix is still poor.
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
