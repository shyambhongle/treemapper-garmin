import Toybox.Application;
import Toybox.Lang;
import Toybox.System;

//! A durable outbox for points the phone has not acknowledged.
//!
//! Under the normal flow the phone is present and every point goes straight
//! out, so this stays empty. It exists for the case that actually loses work:
//! the person walks out of Bluetooth range, or the phone app is closed, and
//! keeps pressing the watch button. Those points survive in Application.Storage
//! and flush when the link returns.
//!
//! Storage limits that shape the design: 8 KB per key, 128 KB per app, and no
//! permission needed. Points are written in chunks rather than one key each,
//! because per key overhead would waste most of the budget.
class PointQueue {

    const CHUNK = 25;        // points per storage key, about 3.5 KB
    const MAX_CHUNKS = 20;   // 500 points, about 70 KB, well inside 128
    const K_HEAD = "q_head";
    const K_TAIL = "q_tail";

    private var _head as Number = 0;   // chunk index being read from
    private var _tail as Number = 0;   // chunk index being written to
    private var _count as Number = 0;

    function initialize() {
        load();
    }

    private function key(index as Number) as String {
        return "q_" + index.format("%d");
    }

    private function load() as Void {
        var h = Application.Storage.getValue(K_HEAD);
        var t = Application.Storage.getValue(K_TAIL);
        _head = (h instanceof Number) ? h : 0;
        _tail = (t instanceof Number) ? t : 0;
        _count = recount();
    }

    private function recount() as Number {
        var total = 0;
        for (var i = _head; i <= _tail; i++) {
            var chunk = Application.Storage.getValue(key(i));
            if (chunk instanceof Array) {
                total += chunk.size();
            }
        }
        return total;
    }

    function size() as Number {
        return _count;
    }

    function isEmpty() as Boolean {
        return _count <= 0;
    }

    function isFull() as Boolean {
        return (_tail - _head) >= MAX_CHUNKS;
    }

    //! Append a point. Returns false when the queue is full, which the caller
    //! should surface rather than swallow: silently dropping field data is the
    //! one thing this app must never do.
    function push(point as Dictionary) as Boolean {
        if (isFull()) { return false; }

        var chunk = Application.Storage.getValue(key(_tail));
        if (!(chunk instanceof Array)) {
            chunk = [] as Array<Dictionary>;
        }

        if (chunk.size() >= CHUNK) {
            _tail++;
            chunk = [] as Array<Dictionary>;
        }

        chunk.add(point);

        try {
            Application.Storage.setValue(key(_tail), chunk);
            Application.Storage.setValue(K_TAIL, _tail);
            _count++;
            return true;
        } catch (e) {
            // Storage full or the value would not serialise. Better to report
            // it than to pretend the point was kept.
            return false;
        }
    }

    //! The oldest point, without removing it.
    function peek() as Dictionary or Null {
        for (var i = _head; i <= _tail; i++) {
            var chunk = Application.Storage.getValue(key(i));
            if (chunk instanceof Array and chunk.size() > 0) {
                if (i != _head) {
                    _head = i;
                    Application.Storage.setValue(K_HEAD, _head);
                }
                return chunk[0];
            }
        }
        return null;
    }

    //! Drop the oldest point, once the phone has acknowledged it.
    function pop() as Void {
        for (var i = _head; i <= _tail; i++) {
            var chunk = Application.Storage.getValue(key(i));
            if (chunk instanceof Array and chunk.size() > 0) {
                chunk = chunk.slice(1, null);
                if (chunk.size() == 0 and i < _tail) {
                    Application.Storage.deleteValue(key(i));
                    _head = i + 1;
                    Application.Storage.setValue(K_HEAD, _head);
                } else {
                    Application.Storage.setValue(key(i), chunk);
                }
                _count--;
                if (_count < 0) { _count = 0; }
                return;
            }
        }
    }

    //! Wipe the outbox. Called when a session ends with everything delivered,
    //! so a later session does not inherit stale chunk indices.
    function clear() as Void {
        for (var i = _head; i <= _tail; i++) {
            Application.Storage.deleteValue(key(i));
        }
        _head = 0;
        _tail = 0;
        _count = 0;
        Application.Storage.setValue(K_HEAD, 0);
        Application.Storage.setValue(K_TAIL, 0);
    }
}
