import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;

//! Screen metrics derived from the Dc, so one layout works from a 208 px
//! Instinct to a 454 px AMOLED without per-device resource folders.
//!
//! Build one in View.onLayout() and keep it. Never build one in onUpdate().
class Layout {

    public var w as Number;
    public var h as Number;
    public var cx as Number;
    public var cy as Number;
    public var r as Number;              // usable radius

    public var isRound as Boolean;
    public var isTouch as Boolean;

    public var ringRadius as Number;     // outer progress ring
    public var ringWidth as Number;
    public var trackInset as Number;     // safe inset from the glass edge

    public var topLabelY as Number;
    public var bottomHintY as Number;
    public var statusY as Number;

    public var fontHero as Graphics.FontType;
    public var fontTitle as Graphics.FontType;
    public var fontBody as Graphics.FontType;
    public var fontLabel as Graphics.FontType;

    function initialize(dc as Graphics.Dc) {
        w = dc.getWidth();
        h = dc.getHeight();
        cx = w / 2;
        cy = h / 2;
        r = (w < h ? w : h) / 2;

        var settings = System.getDeviceSettings();
        isRound = (settings.screenShape == System.SCREEN_SHAPE_ROUND);
        isTouch = settings.isTouchScreen;

        // Ring hugs the edge on round screens, sits further in on square ones
        // so the corners do not clip it.
        trackInset = isRound ? (r * 0.055).toNumber() : (r * 0.16).toNumber();
        if (trackInset < 4) { trackInset = 4; }

        ringWidth = (r * 0.075).toNumber();
        if (ringWidth < 4) { ringWidth = 4; }

        ringRadius = r - trackInset - (ringWidth / 2);

        // Vertical rhythm as fractions of height, so it scales.
        topLabelY    = (h * 0.20).toNumber();
        statusY      = (h * 0.70).toNumber();
        bottomHintY  = (h * 0.83).toNumber();

        fontHero  = pickHero();
        fontTitle = Graphics.FONT_MEDIUM;
        fontBody  = Graphics.FONT_SMALL;
        fontLabel = Graphics.FONT_XTINY;
    }

    //! The biggest numeric font the screen can carry without crowding the ring.
    private function pickHero() as Graphics.FontType {
        if (r >= 200) { return Graphics.FONT_NUMBER_THAI_HOT; }
        if (r >= 150) { return Graphics.FONT_NUMBER_HOT; }
        if (r >= 110) { return Graphics.FONT_NUMBER_MEDIUM; }
        return Graphics.FONT_NUMBER_MILD;
    }

    //! Which mark bitmap suits this screen.
    //!
    //! The resource compiler cannot scale a bitmap by a fraction of the screen,
    //! so three sizes ship and the right one is chosen here. Each is about 30
    //! percent of its target screen width.
    function markResource() as Lang.ResourceId {
        if (w >= 360) { return Rez.Drawables.MarkLarge; }
        if (w >= 260) { return Rez.Drawables.MarkMedium; }
        return Rez.Drawables.MarkSmall;
    }

    //! A smaller mark, for the About page.
    function markResourceSmall() as Lang.ResourceId {
        if (w >= 390) { return Rez.Drawables.MarkMedium; }
        return Rez.Drawables.MarkSmall;
    }

    //! Vertical centre for a block of text of the given font.
    function textTop(font as Graphics.FontType, centreY as Number) as Number {
        return centreY - (Graphics.getFontHeight(font) / 2);
    }
}
