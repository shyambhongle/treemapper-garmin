import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! Landing screen. A breathing tree mark, the wordmark, and one instruction.
//! The whole point of this screen is that there is exactly one thing to do.
class HomeView extends WatchUi.View {

    private var _layout as Layout or Null;
    private var _timer as Timer.Timer or Null;
    private var _entered as Anim.Timeline;
    private var _mark as WatchUi.BitmapResource or Null;

    function initialize() {
        View.initialize();
        _entered = new Anim.Timeline(600);
    }

    function onLayout(dc as Graphics.Dc) as Void {
        var L = new Layout(dc);
        _layout = L;
        // Loaded once. Loading a resource inside onUpdate is expensive.
        _mark = WatchUi.loadResource(L.markResource()) as WatchUi.BitmapResource;
    }

    function onShow() as Void {
        _entered.start();
        _timer = new Timer.Timer();
        _timer.start(method(:onFrame), 60, true);
    }

    function onHide() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    function onFrame() as Void {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var L = _layout;
        if (L == null) { return; }

        dc.setColor(Theme.BG, Theme.BG);
        dc.clear();
        UiKit.smooth(dc, true);

        var intro = Anim.easeOut(_entered.progress());
        var now = System.getTimer();

        // A halo that breathes slowly behind the mark, so the screen is not a
        // flat black field. The mark is a bitmap and cannot be scaled at draw
        // time on older devices, so the motion lives in the ring instead.
        var haloR = (L.r * 0.48 * (0.96 + 0.04 * Anim.breathe(now, 4200))).toNumber();
        dc.setPenWidth(2);
        dc.setColor(Theme.blend(Theme.BG, Theme.GREEN, 0.60 * intro),
                    Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(L.cx, (L.h * 0.355).toNumber(), haloR);

        var mark = _mark;
        if (mark != null) {
            UiKit.bitmapCentred(dc, L.cx, (L.h * 0.355).toNumber(), mark);
        }

        // Wordmark
        UiKit.caption(dc, L.cx, (L.h * 0.63).toNumber(), "TREEMAPPER",
                      L.fontTitle, Theme.blend(Theme.BG, Theme.TEXT, intro));
        UiKit.caption(dc, L.cx, (L.h * 0.72).toNumber(), "GPS companion",
                      L.fontLabel, Theme.blend(Theme.BG, Theme.TEXT_FAINT, intro));

        // One instruction, and it pulses just enough to be noticed.
        var hintAlpha = 0.55 + (0.45 * Anim.breathe(now, 2400));
        var hint = L.isTouch ? "Tap to begin" : "START to begin";
        UiKit.caption(dc, L.cx, L.bottomHintY, hint, L.fontBody,
                      Theme.fade(Theme.GREEN_LIGHT, hintAlpha * intro));
    }
}

//! Home input. One action in, one action out.
class HomeDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        beginSession();
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        beginSession();
        return true;
    }

    private function beginSession() as Void {
        var session = $.gSession;
        if (session != null) {
            session.startSession();
        }
        WatchUi.pushView(new AcquiringView(), new AcquiringDelegate(), WatchUi.SLIDE_UP);
    }
}
