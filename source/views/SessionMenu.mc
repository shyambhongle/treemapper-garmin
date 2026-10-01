import Toybox.Lang;
import Toybox.WatchUi;

//! The settings menu, built with the native Menu2 controls rather than a
//! custom view. Native controls inherit the device's own scrolling, fonts and
//! Enhanced Readability behaviour for free, and they are what a Garmin user
//! already knows how to operate.
//!
//! There is no "end session" item because there is no session to end. The
//! watch holds nothing between trees, so leaving the app is just BACK from the
//! acquiring screen.
module SessionMenu {
    function build() as WatchUi.Menu2 {
        var session = $.gSession;
        var menu = new WatchUi.Menu2({ :title => "Settings" });

        menu.addItem(new WatchUi.MenuItem(
            "Warn below",
            session != null ? session.minQualityLabel() : "Usable",
            :quality,
            {}));

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
                // This only colours the interface. The watch sends every
                // point with its quality attached; the phone decides what to
                // keep. Two settings, because the receiver reports steps and a
                // five value slider would be false precision.
                session.minQuality = (session.minQuality >= 4) ? 3 : 4;
                item.setSubLabel(session.minQualityLabel());
            }
        } else if (id == :about) {
            WatchUi.pushView(new AboutView(), new AboutDelegate(),
                             WatchUi.SLIDE_LEFT);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
