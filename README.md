# TreeMapper GPS for Garmin

A Connect IQ watch app that acts as a high accuracy GPS source for the
TreeMapper phone app.

This is the real thing: `Toybox.Position` drives the fix, `Toybox.Communications`
carries it to the phone, and `Application.Storage` holds anything the phone has
not acknowledged.

- [`PROTOCOL.md`](PROTOCOL.md) is the contract to implement the phone side against.
- [`TESTING.md`](TESTING.md) is the procedure for testing on a real watch.
- [`DESIGN.md`](DESIGN.md) is the architecture and the reasoning.
- [`docs-research/`](docs-research/) is the Connect IQ platform reference.

**The constraint that shapes everything:** `Position.enableLocationEvents()` is
limited to device apps and widgets, so a background service cannot turn the
receiver on. The watch app must be running in the foreground to produce a fresh
fix. A cold multi-band fix takes tens of seconds, so the app starts the receiver
on launch and keeps it warm for the session. Open it at the plot, leave it
running, and every request answers in milliseconds.

---

## Screens

| | Screen | Purpose |
|---|---|---|
| 1 | **Home** | A short splash. The receiver already started in `onStart`, so this holds for 1.5 s then advances on its own. START skips it. |
| 2 | **Acquiring** | Sweeping arc while the receiver converges, with an elapsed counter so slow is distinguishable from broken. Advances on a real fix, or after 90 seconds with any position. |
| 3 | **Capture** | The working screen. Quality ring, one large count, START to send. |
| 4 | **Sending** | The point is genuinely in flight, and the screen says whether the phone or the watch button asked for it. |
| 5 | **Sent** | It reached TreeMapper. Offers the next tree or finish, and continues on its own after four seconds. |
| 6 | **Held on watch** | The same screen when the phone was not listening. The point is recorded, not delivered, and it says so. |
| 7 | **Waiting** | Capture screen with the fix below the floor: ring breathes, action hint goes dead, warning strip appears. |
| 8 | **Summary** | What was collected, how long it took, how much of it was a good fix. |

Plus a native `Menu2` for the quality floor and ending the session,
and a small About page.

Static previews are in [`previews/`](previews/). Regenerate with:

```bash
python3 tools/preview.py
```

That script mirrors the drawing maths from `source/ui/UiKit.mc` in Python. It is
a review aid so the design can be looked at without launching the simulator; it
is not part of the app.

---

## Design notes

**Almost everything is drawn in code.** No layout XML. The only bitmaps are the
launcher icon and the TreeMapper mark, which is the real asset rather than code
art so the watch matches the phone app exactly. The mark ships at three fixed
sizes and `Layout.markResource()` picks one from the screen width: the resource
compiler's `scaleX` takes a pixel format, not a fraction of the screen, so it
cannot scale relative to the display for us. One set of proportions in `source/ui/Layout.mc` derives every
position from the `Dc` dimensions, so the same binary looks right on a 208 px
Instinct and a 454 px AMOLED without per device resource folders.

**The quality ring has four segments, not a smooth gauge.** `Position.Quality`
is a discrete 0 to 4 enum, not a value in metres. A continuous gauge would imply
a precision the receiver does not report. Four steps is the honest picture.

**Black background throughout.** Cheapest on both memory in pixel and AMOLED
panels, and it makes the green carry the whole interface.

**Two greens, on purpose.** `Theme.GREEN` is the brand `#007A49` and carries
everything with mass: the rings, the fills, the mark. `Theme.GREEN_LIGHT` is the
same hue lifted, and is used only for small captions and thin hints. At one or
two pixel weights on black, `#007A49` drops below comfortable contrast outdoors.
If strict brand fidelity matters more than sunlight legibility, set
`GREEN_LIGHT = GREEN` in `Theme.mc` and nothing else changes.

**The phone link is an exception report, not a status badge.** There is no
permanent "phone connected" pill. When the link is healthy, which is almost
always, the screen says nothing about it, because a badge that is true on every
screen stops being read. The strip appears only when the link drops, and the
per-point confirmation already proves delivery: a point that reached the phone
says SENT, a point that did not says HELD ON WATCH. That distinction is the
thing the user actually needs.

**Sending is shown, not assumed.** Press, brief spinner, then a result. The
watch does not claim a point was delivered before it was.

**Fades are colour blends, not alpha.** `Theme.blend()` mixes toward the
background. Alpha only arrived in API 4.0.0, and this app should run on older
products too.

**No haptics.** The watch confirms visually only. Vibration was removed on request; if it comes back, the place for it is `SessionState`, one call beside each send outcome.

