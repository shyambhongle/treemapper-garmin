import Toybox.Lang;
import Toybox.System;

//! Session orchestration. This is the brain: it owns the receiver, the phone
//! link and the outbox, and it is the only thing the views talk to.
//!
//! The rule that runs through all of it: a point is not "sent" until the phone
//! says so. Everything captured goes into a durable outbox first, and the
//! counters are derived from what has actually been acknowledged. A dropped
//! link then costs a delay, never a tree.

var gSession as SessionState or Null = null;

// Phone link states.
enum {
    LINK_CONNECTED = 0,   // phone in range, nothing waiting
    LINK_BUFFERING = 1,   // points waiting, link unhealthy or app closed
    LINK_OFFLINE   = 2    // no phone in range at all
}

// Outcome of a send.
enum {
    SEND_SENT     = 0,   // the phone acknowledged it
    SEND_QUEUED   = 1,   // held on the watch, goes when the link returns
    SEND_REJECTED = 2,   // nothing recorded: no position, or outbox full
    SEND_PENDING  = 3    // in flight, ask again next frame
}

// Why a send was refused.
enum {
    REJECT_NONE = 0,
    REJECT_NO_POSITION = 1,
    REJECT_QUEUE_FULL = 2
}

class SessionState {

    // ---- state the views read --------------------------------------------

    public var quality as Number = 0;          // Position.Quality, 0..4
    public var sent as Number = 0;             // acknowledged by the phone
    public var link as Number = LINK_OFFLINE;

    //! The quality at or above which a fix is called good. This is a WARNING
    //! threshold, not a gate. Per the agreed design the watch sends whatever
    //! the receiver reports, with the quality attached, and the phone decides
    //! what to keep. This value only colours the interface.
    public var minQuality as Number = 3;

    public var histogram as Array<Number> = [0, 0, 0, 0, 0] as Array<Number>;

    // ---- collaborators ----------------------------------------------------

    private var _gps as GpsService;
    private var _phone as PhoneLink;
    private var _outbox as PointQueue;

    // ---- send bookkeeping -------------------------------------------------

    private var _seq as Number = 0;
    private var _startedMs as Number = 0;
    private var _pendingResult as Number = SEND_PENDING;
    private var _inFlight as Boolean = false;
    private var _sendStartedMs as Number = 0;
    private var _rejectReason as Number = REJECT_NONE;
    private var _lastSource as String = "watch";
    private var _remoteActive as Boolean = false;

    // Retry pacing. A failed transmit must never be retried immediately.
    private var _nextPumpMs as Number = 0;

    //! Next rung of the payload ladder in Probe.mc. Inert unless
    //! PROBE_MODE is on.
    private var _probeIndex as Number = 0;
    private var _failures as Number = 0;

    // Work asked for by the phone, deferred out of the receive callback.
    private var _pendingAnnounce as Boolean = false;
    private var _pendingFixId as Number or Null = null;
    private var _hasPendingFix as Boolean = false;

    const SEND_TIMEOUT_MS = 2500;

    function initialize() {
        _gps = new GpsService();
        _phone = new PhoneLink();
        _outbox = new PointQueue();
        _startedMs = System.getTimer();
    }

    // ---- lifecycle --------------------------------------------------------

