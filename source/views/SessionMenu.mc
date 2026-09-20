import Toybox.Lang;
import Toybox.WatchUi;

//! The in session menu, built with the native Menu2 controls rather than a
//! custom view. Native controls inherit the device's own scrolling, fonts and
//! Enhanced Readability behaviour for free, and they are what a Garmin user
//! already knows how to operate.
module SessionMenu {
    function build() as WatchUi.Menu2 {
        var session = $.gSession;
        var menu = new WatchUi.Menu2({ :title => "Session" });

        menu.addItem(new WatchUi.MenuItem(
            "Quality floor",
            session != null ? session.minQualityLabel() : "Usable",
            :quality,
            {}));

        menu.addItem(new WatchUi.MenuItem("End session", null, :end, {}));
        menu.addItem(new WatchUi.MenuItem("About", null, :about, {}));

        return menu;
    }
}

class SessionMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var session = $.gSession;
        var id = item.getId();

        if (id == :quality) {
            if (session != null) {
                // Two sensible floors only. A slider of five values would be
                // false precision: the receiver reports steps, not metres.
                session.minQuality = (session.minQuality >= 4) ? 3 : 4;
                item.setSubLabel(session.minQualityLabel());
            }
        } else if (id == :end) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            WatchUi.switchToView(new SummaryView(), new SummaryDelegate(),
                                 WatchUi.SLIDE_DOWN);
        } else if (id == :about) {
            WatchUi.pushView(new AboutView(), new AboutDelegate(),
                             WatchUi.SLIDE_LEFT);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