**The render timer drops to 1 Hz when nothing is moving.** `CaptureView` runs at
40 ms only during an animation. On a real device with the GNSS receiver already
running, this is the difference between a working day and an afternoon.

**Back does not silently exit.** From the capture screen, back goes to the
summary. Losing a morning of work to a stray button press would be the worst
failure this app could have.

**The confirmation continues on its own.** The sent screen offers the next tree
or finish, but mapping sixty trees should not cost sixty extra decisions, so
continuing is the default and a draining arc shows the four seconds left.
Pressing START skips the wait, BACK finishes instead. Set `AUTO_MS = 0` in
`SentView.mc` to require a press every time.

---

## Project layout

```
manifest.xml            products, permissions, entry point
monkey.jungle           build configuration
source/
  TreeMapperApp.mc      AppBase, entry point
  SessionState.mc       MOCK session data. Replace this with the real thing.
  ui/
    Theme.mc            colour tokens, blending, quality mapping
    Layout.mc           screen metrics derived from the Dc
    UiKit.mc            drawing primitives: rings, spinner, tick, ripple
    Anim.mc             easings and a one shot timeline
  views/
    HomeView.mc
    AcquiringView.mc
    CaptureView.mc      the main screen
    SentView.mc         confirmation, next tree or finish
    SummaryView.mc
    SessionMenu.mc      native Menu2
    AboutView.mc
resources/
  drawables/            launcher icon, white mark for dark screens
  strings/
tools/make_icons.py     builds the drawables from tools/source_icon.png
tools/preview.py        renders previews/, review aid only
previews/               static screen renders
```

---

## Running it

1. Install the Connect IQ SDK Manager (needs JRE 11 or newer) and the **Monkey C**
   VS Code extension, then run `Monkey C: Verify Installation`.
2. Open this folder in VS Code.
3. `Monkey C: Edit Products` and pick the devices you actually have. The list in
   `manifest.xml` is a starting guess and the ids are not validated until you do
   this.
4. Run with **Ctrl+F5** (Windows/Linux) or **Cmd+F5** (macOS) with a `.mc` file
   focused.

In the simulator, use *Simulation > Position* to feed coordinates and
*Simulation > Bluetooth* to fake the phone link. To exercise the real protocol,
drive it from the Android SDK's ADB transport; see `PROTOCOL.md`.

### Expected build warning

```
WARNING: The launcher icon (128x128) isn't compatible with the specified
launcher icon size of the device (60x60). The image will be scaled.
```

This is cosmetic. Every product asks for a different launcher size, and a clean
downscale from 128 beats shipping one small icon that gets scaled up elsewhere.
Once the device list is final, add a `resources-<product>/drawables/` folder per
device with the exact size that product wants and the warning goes away.

---

## How the pieces fit

```
TreeMapperApp        starts and stops the session with the app
  SessionState       the brain: owns the three below, the only thing views touch
    GpsService       Toybox.Position. Picks the best supported GNSS config,
                     keeps the receiver warm, hands out snapshots
    PhoneLink        Toybox.Communications. One parcel in flight at a time,
                     explicit acknowledgement, link state
    PointQueue       Application.Storage. Durable outbox, about 500 points
```

Two rules run through it:

**A point is not sent until the phone says so.** Everything captured goes into
the outbox first and the counters derive from what was acknowledged. A dropped
link costs a delay, never a tree.

**The watch never filters on quality.** Every point travels with its
`Position.Quality` value and the phone decides what to keep. The watch refuses
only when there is no position at all, or the outbox is full.

## Not built yet

- No `Background` permission and no background service. Everything happens while
  the app is open, which is forced by the Position restriction above.
- No activity recording or FIT output.
- Reconnect is best effort: the outbox flushes on the next tick when the link
  returns, with no backoff.

---

## Open questions

- **Which devices?** The product list is a guess. This drives the test matrix and
  should be settled before any device specific tuning.
- **Brand green.** `Theme.GREEN` is `#007A49`. `Theme.GREEN_LIGHT` is a lifted
  variant used only for small text; see the design notes above.
- **Wording.** "TREES" as the count label assumes one point per tree. If a tree
  can carry several points, or plots are the unit, the label changes.


---

## Regenerating the icons

`tools/source_icon.png` is the TreeMapper artwork as supplied: the white glyph on
the brand green field. `tools/make_icons.py` derives everything else from it.

```bash
python3 tools/make_icons.py
```

It writes the 128 px launcher icon, plus white and green glyph-only versions on
transparent backgrounds. The app draws the white one, since every screen is
black. Replace `source_icon.png` and rerun to change the artwork.
