import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! A quiet credits page. Static, so it costs one draw and no timer.
class AboutView extends WatchUi.View {

    private var _layout as Layout or Null;
    private var _mark as WatchUi.BitmapResource or Null;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        var L = new Layout(dc);
        _layout = L;
        _mark = WatchUi.loadResource(L.markResourceSmall()) as WatchUi.BitmapResource;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var L = _layout;
        if (L == null) { return; }

        dc.setColor(Theme.BG, Theme.BG);
        dc.clear();
        UiKit.smooth(dc, true);

        var mark = _mark;
        if (mark != null) {
            UiKit.bitmapCentred(dc, L.cx, (L.h * 0.30).toNumber(), mark);
        }

        UiKit.caption(dc, L.cx, (L.h * 0.52).toNumber(), "TreeMapper GPS",
                      L.fontBody, Theme.TEXT);
        UiKit.caption(dc, L.cx, (L.h * 0.62).toNumber(), "UI prototype 0.1",
                      L.fontLabel, Theme.TEXT_FAINT);

        UiKit.hairline(dc, L.cx, (L.h * 0.70).toNumber(),
                       (L.w * 0.30).toNumber(), Theme.HAIRLINE);

        UiKit.caption(dc, L.cx, (L.h * 0.78).toNumber(), "Plant-for-the-Planet",
                      L.fontLabel, Theme.GREEN_LIGHT);
    }
}

class AboutDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onSelect() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
