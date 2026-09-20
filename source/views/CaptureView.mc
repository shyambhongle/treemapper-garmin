import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! The main working screen.
//!
//! Design intent: the user is standing at a tree, often in rain, often wearing
//! gloves, often not looking at the watch. So the screen carries the fewest
//! facts that still let them act, and the confirmation is mostly haptic.
//!
//!   1. Is the fix good enough right now  -> the edge ring and its colour
//!   2. How much have I collected         -> one large number
//!   3. Is anything wrong                 -> a warning strip, and only then
//!
//! Point 3 is deliberately an exception report. A permanent "phone connected"
//! badge is true on almost every screen the user ever sees, so it stops being
//! read. What matters is the moment it stops being true.

// Confirmation overlay states.
enum {
    OVERLAY_NONE = 0,
    OVERLAY_SENDING = 1,
    OVERLAY_REJECTED = 2
}

class CaptureView extends WatchUi.View {
    private var _layout as Layout or Null;
    private var _timer as Timer.Timer or Null;
    private var _rateMs as Number = 1000;

    private var _overlay as Number = OVERLAY_NONE;
    private var _overlayAnim as Anim.Timeline;
    private var _entered as Anim.Timeline;

    function initialize() {
        View.initialize();
        _overlayAnim = new Anim.Timeline(700);
        _entered = new Anim.Timeline(400);
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _layout = new Layout(dc);
    }

