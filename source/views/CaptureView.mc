import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! The main working screen.
//!
//! The person is standing at a tree, often in rain, often wearing gloves, often
//! not looking at the watch. So the screen carries the fewest facts that let
//! them act:
//!
//!   1. Is the receiver giving a good fix  -> the edge ring and its colour
//!   2. How much have I collected          -> one large number
//!   3. Is anything wrong                  -> a strip, and only then
//!
//! Point 3 is an exception report on purpose. A permanent "phone connected"
//! badge is true on almost every screen, so it stops being read. What matters
//! is the moment it stops being true.
//!
//! Two things can start a send: the START button here, or a "fix" command from
//! the phone. Both land in the same place, so the watch confirms either way and
//! the person can work from the phone or from the wrist.

// Confirmation overlay states.
enum {
    OVERLAY_NONE = 0,
    OVERLAY_SENDING = 1,
    OVERLAY_REJECTED = 2
}

class CaptureView extends WatchUi.View {

    //! Animation tick. 50 ms is the smallest interval Connect IQ
    //! accepts; anything lower is silently clamped and logs
    //! "Timer interval is too small" on every view change.
    private const FRAME_MS = 50;

    private var _layout as Layout or Null;
    private var _timer as Timer.Timer or Null;
    private var _rateMs as Number = 1000;

    private var _overlay as Number = OVERLAY_NONE;
    private var _rejectAnim as Anim.Timeline;
    private var _entered as Anim.Timeline;

    function initialize() {
        View.initialize();
        _rejectAnim = new Anim.Timeline(900);
        _entered = new Anim.Timeline(400);
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _layout = new Layout(dc);
    }

    function onShow() as Void {
        _overlay = OVERLAY_NONE;
        _entered.start();
        setRate(FRAME_MS);
    }

    function onHide() as Void {
        stopTimer();
    }

    private function stopTimer() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    //! Drop to a slow tick when nothing is moving. The receiver is already the
    //! expensive thing running; the screen should not add to it.
    private function setRate(ms as Number) as Void {
        if (_timer != null and _rateMs == ms) { return; }
        stopTimer();
        _rateMs = ms;
        _timer = new Timer.Timer();
        _timer.start(method(:onFrame), ms, true);
    }

    function onFrame() as Void {
        var session = $.gSession;
        if (session == null) { return; }

        session.tick();

        // The phone asked for a point while we were idle. Show the same
        // confirmation the button would have produced, so the person sees what
        // their phone just did.
        if (_overlay == OVERLAY_NONE and session.isRemoteActive()) {
            _overlay = OVERLAY_SENDING;
        }

        if (_overlay == OVERLAY_SENDING) {
            var result = session.pendingResult();
            if (result != SEND_PENDING) {
                session.clearRemote();
                _overlay = OVERLAY_NONE;
                var view = new SentView(result, session.totalPoints());
                WatchUi.switchToView(view, new SentDelegate(view),
                                     WatchUi.SLIDE_LEFT);
                return;
            }
        }

        if (_overlay == OVERLAY_REJECTED and _rejectAnim.isDone()) {
            _overlay = OVERLAY_NONE;
        }

        var animating = (_overlay != OVERLAY_NONE) or _entered.isRunning();
        setRate(animating ? FRAME_MS : 1000);

        WatchUi.requestUpdate();
    }

    //! Called by the delegate when the user presses to send.
    function requestSend() as Void {
        var session = $.gSession;
        if (session == null or _overlay != OVERLAY_NONE) { return; }

        var outcome = session.requestSend("watch", null);

        if (outcome == SEND_REJECTED) {
            // The only refusal is the absence of a position, or a full outbox.
            // Quality is never a refusal: the point goes with its quality
            // attached and the phone decides.
            _overlay = OVERLAY_REJECTED;
            _rejectAnim = new Anim.Timeline(900);
            _rejectAnim.start();
        } else {
            _overlay = OVERLAY_SENDING;
        }

        setRate(FRAME_MS);
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var L = _layout;
        var session = $.gSession;
        if (L == null or session == null) { return; }

        var bg = Theme.BG;
        if (_overlay == OVERLAY_REJECTED) {
            bg = Theme.blend(Theme.BG, 0x4A2A12, (1.0 - _rejectAnim.progress()) * 0.22);
        }
        dc.setColor(bg, bg);
        dc.clear();
        UiKit.smooth(dc, true);

        drawQualityRing(dc, L, session);

        if (_overlay == OVERLAY_SENDING) {
            drawSending(dc, L, session);
        } else if (_overlay == OVERLAY_REJECTED) {
            drawRejected(dc, L, session);
        } else {
            drawMain(dc, L, session);
        }
    }

    // ---- pieces -----------------------------------------------------------

