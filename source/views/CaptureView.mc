import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! The fix screen: one converged position, offered to the phone.
//!
//! The person is standing at a tree, often in rain, often wearing gloves, often
//! not looking at the watch. So the screen carries the fewest facts that let
//! them act:
//!
//!   1. Is this fix any good            -> the edge ring, and the word
//!   2. What can I do with it           -> send it, or start over
//!   3. Is anything wrong               -> a strip, and only then
//!
//! Point 3 is an exception report on purpose. A permanent "phone connected"
//! badge is true on almost every screen, so it stops being read. What matters
//! is the moment it stops being true.
//!
//! The watch holds nothing. A fix that is sent is forgotten; a fix that fails
//! stays in hand only until the user retries or restarts. To record another
//! tree, the user restarts and the flow runs again from acquisition.
//!
//! Two things can start a send: the START button here, or a "fix" command from
//! the phone. Both land in the same place, so the watch confirms either way and
//! the person can work from the phone or from the wrist.

// Confirmation overlay states.
enum {
    OVERLAY_NONE = 0,
    OVERLAY_SENDING = 1,
    OVERLAY_FAILED = 2,
    OVERLAY_REJECTED = 3
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

        // The phone asked for a fix while we were idle. Show the same
        // confirmation the button would have produced, so the person sees what
        // their phone just did.
        if (_overlay == OVERLAY_NONE and session.isRemoteActive()) {
            _overlay = OVERLAY_SENDING;
        }

        if (_overlay == OVERLAY_SENDING) {
            var result = session.sendResult();
            if (result == SEND_SENT) {
                session.clearRemote();
                _overlay = OVERLAY_NONE;
                WatchUi.switchToView(new SentView(), new SentDelegate(),
                                     WatchUi.SLIDE_LEFT);
                return;
            }
            if (result == SEND_FAILED) {
                session.clearRemote();
                _overlay = OVERLAY_FAILED;
            }
        }

        if (_overlay == OVERLAY_REJECTED and _rejectAnim.isDone()) {
            _overlay = OVERLAY_NONE;
        }

        // The failed screen is static and waits for a press, so it does not
        // need frames. Everything else either animates or is about to change.
        var animating = (_overlay == OVERLAY_SENDING)
            or (_overlay == OVERLAY_REJECTED)
            or _entered.isRunning();
        setRate(animating ? FRAME_MS : 1000);

