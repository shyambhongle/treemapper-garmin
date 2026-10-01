import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

//! End of session. Closes the loop so the user leaves the plot knowing what
//! they collected, rather than trusting that it worked.
class SummaryView extends WatchUi.View {

    private var _layout as Layout or Null;
    private var _timer as Timer.Timer or Null;
    private var _reveal as Anim.Timeline;

    function initialize() {
        View.initialize();
        _reveal = new Anim.Timeline(900);
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _layout = new Layout(dc);
    }

    function onShow() as Void {
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
        if (_reveal.isDone() and _timer != null) {
            // Nothing left to animate: stop burning frames.
            _timer.stop();
            _timer = null;
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

        var p = Anim.easeOut(_reveal.progress());

        // A closing ring, drawn once, that says the session is sealed.
        UiKit.ringTrack(dc, L.cx, L.cy, L.ringRadius, L.ringWidth, Theme.SURFACE);
        UiKit.ringProgress(dc, L.cx, L.cy, L.ringRadius, L.ringWidth, Theme.GREEN, p);

        UiKit.caption(dc, L.cx, L.topLabelY, "SESSION COMPLETE",
                      L.fontLabel, Theme.blend(Theme.BG, Theme.TEXT_FAINT, p));

        dc.setColor(Theme.blend(Theme.BG, Theme.TEXT, p), Graphics.COLOR_TRANSPARENT);
        dc.drawText(L.cx, (L.h * 0.42).toNumber(), L.fontHero,
                    session.totalPoints().format("%d"),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        UiKit.caption(dc, L.cx, (L.h * 0.555).toNumber(),
                      session.totalPoints() == 1 ? "TREE MAPPED" : "TREES MAPPED",
                      L.fontLabel, Theme.blend(Theme.BG, Theme.TEXT_FAINT, p));

        drawQualitySplit(dc, L, session, p);

        // If anything is still on the watch, say so here. Closing the app
        // believing everything reached the phone is how a morning gets lost.
        var waiting = session.outboxSize();
        if (waiting > 0) {
            UiKit.statusPill(dc, L.cx, (L.h * 0.745).toNumber(),
                             waiting.format("%d") + " not sent yet",
                             Theme.BUFFERING, L.fontLabel);
        } else {
            UiKit.caption(dc, L.cx, (L.h * 0.745).toNumber(),
                          session.elapsedString() + "  elapsed",
                          L.fontLabel, Theme.blend(Theme.BG, Theme.TEXT_DIM, p));
        }

        UiKit.caption(dc, L.cx, L.bottomHintY,
                      L.isTouch ? "Tap to close" : "START to close",
                      L.fontBody, Theme.fade(Theme.GREEN_LIGHT, p));
    }

    //! A slim stacked bar: how much of the session was a good fix versus a
    //! merely usable one. Honest, and takes one glance.
    private function drawQualitySplit(dc as Graphics.Dc, L as Layout,
                                      session as SessionState, p as Float) as Void {
        var good = session.histogram[4];
        var usable = session.histogram[3];
        var total = good + usable;
        if (total <= 0) { return; }

        var barW = (L.w * 0.42).toNumber();
        var barH = 5;
        var x = L.cx - (barW / 2);
        var y = (L.h * 0.655).toNumber();

        var goodW = ((barW * good).toFloat() / total.toFloat() * p).toNumber();

        dc.setColor(Theme.blend(Theme.BG, Theme.Q_USABLE, p), Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, barW, barH, barH / 2);

        if (goodW > 0) {
            dc.setColor(Theme.blend(Theme.BG, Theme.Q_GOOD, p), Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, y, goodW, barH, barH / 2);
        }

        var pct = (good * 100) / total;
        UiKit.caption(dc, L.cx, y + 16, pct.format("%d") + "% good fix",
                      L.fontLabel, Theme.blend(Theme.BG, Theme.TEXT_FAINT, p));
    }
}

class SummaryDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        return close();
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        return close();
    }

    function onBack() as Boolean {
        return close();
    }

    private function close() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
