import Toybox.Lang;
import Toybox.System;

//! Orchestration. This is the brain: it owns the receiver and the phone link,
//! and it is the only thing the views talk to.
//!
//! One fix at a time. The watch holds nothing: there is no outbox, no running
//! count, no session record. A fix lives in memory only from the moment the
//! user asks to send it until the phone acknowledges it, and the watch then
//! forgets it entirely. To record another tree the user starts the process
//! again.
//!
//! What that trades away: a point not delivered is a point not kept. If the
//! phone is out of range the send fails, the fix stays in hand, and it is the
//! user who decides to retry or to start over. Nothing is written to storage,
//! so closing the app loses whatever was still in hand. That is deliberate.
//! The phone owns the record; the watch is a sensor.

var gSession as SessionState or Null = null;

// Phone link states.
enum {
    LINK_CONNECTED = 0,   // phone in range and the companion app has spoken
    LINK_WAITING   = 1,   // phone in range, companion app has never spoken
    LINK_OFFLINE   = 2    // no phone in range at all
}

// Where a send has got to.
enum {
    SEND_IDLE     = 0,   // nothing in hand
    SEND_PENDING  = 1,   // on the wire, ask again next frame
    SEND_SENT     = 2,   // the phone acknowledged it
    SEND_FAILED   = 3,   // did not reach the phone, still in hand, retryable
    SEND_REJECTED = 4    // nothing to send: the receiver has no position
}

class SessionState {

    // ---- state the views read --------------------------------------------

    public var quality as Number = 0;          // Position.Quality, 0..4
    public var link as Number = LINK_OFFLINE;

    //! The quality at or above which a fix is called good. This is a WARNING
    //! threshold, not a gate. Per the agreed design the watch sends whatever
    //! the receiver reports, with the quality attached, and the phone decides
    //! what to keep. This value only colours the interface.
    public var minQuality as Number = 3;

    // ---- collaborators ----------------------------------------------------

    private var _gps as GpsService;
    private var _phone as PhoneLink;

    // ---- the one fix in hand ----------------------------------------------

    //! The fix the user asked to send, held until the phone acknowledges it.
    //! Memory only. Null whenever nothing is in flight.
    private var _pending as Dictionary or Null = null;

    private var _seq as Number = 0;
    private var _result as Number = SEND_IDLE;
    private var _inFlight as Boolean = false;
    private var _sendStartedMs as Number = 0;
    private var _lastSource as String = "watch";
    private var _remoteActive as Boolean = false;

    // Work asked for by the phone, deferred out of the receive callback.
    private var _pendingAnnounce as Boolean = false;
    private var _pendingFixId as Number or Null = null;
    private var _hasPendingFix as Boolean = false;

    //! A transmit that never calls back must not wedge the interface.
    const SEND_TIMEOUT_MS = 2500;

    function initialize() {
        _gps = new GpsService();
        _phone = new PhoneLink();
    }

    // ---- lifecycle --------------------------------------------------------

    //! Called once from AppBase.onStart. The receiver comes up immediately and
    //! stays warm for as long as the app is open, so that by the time the user
    //! reaches a tree, or the phone sends its first request, the fix has
    //! already converged. Restarting the capture flow does not restart the
    //! receiver: that is the whole point of keeping it on.
    function startSession() as Void {
        _seq = 0;
        _pending = null;
        _result = SEND_IDLE;
        _inFlight = false;

        _gps.start();
        _phone.start(method(:onPhoneCommand), method(:onTransmitResult));

        // Not announceReady() directly: this runs inside AppBase.onStart,
        // before any view exists and before the link has settled. The first
        // tick() will send it.
        _pendingAnnounce = true;
    }

    //! Called from AppBase.onStop. Releasing the receiver here is not optional:
    //! Connect IQ never switches it off on its own.
    function endSession() as Void {
        _gps.stop();
        _phone.stop();
    }

    function gps() as GpsService {
        return _gps;
    }

    // ---- the pump ---------------------------------------------------------

    //! Called from every view's render timer. Cheap by design: it reads the
    //! receiver, refreshes the link view and serves at most one phone request.
    function tick() as Void {
        quality = _gps.quality();
        refreshLink();
        servePhoneRequests();

        if (_inFlight and (System.getTimer() - _sendStartedMs) > SEND_TIMEOUT_MS) {
            _inFlight = false;
            _result = SEND_FAILED;
        }
    }

    private function refreshLink() as Void {
        if (!_phone.isPhoneConnected()) {
            link = LINK_OFFLINE;
        } else if (!_phone.hasHeardFromPhone()) {
            link = LINK_WAITING;
        } else {
            link = LINK_CONNECTED;
        }
    }

    // ---- capture ----------------------------------------------------------

    //! Take a fix and put it on the wire.
    //!
    //! Returns SEND_PENDING when it is in flight, in which case the caller
    //! polls sendResult(). Returns SEND_REJECTED when the receiver has no
    //! position at all, which is the only thing the watch refuses: not a
    //! quality judgement. Returns SEND_FAILED when nothing left the watch,
    //! in which case the fix is still in hand and retrySend() will try again.
    function requestSend(source as String, requestId as Number or Null) as Number {
        var snapshot = _gps.snapshot();
        if (snapshot == null) {
            _pending = null;
            _result = SEND_REJECTED;
            return SEND_REJECTED;
        }

        _seq++;

        // Built key by key so nothing null is ever present. A Dictionary
        // carrying a null has to survive serialisation into a Java Map on the
        // other side of the link, and that path is a known crash suspect.
        // "r" is null on a watch-initiated send, and alt/spd are null whenever
        // the receiver has none.
        var point = {
            "t"   => "pt",
            "n"   => _seq,
            "src" => source,
            "lat" => snapshot["lat"],
            "lon" => snapshot["lon"],
            "q"   => snapshot["q"],
            "ts"  => snapshot["ts"]
        };
        if (requestId != null)       { point["r"]   = requestId; }
        if (snapshot["alt"] != null) { point["alt"] = snapshot["alt"]; }
        if (snapshot["spd"] != null) { point["spd"] = snapshot["spd"]; }

        _pending = point;
        _lastSource = source;

        return attemptSend();
    }