        WatchUi.requestUpdate();
    }

    //! Called by the delegate when the user presses to send, or to try again
    //! after a failure.
    function requestSend() as Void {
        var session = $.gSession;
        if (session == null) { return; }

        var outcome;
        if (_overlay == OVERLAY_FAILED) {
            // Same fix, second attempt. Re-reading the receiver here would
            // quietly send a different coordinate than the one that failed.
            outcome = session.retrySend();
        } else if (_overlay == OVERLAY_NONE) {
            outcome = session.requestSend("watch", null);
        } else {
            return;   // already sending, or showing a refusal
        }

        if (outcome == SEND_REJECTED) {
            // The only refusal is the absence of a position. Quality is never
            // a refusal: the fix goes with its quality attached and the phone
            // decides.
            _overlay = OVERLAY_REJECTED;
            _rejectAnim = new Anim.Timeline(900);
            _rejectAnim.start();
        } else if (outcome == SEND_FAILED) {
            _overlay = OVERLAY_FAILED;
        } else {
            _overlay = OVERLAY_SENDING;
        }

        setRate(FRAME_MS);
        WatchUi.requestUpdate();
    }

    //! Throw this fix away and go back to acquiring, ready for another tree.
    function restart() as Void {
        var session = $.gSession;
        if (session != null) {
            session.discard();
        }
        WatchUi.switchToView(new AcquiringView(), new AcquiringDelegate(),
                             WatchUi.SLIDE_RIGHT);
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
        } else if (_overlay == OVERLAY_FAILED) {
            drawFailed(dc, L);
        } else if (_overlay == OVERLAY_REJECTED) {
            drawRejected(dc, L);
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

        UiKit.caption(dc, L.cx, L.topLabelY, "GNSS FIX",
                      L.fontLabel, Theme.blend(Theme.BG, Theme.TEXT_FAINT, intro));

        // The quality word is the hero. There is no metric accuracy to show:
        // Connect IQ reports Position.Quality and nothing else. fontTitle, not
        // fontHero, because the FONT_NUMBER_* faces carry digits only.
        UiKit.caption(dc, L.cx, (L.h * 0.42).toNumber(),
                      Theme.qualityLabel(session.quality),
                      L.fontTitle, Theme.blend(Theme.BG, qColour, intro));

        // Warnings only. Nothing is drawn here when everything is working.
        if (!session.isLinked()) {
            UiKit.statusPill(dc, L.cx, L.statusY, session.linkWarning(),
                             session.linkColour(), L.fontLabel);
        }

        UiKit.hairline(dc, L.cx, (L.h * 0.705).toNumber(),
                       (L.w * 0.30).toNumber(), Theme.HAIRLINE);

        // The only thing that disables the action is having no position at
        // all. The quality word above already says what the fix is worth, so
        // this line says only what the button will do.
        var ready = session.gps().hasPosition();
        var send = ready
            ? (L.isTouch ? "Tap to send" : "START  send")
            : "no position yet";
        UiKit.caption(dc, L.cx, L.bottomHintY, send, L.fontBody,
                      ready ? Theme.blend(Theme.BG, Theme.GREEN_LIGHT, intro)
                            : Theme.blend(Theme.BG, Theme.TEXT_FAINT, intro));

        UiKit.caption(dc, L.cx, L.secondHintY,
                      L.isTouch ? "Swipe back to restart" : "BACK  restart",
                      L.fontLabel, Theme.blend(Theme.BG, Theme.TEXT_FAINT, intro));
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

        // Say who asked, so a fix leaving on its own is never a mystery.
        UiKit.caption(dc, L.cx, (L.h * 0.71).toNumber(),
                      session.lastSource().equals("phone")
                          ? "requested by phone" : "to TreeMapper",
                      L.fontLabel, Theme.TEXT_FAINT);
    }

    //! The fix did not reach the phone. It is still in hand, so the honest
    //! thing is to offer the same fix again rather than silently take a new
    //! one, and to say plainly that nothing was kept.
    private function drawFailed(dc as Graphics.Dc, L as Layout) as Void {
        UiKit.cross(dc, L.cx, (L.h * 0.355).toNumber(), (L.r * 0.30).toFloat(),
                    Theme.OFFLINE, 1.0);

        UiKit.caption(dc, L.cx, (L.h * 0.545).toNumber(), "NOT SENT",
                      L.fontBody, Theme.TEXT);
        UiKit.caption(dc, L.cx, (L.h * 0.625).toNumber(), "phone not in range",
                      L.fontLabel, Theme.OFFLINE);

        UiKit.hairline(dc, L.cx, (L.h * 0.705).toNumber(),
                       (L.w * 0.30).toNumber(), Theme.HAIRLINE);

        UiKit.caption(dc, L.cx, L.bottomHintY,
                      L.isTouch ? "Tap to try again" : "START  try again",
                      L.fontBody, Theme.GREEN_LIGHT);
        UiKit.caption(dc, L.cx, L.secondHintY,
                      L.isTouch ? "Swipe back to restart" : "BACK  restart",
                      L.fontLabel, Theme.TEXT_FAINT);
    }

    private function drawRejected(dc as Graphics.Dc, L as Layout) as Void {
        var p = _rejectAnim.progress();
        var size = (L.r * 0.30) * Anim.easeBack(Anim.clamp(p * 1.5));
        UiKit.cross(dc, L.cx, (L.h * 0.43).toNumber(), size.toFloat(),
                    Theme.Q_USABLE, Anim.clamp(p * 1.8));

        UiKit.caption(dc, L.cx, (L.h * 0.66).toNumber(), "NOT SENT",
                      L.fontBody, Theme.TEXT);
        UiKit.caption(dc, L.cx, (L.h * 0.755).toNumber(), "no position yet",
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

    //! Back throws this fix away and starts the process again. It does not
    //! leave the app: one more BACK from the acquiring screen does that, so
    //! the fix in hand is never one stray press away from being lost.
    function onBack() as Boolean {
        _view.restart();
        return true;
    }
}
