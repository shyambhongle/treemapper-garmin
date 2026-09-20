# Garmin Connect IQ — Technical Briefing: App Types, UI Layer, Device Diversity

> Sourcing note: `developer.garmin.com/connect-iq/*` doc pages are client-rendered (Gatsby) and return an empty body to fetchers. The real content is served as static HTML at `https://developer.garmin.com/connect-iq/articles/<section>/<File_Name>.html` (discoverable via `https://developer.garmin.com/page-data/<path>/page-data.json` → `pageContext.fileName`). All quotes/snippets below come from those article files, the JSDoc `api-docs` pages, and Garmin's own forum announcement posts. Current SDK at time of writing: **Connect IQ 9.2.0**.

---

## 1. App Types

Every app declares its type in `manifest.xml`. The type sets the runtime sandbox, entry-point class, memory budget and available Toybox modules. **Five manifest `type` values exist:**

1. `watchface`
2. `datafield`
3. `widget`
4. `watch-app`
5. `audio-content-provider-app`

Glances, complications and background services are **not** app types — they are additional entry points/capabilities layered onto the five.

> "A Toybox module requested for your app type that is outside this list will result in a *Symbol Not Found* error."

### 1.0 Module availability by app type (from App_Types.html)

| Module | Data Field | Watch Face | Widget | App | ACP | API Level |
|---|---|---|---|---|---|---|
| Toybox.Activity | ✓ | | | ✓ | ✓ | 1.0.0 |
| Toybox.ActivityMonitor* | ✓ | ✓ | ✓ | ✓ | ✓ | 1.0.0 |
| Toybox.ActivityPrompts* | ✓ | | | | | 5.2.0 |
| Toybox.ActivityRecording* | | | | ✓ | | 1.0.0 |
| Toybox.Ant* | ✓ | | ✓ | ✓ | ✓ | 1.0.0 |
| Toybox.Application / Properties / Storage | ✓ | ✓ | ✓ | ✓ | ✓ | 1.0.0 / 2.4.0 |
| Toybox.Attention | ✓ | | ✓ | ✓ | ✓ | 1.0.0 |
| Toybox.Authentication | ✓ | ✓ | ✓ | ✓ | ✓ | 3.3.0 |
| Toybox.Background* | ✓ | ✓ | ✓ | ✓ | ✓ | 2.3.0 |
| Toybox.BluetoothLowEnergy* | | ✓ | ✓ | ✓ | ✓ | 3.1.0 |
| Toybox.Communications* | ✓** | | ✓ | ✓ | ✓ | 1.0.0 |
| Toybox.Complications* | | ✓ | | ✓ | ✓ | 4.1.0 |
| Toybox.Cryptography* | ✓ | ✓ | ✓ | ✓ | ✓ | 3.0.0 |
| Toybox.FitContributor* | ✓ | | | ✓ | ✓ | 1.3.0 |
| Toybox.Graphics / Lang / Math / WatchUi | ✓ | ✓ | ✓ | ✓ | ✓ | 1.0.0 |
| Toybox.Media | | | | | ✓ | 3.0.0 |
| Toybox.Notifications* | ✓ | ✓ | ✓ | ✓ | ✓ | 5.1.0 |
| Toybox.PersistedContent* | | | ✓ | ✓ | ✓ | 2.2.0 |
| Toybox.PersistedLocations* | | | | ✓ | ✓ | 1.0.0 |
| Toybox.Position* | | | ✓ | ✓ | ✓ | 1.0.0 |
| Toybox.Sensor* | | | ✓ | ✓ | ✓ | 1.0.0 |
| Toybox.SensorHistory* | ✓ | ✓ | ✓ | ✓ | ✓ | 2.1.0 |
| Toybox.SensorLogging* | | | | ✓ | ✓ | 2.3.0 |
| Toybox.Timer | | ✓ | ✓ | ✓ | ✓ | 1.0.0 |
| Toybox.UserProfile* | ✓ | ✓ | ✓ | ✓ | ✓ | 1.0.0 |
| Toybox.Weather | ✓ | ✓ | ✓ | ✓ | ✓ | 3.2.0 |
| Toybox.StringUtil / System / Test / Time | ✓ | ✓ | ✓ | ✓ | ✓ | 1.0.0–2.1.0 |

`*` = requires app permission. `**` = Communications support in data fields introduced in **API level 5.0.0**.

### 1.1 Watch faces (`watchface`)

- **What**: the home screen of Garmin wearables. Base class `WatchUi.WatchFace` (extends `WatchUi.View`); app class extends `Application.AppBase`; `getInitialView()` returns `[view]` or `[view, WatchUi.WatchFaceDelegate]`.
- **Why constrained**: "Watch faces run continuously on the device and can have the most effect on power consumption." They get the **least** API access: graphics, bitmaps, fonts, activity-tracker status, battery, user profile. **No compass, no GPS, no other sensors.** No `Toybox.Activity`, no `ActivityRecording`, no `Position` (except read-only under permission, and they may not call `Position.enableLocationEvents()`).
- **Power states**:
  - **Sleep / low-power mode** (the majority of the time): `onUpdate()` once **per minute**; **no timers, no animations**.
  - Raise-to-wake / return-to-watch-face → `WatchFace.onExitSleep()`; updates go to **once per second**, timers and animations allowed, typically ~10 s.
  - Back to sleep → `WatchFace.onEnterSleep()`; kill timers here.
- **Partial updates (always-on)**: `WatchFace.onPartialUpdate(dc)` is called each second for the first 59 s of each minute on supporting devices. You **must** call `Dc.setClip()` to restrict the region — the power budget is computed from the clipped area. Exceeding it fires `WatchFaceDelegate.onPowerBudgetExceeded()` and the partial update is not drawn. `System.print()/println()` do not execute inside `onPartialUpdate()` on real hardware.
- **WatchFaceDelegate** (*since 2.3.0*): returned as element 2 of `getInitialView()`. Used for `onPowerBudgetExceeded()` and (on complication-capable devices) `onPress(clickEvent)` for hold-to-launch.
- **Other hooks**: `AppBase.getGoalView()` to override goal views.
- **Rendering classes** (from UX Entry Points):
  - **MIP standard** — minute updates, second updates on gesture.
  - **MIP always active** — full minute updates + partial second updates.
  - **AMOLED standard** — screen off by default, enables on gesture.
  - **AMOLED v1** — burn-in detection: 4-minute per-pixel limit, max 10 % of screen.
  - **AMOLED v2** — 10 % screen-pixel limit; gestures disable restrictions.
- **Always-on AMOLED rules**: "only update every minute, and each update is limited to using 10% of the available pixels." Design guidance: avoid bright white/blue (use light gray), thin-weight fonts, minimize static elements, shift static elements **up to 4 px per minute**.
- **Memory tip from docs**: "If you use custom fonts for numeric display, use the filter option to only load the critical glyphs."
- **On-device settings**: System 4+ devices can launch a watch-face configuration flow from the native watch-face menu (push/pop views supported).

### 1.2 Data fields (`datafield`)

- **What**: plug-ins to Garmin's native activity experience. Two base classes:
  - `WatchUi.SimpleDataField` — implement only `compute(info)`; Connect IQ handles drawing, font choice and all layout sizes. Use it "when possible to guarantee your data field will have the native look and feel."
  - `WatchUi.DataField` (extends `WatchUi.View`) — full custom drawing; you must handle 1-, 2-, 3-, 4-field and other layouts yourself.
- **Lifecycle**: `compute(info as Activity.Info)` is called each second; `onUpdate(dc)` each time the field must redraw.
- **Sample from docs** (as printed, including the `SimpleField` typo in the source):

```monkeyc
using Toybox.Application;
using Toybox.WatchUi;

class BeerView extends WatchUi.SimpleField
{
    function initialize() {
        units = "beers";
    }

    function compute(info) {
        return info.calories / 150; // Calories in average bottle of beer
    }
}

class BeersEarned extends Application.AppBase
{
    function getInitialView() {
        return new BeerView();
    }
}
```

- **Input**: extremely limited — only `InputDelegate.onTap()` on touch devices.

```monkeyc
class DataFieldApp extends App.AppBase {
    function getInitialView() {
        return [ new DataFieldView(), new DataFieldDelegate() ];
    }
}

class DataFieldDelegate extends Ui.InputDelegate {
    function onTap(evt) {
        // Process the touch event
    }
}
```

- **Obscurity**: "Connect IQ will communicate if the top, left, right or bottom of your visual area is obscured by the curvature" — rearrange the layout accordingly on round screens.
- **Alerts** (*3.2.0*): `WatchUi.DataFieldAlert` + `DataField.showAlert()`; requires the `Data Field Alert` permission. Full-page, no input, auto-times-out. **Disabled by default** — user must enable *Settings → Alerts → Connect IQ*.
- **FIT recording**: `Toybox.FitContributor` lets a field "define and record up to 16 metrics in an activity file" at 1 s intervals; shown as area charts in Garmin Connect with developer-chosen labels and colors. Requires the `Fit` permission.
- **Communications**: only from API level **5.0.0**.
- **Activity filtering** (*5.2.0*): post-install flow associates the field with activities; filter in the manifest:

```xml
<iq:activityFilter>
    <iq:activity sport="Toybox.Activity.SPORT_RUNNING" subsport="Toybox.Activity.SUB_SPORT_GENERIC" />
    <iq:activity sport="Toybox.Activity.SPORT_RUNNING" subsport="Toybox.Activity.SUB_SPORT_TRAIL" />
    <iq:activity sport="Toybox.Activity.SPORT_RUNNING" subsport="Toybox.Activity.SUB_SPORT_TRACK" />
</iq:activityFilter>
```