    //! Try the fix already in hand again. The user's retry after a failure.
    function retrySend() as Number {
        return attemptSend();
    }

    //! Put the fix in hand on the wire.
    //!
    //! A failure here is final until the user asks again. There is no
    //! automatic retry on a timer: with nothing stored there is nothing to
    //! flush, and a background retry could deliver a fix the user had already
    //! given up on and moved past, which is how duplicates happen.
    private function attemptSend() as Number {
        var point = _pending;
        if (point == null) {
            _result = SEND_IDLE;
            return SEND_IDLE;
        }

        if (_phone.isBusy()) {
            _result = SEND_PENDING;
            return SEND_PENDING;
        }

        if (!_phone.send(point)) {
            // Nothing went out: no phone in range, or the companion app has
            // never spoken to us so the watch has nobody to speak to.
            _inFlight = false;
            _result = SEND_FAILED;
            return SEND_FAILED;
        }

        _inFlight = true;
        _sendStartedMs = System.getTimer();
        _result = SEND_PENDING;
        return SEND_PENDING;
    }

    //! Throw away the fix in hand. Called when the user restarts.
    function discard() as Void {
        _pending = null;
        _inFlight = false;
        _remoteActive = false;
        _result = SEND_IDLE;
    }

    //! SEND_PENDING while in flight, then SEND_SENT or SEND_FAILED.
    function sendResult() as Number {
        return _result;
    }

    function lastSource() as String {
        return _lastSource;
    }

    //! True while the phone, rather than the watch button, is driving.
    function isRemoteActive() as Boolean {
        return _remoteActive;
    }

    function clearRemote() as Void {
        _remoteActive = false;
    }

    //! Transmit finished. Only now is a fix genuinely delivered, and the watch
    //! lets go of it the moment it is.
    function onTransmitResult(ok as Boolean) as Void {
        _inFlight = false;
        if (ok) {
            _pending = null;
            _result = SEND_SENT;
        } else {
            _result = SEND_FAILED;
        }
        refreshLink();
    }

    // ---- phone commands ---------------------------------------------------

    //! Dispatch for inbound parcels. See PhoneLink for the protocol.
    function onPhoneCommand(data as Dictionary) as Void {
        var c = data["c"];
        if (!(c instanceof String)) { return; }

        if (c.equals("fix")) {
            var r = data["r"];
            _pendingFixId = (r instanceof Number) ? r : null;
            _hasPendingFix = true;
            _remoteActive = true;

        } else if (c.equals("hello") or c.equals("ping")) {
            _pendingAnnounce = true;
        }
    }

    //! Do the work the phone asked for, on our own schedule.
    //!
    //! Deliberately never called from onPhoneCommand. Transmitting from inside
    //! the receive callback re-enters the comms stack, and that is the most
    //! likely cause of the simulator crash on the tethered link. At most one
    //! parcel leaves per tick.
    private function servePhoneRequests() as Void {
        if (_hasPendingFix) {
            _hasPendingFix = false;
            var reqId = _pendingFixId;
            _pendingFixId = null;

            if (requestSend("phone", reqId) == SEND_REJECTED) {
                _remoteActive = false;
                sendError(reqId, "no_position");
            }
            return;
        }

        if (_pendingAnnounce and !_phone.isBusy()) {
            // Only clear the flag once the send was actually accepted, so the
            // opening state still reaches a phone that connects later.
            if (announceReady()) {
                _pendingAnnounce = false;
            }
        }
    }

    //! Tell the phone what state the watch is in. Sent on start and in answer
    //! to hello or ping, so the phone modal can show something truthful while
    //! the receiver is still converging.
    private function announceReady() as Boolean {
        return _phone.send({
            "t"   => "ready",
            "v"   => $.PROTOCOL_VERSION,
            "q"   => quality,
            "gps" => _gps.isRunning() ? 1 : 0,
            "mb"  => _gps.isMultiBand() ? 1 : 0,
            // Kept at 0 for wire compatibility with protocol version 1. This
            // watch holds nothing, so there is never a backlog to report.
            "buf" => 0
        });
    }

    private function sendError(requestId as Number or Null, code as String) as Void {
        _phone.send({ "t" => "err", "r" => requestId, "code" => code });
    }

    // ---- what the views read ---------------------------------------------

    function isLinked() as Boolean {
        return link == LINK_CONNECTED;
    }

    //! Only ever shown when something is wrong. A badge that is true on every
    //! screen stops being read; the moment it stops being true is what matters.
    function linkWarning() as String {
        if (link == LINK_OFFLINE) {
            return "No phone in range";
        }
        if (link == LINK_WAITING) {
            return "Open TreeMapper on phone";
        }
        return "";
    }

    function linkColour() as Number {
        if (link == LINK_OFFLINE) { return Theme.OFFLINE; }
        if (link == LINK_WAITING) { return Theme.BUFFERING; }
        return Theme.LINKED;
    }

    function minQualityLabel() as String {
        return minQuality >= 4 ? "Good only" : "Usable";
    }
}
