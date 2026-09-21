import Toybox.Lang;

//! A payload ladder for the tethered-transport crash.
//!
//! When the Connect IQ simulator dies with "Socket Error in packet header"
//! there is no stack and no error code, so the only way to learn anything is to
//! send progressively richer payloads and see which one is the last to be
//! logged. Each rung adds exactly one thing to the rung below it:
//!
//!   0  a bare String                     the simplest thing transmit accepts
//!   1  a bare Number
//!   2  an Array of one String            tests the container, not the content
//!   3  a Dictionary, one String value    tests Dictionary serialisation
//!   4  the same plus one Number value    tests mixed value types
//!   5  the real `ready` message          the shape the protocol actually uses
//!
//! One rung leaves per tick and only after the previous one has reported back,
//! so the last "[tm] PROBE n" line in the console names the culprit exactly.
//!
//! Set PROBE_MODE to false to go back to the real protocol. Leave this file in
//! the project: the next SDK release is as likely to reintroduce the problem as
//! to fix it.
const PROBE_MODE = true;
const PROBE_COUNT = 6;

//! What rung n is testing, for the log.
function probeName(n as Number) as String {
    if (n == 0) { return "String"; }
    if (n == 1) { return "Number"; }
    if (n == 2) { return "Array of String"; }
    if (n == 3) { return "Dictionary, one String value"; }
    if (n == 4) { return "Dictionary, String + Number"; }
    return "the real ready message";
}

//! Rung n itself. Deliberately not a Dictionary until rung 3.
function probePayload(n as Number) {
    if (n == 0) { return "probe0"; }
    if (n == 1) { return 1; }
    if (n == 2) { return ["probe2"]; }
    if (n == 3) { return { "t" => "probe3" }; }
    if (n == 4) { return { "t" => "probe4", "v" => 1 }; }
    return {
        "t"   => "ready",
        "v"   => 1,
        "q"   => 0,
        "gps" => 1,
        "mb"  => 0,
        "buf" => 0
    };
}
