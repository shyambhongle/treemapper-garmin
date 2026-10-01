import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! Confirmation that a fix reached TreeMapper.
//!
//! Only ever shown on success. A send that fails stays on the capture screen,
//! where the fix is still in hand and can be tried again; it would be
//! dishonest to show a confirmation for it.
//!
//! The watch has already forgotten the coordinate by the time this appears, so
//! there is nothing here to act on. It holds for a beat and returns to
//! acquisition for the next tree. Pressing START skips the wait.
//! Milliseconds before the screen continues on its own.
const AUTO_MS = 2000;

class SentView extends WatchUi.View {

    private var _layout as Layout or Null;
    private var _timer as Timer.Timer or Null;
    private var _reveal as Anim.Timeline;
    private var _shownAtMs as Number = 0;
    private var _moved as Boolean = false;

    function initialize() {
        View.initialize();
        _reveal = new Anim.Timeline(600);
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _layout = new Layout(dc);
    }

    function onShow() as Void {
        _moved = false;
        _shownAtMs = System.getTimer();
        _reveal.start();
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
        if (session != null) {
            session.tick();
        }

        if ((System.getTimer() - _shownAtMs) >= AUTO_MS) {
            advance();
            return;
        }
        WatchUi.requestUpdate();
    }

    //! Start the process again for the next tree. The receiver never stopped,
    //! so acquisition is normally instant.
    function advance() as Void {
        if (_moved) { return; }
        _moved = true;
        WatchUi.switchToView(new AcquiringView(), new AcquiringDelegate(),
                             WatchUi.SLIDE_RIGHT);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var L = _layout;
        if (L == null) { return; }

        dc.setColor(Theme.BG, Theme.BG);
        dc.clear();
        UiKit.smooth(dc, true);

        var p = _reveal.progress();
        var eased = Anim.easeOut(p);

        // A thin draining arc, deliberately unlike the segmented quality ring,
        // so it reads as a countdown rather than as signal strength.
        var elapsed = System.getTimer() - _shownAtMs;
        var left = 1.0 - (elapsed.toFloat() / AUTO_MS.toFloat());
        if (left < 0.0) { left = 0.0; }
        UiKit.ringProgress(dc, L.cx, L.cy, L.ringRadius, (L.ringWidth / 2) + 1,
                           Theme.fade(Theme.GREEN_LIGHT, 0.55), left);

        // Kept tight, so the rings never cross the label below.
        UiKit.ripple(dc, L.cx, (L.h * 0.40).toNumber(),
                     (L.r * 0.32).toNumber(), Theme.GREEN_LIGHT, p);

        var size = (L.r * 0.30) * Anim.easeBack(Anim.clamp(p * 1.5));
        UiKit.check(dc, L.cx, (L.h * 0.40).toNumber(), size.toFloat(),
                    Theme.GREEN_LIGHT, Anim.clamp(p * 1.8));

        UiKit.caption(dc, L.cx, (L.h * 0.62).toNumber(), "SENT",
                      L.fontBody, Theme.blend(Theme.BG, Theme.TEXT, eased));

        UiKit.caption(dc, L.cx, (L.h * 0.70).toNumber(), "TreeMapper has it",
                      L.fontLabel, Theme.blend(Theme.BG, Theme.TEXT_FAINT, eased));

        UiKit.caption(dc, L.cx, L.bottomHintY, "next tree",
                      L.fontLabel, Theme.blend(Theme.BG, Theme.GREEN_LIGHT,
                                               eased * 0.85));
    }
}

class SentDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        return skip();
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        return skip();
    }

    //! Nothing is in hand here, so back and forward mean the same thing: get
    //! on with the next tree.
    function onBack() as Boolean {
        return skip();
    }

    private function skip() as Boolean {
        WatchUi.switchToView(new AcquiringView(), new AcquiringDelegate(),
                             WatchUi.SLIDE_RIGHT);
        return true;
    }
}
