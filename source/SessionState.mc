import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

//! Mock session state.
//!
//! THIS FILE IS THE FAKE. Nothing here touches Position or Communications.
//! It exists so the whole interface can be driven and reviewed in the
//! simulator. When the real work lands, replace the body of tick() and
//! send() with the GNSS reads and phone messaging from DESIGN.md and leave
//! the views untouched.

var gSession as SessionState or Null = null;

// Phone link states.
enum {
    LINK_CONNECTED = 0,
    LINK_BUFFERING = 1,
    LINK_OFFLINE   = 2
}

// What happened when the user pressed send.
enum {
    SEND_SENT     = 0,   // the phone acknowledged it
    SEND_QUEUED   = 1,   // held on the watch, phone not listening
    SEND_REJECTED = 2    // fix below the quality floor, nothing recorded
}

class SessionState {
    public var quality as Number = 0;          // mirrors Position.Quality, 0..4
    public var sent as Number = 0;             // acknowledged by the phone
    public var queued as Number = 0;           // waiting on the watch
    public var link as Number = LINK_CONNECTED;

    public var minQuality as Number = 3;       // QUALITY_USABLE

    private var _startedMs as Number = 0;
    private var _lastWanderMs as Number = 0;
    private var _lastLinkMs as Number = 0;

    // Mock histogram of recorded qualities, index 0..4
    public var histogram as Array<Number> = [0, 0, 0, 0, 0] as Array<Number>;

    function initialize() {
        _startedMs = System.getTimer();
    }

    function startSession() as Void {
        quality = 0;
        sent = 0;
        queued = 0;
        link = LINK_CONNECTED;
        histogram = [0, 0, 0, 0, 0] as Array<Number>;
        _startedMs = System.getTimer();
        _lastWanderMs = _startedMs;
        _lastLinkMs = _startedMs;
    }

    function elapsedMs() as Number {
        return System.getTimer() - _startedMs;
    }

    function elapsedSeconds() as Number {
        return elapsedMs() / 1000;
    }

    //! mm:ss for the summary screen.
    function elapsedString() as String {
        var total = elapsedSeconds();
        var mins = total / 60;
        var secs = total % 60;
        return mins.format("%d") + ":" + secs.format("%02d");
    }

    //! Every point recorded this session, sent or still waiting.
    function totalPoints() as Number {
        return sent + queued;
    }

    //! Advance the simulation. Called from each view's render timer.
    function tick() as Void {
        var now = System.getTimer();
        var age = now - _startedMs;

        // Ramp up over the first six seconds, the way a cold receiver behaves.
        if (age < 2200) {
            quality = 0;
        } else if (age < 4000) {
            quality = 2;
        } else if (age < 6200) {
            quality = 3;
        } else if ((now - _lastWanderMs) > 6000) {
            // Then wander a little so the interface shows its colour states.
            _lastWanderMs = now;
            var roll = Math.rand() % 10;
            quality = (roll < 6) ? 4 : ((roll < 9) ? 3 : 2);
        } else if (quality < 2) {
            quality = 4;
        }

        // Occasionally drop and restore the phone link, so the queued path is
        // reachable in a demo without unplugging anything.
        if ((now - _lastLinkMs) > 20000) {
            _lastLinkMs = now;
            if (link == LINK_CONNECTED) {
                link = LINK_BUFFERING;
            } else {
                link = LINK_CONNECTED;
                sent += queued;      // the backlog flushes on reconnect
                queued = 0;
            }
        }
    }

    //! Try to record and send a point.
    //! Returns SEND_SENT, SEND_QUEUED or SEND_REJECTED.
    function send() as Number {
        if (quality < minQuality) {
            return SEND_REJECTED;
        }

        if (quality >= 0 and quality <= 4) {
            histogram[quality] = histogram[quality] + 1;
        }

        if (link == LINK_CONNECTED) {
            sent++;
            return SEND_SENT;
        }

        queued++;
        return SEND_QUEUED;
    }

    function isLinked() as Boolean {
        return link == LINK_CONNECTED;
    }

    //! Only ever shown when something is wrong. See README, "silence is good
    //! news": a permanent "connected" badge tells the user nothing on the
    //! ninety nine screens where it is true.
    function linkWarning() as String {
        if (link == LINK_BUFFERING) {
            return "Phone lost, holding " + queued.format("%d");
        }
        if (link == LINK_OFFLINE) {
            return "Watch only";
        }
        return "";
    }

    function linkColour() as Number {
        if (link == LINK_BUFFERING) { return Theme.BUFFERING; }
        if (link == LINK_OFFLINE) { return Theme.OFFLINE; }
        return Theme.LINKED;
    }

    function minQualityLabel() as String {
        return minQuality >= 4 ? "Good only" : "Usable";
    }
}
