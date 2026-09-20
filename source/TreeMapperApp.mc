import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! TreeMapper GPS for Garmin.
//!
//! UI prototype. Nothing here touches the GNSS receiver or the phone: the
//! session data is simulated in SessionState so every screen and transition can
//! be reviewed in the simulator. See DESIGN.md for the intended architecture.
class TreeMapperApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        $.gSession = new SessionState();
    }

    function onStop(state as Dictionary?) as Void {
        $.gSession = null;
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new HomeView(), new HomeDelegate()];
    }
}