- **Simulator**: *Simulation → FIT Data → Simulate* (random valid data) or *Playback File…* (recorded FIT).
- **Memory**: the tightest budget of all app types (see §3.4).

### 1.3 Widgets (`widget`)

- **What**: mini-apps for glanceable information. Launched from the widget carousel (wearables) or a side view (Edge / handhelds).
- **Key limits**: widgets **time out after inactivity** and **cannot record activities** (no `ActivityRecording`), but are launchable at any time.
- **Base-view input restriction**: while the base view returned by `getInitialView()` is showing, the delegate **never receives up/down button or up/down swipe events** — those belong to carousel navigation. Views pushed on top with `WatchUi.pushView()` have no such restriction.
- **Menu**: the system menu's first item opens the widget's own menu → `BehaviorDelegate.onMenu()`.
- **Widget → glance / launcher transition (API 4.0.0)**: *"On API level 4.0 devices and below, widgets run from a carousel on the watch face. On API 4.0.0 and later, widgets launch from the app launcher."* Existing widgets still build and run unchanged on 4.0 products, but **you should add a glance** so the app appears in the glance list. Glances give users two launch paths.

### 1.4 Glances (*since API level 3.1.0*)

Not an app type — a second entry point for widgets (3.1.0+) and, from API 4.0.0, for device apps too.

- **What**: the fēnix 6 replaced the widget carousel with a **list/dashboard**. Each list row is a small canvas; selecting it launches the full app.
- **Entry point**: override `AppBase.getGlanceView()` returning `[new MyGlanceView()]`; the class extends `WatchUi.GlanceView`.
- **Annotation**: annotate the glance view class *and* `getGlanceView()` with `(:glance)`, exactly like `(:background)` for background services, to keep the glance build small.
- **Default behaviour**: before API 4.0.0, a widget without `getGlanceView()` got a default glance showing just the app name. **From API 4.0.0, apps and widgets must implement a glance view to appear in the glance list.**
- **Memory**: "started in Glance mode with limited memory allocated (**32KB for most devices**)."
- **Restrictions**:
  - No input at all ("Glance views run in a limited runtime space, with reduced memory and privileges and do not accept any input").
  - No `WatchUi.Layer` / `addLayer()` / `removeLayer()` / `insertLayer()` / `clearLayers()`.
  - No page control — only one view is allowed in glance mode.
  - `dc` is bounded by the glance strip, not the full screen.
- **Two update models**:
  - **Live UI update** — devices with ample resources (per the docs' footnote: **music-capable wearables**) keep the widget alive in glance mode; `WatchUi.requestUpdate()` works. "It's highly recommended that the update rate should be kept under 1HZ."
  - **Background UI update** — lower-memory devices (**non-music wearables**) start the app only when the system decides; `requestUpdate()` **has no effect**. Updates happen when the glance becomes visible and ≥30 s since the last update. A full lifecycle runs each time: `AppBase.onStart()` → `getGlanceView()` → `onLayout()` → `onShow()` → `onUpdate()` → `onHide()` → `AppBase.onStop()`. What you rendered to the `Dc` is **cached on the filesystem** and displayed until the next update.
- **Glance canvas sizes (fēnix 6 family)**: 6S 151×63, 6 171×63, 6X 191×63.
- **Detecting glance context**: check `DeviceInfo` for `isGlanceModeEnabled`; if glances are on you can launch straight into the interactive part of the widget instead of the base view.
- Storage and web requests still work in a glance; move CPU-heavy work to a background service.

Minimal glance (from Garmin's "Widget Glances" post):

```monkeyc
using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;

(:glance)
class WidgetGlanceView extends Ui.GlanceView {
    function initialize() {
        GlanceView.initialize();
    }
    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.drawRectangle(0, 0, dc.getWidth(), dc.getHeight());
    }
}
```

```monkeyc
using Toybox.Application;

class WidgetApp extends Application.AppBase {
    function getGlanceView() {
        return [ new WidgetGlanceView() ];
    }
}
```

Performance pattern — cache into a `BufferedBitmap` and **limit its palette** (a real case cut peak memory 29.8 kB → 22.4 kB and fixed OutOfMemory on fēnix 6X):

```monkeyc
bufferedBitmap = new Gfx.BufferedBitmap({:width=>width, :height=>height,
     :palette=>[Gfx.COLOR_DK_GRAY, Gfx.COLOR_LT_GRAY, Gfx.COLOR_BLUE,
                Gfx.COLOR_RED, Gfx.COLOR_BLACK, Gfx.COLOR_WHITE]});
```

### 1.5 Device apps / watch apps (`watch-app`)

- **What**: "by far the most robust type of app available" — most system access: ANT+ sensors, accelerometer, GPS, FIT read/record, BLE, positioning, activity recording.
- **Entry point**: `AppBase.getInitialView()` → `[View, InputDelegate]`.
- **No timeout** when launched from the activity/app list — the user must explicitly back out. **A timeout *is* applied** if launched from the glance list.
- Detect the launch origin:

```monkeyc
class MySuperApp extends Application.AppBase {
    function onStart(state) {
         if ((state != null) && (state.get(:launchedFromGlance)) {
            // Launched from glance
        } else {
            // Launched from activity menu
        }
    }
}
```

- **UX guidance**: the initial view should be a **call to action** (e.g. "press start"); use **page loops** (carousels) for multiple data views; keep long text centred because the top/bottom of round screens have limited viewing area — use the top for headers, scroll arrows and small hints.
- **Complications**: device apps may **publish** up to four complications (API 4.1.0+, `ComplicationProvider`/`ComplicationPublisher` permission).
- From API 4.0.0 a device app can also have a glance.

### 1.6 Audio content providers (`audio-content-provider-app`)

- **What**: plug-ins to the media player on music-enabled wearables; bridge between a streaming service and the Garmin media player. Users pick content, sync it over Wi-Fi, then play offline.
- **Base class**: `Application.AudioContentProviderApp` (instead of `AppBase`).
- **Three contexts**: 1) Playback Configuration, 2) Sync (device enables Wi-Fi, app downloads content), 3) Playback.
- **Required overrides**:

| Method | Purpose |
|---|---|
| `AudioContentProviderApp.getContentDelegate()` | Return a `Media.ContentDelegate` for the system to enumerate media on device |
| `AudioContentProviderApp.getPlaybackConfigurationView()` | Initial view when launched by the media player |
| `AudioContentProviderApp.getProviderIconInfo()` | Provider icon info |
| `AppBase.getSyncDelegate()` | Return a `Communications.SyncDelegate` reporting sync status |

- **Deprecated**: Sync Configuration. Garmin recommends giving the user a download mechanism inside playback configuration instead.
- Only app type with access to `Toybox.Media`. May also publish complications.

### 1.7 Complications (*API 4.1.0 module, 4.2.0 object model*)

Publish/subscribe framework in `Toybox.Complications`.

