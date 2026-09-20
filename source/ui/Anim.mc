import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

//! Small animation helpers.
//!
//! Connect IQ has WatchUi.AnimationLayer for .mmm movies, but for a few rings
//! and a ripple, driving values from a timer is lighter and scales to any screen
//! size. Nothing here allocates, so it is safe to call from onUpdate().
module Anim {

    //! Ease out cubic. Fast start, gentle settle. Good for things arriving.
    function easeOut(t as Float) as Float {
        var k = clamp(t);
        var inv = 1.0 - k;
        return 1.0 - (inv * inv * inv);
    }

    //! Ease in out cubic. Good for things that loop.
    function easeInOut(t as Float) as Float {
        var k = clamp(t);
        if (k < 0.5) {
            return 4.0 * k * k * k;
        }
        var f = (2.0 * k) - 2.0;
        return 1.0 + (f * f * f) / 2.0;
    }

    //! Overshoot slightly then settle. Used for the capture confirmation.
    function easeBack(t as Float) as Float {
        var k = clamp(t);
        var s = 1.70158;
        var f = k - 1.0;
        return (f * f * ((s + 1.0) * f + s)) + 1.0;
    }

    //! A 0..1 triangle wave over the given period, in milliseconds.
    function pulse(elapsedMs as Number, periodMs as Number) as Float {
        var phase = (elapsedMs % periodMs).toFloat() / periodMs.toFloat();
        if (phase < 0.5) {
            return phase * 2.0;
        }
        return (1.0 - phase) * 2.0;
    }

    //! A smooth 0..1 breathing wave over the given period.
    function breathe(elapsedMs as Number, periodMs as Number) as Float {
        var phase = (elapsedMs % periodMs).toFloat() / periodMs.toFloat();
        return (1.0 - Math.cos(phase * Math.PI * 2.0)).toFloat() / 2.0;
    }

    function clamp(t as Float) as Float {
        if (t < 0.0) { return 0.0; }
        if (t > 1.0) { return 1.0; }
        return t;
    }

    function lerp(a as Float, b as Float, t as Float) as Float {
        return a + (b - a) * clamp(t);
    }

    //! A one shot timeline. Construct it, call start(), read progress() each
    //! frame, and check isDone() to stop the render timer.
    class Timeline {
        private var _durationMs as Number;
        private var _startMs as Number or Null;

        function initialize(durationMs as Number) {
            _durationMs = durationMs;
            _startMs = null;
        }

        function start() as Void {
            _startMs = System.getTimer();
        }

        function isRunning() as Boolean {
            return _startMs != null and !isDone();
        }

        function isDone() as Boolean {
            if (_startMs == null) { return true; }
            return (System.getTimer() - _startMs) >= _durationMs;
        }

        //! Raw 0..1 progress.
        function progress() as Float {
            if (_startMs == null) { return 1.0; }
            var elapsed = System.getTimer() - _startMs;
            if (elapsed >= _durationMs) { return 1.0; }
            return elapsed.toFloat() / _durationMs.toFloat();
        }

        function reset() as Void {
            _startMs = null;
        }
    }
}