    function onShow() as Void {
        _overlay = OVERLAY_NONE;
        _entered.start();
        setRate(40);
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

    //! Drop to a slow tick when nothing is moving. On a real device, with the
    //! GNSS receiver already running, this is the difference between a working
    //! day and an afternoon.
    private function setRate(ms as Number) as Void {
        if (_timer != null and _rateMs == ms) { return; }
        stopTimer();
        _rateMs = ms;
        _timer = new Timer.Timer();
        _timer.start(method(:onFrame), ms, true);
    }

    function onFrame() as Void {
        var session = $.gSession;
        if (session != null) {
            session.tick();
        }

        // The send animation finishing is what advances to the sent screen.
        if (_overlay == OVERLAY_SENDING and _overlayAnim.isDone()) {
            finishSend();
            return;
        }
        if (_overlay == OVERLAY_REJECTED and _overlayAnim.isDone()) {
            _overlay = OVERLAY_NONE;
        }

        var animating = (_overlay != OVERLAY_NONE) or _entered.isRunning();
        setRate(animating ? 40 : 1000);

        WatchUi.requestUpdate();
    }

    //! Called by the delegate when the user asks to send a point.
    function requestSend() as Void {
        var session = $.gSession;
        if (session == null or _overlay != OVERLAY_NONE) { return; }

        // Reject immediately: there is nothing to send, so do not pretend to
        // work for half a second first.
        if (session.quality < session.minQuality) {
            _overlay = OVERLAY_REJECTED;
            _overlayAnim = new Anim.Timeline(900);
            _overlayAnim.start();
            setRate(40);
            WatchUi.requestUpdate();
            return;
        }

        _overlay = OVERLAY_SENDING;
        _overlayAnim = new Anim.Timeline(700);
        _overlayAnim.start();
        setRate(40);
        WatchUi.requestUpdate();
    }

    private function finishSend() as Void {
        var session = $.gSession;
        if (session == null) { return; }

        var outcome = session.send();
        _overlay = OVERLAY_NONE;

        var sent = new SentView(outcome, session.totalPoints());
        WatchUi.switchToView(sent, new SentDelegate(sent), WatchUi.SLIDE_LEFT);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var L = _layout;
        var session = $.gSession;
        if (L == null or session == null) { return; }

        var overlayP = _overlayAnim.progress();

        var bg = Theme.BG;
        if (_overlay == OVERLAY_REJECTED) {
            bg = Theme.blend(Theme.BG, 0x4A2A12, (1.0 - overlayP) * 0.22);
        }
        dc.setColor(bg, bg);
        dc.clear();
        UiKit.smooth(dc, true);

        drawQualityRing(dc, L, session);

        if (_overlay == OVERLAY_SENDING) {
            drawSending(dc, L);
        } else if (_overlay == OVERLAY_REJECTED) {
            drawRejected(dc, L, overlayP);
        } else {
            drawMain(dc, L, session);
        }
    }

    // ---- pieces -----------------------------------------------------------

    private function drawQualityRing(dc as Graphics.Dc, L as Layout,
                                     session as SessionState) as Void {
        var colour = Theme.quality(session.quality);

        // While the fix sits below the floor the ring breathes. This is the one
        // moment we actively want to pull the eye.
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

        // 1. Fix quality
        UiKit.caption(dc, L.cx, L.topLabelY,
                      "GNSS " + Theme.qualityLabel(session.quality),
                      L.fontLabel, Theme.blend(Theme.BG, qColour, intro));

        // 2. The count, the one thing worth a large font
        dc.setColor(Theme.blend(Theme.BG, Theme.TEXT, intro), Graphics.COLOR_TRANSPARENT);
        dc.drawText(L.cx, (L.h * 0.45).toNumber(), L.fontHero,
                    session.totalPoints().format("%d"),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        UiKit.caption(dc, L.cx, (L.h * 0.585).toNumber(),
                      session.totalPoints() == 1 ? "TREE" : "TREES",
                      L.fontLabel, Theme.blend(Theme.BG, Theme.TEXT_FAINT, intro));

        // 3. Warnings only. Nothing is drawn here when the link is healthy.
        if (!session.isLinked()) {
            UiKit.statusPill(dc, L.cx, L.statusY, session.linkWarning(),
                             session.linkColour(), L.fontLabel);
        }

        // Action hint, dead when the fix is not good enough to act on.
        var ready = session.quality >= session.minQuality;
        var hint = ready
            ? (L.isTouch ? "Tap to send" : "START to send")
            : "Waiting for fix";

        UiKit.hairline(dc, L.cx, L.bottomHintY - (L.r * 0.12).toNumber(),
                       (L.w * 0.30).toNumber(), Theme.HAIRLINE);
        UiKit.caption(dc, L.cx, L.bottomHintY, hint, L.fontBody,
                      ready ? Theme.blend(Theme.BG, Theme.GREEN_LIGHT, intro)
                            : Theme.blend(Theme.BG, Theme.TEXT_FAINT, intro));
    }

    private function drawSending(dc as Graphics.Dc, L as Layout) as Void {
        var phase = ((System.getTimer() / 1000.0) * 300).toNumber() % 360;
        var radius = (L.r * 0.34).toNumber();
        var pen = (L.r * 0.055).toNumber();

        // A dim full circle behind the chaser, so the spinner reads as a ring
        // that is working rather than as a stray arc.
        UiKit.ringTrack(dc, L.cx, (L.h * 0.42).toNumber(), radius, pen, Theme.SURFACE);
        UiKit.spinner(dc, L.cx, (L.h * 0.42).toNumber(), radius, pen,
                      Theme.GREEN_LIGHT, phase);

        UiKit.caption(dc, L.cx, (L.h * 0.62).toNumber(), "SENDING",
                      L.fontBody, Theme.TEXT);
        UiKit.caption(dc, L.cx, (L.h * 0.71).toNumber(), "to TreeMapper",
                      L.fontLabel, Theme.TEXT_FAINT);
    }

    private function drawRejected(dc as Graphics.Dc, L as Layout, p as Float) as Void {
        var size = (L.r * 0.30) * Anim.easeBack(Anim.clamp(p * 1.5));
        UiKit.cross(dc, L.cx, (L.h * 0.43).toNumber(), size.toFloat(),
                    Theme.Q_USABLE, Anim.clamp(p * 1.8));

        UiKit.caption(dc, L.cx, (L.h * 0.66).toNumber(), "NOT SENT",
                      L.fontBody, Theme.TEXT);
        UiKit.caption(dc, L.cx, (L.h * 0.755).toNumber(), "fix too weak",
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
    //! dropping the user out. Losing a morning of work to a stray press is the
    //! worst failure this app could have.
    function onBack() as Boolean {
        WatchUi.switchToView(new SummaryView(), new SummaryDelegate(),
                             WatchUi.SLIDE_DOWN);
        return true;
    }
}