- **Publishers**: device apps and audio content providers — up to **4** complications each. Permission: `ComplicationProvider` (manifest table) / `ComplicationPublisher` (article text).
- **Subscribers**: **only watch faces**. Permission: `ComplicationSubscriber`.
- **Face It** (Garmin's mobile watch-face builder) is also a consumer of `public` complications.
- **Complication object fields**: `complicationId`, `longLabel`, `shortLabel` (5 chars, for radial display), `unit`, `value`, `ranges`; accessors `getIcon()`, `getType()`.
- **Canonical units** published by the system: `UNIT_DISTANCE`/`UNIT_ELEVATION`/`UNIT_HEIGHT` = meters, `UNIT_SPEED` = m/s, `UNIT_TEMPERATURE` = °C, `UNIT_WEIGHT` = grams. **The subscriber converts to the user's system settings.**
- Subscribing:

```monkeyc
var complication = Complications.getComplication(
    new Id(Complications.COMPLICATION_TYPE_CALORIES)
);
```

```monkeyc
function onStart(params as Dictionary) as Void {
    mComplicationId = Storage.getValue(COMPLICATION_ID_KEY);
    Complications.registerComplicationChangeCallback(
        self.method(:onComplicationChanged));
    Complications.subscribeToUpdates(mComplicationId);
}
```

```monkeyc
function onComplicationChanged(complicationId as Complication.Id) as Void {
    if (complicationId == mComplicationId) {
        try {
            var data = Complications.getComplication(complicationId);
            updateData(complicationId, data);
        } catch (e instanceof ComplicationNotFoundException) {
            handleComplicationRemoval(complicationId);
        }
    }
}
```

- **All subscriptions die at app shutdown and must be re-registered on launch.**
- If the publishing app is uninstalled you get a `ComplicationNotFoundException` and an automatic unsubscribe event.
- Wheelchair mode swaps `COMPLICATION_TYPE_STEPS` and `COMPLICATION_TYPE_FLOORS_CLIMBED` for `COMPLICATION_TYPE_WHEELCHAIR_PUSHES`.
- **Hold-to-launch** from a watch face:

```monkeyc
function onPress(clickEvent as ClickEvent) as Boolean {
    if ((mComplicationId != null) && isClickInside(clickEvent, mBoundingBox)) {
        try {
            Complications.exitTo(mComplicationId);
            return true;
        } catch (e instanceof AppNotInstalledException) { }
    }
    return false;
}
```

The launched publisher gets `:launchedFromComplication` in its `onStart()` state dictionary.

- **Publisher resource definition**:

```xml
<complications>
    <complication id="0" access="public"
                  longLabel="@Strings.myLongLabel"
                  shortLabel="@Strings.myShortLabel"
                  icon="@Drawables.MyComplication"
                  glancePreview="true">
        <faceIt defaultText="@Strings.complicationName" />
        <range>
            <value>0</value><value>24</value><value>33</value>
            <value>41</value><value>50</value><value>53</value>
        </range>
    </complication>
</complications>
```

`id` 0–255 and **must stay stable across versions**. `icon` must be an **SVG** for `public`/`protected` access and cannot change at runtime. Access matrix:

| Access | Your Apps | Face It | All Apps |
|---|---|---|---|
| `public` | X | X | X |
| `protected` | X | X | |
| `private` | X | | |

- **Publishing values**:

```monkeyc
var data = {
    :value => newValue,           // String, Number, Float, Long, Double, or null
    :shortLabel => newShortLabel, // String
    :units => newUnits,           // String or Complication.UNITS_* value
    :ranges => newRanges,         // Array<Numeric>, at least 3 elements
}
Complications.updateComplication(0, data);
```

- Best practice: high-contrast Face It icon that works in mobile light *and* dark mode; Latin characters (A-Z, a-z, 0-9) only in published strings.

### 1.8 Background services (*since API level 2.3.0*)

- Registered by any app type via `Toybox.Background` (permission: `Background`).
- **Entry point**: `AppBase.getServiceDelegate()` → `[System.ServiceDelegate]`; the method matching the trigger is invoked; finish with `Background.exit(data)` (pass `null` for no data).
- **Hard limits**: "Services may be terminated at any time [to] free memory for foreground applications. Services will also be terminated automatically if [they] do not exit properly within **30 seconds** of opening." The background memory pool is far smaller than the app pool — often smaller than the whole executable.
- **`(:background)` annotation** selects what gets compiled into the service. Everything reachable from the service — including the `AppBase` subclass and any globals used in its constructor — must carry it.

| Event | Register with | API Level |
|---|---|---|
| Activity Completed | `Background.registerForActivityCompletedEvent()` | 3.1.0 |
| Goal | `Background.registerForGoalEvent()` | 2.3.0 |
| OAUTH Response | `Background.registerForOAuthResponseEvent()` | 2.3.0 |
| Phone App Message | `Background.registerForPhoneAppMessageEvent()` | 3.2.0 |
| Sleep | `Background.registerForSleepEvent()` | 2.3.0 |
| Steps (every 1000 steps) | `Background.registerForStepsEvent()` | 2.3.0 |
| Temporal (min interval **5 minutes**) | `Background.registerForTemporalEvent()` | 2.3.0 |

```monkeyc
import Toybox.Application;
import Toybox.Background;
import Toybox.System;
import Toybox.Time;

(:background)
var globalMember;

(:background)
class MyApp extends Application.AppBase {
    public function initialize() {
        if(Background.getTemporalEventRegisteredTime() != null) {
            Background.registerForTemporalEvent(new Time.Duration(5 * 60))
        }
        $.globalMember = true;
    }
    public function getServiceDelegate() as [System.ServiceDelegate] {
        return [new MyServiceDelegate()];
    }
}

(:background)
class MyServiceDelegate extends System.ServiceDelegate {
    public function onTemporalEvent() as Void {
        // Do fun stuff here
    }
}
```

With type-check level `informative` or above the compiler flags background code referencing non-background symbols. Simulator: *Simulation* menu → trigger background service manually.

### 1.9 Entry-point summary (UX guidelines)

| Entry point | App types | Notes |
|---|---|---|
| Activity data-field screen | Data fields | API 3.2+: on-device settings flow |
| Activity / app list | Device apps | No timeout; user reorders on device or in Garmin Connect |
| Glance list | Device apps (4.0+), Widgets (3.1+) | Auto-terminates after inactivity |
| Media player | Audio content providers | Initial view handles onboarding/auth |
| Watch face | Watch faces | No user input |
| Widget loop | Widgets | Next/prev from watch face (wearables) or swipe down (Edge); auto-terminates |

---

## 2. The UI Layer

### 2.1 Application lifecycle (`Application.AppBase`)

Every app has exactly one class extending `Application.AppBase`, named in `manifest.xml`'s `entry` attribute. It is reachable throughout via `Application.getApp()`.

Four lifecycle states (*state model formalised in API 4.2.0*): **launched, active, inactive, suspended**.

- `AppBase.onStart(state)` — initialize, restore state. If launched via `System.Intent`, `state` holds the arguments. **Do not push a `WatchUi.View` here.**
- The system then asks for the initial view, per app type: `getInitialView()`, `getGlanceView()`, `getGoalView()`, or the ACP's `getPlaybackConfigurationView()`. All return an **array** of `[View]` or `[View, InputDelegate]`.
- `AppBase.onActive()` / `AppBase.onInactive()` (*4.2.0*) — on devices with a task switcher, when the app moves between active and inactive.
- `AppBase.onStop(state)` — save state. With a task switcher the system may terminate an inactive app and pass `:suspend`; on return `onStart()` receives `:resume`.

```monkeyc
class MyApp extends Application.AppBase {
    function onStart(state) {
        if ((state != null) && (state.get(:resume)) {
                restoreState();
        }
    }
    function onStop(state) {
        if ((state != null) && (state.get(:suspend)) {
            saveState();
        }
    }
}
```

- `AppBase.onAppInstall()` / `AppBase.onAppUpdate()` (*3.0.0*, require `Background` permission) — run in the background on install/update. **Not guaranteed to run** — never depend on them.

**Resource access, active vs inactive** (4.2.0 task-switcher devices):

| Resource | Active | Inactive |
|---|---|---|
| Activity | With permission, start/stop recording | If recording, continues; cannot start/stop |
| GPS | May be denied if another app is recording | If recording + receiving position events, continues; otherwise cannot modify GPS state |
| ANT | May be denied if another app is recording | If recording, permitted; otherwise channels close and reopen on becoming active |
| High-frequency sensors | If recording, permitted; otherwise may fail non-fatally | If recording, permitted; otherwise max **10 Hz** |
| Sensors | If recording, permitted; otherwise may fail non-fatally | If recording, permitted; otherwise limited |
| Attention | Allowed | **Denied** |

### 2.2 View lifecycle (`WatchUi.View`)

A `View` is a page. Views live on a **page stack**.

| Callback | When | Typical use |
|---|---|---|
| `onLayout(dc)` | Once, when the view is laid out | `setLayout(Rez.Layouts.MainLayout(dc))`; create layers |
| `onShow()` | "Called when your `WatchUi.View` is first made visible" | On-demand init of resources and timers |
| `onUpdate(dc)` | "Called when your view needs to update the display" | Call `View.onUpdate(dc)` to draw the layout, then draw dynamic content on top |
| `onHide()` | "Called when your `View` is being removed from the view stack" | Stop timers, release resources |

Stack manipulation: `WatchUi.pushView(view, delegate, transition)`, `WatchUi.popView(transition)`, `WatchUi.switchToView(view, delegate, transition)`. Transitions include `SLIDE_IMMEDIATE`, `SLIDE_UP`, `SLIDE_DOWN`, `SLIDE_LEFT`, `SLIDE_RIGHT`, `SLIDE_BLINK`. UX guidance: menus slide in from the right and dismiss to the right; page loops slide up/down to sell the carousel illusion.

Redraw is requested with **`WatchUi.requestUpdate()`** (no-op in background-update glance mode). `Toybox.Timer` is available to every app type **except data fields**.

**Enhanced Readability Mode** (*4.2.0*): some devices enlarge fonts in menus, glances and app pages. Check `System.DeviceSettings` for `:fontScale`; use `Graphics.getVectorFont()` with `:font` and `:scale`. React at runtime via `AppBase.onEnhancedReadabilityModeChanged()` or `AppBase.onDeviceSettingChanged()`.

### 2.3 Drawables and Layers

- A layout is **an array of `WatchUi.Drawable` objects**; each draws itself via `Drawable.draw(dc)`. Built-ins: `WatchUi.Text`, `WatchUi.Bitmap`.
- **Layers** (*3.1.0*) "fuse multiple levels of drawable content belonging to the same view." They behave more like `Graphics.BufferedBitmap` than `Drawable` and carry **similar memory cost**. Rendered automatically in add order. **Not supported in `GlanceView`.**

```monkeyc
class MyLayerView extends WatchUi.View {
    function initialize() {
        // create a 240x240 layer, at [0,0] offset from the top-left corner of the screen
        var backgroundLayer = new WatchUi.Layer({:x=>0, :y=>0, :width=>240, :height=>240});
        backgroundLayer.getDc().drawBitmap( ... );
        backgroundLayer.getDc().drawPolyline( ... );
        addLayer(backgroundLayer);

        var foregroundLayer = new WatchUi.Layer({:x=>10, :y=>10, :width=>20, :height=>20});
        addLayer(foregroundLayer);
        foregroundLayer.getDc().drawText( ... );
    }
}
```

- `WatchUi.AnimationLayer` + `WatchUi.AnimationResource` overlay animations on view content (or static content over an animation).

### 2.4 Graphics / `Graphics.Dc`

The `Dc` is handed to `onLayout()`, `onUpdate()` and `onPartialUpdate()`. Size via `Dc.getWidth()` / `Dc.getHeight()`.

| Operation | Draw | Fill | API Level |
|---|---|---|---|
| Set pen/fill color | `Dc.setColor()`, `Dc.setStroke()` | `Dc.setColor()`, `Dc.setFill()` | 1.0.0 / 4.0.0 |
| Pen width | `Dc.setPenWidth()` | — | 1.0.0 |
| Clear | — | `Dc.clear()` | 1.0.0 |
| Bitmap | `Dc.drawBitmap()` / `Dc.drawBitmap2()` | — | 1.0.0 / 4.2.0 |
| Text | `Dc.drawText()` | — | 1.0.0 (only honours `setColor()`) |
| Point / Line | `Dc.drawPoint()`, `Dc.drawLine()` | — | 1.0.0 |
| Circle / Ellipse | `Dc.drawCircle()`, `Dc.drawEllipse()` | `Dc.fillCircle()`, `Dc.fillEllipse()` | 1.0.0 |
| Rectangle / rounded | `Dc.drawRectangle()`, `Dc.drawRoundedRectangle()` | `Dc.fillRectangle()`, `Dc.fillRoundedRectangle()` | 1.0.0 |
| Arc | `Dc.drawArc()` | — | 1.0.0 |
| Polygon | — (no draw) | `Dc.fillPolygon()` | 1.0.0 |
| Clip | `Dc.setClip()` / `Dc.clearClip()` | — | 2.3.0 |

Text metrics: `Dc.getTextDimensions()`, `Dc.getTextWidthInPixels()`, `Dc.getFontHeight()` / `Graphics.getFontHeight()` (1.2.0), `Graphics.getFontAscent()` / `getFontDescent()` (1.2.0).

- **Scalable (vector) fonts** (*4.2.2*): `Graphics.getVectorFont({:face=>..., :size=>...})`; `:face` accepts an array of fallback face names. Only available where the Device Reference lists `Scalable Font` entries. `Dc.drawAngledText()` and `Dc.drawRadialText()` (*4.2.2*) **only** work with scalable fonts, never with custom `.fnt` resources.
- **Anti-aliasing** (*3.2.0*), guard with `has`:

```monkeyc
function draw(dc) {
    if(dc has :setAntiAlias) {
        dc.setAntiAlias(true);
    }
    dc.drawPolygon()
}
```

- **Alpha / stroke / fill / blend** (*4.0.0*): `Dc.setFill()` and `Dc.setStroke()` take **32-bit AARRGGBB** and also accept a `Graphics.BitmapTexture`. `Dc.setBlendMode()` supports `BLEND_MODE_NO_BLEND` (write colour+alpha straight into a `BufferedBitmap`) and `BLEND_MODE_ADDITION`.
- **Graphics pool** (*4.0.0*): bitmaps and fonts loaded at runtime go into a pool **separate from the application heap**; you get a `Graphics.ResourceReference`. The pool caches, purges and reloads automatically. `ResourceReference.get()` locks the resource while the returned object is in scope. **Purged `BufferedBitmap`s are *not* restored** (unlike static resources) — you must re-render them.
- **BufferedBitmap** (*2.3.0*): off-screen surface, from a bitmap resource or from `{:width, :height, :palette}`. `getDc()`, `getPalette()`, `setPalette()` (new palette must have the same colour count). Resource-compiled palettes get an extra transparent index at the end unless `disableTransparency` is set.

```monkeyc
import Toybox.Graphics;

//! Factory function to create buffered bitmap
function bufferedBitmapFactory(options as {
            :width as Number, :height as Number,
            :palette as Array<ColorType>, :colorDepth as Number,
            :bitmapResource as WatchUi.BitmapResource
        }) as BufferedBitmapReference or BufferedBitmap {
    if (Graphics has :createBufferedBitmap) {
        return Graphics.createBufferedBitmap(options);
    } else {
        return new Graphics.BufferedBitmap(options);
    }
}
```

- **Transforms** (*4.2.2*): `Graphics.AffineTransform` (rotate, scale, shear) passed as `:transform` to `Dc.drawBitmap2()`.
- **Tinting** (*4.2.2*): `:tintColor` on `Dc.drawBitmap2()` recolours a grayscale asset — the recommended way to theme complication icons.

### 2.5 Layouts in XML

```xml
<resources xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:noNamespaceSchemaLocation="http://developer.garmin.com/downloads/connect-iq/resources.xsd">
    <layout id="MainLayout">
        <drawable id="MainBackground" />
        <label text="Page Heading" x="10" y="25" font="Gfx.FONT_LARGE" color="Gfx.COLOR_BLACK" />
        <label text="Your information goes here." x="50%" y="50%" font="Gfx.FONT_MEDIUM" color="Gfx.COLOR_DK_GRAY" />
    </layout>
</resources>
```

```monkeyc
class MainView extends WatchUi.View {
    public function onLayout( dc as Dc ) as Void {
        setLayout( Rez.Layouts.MainLayout( dc ) );
    }
    public function onUpdate( dc as Dc) as Void {
        // Call parent's onUpdate(dc) to redraw the layout
        View.onUpdate( dc );
        // Include anything that needs to be updated here
    }
}
```

**Draw order is document order** — a later drawable paints over an earlier one.

- **`<label>`** attributes: `id`, `text`, `font`, `x`, `y` (pixel, `%`, `center`/`left`/`right`/`start`, `center`/`top`/`bottom`/`start`), `justification` (default `Graphics.TEXT_JUSTIFY_LEFT`), `color` (default `COLOR_WHITE`), `background` (default `COLOR_TRANSPARENT`), `visible` (**3.3.0+ only**).
- **`<text-area>`** (*3.1.0*): adds `width`/`height` (pixel, `%`, or `fill`) and auto-fits by choosing a font, wrapping, or truncating. Font sequence:

```xml
<text-area id="BlockOfText" text="Lorem ipsum dolor sit amet, consectetur adipiscing elit." x="10%" y="10%" width="80%" height="80%">
    <fonts>
        <font>Gfx.FONT_MEDIUM</font>
        <font>@Rez.Fonts.MySmallFont</font>
        <font>Gfx.FONT_XTINY</font>
    </fonts>
</text-area>
```

- **Font references**: system (`Graphics.FONT_SMALL`), custom (`@Rez.Fonts.MySmallFont`), scalable (`"#BionicBold,Roboto:12"`).
- **`<drawable-list>`** with `<shape>` and `<bitmap>` children:

```xml
<drawable-list id="Smiley" background="Gfx.COLOR_YELLOW">
    <shape type="circle" x="10" y="10" radius="5" color="Gfx.COLOR_BLACK" />
    <shape type="circle" x="30" y="10" radius="5" color="Gfx.COLOR_BLACK" />
    <bitmap id="mouth" x="15" y="25" filename="../bitmaps/mouth.png" />
</drawable-list>
```

```monkeyc
function onUpdate( dc as Dc ) as Void {
    var mySmiley = new Rez.Drawables.Smiley();
    mySmiley.draw( dc );
}
```

`<shape type>` ∈ `rectangle | ellipse | circle | polygon`; attributes `x, y, points, width, height, a, b, color, corner_radius, radius, border_width, border_color`. Polygons need ≥3 points; `border_*` is not valid on polygons.

- **Custom drawables** via `class`, with `<param>` children:

```xml
<layout>
    <drawable id="MoveBar" class="CustomMoveBar">
        <param name="color">Gfx.COLOR_RED</param>
        <param name="string">"Hello Custom Drawable!"</param>
    </drawable>
</layout>
```

```monkeyc
import Toybox.WatchUi;

class CustomMoveBar extends WatchUi.Drawable {
    private var _color, _string;
    public function initialize(params as Dictionary) {
        Drawable.initialize(params);
        _color = params.get(:color);
        _string = params.get(:string);
    }
    function draw(dc as Dc) as Void {
        // Draw the move bar here
    }
}
```

Param names arrive as **symbols**; values are pasted verbatim, so strings must be quoted inside the XML.

### 2.6 Resources and the `Rez` module

```xml
<resources xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:noNamespaceSchemaLocation="http://developer.garmin.com/downloads/connect-iq/resources.xsd">
    <bitmap id="bitmap_id" filename="path/for/image" />
    <font id="font_id" filename="path/to/fnt" />
    <string id="string_id">Hello World!</string>
</resources>
```

- The resource compiler generates module **`Rez`**; IDs are of type `Lang.ResourceId`.
- Load with `WatchUi.loadResource()` (1.0.0) or `Application.loadResource()` (3.1.0 — moved because `Toybox.WatchUi` is unreachable from background services).

```monkeyc
image = Application.loadResource( Rez.Drawables.bitmap_id ) as BitmapResource;
dc.drawBitmap( 50, 50, image );
```

> "Resources are reference counted just like other Monkey C objects. Loading a resource can be an expensive operation, so **do not load resources when handling screen updates**."

- **Cross-references inside resource files**: `@<module>.<id>`, e.g. `label="@Strings.menu_item_1_label"`.

**Resource scopes** (*3.1.0*) — on `<layout>`, `<drawable-list>`, `<bitmap>`, `<string>`, `<font>`, `<jsonData>`. Values: `background`, `glance`, `foreground` (default).

```xml
<string id="MyBackgroundString" scope="background">Background String</string>
<string id="MyGlanceString" scope="glance">Glance String</string>
<string id="MyForegroundString" scope="foreground">Foreground String</string>
```

| Application Mode | MyBackgroundString | MyGlanceString | MyForegroundString |
|---|---|---|---|
| Background Service | X | | |
| Glance | X | X | |
| Foreground | X | X | X |

Strings additionally support `scope="settings"` (removed from the runtime entirely) and `translatable="false"`.

**Bitmaps**: compiler accepts `JPG/JPEG`, `BMP/WBMP`, `GIF`, `SVG`, `PNG`. Attributes: `id`, `filename`, `dithering` (`floyd_steinberg` | `none`), `compress`, `automaticPalette` (defaults `true` on 16-bit colour devices, caps at 256 colours), `packingFormat`, `scaleX`, `scaleY`, `scaleRelativeTo` (`screen` | `image`), `personality`. Optional `<palette disableTransparency="false">` with `<color>` children maps developer colours to the nearest device colours.

```xml
<bitmap id="bitmap_id" filename="path/for/image">
    <palette disableTransparency="false">
        <color>FF0000</color>
        <color>FFFFFF</color>
        <color>0000FF</color>
    </palette>
</bitmap>
```

**Bitmap packing formats** (*4.0.0*):

| Format | Advantage | Disadvantage | Use case |
|---|---|---|---|
| `default` | On all products, fastest load, alpha | No compression | Pre-4.0 devices; low-palette images |
| `png` | Lossless, compressed, alpha | Slowest to load (costly if purged/reloaded from the pool) | Non-photo images |
| `jpg` | Compresses very well, fast | Lossy, **no alpha** | Photos without alpha |
| `yuv` | Compresses well, alpha, fast | Lossy | Photos with alpha |

**Fonts**: `.fnt`/`.png` from **BMFont** (angelcode.com), exported with the **Unicode** character set. Defaults to non-anti-aliased 1-bit to save RAM.

```xml
<font id="font_id" filename="roboto.fnt" antialias="true" />
<font id="font_id" filename="big_font.fnt" filter="0123456789:"/>
```

Attributes: `id`, `filename`, `filter`, `antialias` (default `false`), `scope`, `personality`.

**JSON data** — big lookup tables kept out of RAM until needed:

```xml
<jsonData id="jsonDictionary">{"key":"value", "3":"three", "three":3}</jsonData>
<jsonData id="jsonArray">[1,2,3,4,5,6]</jsonData>
<jsonData id="jsonMix">[1,{"1":"one"},["a","b","c"]]</jsonData>
<jsonData id="jsonPrimitive">5</jsonData>
<jsonData id="jsonFile" filename="data.json"/>
```

```monkeyc
var array = Application.loadResource(Rez.JsonData.jsonArray);
```

**Animations** (*3.1.0*) — Monkey Motion tool, imports `YUV`/`GIF`; alpha supplied as a second greyscale YUV.

```bash
ffmpeg -i input.mp4 -vf format=yuv420p output.y4m
ffmpeg -i input.gif -vf alphaextract,format=yuv420p output.y4m
```

```xml
<animation id="swirl" filename="swirl.mmm" />
```

```monkeyc
class MyAnimationView extends WatchUi.View {
   var mySwirl;
   function initialize( dc ) {
       var dev = System.getDeviceSettings();
       var x = ( dev.screenWidth - mySwirl.getWidth() ) / 2;
       var y = ( dev.screenHeight - mySwirl.getHeight() ) / 2;
       mySwirl = new WatchUi.AnimationLayer(Rez.Drawables.swirl, {:locX=>x, :locY=>y});
       view.addLayer( mySwirl );
    }
    function onShow() { mySwirl.play(); View.onShow(); }
    function onUpdate(dc) { dc.clear(); }
}
```

### 2.7 Resource qualifiers (device / family / language)

Folder naming: `resources[-<device|family>][-<lang>]`.

- **Device qualifier**: `resources-fenix5`. Highest precedence.
- **Family qualifiers**: screen shape first, then optional size.
  - `resources-round` — valid
  - `resources-round-218x218` — valid
  - `resources-218x218` — **invalid** (no shape)
  - `resources-218x218-round` — **invalid** (shape not first)
  - `resources-round-fenix3` — **invalid**: device and family qualifiers cannot co-exist; silently skipped.
- **Localization qualifiers** (ISO 639-2) always come last: `resources-fre`, `resources-round-fre`, `resources-fenix5s-fre`.
- Precedence: device > more-specific family > less-specific family > base. Untranslated strings fall back to the base-language file.

**Supported language qualifiers**: `ara bul ces dan deu dut eng est fin fre hrv hun ind ita jpn kor lav lit nob pol por slo slv spa swe rus ron tha tur ukr vie zsm zhs zht` (plus the unqualified base). "All Connect IQ devices support English, but not all devices support all languages."

### 2.8 Jungles (build configuration)

```
base.sourcePath = source

# Configure paths based on screen shape
round.resourcePath = $(base.resourcePath);resource-round
semiround.resourcePath = $(base.resourcePath);resource-semiround
rectangle.resourcePath = $(base.resourcePath);resource-rectangle

# Set the venu source and resource paths
venu.sourcePath = $(base.sourcePath);source-venu
venu.resourcePath = $(base.resourcePath);resource-venu
```

Prefixes: `base`, `round`, `semiround`, `rectangle`, `semioctagon`, `<product id>`. Shape prefixes accept an optional `-<width>x<height>` suffix.

Annotation-based dead-code elimination:

```monkeyc
(:roundVersion)
function drawThis(dc) { /* Implementation */ }

(:regularVersion)
function drawThis(dc) { }
```

```
base.excludeAnnotations = roundVersion
round.excludeAnnotations = regularVersion
```

Jungles also declare Monkey Barrels (shareable libraries) and the `personality` selector chain.

### 2.9 Manifest

```xml
<iq:products>
    <iq:product id="round-watch"/>
</iq:products>

<iq:permissions>
    <iq:uses-permission id="Sensor"/>
</iq:permissions>

<iq:barrels>
    <iq:depends name="Barcode" version="2.0.0"/>
</iq:barrels>
```

- `id` = 128-bit UUID; `entry` = the `AppBase` class; `name` must reference a **string** resource; `launcherIcon` a **bitmap** resource (auto-sized per product; **do not reuse that resource elsewhere in the app** — duplicate it).
- `minApiLevel` — micro version is written (e.g. `1.2.1`) but **only major.minor are considered** for device support.
- Barrel version syntax: exact `"1.2.3"`, minimum `">=1.2.3"`, pessimistic `"~>1.2.3"`, or omitted (unenforced).

**Permissions by app type**:

| Permission | API Level | Watch Face | Data Field | Widget | App | ACP |
|---|---|---|---|---|---|---|
| Ant | 1.0.0 | | x | x | x | x |
| Background | 2.3.0 | x | x | x | x | x |
| BluetoothLowEnergy | 3.1.0 | | x | x | x | x |
| Communications | 1.0.0 | x¹ | x¹ | x | x | x |
| ComplicationProvider | 4.1.0 | | | | x | x |
| ComplicationSubscriber | 4.1.0 | x | | | | |
| Data Field Alert | 3.2.0 | | x | | | |
| Fit | 1.0.0 | | | | x | |
| PersistedContent | 2.2.0 | | | x | x | x |
| Positioning | 1.0.0 | x² | x² | x | x | x² |
| Sensor | 1.0.0 | | x | x | x | x |
| SensorHistory | 2.1.0 | | | x | x | x |
| SensorLogging | 2.3.0 | | | | | |
| UserProfile | 1.0.0 | x | x | x | x | x |

¹ Communications requires the Background permission; Authentication does not.
² Only widgets and apps may call `Position.enableLocationEvents()`.

An app holding the `Fit` permission shows in the device's **Activities** list rather than the apps list.

### 2.10 Input handling

**Per app type**: a watch face only learns it was **pressed** (`WatchFaceDelegate.onPress()`); a data field only learns it was **tapped** (`InputDelegate.onTap()`); widgets and glances receive input (glances: none at all); watch apps have the most.

**`WatchUi.InputDelegate` (low level)**:

| API | Purpose | API Level |
|---|---|---|
| `onDrag()` | Dragging the touch screen | 3.3.0 |
| `onFlick()` | Flick on the touch screen | 3.3.0 |
| `onKey()` | Physical button pressed **and released** | 1.0.0 |
| `onKeyPressed()` | Button pressed down | 1.1.2 |
| `onKeyReleased()` | Button released | 1.1.2 |
| `onTap()` | Quick touch and release | 1.0.0 |
| `onHold()` | Touched and not released | 1.0.0 |
| `onRelease()` | Only after `onHold()` | 1.0.0 |
| `onSwipe()` | Swipe | 1.0.0 |
| `onSelectable()` | `WatchUi.Selectable` state changed | 2.1.0 |

Return `true` = handled; `false` = let the system handle it.

**`WatchUi.BehaviorDelegate` (high level, superclass of `InputDelegate`)** — portable intent, not raw input:

| API | Purpose |
|---|---|
| `onBack()` | Back behavior |
| `onMenu()` | Menu behavior |
| `onNextPage()` | Next page in a page loop |
| `onPreviousPage()` | Previous page |
| `onSelect()` | Select |

All 1.0.0. **Prefer `BehaviorDelegate` for portable code** across touch and button devices.

**Selectables and Buttons** (*2.1.0*): `WatchUi.Selectable` has four states — `:stateDefault`, `:stateHighlighted`, `:stateSelected`, `:stateDisabled` — each mapped to a `Drawable`, a `Graphics.COLOR` constant, or `0xRRGGBB`. Selectables **must** be registered through `View.setLayout()`; stacked selectables resolve last-in-first-drawn/selected. `WatchUi.Button` extends `Selectable` and binds a behaviour method. `View.setKeyToSelectableInteraction()` lets up/down keys cycle highlight on **button-only** products — the key bridge for one UI across both input styles.

```xml
<layout id="ButtonLayout">
    <button x="40" y="center" width="50" height="50" background="Gfx.COLOR_BLACK" behavior="onBack">
        <state id="stateDefault" bitmap="@Drawables.DefaultBackButton" />
        <state id="stateHighlighted" bitmap="@Drawables.PressedBackButton" />
        <state id="stateSelected" bitmap="@Drawables.PressedBackButton" />
        <state id="stateDisabled" color="Graphics.COLOR_BLACK" />
    </button>
    <button x="115" y="center" width="50" height="50">
        <state id="stateDefault" bitmap="@Drawables.DefaultMenuButton" />
        <state id="stateHighlighted" bitmap="@Drawables.PressedMenuButton" />
        <state id="stateSelected" bitmap="@Drawables.PressedMenuButton" />
        <state id="stateDisabled" color="Graphics.COLOR_BLACK" />
        <param name="background">Graphics.COLOR_BLACK</param>
        <param name="behavior">onMenu</param>
    </button>
</layout>
```

### 2.11 Native controls

**Menu2** (*3.0.0*) — `WatchUi.Menu2`, `WatchUi.MenuItem`, `WatchUi.IconMenuItem`, `WatchUi.ToggleMenuItem`, `WatchUi.CheckboxMenu`, `WatchUi.CheckboxMenuItem`, handled by `WatchUi.Menu2InputDelegate` (`onSelect()`, `onBack()`, `onDone()` — the latter two pop the page if not overridden).

```monkeyc
import Toybox.WatchUi;

class MyBehaviorDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }

    function onMenu() as Boolean{
        var menu = new WatchUi.Menu2({:title=>"My Menu2"});
        var delegate;
        menu.addItem(new MenuItem("Item 1 Label", "Item 1 subLabel", "itemOneId", {}));
        menu.addItem(new MenuItem("Item 2 Label", "Item 2 subLabel", "itemTwoId", {}));
        delegate = new MyMenu2Delegate();
        WatchUi.pushView(menu, delegate, WatchUi.SLIDE_IMMEDIATE);
        return true;
    }
}
```

```xml
<menu2 id="MainMenu" title="@Strings.MainMenuTitle">
  <menu-item id="generic1" label="Generic 1" subLabel="With Sublabel"></menu-item>
  <menu-item id="generic2" label="Generic 2"></menu-item>
</menu2>
```

```xml
<checkbox-menu id="CheckMenu" title="@Strings.CheckMenuTitle">
    <checkbox-menu-item id="defaultAlign" label="@Strings.CheckDefaultLabel"
     subLabel="@Strings.CheckDefaultSubLabel" checked="true" />
    <checkbox-menu-item id="right" label="@Strings.CheckRightLabel"
     subLabel="@Strings.CheckRightSubLabel" checked="false">
        <param name="alignment">Ui.MenuItem.MENU_ITEM_LABEL_ALIGN_RIGHT</param>
    </checkbox-menu-item>
</checkbox-menu>
```

```xml
<menu2 id="ToggleMenu" title="@Strings.ToggleMenuTitle">
    <toggle-menu-item id="defaultAlign" label="@Strings.ToggleLabel1"
     subLabel="@Strings.ToggleOnSubLabel" disabledSubLabel="@Strings.ToggleOffSubLabel" checked="true" />
</menu2>
```

```xml
<menu2 id="IconMenu" title="@Strings.IconMenuTitle">
    <icon-menu-item id="defaultAlign" label="@Strings.IconDefaultLabel"
     subLabel="@Strings.IconDummySubLabel" icon="@Drawables.LauncherIcon" />
    <icon-menu-item id="right" label="@Strings.IconRightLabel"
     subLabel="@Strings.IconDummySubLabel" icon="@Drawables.LauncherIcon">
        <param name="alignment">WatchUi.MenuItem.MENU_ITEM_LABEL_ALIGN_RIGHT</param>
    </icon-menu-item>
</menu2>
```

`<menu2>` attributes: `id` (required), `title`, `icon` (**Instinct 2 sub-screen only**), `dividerType` (*5.0.1+*, default `DIVIDER_TYPE_DEFAULT`), `theme` (default `MENU_THEME_DEFAULT`), `personality`. `<menu-item>`: `id`, `label` (required), `subLabel`, `icon`, `personality`. Toggle adds `disabledSubLabel` and `checked`.

**Action menus** (*3.4.0*) — contextual menu attached to a page; `WatchUi.showActionMenu()`; resource `<action-menu theme="WatchUi.ACTION_MENU_THEME_DARK|_LIGHT">` with `<action-menu-item id label personality>` children. Theme is not configurable on all products.

**Legacy `WatchUi.Menu`** (still valid, `MenuInputDelegate.onMenuItem(item)`):

```xml
<menu id="MainMenu">
    <menu-item id="item_1" label="@Strings.menu_item_1_label" />
    <menu-item id="item_1" label="@Strings.menu_item_2_label" />
</menu>
```

```monkeyc
class MyView extends WatchUi.View {
    function openTheMenu() {
        WatchUi.pushView( new Rez.Menus.MainMenu(), new MyMenuDelegate(), Ui.SLIDE_UP );
    }
}

class MyMenuDelegate extends WatchUi.MenuInputDelegate {
    function onMenuItem(item) {
        if ( item == :item_1 ) {
            // Do something here
        } else if ( item == :item_2 ) {
            // Do something else here
        }
    }
}
```

**Pickers**: `WatchUi.Picker` + `WatchUi.PickerDelegate` + `WatchUi.PickerFactory`. Layout = title bar, up/down arrows, previous selection, current selection (centre), next item or confirm.

**Confirmation**: `WatchUi.Confirmation` + `WatchUi.ConfirmationDelegate` — simple yes/no.

**Progress bar**: full-page wait dialog; two modes (percent and indeterminate). Appearance is device-specific.

**ViewLoop**: `WatchUi.ViewLoop` — carousel of views; past the last page it wraps to the first.

**Toasts** (*3.4.0*): `WatchUi.showToast()` — partial-screen banner with text and optional icon; auto-dismisses, takes no input.

**Maps** (*3.0.0*): `WatchUi.MapView` (static), `WatchUi.MapTrackView` (live position), `WatchUi.MapPolyline`, `WatchUi.MapMarker`.

```monkeyc
import Toybox.WatchUi;
import Toybox.Position;

class MyMapView extends MapView {
    function initialize() {
        MapView.initialize();
        var topLeft = new Position.Location({:latitude => 38.85695,
         :longitude =>-94.80051, :format => :degrees});
        var bottomRight = new Position.Location({:latitude => 38.85391,
         :longitude =>-94.7963, :format => :degrees});
        MapView.setMapVisibleArea(topLeft, bottomRight);
        MapView.setScreenVisibleArea(0, 0, 240, 240/2);
        MapView.setMapMode(WatchUi.MAP_MODE_PREVIEW);
    }
}
```

```monkeyc
var polyline = new WatchUi.MapPolyline();
polyline.setColor(Toybox.Graphics.COLOR_RED);
polyline.setWidth(2);
polyline.addLocation(new Position.Location({:latitude => 38.85391, :longitude =>-94.79630, :format => :degrees}));
polyline.addLocation(new Position.Location({:latitude => 38.85465, :longitude =>-94.79922, :format => :degrees}));
MapView.setPolyline(polyline);
```

```monkeyc
var bitmapMarker = new WatchUi.MapMarker(
    new Position.Location({:latitude => 38.85391, :longitude =>-94.79630, :format => :degrees}));
bitmapMarker.setIcon(WatchUi.loadResource(Rez.Drawables.MapPin), 12, 24);
bitmapMarker.setLabel("Custom Icon");

var defaultMarker = new WatchUi.MapMarker(
    new Position.Location({:latitude => 38.85508, :longitude =>-94.79959, :format => :degrees}));
defaultMarker.setIcon(WatchUi.MAP_MARKER_ICON_PIN, 0, 0);
defaultMarker.setLabel("Predefined Icon");

var markers = [];
markers.add(bitmapMarker);
markers.add(defaultMarker);
MapView.setMapMarker(markers);
```

Modes: `MAP_MODE_PREVIEW` (fixed) and `MAP_MODE_BROWSE` (pan/zoom); tracking centres on GPS. Simulator map-coverage overlay: green = low detail, blue = medium, red = high.

### 2.12 Getting the user's attention (`Toybox.Attention`)

`Attention.backlight()`, `Attention.setFlashlightMode()`, `Attention.playTone()`, `Attention.vibrate()` — all 1.0.0 (flashlight enums 4.2.0). Backlight brightness 0.0–1.0 from 3.2.0 (boolean before). **Attention is denied while the app is inactive.** MIP: keep backlight off by default. AMOLED: extended full brightness can damage the display. Flashlight: `FLASHLIGHT_MODE_OFF/ON/STROBE`, colours white/green/red (device dependent), strobe `BLINK`/`PULSE`/`BLITZ` at `SLOW`/`MEDIUM`/`FAST`.

### 2.13 Persisting data

- `Application.Storage.getValue()/setValue()` (*2.4.0*) — runtime read/write, app-private. Types: Number, Float, Long, Double, Char, String, Boolean, plus Array/Dictionary **of those types only** (no symbols inside). **Limits: 8 KB per key/value pair, 128 KB total.**
- `Application.Properties.getValue()/setValue()` (*2.4.0*) — build-time-defined settings; writing an undefined property throws.
- Legacy `AppBase.getProperty()/setProperty()` (1.0.0) — object store, lives in RAM until the app exits, costs runtime memory.

```monkeyc
Storage.setValue("location", locationValue.toDegrees());
var myLastLocation = Application.Storage.getValue("location");
```

```monkeyc
if ( Toybox.Application has :Storage ) {
    // use Storage and Properties methods
} else {
    // use AppBase methods
}
```

---

## 3. Device Diversity

### 3.1 Screen shapes

Four shapes, used both as jungle prefixes and resource-family qualifiers:

- `round`
- `semiround` (semi-round)
- `rectangle` (rectangle/square)
- `semioctagon` (octagon with sub-window — the Instinct family; note its second sub-screen, which is why `icon` attributes exist on menus/menu items "for Instinct 2 sub-screen")

### 3.2 Screen sizes and display technology

- Resolutions span **163×156 (Instinct 2S)** to **480×800 (Montana 7, Edge 1050)**.
- Display types: **AMOLED**, **Memory-in-Pixel (MIP)** at various colour depths, **transflective LCD**.
- Colour capability from the Device Reference: **2, 8, 14, 64 … 65536 colours**.
- MIP palettes: standard MIP = 64 colours; **Forerunner 45/55 = 8 colours** (`0xFFFFFF, 0xFFFF00, 0xFF00FF, 0xFF0000, 0x00FFFF, 0x00FF00, 0x0000FF, 0x000000`).
- MIP is reflective (brightest outdoors, low power, limited palette); AMOLED/LCD are emissive (vibrant, many colours, higher power outdoors).

### 3.3 Input

- Device Reference lists per-device **touch screen yes/no**, **icon size**, and the **button set** (typical: `down, enter, esc, menu, up`; cycling/nav devices add `lap`, `start`).
- Three canonical input configurations (UX guidelines):
  - **Five-button**: top-left backlight (hold = controls), middle-left prev/up (hold = menu), bottom-left next/down, top-right select (often start/stop), bottom-right back.
  - **Touchscreen two-button**: top start/stop (hold = controls), bottom back (hold = menu); swipe up = prev, swipe down = next, tap = select, swipe right-to-left = back, drag/flick = navigate.
  - **Touchscreen one-button (Edge)**: swipe left-to-right = prev, right-to-left = next, tap = select, on-screen back button, on-screen hamburger = menu.

### 3.4 Memory tiers

Garmin does not publish a single public memory table on the web; per-device budgets live in the SDK/simulator (*View Memory* → **Peak Memory**) and in `System.getSystemStats()`. Documented anchor points:

- **Glance mode: 32 KB on most devices** (official; the fēnix 6X case study crashed at 28.6 kB peak and was safe at 22.4 kB).
- Background services: a much smaller pool than the app pool, "in many instances, the executable code of your application will be larger than the memory pool available."
- Illustrative device extremes (Garmin forum, `System.getSystemStats().totalMemory`):
  - **epix (gen 1)**: watch face / watch app / widget **1,048,576 B (1 MB)**; data field **131,072 B (128 KB)**.
  - **Forerunner 920XT**: watch face / watch app / widget **65,536 B (64 KB)**; data field **16,384 B (16 KB)**.
  - CIQ 1.x VM devices: data fields ≈16 KB. CIQ 2.x VM devices: data fields ≈26 KB. Edge/Oregon/Rino handhelds get larger data-field budgets.
- There is also an **object-count ceiling** (reported around 256 live objects) that can trigger failures well below the byte limit.
- From API 4.0.0 the **graphics pool** is separate from the application heap, which materially changes the practical budget for bitmap-heavy apps.

### 3.5 API levels

- Range currently in the field: **1.2 through 6.0** (per the Compatible Devices filter); SDK 9.2.0.
- `minApiLevel` in the manifest gates which products you can target; **only major.minor count**.
- Guard everything newer than your `minApiLevel` with `has` checks: `if (dc has :setAntiAlias)`, `if (Graphics has :createBufferedBitmap)`, `if (Toybox.Application has :Storage)`, `if (Styles.system_input__action_menu has :button)`.

### 3.6 Targeting many devices — the toolkit

1. **`BehaviorDelegate`** instead of `InputDelegate` wherever possible.
2. **Relative coordinates** (`50%`, `center`, `fill`) in layouts rather than pixels.
3. **Resource qualifier folders** for device / shape / size / language.
4. **Jungles** for per-device source and resource paths plus `excludeAnnotations` dead-code elimination.
5. **`SimpleDataField`** to inherit native layout handling for free.
6. **`View.setKeyToSelectableInteraction()`** to make one touch-oriented layout work on button-only devices.
7. **Monkey Style / Personality UI** to move device variance out of code into compile-time constants.
8. **Device Reference** table (shape, size, touch, colours, icon size, buttons) and the **Compatible Devices** filter (device type, min API level) to pick your target set.

---

## 4. UX Guidelines and Personality Library

### 4.1 The four-step design process

1. Understanding what you are building
2. Developing the concepts
3. Designing workflows and interactions
4. Incorporating the visual design and product personalities

**Understanding what you are building**: "Focus on the 'jobs' they are 'hiring' your app to do." "Apps on Garmin devices should be focused on presenting key information to the user quickly and with minimal interaction." Reserve deep features for mobile/web. Six common use cases: custom watch faces, third-party sensors, workout content, new activities (dance, inline skating), extending an existing service to a 24/7 wearable, music services.

**Developing the concepts**: choose the app type from the user goal. "Information forward" — key data immediately, limited interaction for depth.

**Designing workflows**: limit hierarchy depth; standard behaviours = Select, Start/Stop, Next/Previous, Back, Menu. Patterns = page loops, dialogs, progress bars, confirmations, selection menus, settings menus. Mobile settings value types: Boolean, Number, Text, Phone, Email, URL, Date, Password. Mobile auth is OAuth2 through the phone browser.

Best practices: get to information in **3–4 interactions**; use **up/down page loops** (more portable than left/right); keep on-screen buttons obvious; minimise interaction during activity; avoid on-device text entry — push it to mobile settings; use native menus/confirmations/progress bars; never break standard back behaviour; the app must be usable **before** the user configures mobile settings.

**Views**: full-screen canvases on a stack; back pops. Transitions: immediate, slide (L/R/T/B), blink. Provide **interaction hints** when you cannot show content and navigation together.

**Menus**: group into categories, **max ~7 items per list**; toggles for on/off, checkboxes for multi-select; secondary menus show the current selection as subtext; custom footer hints for "more below".

**Confirmations**: "Confirmations add friction to the experience, so only use them when the friction is necessary." Button labels may be Yes/No **or** product-specific glyphs — design for both. Phrase as an unambiguous yes/no question.

**Progress bars**: percent and infinite. Always provide a back behaviour to cancel; be informative; represent chained processes in one bar (or use infinite) and update the message.

**Map views**: preview / browse / tracking modes; bitmaps and polylines overlay the native cartography.

**Localization**: check user settings before showing distance, elevation, height, pace, temperature or weight; allow for text expansion/contraction (test in the simulator); consider cultural meanings of icons and colours; support multiple date formats; minimise text input.

### 4.2 Visual design and product personality

- **Themes**: dark-on-light is "used predominately during activities to provide better contrast" and suits MIP outdoors; **light-on-dark is the default for AMOLED/LCD** (better battery, allows imagery). Edge products theme adaptively (white/black by day, black/white by night).
- **Typography**: the system provides a **text font** and a **number font**, each in several sizes, pre-tested for readability — prefer them. Custom typefaces import at a **single point size** — use them as accents or branding.
- **Headers/footers**: solid colour on MIP; **gradient fading to black** on LCD/AMOLED.
- **Imagery**: subtle backgrounds only on LCD/AMOLED.
- Best practices: show the same content regardless of display size; put critical information where it is seen first; pick one brand theme colour for icons and headers; keep text short or split across pages because typeface sizes vary per device.

### 4.3 Monkey Style (`.mss`)

CSS-like property language producing **compile-time constants** — no runtime heap cost.

```
personality_class {
    property: "constant";
}
```

Value types: Number `500`, Percent `80%`, String, Boolean, Color `#555555`, Symbol `:myBitmap`, Resource `@Rez.Strings.promptTitle`, API constant `Graphics.TEXT_JUSTIFY_CENTER`, Array `[Graphics.FONT_SMALL, Graphics.FONT_TINY]`.

```
layout1__time {
    x: "center";
    y: 10%;
    font: Graphics.FONT_LARGE;
    justification: Graphics.TEXT_JUSTIFY_CENTER;
    color: Graphics.COLOR_BLUE;
}
```

```xml
<layout id="WatchFace">
    <drawable class="Background" />
    <label id="TimeLabel" personality="layout1__time" />
</layout>
```

```monkeyc
dc.setFont(Rez.Styles.layout1__time.font);
```

```
fenix7system6preview.personality=$(fenix7system6preview.personality);resources-fenix2022
```

The `personality` attribute is available on `<bitmap>`, `<font>`, `<menu2>`, `<menu-item>`, `<action-menu>`, `<action-menu-item>`, `<animation>` and layout elements, and accepts **multiple space-separated classes**.

### 4.4 Personality UI library

Introduced with **Connect IQ System 6**; "combines a style language with a design library to better facilitate separation of view and business logic." Requires `minApiLevel` **3.4.0**.

Components: Colors, Iconography, Typography, Input Hints, Prompts, Confirmations, Toasts, Action Views, Page Loops, Progress Indicators.

Project shape: `strings.xml`, `layout.xml`, `menus.xml`, `personality.mss`, `View.mc`, `InputDelegate.mc`, plus per-device `resources-<device>/personality.mss` overrides wired in the jungle:

```
venu2.personality=$(venu2.personality);resources-venu2022
venu2s.personality=$(venu2s.personality);resources-venu2022
venu2plus.personality=$(venu2plus.personality);resources-venu2022
venusq2.personality=$(venusq2.personality);resources-venu2022
venusq2m.personality=$(venusq2m.personality);resources-venu2022
```

**Colour selectors** come in `_light` / `_dark` pairs; use only `_dark` on products without night mode, and react to `onNightModeChanged()`:

| Selector | Purpose |
|---|---|
| `system_color_light/dark__background` | Default system background |
| `system_color_light/dark__text` | Default system text |
| `activity_color_light/dark__background` / `__text` | Activity context |
| `prompt_color_light/dark__background` / `__title` / `__body` | Prompts |
| `confirmation_color_light/dark__background` / `__body` | Confirmations |

**Typography selectors** supply size and alignment (colour, position and bounds come from separate selectors):

```xml
<!-- layout.xml -->
<text-area text="@Strings.warningPrompt" personality="
    prompt_color_dark__body
    prompt_size__body_with_title
    prompt_loc__body_with_title
    prompt_font__body_with_title
" />
```

`confirmation_font__body`, `prompt_font__title`, `prompt_font__body_no_title`, `prompt_font__body_with_title`.

**Input hints** — highlight the physical button that performs the next action on button-only products:

```xml
<!-- layout.xml -->
<!-- Left top hint -->
<bitmap id="leftTop" personality="
    system_icon_dark__hint_button_left_top
    system_loc__hint_button_left_top" />
```

Selectors exist per button position (left/right × top/middle/bottom), each with light/dark icon, `system_loc__*` and `system_size__*` variants. **"Hints applied to a product that does not have a button in that position will automatically be excluded when building for that product."**

**Cross-device action button** — the same selector resolves to a button on button devices and a touch target elsewhere:

```monkeyc
function isActionButton(button as WatchUi.Key) as Boolean {
    if (Styles.system_input__action_menu has :button &&
        button == Styles.system_input__action_menu.button) {
        return true;
    }
    return false;
}
```

Key selectors: `system_color_dark__text`, `prompt_size__body_no_title`, `prompt_loc__body_no_title`, `system_icon_dark__hint_action_menu`, `system_input__action_menu`.

---

## 5. Practical Gotchas

**Memory**
1. Glances get **32 KB**. Peak, not average — check *View Memory → Peak Memory* in the simulator on your **largest-screen** target; a bigger canvas alone pushed fēnix 6X from 27.4 kB to 29.8 kB and caused OutOfMemory.
2. `BufferedBitmap` without an explicit `:palette` uses full system colour and is expensive. Setting a 6-colour palette cut a real glance from 28.6 kB to 22.4 kB.
3. **Never `loadResource()` inside `onUpdate()`** — loading is expensive and `onUpdate()` runs every second (or every frame).
4. `Layer` costs roughly what a `BufferedBitmap` costs. Budget for it.
5. Use `scope="background"` / `scope="glance"` / `scope="settings"` on resources; unqualified resources default to `foreground` and still cost runtime memory in every mode they reach.
6. Custom numeric fonts: always use `filter="0123456789:"`. Anti-aliased fonts cost much more RAM than the default 1-bit.
7. Post-4.0 graphics pool: purged `BufferedBitmap`s are **not** restored — re-render or hold a `get()` reference (which risks exhausting the pool).
8. Watch out for the object-count ceiling, which can bite before the byte limit does.
9. `Storage`: 8 KB per key, 128 KB total. Legacy object store lives in RAM until exit.

**Lifecycle**
10. Do **not** push a view from `AppBase.onStart()`.
11. Glance subscriptions/complication subscriptions are torn down at shutdown — re-register in `onStart()` every launch.
12. On low-memory devices a glance runs a **full app lifecycle** every update and `requestUpdate()` does nothing — design for a cached, filesystem-backed image, not a live view.
13. Background services are killed at **30 s**; call `Background.exit()`.
14. `onAppInstall()` / `onAppUpdate()` are **not guaranteed** to run.
15. Temporal background events fire **at most every 5 minutes**.
16. Apps launched from the **glance list** get a timeout; from the activity list they do not. Branch on `state.get(:launchedFromGlance)`.

**Annotations and build**
17. `(:background)` and `(:glance)` are viral — your `AppBase` subclass, any globals referenced from its constructor, and every transitively reachable symbol must be annotated, or you get *Symbol Not Found* at runtime. Set type-check level to `informative`+ to catch it at build time.
18. `resources-round-fenix3` and `resources-218x218` are **silently ignored** — no build error, just missing resources.
19. `minApiLevel` micro version is written but ignored; only major.minor gate device support.

**UI**
20. A widget's **base view never receives up/down key or swipe events** — that is carousel navigation. Push a view to get them.
21. From **API 4.0.0 a widget/app without a `GlanceView` does not appear in the glance list at all** (before 4.0 you got a default name-only glance).
22. `GlanceView` cannot use layers or push views, and receives no input.
23. Data fields cannot use `Toybox.Timer`, get only `onTap()`, and got `Communications` only at API 5.0.0.
24. Watch faces have no GPS/sensors/compass and cannot call `Position.enableLocationEvents()`.
25. `onPartialUpdate()` **must** `setClip()` — otherwise you blow the power budget and nothing is drawn; `System.println()` is silently dropped there on hardware.
26. AMOLED always-on: once per minute, ≤10 % of pixels, shift static elements up to 4 px/minute.
27. `visible` on `<label>`/`<bitmap>`/`<text-area>` only works on CIQ **3.3.0+**.
28. `Dc.drawText()` honours `setColor()` only — not `setStroke()`/`setFill()`. There is no `drawPolygon()`, only `fillPolygon()`.
29. `drawAngledText()` / `drawRadialText()` need **scalable** fonts and reject custom `.fnt` resources.
30. Data field alerts are **off by default**; the user must enable *Settings → Alerts → Connect IQ*. Same trap for glances, which the user can switch off under *Widgets*.
31. `menu2`/`menu-item` `icon` attributes only render on the **Instinct 2 sub-screen**.
32. The `launcherIcon` bitmap resource must not be reused inside the app — duplicate the resource.
33. Complication `id` must stay stable across app versions; `public`/`protected` icons must be **SVG** and cannot change at runtime.
34. Complication subscribers must convert from the canonical unit (meters, m/s, °C, grams) to the user's system settings themselves, and must catch `ComplicationNotFoundException`.
35. `Attention` is denied while the app is inactive; high-frequency sensors drop to 10 Hz when inactive.
36. ACP Sync Configuration is deprecated — put downloads inside playback configuration.
37. Localisation: assume text length changes; do not assume every device supports every language; always read user unit preferences.
38. The `(:glance)` and glance-mode path may be **skipped entirely** — "There is no guarantee that a widget will always start in glance mode … before transitioning to its standard widget mode."

---

## URLs used

Documentation hubs
- https://developer.garmin.com/connect-iq/core-topics/
- https://developer.garmin.com/connect-iq/user-experience-guidelines/
- https://developer.garmin.com/connect-iq/compatible-devices/
- https://developer.garmin.com/connect-iq/device-reference/
- https://developer.garmin.com/connect-iq/personality-library/
- https://developer.garmin.com/connect-iq/connect-iq-basics/
- https://developer.garmin.com/connect-iq/overview/
- https://developer.garmin.com/connect-iq/api-docs/

Static article sources actually fetched (the canonical content behind the JS pages)
- https://developer.garmin.com/connect-iq/articles/connect-iq-basics/App_Types.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Glances.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Application_and_System_Modules.html
- https://developer.garmin.com/connect-iq/articles/core-topics/User_Interface.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Layouts.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Resources.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Graphics.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Input_Handling.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Native_Controls.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Complications.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Backgrounding.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Manifest_and_Permissions.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Build_Configuration.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Monkey_Style.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Persisting_Data.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Getting_the_Users_Attention.html
- https://developer.garmin.com/connect-iq/articles/user-experience-guidelines/Design_Principles.html
- https://developer.garmin.com/connect-iq/articles/user-experience-guidelines/Understanding_What_You_Are_Building.html
- https://developer.garmin.com/connect-iq/articles/user-experience-guidelines/Developing_the_Concepts.html
- https://developer.garmin.com/connect-iq/articles/user-experience-guidelines/Designing_Workflows_and_Interactions.html
- https://developer.garmin.com/connect-iq/articles/user-experience-guidelines/Incorporating_the_Visual_Design_and_Product_Personalities.html
- https://developer.garmin.com/connect-iq/articles/user-experience-guidelines/Entry_Points.html
- https://developer.garmin.com/connect-iq/articles/user-experience-guidelines/Views.html
- https://developer.garmin.com/connect-iq/articles/user-experience-guidelines/Watch_Faces.html
- https://developer.garmin.com/connect-iq/articles/user-experience-guidelines/Data_Fields.html
- https://developer.garmin.com/connect-iq/articles/user-experience-guidelines/Menus.html
- https://developer.garmin.com/connect-iq/articles/user-experience-guidelines/Confirmations.html
- https://developer.garmin.com/connect-iq/articles/user-experience-guidelines/Progress_Bars.html
- https://developer.garmin.com/connect-iq/articles/user-experience-guidelines/Map_Views.html
- https://developer.garmin.com/connect-iq/articles/user-experience-guidelines/Localization.html
- https://developer.garmin.com/connect-iq/articles/device-reference/Overview.html
- https://developer.garmin.com/connect-iq/articles/personality-library/Personality_UI.html
- https://developer.garmin.com/connect-iq/articles/personality-library/Colors.html
- https://developer.garmin.com/connect-iq/articles/personality-library/Typography.html
- https://developer.garmin.com/connect-iq/articles/personality-library/Input_Hints.html

API reference
- https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/GlanceView.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/WatchFace.html

Garmin forum posts (used for memory figures and Personality UI walkthrough)
- https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/widget-glances---a-new-way-to-present-your-data
- https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/adding-a-touch-of-personality-with-personality-ui
- https://forums.garmin.com/developer/connect-iq/f/discussion/4060/understanding-connect-iq-device-memory-limits

Page-data endpoints used to resolve article filenames
- https://developer.garmin.com/page-data/connect-iq/core-topics/glances/page-data.json
- https://developer.garmin.com/page-data/connect-iq/connect-iq-basics/app-types/page-data.json
- https://developer.garmin.com/page-data/connect-iq/device-reference/page-data.json
- https://developer.garmin.com/page-data/connect-iq/personality-library/page-data.json
- https://developer.garmin.com/page-data/connect-iq/user-experience-guidelines/entry-points/page-data.json

---

### Gaps worth flagging
- **Per-device memory budgets are not published on the public web.** The Device Reference table carries shape, size, touch, colour count, icon size and buttons only. Real budgets come from the SDK device definitions, the simulator's *View Memory* panel, and `System.getSystemStats()` at runtime. The figures in §3.4 outside the official 32 KB glance limit are from Garmin forum threads, not the docs.
- The **Compatible Devices** page is a client-side React page with no static article twin, so its full device/API-level matrix could not be extracted verbatim; the shape/size/API-level ranges above come from its rendered summary plus the Device Reference overview table.