    private function drawQualityRing(dc as Graphics.Dc, L as Layout,
                                     session as SessionState) as Void {
        var colour = Theme.quality(session.quality);

        // While the fix is below the warning threshold the ring breathes. This
        // is the one moment we actively want to pull the eye.
        if (session.quality < session.minQuality) {
            var b = 0.45 + (0.55 * Anim.breathe(System.getTimer(), 1400));
            colour = Theme.fade(Theme.quality(session.quality), b.toFloat());
        }

        UiKit.ringSegments(dc, L.cx, L.cy, L.ringRadius, L.ringWidth,
                           session.quality, colour, Theme.SURFACE);
    }

    private function drawMain(dc as Graphics.Dc, L as Layout,
                              session as SessionState) as Void {
        var intro = Anim.easeOut(_entered.progress());
        var qColour = Theme.quality(session.quality);

        UiKit.caption(dc, L.cx, L.topLabelY,
                      "GNSS " + Theme.qualityLabel(session.quality),
                      L.fontLabel, Theme.blend(Theme.BG, qColour, intro));

        dc.setColor(Theme.blend(Theme.BG, Theme.TEXT, intro), Graphics.COLOR_TRANSPARENT);
        dc.drawText(L.cx, (L.h * 0.45).toNumber(), L.fontHero,
                    session.totalPoints().format("%d"),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        UiKit.caption(dc, L.cx, (L.h * 0.585).toNumber(),
                      session.totalPoints() == 1 ? "TREE" : "TREES",
                      L.fontLabel, Theme.blend(Theme.BG, Theme.TEXT_FAINT, intro));

        // Warnings only. Nothing is drawn here when everything is working.
        if (!session.isLinked()) {
            UiKit.statusPill(dc, L.cx, L.statusY, session.linkWarning(),
                             session.linkColour(), L.fontLabel);
        }

        // The only thing that disables the action is having no position at all.
        var ready = session.gps().hasPosition();
        var hint = ready
            ? (L.isTouch ? "Tap to send" : "START to send")
            : "Waiting for first fix";

        UiKit.hairline(dc, L.cx, L.bottomHintY - (L.r * 0.12).toNumber(),
                       (L.w * 0.30).toNumber(), Theme.HAIRLINE);
        UiKit.caption(dc, L.cx, L.bottomHintY, hint, L.fontBody,
                      ready ? Theme.blend(Theme.BG, Theme.GREEN_LIGHT, intro)
                            : Theme.blend(Theme.BG, Theme.TEXT_FAINT, intro));
    }

    private function drawSending(dc as Graphics.Dc, L as Layout,
                                 session as SessionState) as Void {
        var phase = ((System.getTimer() / 1000.0) * 300).toNumber() % 360;
        var radius = (L.r * 0.34).toNumber();
        var pen = (L.r * 0.055).toNumber();

        UiKit.ringTrack(dc, L.cx, (L.h * 0.42).toNumber(), radius, pen, Theme.SURFACE);
        UiKit.spinner(dc, L.cx, (L.h * 0.42).toNumber(), radius, pen,
                      Theme.GREEN_LIGHT, phase);

        UiKit.caption(dc, L.cx, (L.h * 0.62).toNumber(), "SENDING",
                      L.fontBody, Theme.TEXT);

        // Say who asked, so a point appearing on its own is never a mystery.
        UiKit.caption(dc, L.cx, (L.h * 0.71).toNumber(),
                      session.lastSource().equals("phone")
                          ? "requested by phone" : "to TreeMapper",
                      L.fontLabel, Theme.TEXT_FAINT);
    }

    private function drawRejected(dc as Graphics.Dc, L as Layout,
                                  session as SessionState) as Void {
        var p = _rejectAnim.progress();
        var size = (L.r * 0.30) * Anim.easeBack(Anim.clamp(p * 1.5));
        UiKit.cross(dc, L.cx, (L.h * 0.43).toNumber(), size.toFloat(),
                    Theme.Q_USABLE, Anim.clamp(p * 1.8));

        UiKit.caption(dc, L.cx, (L.h * 0.66).toNumber(), "NOT SENT",
                      L.fontBody, Theme.TEXT);

        var why = (session.rejectReason() == REJECT_QUEUE_FULL)
            ? "watch memory full"
            : "no position yet";
        UiKit.caption(dc, L.cx, (L.h * 0.755).toNumber(), why,
                      L.fontLabel, Theme.Q_USABLE);
    }
}

class CaptureDelegate extends WatchUi.BehaviorDelegate {

    // Held directly rather than looked up with WatchUi.getCurrentView(), which
    // needs a newer API level than this app targets.
    private var _view as CaptureView;

    function initialize(view as CaptureView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Boolean {
        _view.requestSend();
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        _view.requestSend();
        return true;
    }

    function onMenu() as Boolean {
        WatchUi.pushView(SessionMenu.build(), new SessionMenuDelegate(),
                         WatchUi.SLIDE_LEFT);
        return true;
    }

    //! Back ends the session and shows the summary rather than silently
    //! dropping out. Losing a morning of work to a stray press is the worst
    //! failure this app could have.
    function onBack() as Boolean {
        WatchUi.switchToView(new SummaryView(), new SummaryDelegate(),
                             WatchUi.SLIDE_DOWN);
        return true;
    }
}
