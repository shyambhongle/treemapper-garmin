import Toybox.Lang;

//! Colour tokens and colour maths for the whole app.
//!
//! Everything is a plain 0xRRGGBB Number so it works on every device, including
//! pre-4.0 products with no alpha support. Fades are done by mixing toward the
//! background rather than by using alpha.
module Theme {

    // Brand
    //
    // GREEN is the TreeMapper brand colour and carries every large element:
    // the mark, the rings, the fills.
    //
    // GREEN_LIGHT is the same hue lifted for legibility. #007A49 is a dark
    // green, and at the one or two pixel weights used for small captions on a
    // black screen it drops below comfortable contrast, especially outdoors in
    // sunlight. Small text and thin hints use GREEN_LIGHT; anything with mass
    // uses GREEN. If strict brand fidelity matters more than sunlight
    // legibility, set GREEN_LIGHT = GREEN and everything still works.
    const GREEN        = 0x007A49;  // brand
    const GREEN_LIGHT  = 0x35A97A;  // same hue, lifted for small text on black

    // Surface
    const BG           = 0x000000;  // true black: cheapest on both MIP and AMOLED
    const SURFACE      = 0x101010;
    const HAIRLINE     = 0x2A2A2A;

    // Text
    const TEXT         = 0xFFFFFF;
    const TEXT_DIM     = 0x9A9A9A;
    const TEXT_FAINT   = 0x5A5A5A;

    // Signal quality, matching Position.Quality 0..4
    const Q_NONE       = 0x5A5A5A;
    const Q_POOR       = 0xE04A3C;
    const Q_USABLE     = 0xE8A33D;
    const Q_GOOD       = 0x009A5C;  // brand hue, a touch lifted so the thin
                                    // ring reads at a glance next to the amber

    // Link state
    const LINKED       = 0x009A5C;
    const BUFFERING    = 0xE8A33D;
    const OFFLINE      = 0xE04A3C;

    //! Colour for a Position.Quality value, 0..4.
    function quality(q as Number) as Number {
        if (q >= 4) { return Q_GOOD; }
        if (q == 3) { return Q_USABLE; }
        if (q == 2) { return Q_POOR; }
        return Q_NONE;
    }

    //! Human label for a quality value.
    function qualityLabel(q as Number) as String {
        if (q >= 4) { return "GOOD"; }
        if (q == 3) { return "USABLE"; }
        if (q == 2) { return "POOR"; }
        if (q == 1) { return "STALE"; }
        return "NO FIX";
    }

    //! Linear blend between two 0xRRGGBB colours. t runs 0.0 (a) to 1.0 (b).
    //! This is how every fade in the app is done, since alpha is not available
    //! on older products.
    function blend(a as Number, b as Number, t as Float) as Number {
        var k = t;
        if (k < 0.0) { k = 0.0; }
        if (k > 1.0) { k = 1.0; }

        var ar = (a >> 16) & 0xFF;
        var ag = (a >> 8) & 0xFF;
        var ab = a & 0xFF;

        var br = (b >> 16) & 0xFF;
        var bg = (b >> 8) & 0xFF;
        var bb = b & 0xFF;

        var r = (ar + (br - ar) * k).toNumber();
        var g = (ag + (bg - ag) * k).toNumber();
        var bl = (ab + (bb - ab) * k).toNumber();

        return (r << 16) | (g << 8) | bl;
    }

    //! Fade a colour toward the background. 1.0 is fully visible, 0.0 invisible.
    function fade(colour as Number, alpha as Float) as Number {
        return blend(BG, colour, alpha);
    }
}