    //! Called once from AppBase.onStart. The receiver comes up immediately, so
    //! that by the time the user reaches the first tree, or the phone sends its
    //! first request, the fix has already converged.
    function startSession() as Void {
        sent = 0;
        _seq = 0;
        histogram = [0, 0, 0, 0, 0] as Array<Number>;
        _startedMs = System.getTimer();
        _rejectReason = REJECT_NONE;
        _failures = 0;
        _nextPumpMs = 0;
        _probeIndex = 0;

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

    function outboxSize() as Number {
        return _outbox.size();
    }

    // ---- the pump ---------------------------------------------------------

    //! Called from every view's render timer. Cheap by design: it reads the
    //! receiver, refreshes the link view and pushes at most one parcel.
    function tick() as Void {
        quality = _gps.quality();
        refreshLink();
        servePhoneRequests();
        pump();

        // A transmit that never reports back must not wedge the interface.
        if (_inFlight and (System.getTimer() - _sendStartedMs) > SEND_TIMEOUT_MS) {
            _inFlight = false;
            _pendingResult = SEND_QUEUED;
        }
    }

    //! Move one point off the outbox if the link is free and it is time to try.
    //!
    //! The backoff is not politeness, it is the difference between a failed
    //! send and a dead simulator. Without it, a transmit that reports failure
    //! is retried on the very next tick, 40 ms later, and hammering a broken
    //! socket takes the whole process down with "Socket Error in packet
    //! header". One failure is a problem; sixty a second is a crash.
    private function pump() as Void {
        if (_phone.isBusy() or _outbox.isEmpty()) { return; }
        if (System.getTimer() < _nextPumpMs) { return; }

        var point = _outbox.peek();
        if (point == null) { return; }

        _phone.send(point);
    }

    //! How long to wait after a failed send: 2s, 4s, 8s, 16s, then 30s.
    private function backoffMs() as Number {
        var wait = 2000;
        for (var i = 1; i < _failures and wait < 30000; i++) {
            wait = wait * 2;
        }
        return wait > 30000 ? 30000 : wait;
    }

    private function refreshLink() as Void {
        if (!_phone.hasHeardFromPhone()) {
            link = LINK_BUFFERING;
            return;
        }
        if (!_phone.isPhoneConnected()) {
            link = LINK_OFFLINE;
        } else if (!_outbox.isEmpty() or !_phone.lastSendOk()) {
            link = LINK_BUFFERING;
        } else {
            link = LINK_CONNECTED;
        }
    }

    // ---- capture ----------------------------------------------------------

    //! Record a point and start it on its way.
    //!
    //! Returns SEND_PENDING when the point is on the wire, in which case the
    //! caller polls pendingResult(). Returns SEND_REJECTED immediately when
    //! there is nothing to send, which is the only case the watch refuses: not
    //! a quality judgement, just the absence of a position.
    function requestSend(source as String, requestId as Number or Null) as Number {
        System.println("[tm] requestSend from " + source);
        var snapshot = _gps.snapshot();
        if (snapshot == null) {
            System.println("[tm] no position, refused");
            _rejectReason = REJECT_NO_POSITION;
            return SEND_REJECTED;
        }

        _seq++;

        // Built key by key so nothing null is ever present. The old literal
        // always carried at least one: "r" is null on a watch-initiated send,
        // and alt/spd are null whenever the receiver has none. That dictionary
        // is written to Application.Storage before it is transmitted, so a null
        // had two chances to break serialisation, not one.
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

        System.println("[tm] point built, seq " + _seq.format("%d"));

        if (!_outbox.push(point)) {
            System.println("[tm] outbox push FAILED");
            _seq--;
            _rejectReason = REJECT_QUEUE_FULL;
            return SEND_REJECTED;
        }

        var q = snapshot["q"];
        if (q instanceof Number and q >= 0 and q <= 4) {
            histogram[q] = histogram[q] + 1;
        }

        _lastSource = source;
        _rejectReason = REJECT_NONE;

        // If anything was already waiting, this point is behind it in the
        // queue. Say so now rather than claim it was delivered when the
        // acknowledgement for an older point arrives.
        if (_outbox.size() > 1) {
            _inFlight = false;
            _pendingResult = SEND_QUEUED;
            pump();
            return SEND_QUEUED;
        }

        _pendingResult = SEND_PENDING;
        _inFlight = true;
        _sendStartedMs = System.getTimer();

        System.println("[tm] stored, pumping");
        pump();
        System.println("[tm] pump returned");
        return SEND_PENDING;
    }

    //! SEND_PENDING while in flight, then SEND_SENT or SEND_QUEUED.
    function pendingResult() as Number {
        return _pendingResult;
    }

    function rejectReason() as Number {
        return _rejectReason;
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

    //! Transmit finished. Only now is a point genuinely delivered.
    function onTransmitResult(ok as Boolean) as Void {
        if (ok) {
            _outbox.pop();
            sent++;
            _failures = 0;
            _nextPumpMs = 0;
            if (_inFlight) {
                _inFlight = false;
                _pendingResult = SEND_SENT;
            }
        } else {
            // The point stays in the outbox, but do not go straight back at it.
            _failures++;
            _nextPumpMs = System.getTimer() + backoffMs();
            System.println("[tm] send failed, attempt " + _failures.format("%d")
                           + ", waiting " + backoffMs().format("%d") + "ms");
            if (_inFlight) {
                _inFlight = false;
                _pendingResult = SEND_QUEUED;
            }
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
        // The payload ladder takes priority over the real protocol: while it
        // is running nothing else may put a parcel on the wire, or the rung
        // that crashed stops being attributable.
        if ($.PROBE_MODE and _probeIndex < $.PROBE_COUNT) {
            if (_phone.isBusy() or !_phone.hasHeardFromPhone()) { return; }
            System.println("[tm] PROBE " + _probeIndex.format("%d")
                           + " -> " + $.probeName(_probeIndex));
            if (_phone.sendRaw($.probePayload(_probeIndex))) {
                _probeIndex++;
            }
            return;
        }

        if (_hasPendingFix) {
            _hasPendingFix = false;
            var reqId = _pendingFixId;
            _pendingFixId = null;

            var outcome = requestSend("phone", reqId);
            if (outcome == SEND_REJECTED) {
                _remoteActive = false;
                sendError(reqId, _rejectReason == REJECT_QUEUE_FULL
                                 ? "queue_full" : "no_position");
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
            "buf" => _outbox.size()
        });
    }

    private function sendError(requestId as Number or Null, code as String) as Void {
        _phone.send({ "t" => "err", "r" => requestId, "code" => code });
    }

    // ---- what the views read ---------------------------------------------

    function totalPoints() as Number {
        return sent + _outbox.size();
    }

    function isLinked() as Boolean {
        return link == LINK_CONNECTED;
    }

    //! Only ever shown when something is wrong. A badge that is true on every
    //! screen stops being read; the moment it stops being true is what matters.
    function linkWarning() as String {
        if (!_phone.hasHeardFromPhone()) {
            var held = _outbox.size();
            return held > 0
                ? "Waiting for phone app, holding " + held.format("%d")
                : "Waiting for phone app";
        }
        if (link == LINK_OFFLINE) {
            return "No phone, holding " + _outbox.size().format("%d");
        }
        if (link == LINK_BUFFERING) {
            if (_failures >= 3) {
                return "Cannot reach phone app";
            }
            if (!_phone.appLikelyListening()) {
                return "Open TreeMapper on phone";
            }
            return "Sending, " + _outbox.size().format("%d") + " left";
        }
        return "";
    }

    function linkColour() as Number {
        if (link == LINK_OFFLINE) { return Theme.OFFLINE; }
        if (link == LINK_BUFFERING) { return Theme.BUFFERING; }
        return Theme.LINKED;
    }

    function minQualityLabel() as String {
        return minQuality >= 4 ? "Good only" : "Usable";
    }

    function elapsedSeconds() as Number {
        return (System.getTimer() - _startedMs) / 1000;
    }

    function elapsedString() as String {
        var total = elapsedSeconds();
        var mins = total / 60;
        var secs = total % 60;
        return mins.format("%d") + ":" + secs.format("%02d");
    }
}
