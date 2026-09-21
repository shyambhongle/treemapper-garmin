import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! Confirmation after a point goes to the phone.
//!
//! Two things happen here. It says plainly whether the coordinate reached
//! TreeMapper or is still sitting on the watch, and it offers the only two
//! things anyone wants next: the following tree, or stop.
//!
//! It also advances on its own after a few seconds. Mapping sixty trees
//! should not cost sixty extra decisions, so continuing is the default and the
//! draining arc at the edge shows how long is left. Pressing START skips the
//! wait; pressing BACK finishes instead. Set AUTO_MS to 0 to require a press
//! every time.
//! Milliseconds before the screen continues on its own. Set to 0 to require
//! a press after every tree.
const AUTO_MS = 4000;

class SentView extends WatchUi.View {

    private var _layout as Layout or Null;
    private var _timer as Timer.Timer or Null;
    private var _reveal as Anim.Timeline;
    private var _outcome as Number;
    private var _treeNumber as Number;
    private var _shownAtMs as Number = 0;
    private var _handled as Boolean = false;

    function initialize(outcome as Number, treeNumber as Number) {
        View.initialize();
        _outcome = outcome;
        _treeNumber = treeNumber;
        _reveal = new Anim.Timeline(600);
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _layout = new Layout(dc);
    }

    function onShow() as Void {
        _handled = false;
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
        if (AUTO_MS > 0 and (System.getTimer() - _shownAtMs) >= AUTO_MS) {
            nextTree();
            return;
        }
        WatchUi.requestUpdate();
    }

    //! Back to the capture screen, ready for the following tree.
    function nextTree() as Void {
        if (_handled) { return; }
        _handled = true;
        var capture = new CaptureView();
        WatchUi.switchToView(capture, new CaptureDelegate(capture),
                             WatchUi.SLIDE_RIGHT);
    }

    //! End the session and show what was collected.
    function finish() as Void {
        if (_handled) { return; }
        _handled = true;
        WatchUi.switchToView(new SummaryView(), new SummaryDelegate(),
                             WatchUi.SLIDE_DOWN);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var L = _layout;
        if (L == null) { return; }

        var ok = (_outcome == SEND_SENT);
        var accent = ok ? Theme.GREEN_LIGHT : Theme.BUFFERING;

        dc.setColor(Theme.BG, Theme.BG);
        dc.clear();
        UiKit.smooth(dc, true);

        var p = _reveal.progress();
        var eased = Anim.easeOut(p);

        // A thin draining arc, deliberately unlike the segmented quality ring,
        // so it reads as a countdown rather than as signal strength.
        if (AUTO_MS > 0) {
            var elapsed = System.getTimer() - _shownAtMs;
            var left = 1.0 - (elapsed.toFloat() / AUTO_MS.toFloat());
            if (left < 0.0) { left = 0.0; }
            UiKit.ringProgress(dc, L.cx, L.cy, L.ringRadius,
                               (L.ringWidth / 2) + 1,
                               Theme.fade(accent, 0.55), left);
        }

        // Kept tight, so the rings never cross the label below.
        UiKit.ripple(dc, L.cx, (L.h * 0.38).toNumber(),
                     (L.r * 0.32).toNumber(), accent, p);

        var size = (L.r * 0.30) * Anim.easeBack(Anim.clamp(p * 1.5));
        UiKit.check(dc, L.cx, (L.h * 0.38).toNumber(), size.toFloat(),
                    accent, Anim.clamp(p * 1.8));

        UiKit.caption(dc, L.cx, (L.h * 0.575).toNumber(),
                      ok ? "SENT" : "HELD ON WATCH",
                      L.fontBody, Theme.blend(Theme.BG, Theme.TEXT, eased));

        UiKit.caption(dc, L.cx, (L.h * 0.655).toNumber(),
                      ok ? ("tree " + _treeNumber.format("%d"))
                         : "phone not in range",
                      L.fontLabel, Theme.blend(Theme.BG,
                          ok ? Theme.TEXT_FAINT : Theme.BUFFERING, eased));

        UiKit.hairline(dc, L.cx, (L.h * 0.715).toNumber(),
                       (L.w * 0.30).toNumber(), Theme.HAIRLINE);

        // The two things anyone wants next.
        UiKit.caption(dc, L.cx, (L.h * 0.785).toNumber(),
                      L.isTouch ? "Tap for next tree" : "START  next tree",
                      L.fontBody, Theme.blend(Theme.BG, Theme.GREEN_LIGHT, eased));

        UiKit.caption(dc, L.cx, (L.h * 0.875).toNumber(),
                      L.isTouch ? "Swipe back to finish" : "BACK  finish",
                      L.fontLabel, Theme.blend(Theme.BG, Theme.TEXT_FAINT, eased));
    }
}

class SentDelegate extends WatchUi.BehaviorDelegate {

    private var _view as SentView;

    function initialize(view as SentView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Boolean {
        _view.nextTree();
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        _view.nextTree();
        return true;
    }

    function onBack() as Boolean {
        _view.finish();
        return true;
    }
}
