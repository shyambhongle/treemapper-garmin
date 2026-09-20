# Garmin Connect IQ — Technical Briefing for a GPS Field-Data / Tree-Mapping App

Sourced from developer.garmin.com core-topics articles and the Toybox API docs (Sept 2026). Where the article text and the API reference disagree, both numbers are given and the conservative one flagged.

---

## 1. Toybox module inventory

The API doc index lists exactly these 35 modules (`Toybox.*`):

| Module | Purpose |
|---|---|
| **Activity** | Read-only live activity state. `Activity.getActivityInfo()` returns `Activity.Info` (speed, HR, distance, `currentLocation`, timer state…). Sport/SubSport enums live here now. |
| **ActivityMonitor** | Daily wellness totals: steps, calories, active minutes, move bar, floors. `getInfo()`, `getHistory()` (7 days), `getHeartRateHistory()`. |
| **ActivityPrompts** | Register the app to be offered when the device auto-detects an activity start. |
| **ActivityRecording** | Create/start/stop/save/discard FIT recording sessions. `createSession()`, `Session`. Needs `Fit` permission. |
| **Ant** | Low-level generic ANT channels — raw packet TX/RX, burst up to 8 KB. Permission `Ant`. |
| **AntPlus** | High-level ANT+ device profiles (HR, bike speed/cadence/power, tempe, bike lights, running dynamics). System owns the channels. API 2.2.0+. |
| **Application** | App lifecycle (`AppBase`) plus submodules `Application.Storage` and `Application.Properties`. |
| **Attention** | Vibration, tones, backlight — `vibrate()`, `playTone()`, `backlight()`. |
| **Authentication** | OAuth via the **Connect IQ Store mobile app** (redirect `connectiq://oauth`). API 3.3.0+. |
| **Background** | Register/deregister background wake events; `exit()`, `getBackgroundData()`, `requestApplicationWake()`. API 2.3.0+. |
| **BluetoothLowEnergy** | Watch acts as BLE **central**: scan, pair, GATT read/write/notify against registered profiles. API 3.1.0+. |
| **Communications** | Web requests via phone proxy, image requests, OAuth, phone-app messaging, Wi-Fi bulk sync. |
| **Complications** | Publish or subscribe to watch-face complication data. API 4.2.0+. |
| **Cryptography** | AES-128/256 (ECB/CBC), SHA-1/SHA-256/MD5, HMAC/CMAC, EC keys (secp224r1, secp256r1), ECDH, `randomBytes()`. API 3.0.0+. |
| **FitContributor** | Developer fields written into FIT record/lap/session messages; surfaces in Garmin Connect charts. |
| **Graphics** | `Dc` drawing, fonts, colors, `BufferedBitmap`. |
| **Lang** | Core types: Number, Long, Float, Double, String, Char, Boolean, Array, Dictionary, Symbol, Method, Object, exceptions. |
| **Math** | Trig, `rand()`, plus `FirFilter` / `IirFilter` for raw sensor smoothing. |
| **Media** | Audio content provider apps: cached `Content`, `PlaybackProfile`, `AlbumArt`. API 3.0.0+. |
| **Notifications** | Access phone notification stream. |
| **PersistedContent** | Read/write device-level user content: courses, routes, tracks, waypoints, workouts. `saveWaypoint()`, `getAppWaypoints()`, iterators. API 2.2.0+ (some fns 3.0.0+). Permission `PersistedContent`. |
| **PersistedLocations** | **Deprecated** (may be removed after System 4). Single fn `persistLocation()` to drop a waypoint. API 1.0.2+. Use `PersistedContent` instead. |
| **Position** | GPS/GNSS. `enableLocationEvents()`, `getInfo()`, `Location`, `Info`, `parse()`, `createBoundingBox()`. |
| **ScanCode** | Render/scan QR and barcode content. |
| **Sensor** | Live 1 Hz sensor events + high-frequency accel/gyro/mag data. |
| **SensorHistory** | Historical on-device sensor series (HR, elevation, temp, pressure, SpO2, body battery, stress). API 2.1.0+. |
| **SensorLogging** | `SensorLogger` that feeds sensor data into a FIT recording session. API 2.3.0+. |
| **StringUtil** | Char/byte array conversions, `convertEncodedString()` (Base64, UTF-8, hex). |
| **System** | `getDeviceSettings()`, `getSystemStats()` (freeMemory/totalMemory/usedMemory), `getTimer()`, `println()`, `exit()`, `ServiceDelegate`. |
| **Test** | Unit-test harness (`(:test)` annotated functions). |
| **Time** | `Moment`, `Duration`, `Gregorian` calendar conversion. |
| **Timer** | `Timer.Timer` one-shot and repeating callbacks. |
| **UserProfile** | Birth year, gender, height, weight, HR zones, activity history. Permission `UserProfile`. |
| **WatchUi** | Views, delegates, layouts, menus, pickers, `requestUpdate()`, `DataFieldAlert`. |
| **Weather** | `getCurrentConditions()`, `getDailyForecast()`, `getHourlyForecast()`, `getSunrise()/getSunset()` (3.3.0+). Cached, refreshed ~every 15 min, location may be user-chosen not current. API 3.2.0+. |

Note: `Toybox.Application.Storage` and `Toybox.Application.Properties` are submodules, not top-level entries.

---

## 2. Activity recording (FIT)

### Flow
1. Enable sensors you want recorded (`Sensor.setEnabledSensors`).
2. `ActivityRecording.createSession(options)`.
3. `session.start()` → data flows into the FIT file.
4. `session.stop()` pauses.
5. `session.save()` writes the FIT, or `session.discard()` deletes it.

FIT files sync to Garmin Connect automatically; you can pull them server-side through the **Garmin Connect Developer Program** API. Sample app: `RecordSample`.

### `createSession()`
```
createSession(options as Dictionary) as ActivityRecording.Session
```
Options:
- `:name` (String) — activity name, keep ≤ 15 chars.
- `:sport` (`Activity.Sport` / legacy `ActivityRecording.Sport`)
- `:subSport` (`Activity.SubSport` / legacy `ActivityRecording.SubSport`)
- `:poolLength` (Float, metres) — required for `SUB_SPORT_LAP_SWIMMING`
- `:sensorLogger` (`SensorLogging.SensorLogger`)
- `:autoLap` (Dictionary with `:type`, `:entry`, `:exit`)

The `ActivityRecording.SPORT_*` / `SUB_SPORT_*` constants are **deprecated** — use `Activity.SPORT_*` / `Activity.SUB_SPORT_*`. Relevant for a field-mapping app: `SPORT_HIKING`, `SPORT_WALKING`, `SPORT_GENERIC`; `SUB_SPORT_TRAIL`, `SUB_SPORT_GENERIC`.

Documented sample (verbatim from the API docs):
```monkeyc
using Toybox.ActivityRecording;
using Toybox.WatchUi;

var session = null;

function onSelect() {
   if (Toybox has :ActivityRecording) {
       if ((session == null) || (session.isRecording() == false)) {
           session = ActivityRecording.createSession({
                 :name=>"Generic",
                 :sport=>Activity.SPORT_GENERIC,
                 :subSport=>Activity.SUB_SPORT_GENERIC
           });
           session.start();
       }
       else if ((session != null) && session.isRecording()) {
           session.stop();
           session.save();
           session = null;
       }
   }
   return true;
}
```

### `Session` methods
`start()`, `stop()`, `save()`, `discard()`, `isRecording()`, `addLap()` — all return Boolean. Plus `createField()` and `setTimerEventListener(listener)` (callback gets `eventType` + an `eventData` Dictionary carrying lap distance/speed/time). API 5.2.2 adds split control (`Select Split Type` / `Start Split` / `End Split` in the simulator dialog).

### FitContributor developer fields

**Resource declaration** (`fitContributions` block):
```xml
<strings>
    <string id="namaste_label">Namastes</string>
    <string id="namaste_graph_label">Namastes</string>
    <string id="namaste_units">N(s)</string>
</strings>
<fitContributions>
    <fitField id="0" displayInChart="true" sortOrder = "0" precision="2"
    chartTitle="@Strings.namaste_graph_label" dataLabel="@Strings.namaste_label"
    unitLabel="@Strings.namaste_units" fillColor="#FF0000" />
</fitContributions>
```

`fitField` attributes: `id` (0–255, unique per app), `displayInChart` (chart fields must be numeric), `displayInActivityLaps`, `displayInActivitySummary`, `sortOrder` (unique), `precision` (0/1/2), `chartTitle`, `dataLabel`, `unitLabel` (all must be string resources), `fillColor` (RRGGBB).

**Code side:**
```monkeyc
const NAMASTE_FIELD_ID = 0;
hidden var mNamasteField;

function setupField(session as Session) {
    mNamasteField =
        session.createField(
            "current_namastes", NAMASTE_FIELD_ID, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType=>Fit.MESG_TYPE_RECORD, :units=>"N" });
}
```
Then `mNamasteField.setData(value);`

`createField(name, fieldId, type, options)` options:
- `:mesgType` — default `MESG_TYPE_RECORD`
- `:units` (String, shown on device; ~16+ byte limit)
- `:count` (Number) — array element count; for strings it is the max combined size **including null terminators**; default 1
- `:nativeNum` — FIT Profile field number when mirroring a standard field

**Data types** (value / bytes): `DATA_TYPE_SINT8` 1/1, `UINT8` 2/1, `SINT16` 3/2, `UINT16` 4/2, `SINT32` 5/4, `UINT32` 6/4, `STRING` 7/var, `FLOAT` 8/4, `DOUBLE` 9/8.

**Message types**: `MESG_TYPE_SESSION` = 18 (written once at end), `MESG_TYPE_LAP` = 19 (once per lap), `MESG_TYPE_RECORD` = 20 (once per second / on new data).

The field `id` in code **must** match the `fitField id` in resources or nothing renders in Garmin Connect. Preview chart rendering with the **Monkey Graph** tool (needs a recorded FIT + an exported `.iq`).

### `Activity.Info` (live, read via `Activity.getActivityInfo()`)
All fields are nullable. Full documented set:

`altitude` (Float, m) · `ambientPressure` (Float, Pa, 2.4.0) · `rawAmbientPressure` (Float, Pa, 2.4.0) · `meanSeaLevelPressure` (Float, Pa) · `averageCadence` (Number, rpm) · `averageDistance` (Float, m, 1.2.2) · `averageHeartRate` (Number, bpm) · `averagePower` (Number, W) · `averageSpeed` (Float, m/s) · `bearing` / `bearingFromStart` (Float, rad, 2.1.0) · `calories` (Number, kcal) · `currentCadence` · `currentHeading` (Float, rad) · `currentHeartRate` · `currentLocation` (**Position.Location**, needs Positioning permission) · `currentLocationAccuracy` (`Position.Quality` 0–4) · `currentOxygenSaturation` (Number, %, 3.2.0) · `currentPower` · `currentSpeed` (Float, m/s) · `distanceToDestination` / `distanceToNextPoint` (Float, m, 2.1.0) · `elapsedDistance` (Float, m) · `elapsedTime` (Number, ms) · `elevationAtDestination` / `elevationAtNextPoint` (2.1.0) · `energyExpenditure` (Float, kcal/min, 1.2.0) · `frontDerailleurIndex/Max/Size`, `rearDerailleurIndex/Max/Size` (2.1.0) · `maxCadence` · `maxHeartRate` · `maxPower` · `maxSpeed` · `nameOfDestination` / `nameOfNextPoint` (String, 2.1.0) · `offCourseDistance` (Float, m, 2.1.0) · `startLocation` (Position.Location) · `startTime` (Time.Moment) · `swimStrokeType` / `swimSwolf` (1.2.2) · `timerState` (`Activity.TimerState`) · `timerTime` (Number, ms) · `totalAscent` / `totalDescent` (Number, m) · `track` (Float, rad) · `trainingEffect` (Float).

For a tree-mapping app, `Activity.Info.currentLocation` + `currentLocationAccuracy` is a cheap way to read GPS **while a session is running** without separately calling `Position.getInfo()`.

---

## 3. Position / GPS (deep dive)

### Enabling location events
```monkeyc
function onPosition( info as Position.Info ) as Void {
    Sys.println( "Position " + info.position.toGeoString( Position.GEO_DM ) );
}

function initializeListener() as Void {
    Position.enableLocationEvents( Position.LOCATION_CONTINUOUS, method( :onPosition ) );
}
```

Signature: `enableLocationEvents(options, listener) as Void`.
`options` is either a legacy acquisition-type Number **or** a Dictionary:

| Key | Values |
|---|---|
| `:acquisitionType` | `LOCATION_ONE_SHOT` (0), `LOCATION_CONTINUOUS` (1), `LOCATION_DISABLE` (2) |
| `:configuration` | `CONFIGURATION_GPS`, `CONFIGURATION_GPS_GLONASS`, `CONFIGURATION_GPS_GALILEO`, `CONFIGURATION_GPS_BEIDOU`, `CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1`, `CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1_L5`, `CONFIGURATION_SAT_IQ` — all API 3.3.6 |
| `:constellations` | Array of `CONSTELLATION_GPS`, `CONSTELLATION_GLONASS`, `CONSTELLATION_GALILEO` |
| `:mode` | `POSITIONING_MODE_NORMAL`, `POSITIONING_MODE_AVIATION` |

GNSS configuration → solution mapping (from the Positioning article):

| Configuration | GPS solution |
|---|---|
| `CONFIGURATION_GPS` | GPS L1 |
| `CONFIGURATION_GPS_GLONAS` *(sic — doc spelling)* | GPS L1, GLONASS |
| `CONFIGURATION_GPS_GALILEO` | GPS L1, GALILEO L1 |
| `CONFIGURATION_GPS_BEIDOU` | GPS L1, BEIDOU L1 |
| `CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1` | GPS L1, GLONASS, GALILEO L1, BEIDOU L1 |
| `CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1_L5` | + GPS L5, GALILEO L5, BEIDOU L5 (multi-band) |
| `CONFIGURATION_SAT_IQ` | Solution chosen dynamically for optimum power |

Gate every use with `Position.hasConfigurationSupport(config)` — not every device supports every mode. **For tree mapping, multi-band L1+L5 is the accuracy win; SatIQ is the battery compromise.**

### Other functions
- `getInfo() as Position.Info` — poll on demand or from a `Timer`.
- `parse(string, format) as Position.Location` — e.g. `Position.parse("38.856147, -94.800953", Position.GEO_DEG);`
- `createBoundingBox(locations) as [Location, Location] or Null` — returns top-left / bottom-right.

### Coordinate formats (`GEO_*`)
`GEO_DEG` (0) decimal degrees · `GEO_DM` (1) degrees/decimal minutes · `GEO_DMS` (2) deg/min/sec · `GEO_MGRS` (3) Military Grid Reference System.

### Quality (`Position.Quality`)
`QUALITY_NOT_AVAILABLE` (0) · `QUALITY_LAST_KNOWN` (1) · `QUALITY_POOR` (2, 2D fix, limited sats) · `QUALITY_USABLE` (3, 3D marginal) · `QUALITY_GOOD` (4, 3D good precision).

### `Position.Info` fields
| Field | Type | Units |
|---|---|---|
| `position` | `Position.Location` or Null | — (radians internally) |
| `accuracy` | `Position.Quality` (non-null) | 0–4 |
| `altitude` | Float or Null | m above MSL (needs GPS) |
| `heading` | Float or Null | radians, true north |
| `speed` | Float or Null | m/s (GPS → foot pod → accelerometer, in that priority) |
| `when` | `Time.Moment` or Null | GPS timestamp of the fix |

Important behaviour note from the docs: `position` is **dead-reckoned between GPS fixes**, and then stops propagating to avoid error build-up. So a returned position can be interpolated, not measured. For survey-grade point capture, always record `accuracy` and `when` alongside the coordinate and reject anything below `QUALITY_USABLE`.

### `Position.Location`
```
new Position.Location({
    :latitude => ..., :longitude => ...,
    :format => :degrees | :radians | :semicircles
})
```
Methods: `toDegrees()` → `[Double, Double]` · `toRadians()` → `[Double, Double]` · `toGeoString(format)` → String · `getProjectedLocation(angle, distance)` → Location (angle in radians from north, distance in metres; API 3.0.0).

### Waypoints / persisted locations
- **`PersistedContent`** (current): `saveWaypoint(location, options)`; retrieval via `getWaypoints()` / `getAppWaypoints()` (app-owned only), plus `getCourses/getRoutes/getTracks/getWorkouts` and their `getApp*` variants. All return an `Iterator`. Content objects expose `getName()`, `getId()`, `toIntent()`, `remove()`. Permission `PersistedContent`, API 2.2.0+ (some fns 3.0.0+).
- **`PersistedLocations`** (deprecated, API 1.0.2): `persistLocation(location, name)`. Permission `PersistedLocations`. Do not build new work on it.

For a tree-mapping app, `PersistedContent.saveWaypoint()` gives the user a native device waypoint they can navigate back to — a nice complement to your own `Storage` record.

---

## 4. Sensors

### Basic 1 Hz sensor events
```monkeyc
using Toybox.Sensor;

function initialize() {
    Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
    Sensor.enableSensorEvents(method(:onSensor));
}

function onSensor(sensorInfo) {
    System.println("Heart Rate: " + sensorInfo.heartRate);
}
```
`setEnabledSensors([])` disables everything.

**`SENSOR_*` constants:** remote — `SENSOR_BIKESPEED` (0), `SENSOR_BIKECADENCE` (1), `SENSOR_BIKEPOWER` (2), `SENSOR_FOOTPOD` (3), `SENSOR_HEARTRATE` (4), `SENSOR_TEMPERATURE` (5), `SENSOR_GENERIC` (9); onboard — `SENSOR_PULSE_OXIMETRY` (6), `SENSOR_ONBOARD_PULSE_OXIMETRY` (7), `SENSOR_ONBOARD_HEARTRATE` (8).

**Sensor data available & units:** accelerometer x/y/z in mg (1.2.0) · altitude m (1.0.0) · cadence rpm · heading radians true north · heart rate bpm · magnetometer x/y/z in mGauss (1.2.0) · oxygen saturation % (3.2.0) · power W · pressure Pa · temperature °C.

### High-frequency raw data (API 2.3.0+)
`Sensor.registerSensorDataListener(callback, options)` / `Sensor.unregisterSensorDataListener()` — **only one active listener at a time**; re-registering overrides.

Options:
| Key | Type | Notes |
|---|---|---|
| `:period` | Number | sample window in seconds, **max 4** |
| `:synchronous` | Boolean | request synchronised streams |
| `:accelerometer` | Dictionary | `:enabled`, `:sampleRate` (Hz), `:includeTimestamps`, `:includePower`, `:includePitch`, `:includeRoll` |
| `:gyroscope` | Dictionary | `:enabled`, `:sampleRate`, `:includeTimestamps` |
| `:magnetometer` | Dictionary | same |
| `:heartBeatIntervals` | Dictionary | `:enabled` |

Callback receives `Sensor.SensorData` wrapping `AccelerometerData` / `GyroscopeData` / `MagnetometerData`. `Sensor.getMaxSampleRate()` tells you what the device can do.

Filtering helpers: `Math.FirFilter` (`:coefficients`, `:gain`) and `Math.IirFilter` (`:coefficientList1`, `:coefficientList2`, `:gain`); coefficients can come from a JSON resource. Both expose `apply()`.

### SensorHistory (API 2.1.0, permission `SensorHistory`)
`getHeartRateHistory()` bpm · `getElevationHistory()` m · `getTemperatureHistory()` °C · `getPressureHistory()` Pa · `getOxygenSaturationHistory()` % · `getBodyBatteryHistory()` 0–100 · `getStressHistory()` 0–100.

Options: `:period` = null (all) | Number (last N samples) | `Time.Duration`; `:order` = `ORDER_NEWEST_FIRST` (0, default) | `ORDER_OLDEST_FIRST` (1).

```monkeyc
var options = { :period => 100, :order => SensorHistory.ORDER_OLDEST_FIRST };
var iterator = Toybox.SensorHistory.getHeartRateHistory(options);
var sample = iterator.next();
while (sample != null) {
    System.println(sample.data);
    sample = iterator.next();
}
```
Always feature-gate:
```monkeyc
if ((Toybox has :SensorHistory) && (Toybox.SensorHistory has :getHeartRateHistory)) { ... }
```
Data persists only back to the last power cycle (except body battery / stress / SpO2). Inter-sample spacing varies per device. `ActivityMonitor.getHeartRateHistory()` marks invalid samples with **255**.

### SensorLogging (API 2.3.0, permission `SensorLogging`)
`new Toybox.SensorLogging.SensorLogger(options)` — pass it into `createSession({:sensorLogger => logger})` so raw accelerometer data is logged into the FIT file and can be replayed in the simulator.

### UserProfile (permission `UserProfile`)
`getProfile()` → birth year, gender (`GENDER_FEMALE` 0 / `GENDER_MALE` 1 / `GENDER_UNSPECIFIED` 2), height, weight, etc. `getCurrentSport()` / `getCurrentSport2()` (5.2.2) · `getHeartRateZones(sport)` returns 6 values (zone 1 min, zone 1 max, then max of zones 2–5); `HR_ZONE_SPORT_GENERIC/RUNNING/BIKING/SWIMMING`; `getHeartRateZones2()` (5.2.2) takes `Activity.Sport`. `getUserActivityHistory()` returns an iterator.

---

## 5. Persistence

Three distinct concepts:
- **Storage** — data written to disk at runtime by your code, invisible to the user.
- **Properties** — constants defined at build time in resources; also supply default values for Settings.
- **Settings** — user-editable, via Garmin Connect Mobile / Garmin Express, backed by Properties.

### `Application.Storage` (API 2.4.0+) — use this
```monkeyc
Storage.setValue("location", locationValue.toDegrees());
var myLastLocation = Application.Storage.getValue("location");
```
Functions: `getValue(key)` (null if absent), `setValue(key, value)` (writes to disk immediately), `deleteValue(key)`, `clearValues()`.

**Types.** Keys: Number, Float, Long, Double, String, Boolean, Char. Values: all key types plus byte arrays (`Lang.ByteArray`), bitmap/animation resources, scan results, complication IDs, watch-face config IDs, Array, Dictionary, null. **An Array or Dictionary may only contain the listed types** — no Symbols nested inside.

**Size limits — the docs disagree, plan for the smaller:**
- Persisting Data article: *"Keys and values are limited to 8 KB each, and a total of 128 KB of storage is available."*
- `Application.Storage` API page: *"Limited to 32 KB per value"*; total object store varies by device and throws if exceeded.

Treat **8 KB per value / 128 KB total** as the safe design budget, and catch the store-full exception regardless.

**Background access (API 3.2.0+):** background processes may call `Storage.setValue()` / `deleteValue()`. If foreground and background are alive at once, `AppBase.onStorageChanged()` fires on the other side and you must reload.

### `Application.Properties` (API 2.4.0+)
```monkeyc
Properties.setValue("mySetting", mySetting);
var mySetting = Properties.getValue("mySetting");
```
Keys **must** be declared in a `<properties>` resource block or you get `Properties.InvalidKeyException`. Other exceptions: `UnexpectedTypeException`, `ObjectStoreAccessException` (writing from a background process on older devices). Values are flushed to disk at `AppBase.onStop()`. ValueType: Number, Float, Long, Double, String, Boolean, and Arrays of those.

**Background processes cannot save Properties** — hand data back to the foreground with `Background.exit()`.

### Deprecated object store (`AppBase.getProperty` / `setProperty` / `deleteProperty` / `clearProperties`)
Pre-2.4.0 path. The object store is a `Lang.Dictionary` that **lives in RAM until the app terminates**, so it costs against your runtime memory. Only use it on Connect IQ System 1 devices. Deprecated; may be removed after System 4.

Migration caveats:
1. Old `.STR` object-store files are **not** auto-converted to the new Storage format — you must write your own migration.
2. Old `setProperty` silently created undefined keys; `Properties.setValue` throws instead.

Compatibility gate:
```monkeyc
if ( Toybox.Application has :Storage ) {
    // use Application.Storage and Application.Properties methods
} else {
    // use Application.AppBase methods
}
```

### Properties & Settings XML
```xml
<properties>
    <property id="appVersion" type="string">1.0.0</property>
</properties>
```
Types: `number`, `long`, `float`, `double`, `boolean`, `string`, `array`.

```xml
<setting propertyKey="@Properties.myString" title="@Strings.Title">
    <settingConfig type="list">
        <listEntry value="0">@Strings.Option1</listEntry>
    </settingConfig>
</setting>
```
`settingConfig` types: `list`, `boolean`, `numeric` (optional min/max), `alphaNumeric`, `phone`, `email`, `url`, `password`, `date` (optional min/max). Settings can be `readonly` or `required`, grouped, and array-valued for variable-length lists.

`AppBase.onSettingsChanged()` fires when GCM/Garmin Express pushes a change while the app is running. Test with the simulator: *File > Edit Persistent Storage > Edit Application.Properties data*.

Sample app: `ApplicationStorage`.

---

## 6. Communications

There is **no direct internet stack on the watch**. Everything goes through the paired phone (Garmin Connect Mobile acting as a BLE proxy), or through Wi-Fi in the special bulk-sync mode (section 6.4).

### 6.1 `makeWebRequest()` (API 1.3.0)
```
makeWebRequest(url, parameters, options, responseCallback) as Void
```
Options:
- `:method` — `HTTP_REQUEST_METHOD_GET` (1), `PUT` (2), `POST` (3), `DELETE` (4)
- `:headers` — Dictionary, e.g. `"Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON`
- `:responseType` — see table below
- `:context` — any object, echoed back as a 3rd callback arg
- `:maxBandwidth` — for audio/HLS
- `:fileDownloadProgressCallback`

Callback is `function(responseCode, data)` or `function(responseCode, data, context)`.

Documented sample:
```monkeyc
import Toybox.System;
import Toybox.Communications;
import Toybox.Lang;

class JsonTransaction {
    function onReceive(responseCode as Number, data as Dictionary?) as Void {
        if (responseCode == 200) {
            System.println("Request Successful");
        } else {
            System.println("Response: " + responseCode);
        };
    };

    function makeRequest() as Void {
        var url = "https://www.garmin.com";
        var params = { "definedParams" => "123456789abcdefg" };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => {
            "Content-Type" => Communications.REQUEST_CONTENT_TYPE_URL_ENCODED},
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_URL_ENCODED
        };
        Communications.makeWebRequest(url, params, options, method(:onReceive));
    }
}
```

**Response content types:** `HTTP_RESPONSE_CONTENT_TYPE_JSON` 0 · `URL_ENCODED` 1 · `GPX` 2 · `FIT` 3 · `AUDIO` 4 · `TEXT_PLAIN` 5 · `HLS_DOWNLOAD` 6 · `ANIMATION_MANIFEST` 7 · `ANIMATION` 8.
**Request content types:** `REQUEST_CONTENT_TYPE_URL_ENCODED` 0 · `REQUEST_CONTENT_TYPE_JSON` 1.

Other functions: `encodeURL(url)` (RFC 3986 percent-encoding), `cancelAllRequests()`, `checkWifiConnection(cb)` (cb gets `{:wifiAvailable, :errorCode}`), `openWebPage(url, params, options)` (opens in the phone browser, **no callback, no success signal**).

### 6.2 Error codes (negative = transport/system, distinct from HTTP status)
| Code | Value | Meaning |
|---|---|---|
| `UNKNOWN_ERROR` | 0 | generic |
| `BLE_ERROR` | -1 | BLE failure |
| `BLE_HOST_TIMEOUT` | -2 | phone didn't respond |
| `BLE_SERVER_TIMEOUT` | -3 | server didn't respond |
| `BLE_NO_DATA` | -4 | empty response |
| `BLE_REQUEST_CANCELLED` | -5 | system cancelled |
| `BLE_QUEUE_FULL` | -101 | too many pending requests |
| `BLE_REQUEST_TOO_LARGE` | -102 | **request body exceeded the BLE size limit** |
| `BLE_UNKNOWN_SEND_ERROR` | -103 | |
| `BLE_CONNECTION_UNAVAILABLE` | -104 | **phone not connected** |
| `INVALID_HTTP_HEADER_FIELDS_IN_REQUEST` | -200 | |
| `INVALID_HTTP_BODY_IN_REQUEST` | -201 | |
| `INVALID_HTTP_METHOD_IN_REQUEST` | -202 | |
| `NETWORK_REQUEST_TIMED_OUT` | -300 | |
| `INVALID_HTTP_BODY_IN_NETWORK_RESPONSE` | -400 | body didn't match `:responseType` |
| `INVALID_HTTP_HEADER_FIELDS_IN_NETWORK_RESPONSE` | -401 | |
| `NETWORK_RESPONSE_TOO_LARGE` | -402 | **response exceeded size limit** |
| `NETWORK_RESPONSE_OUT_OF_MEMORY` | -403 | **not enough RAM to parse the response** |
| `STORAGE_FULL` | -1000 | |
| `SECURE_CONNECTION_REQUIRED` | -1001 | **HTTPS required** |
| `UNSUPPORTED_CONTENT_TYPE_IN_RESPONSE` | -1002 | |
| `REQUEST_CANCELLED` | -1003 | |
| `REQUEST_CONNECTION_DROPPED` | -1004 | |
| `UNABLE_TO_PROCESS_MEDIA` | -1005 | |
| `UNABLE_TO_PROCESS_IMAGE` | -1006 | |
| `UNABLE_TO_PROCESS_HLS` | -1007 | |

Phone-app message errors: `PHONE_APP_MESSAGE_ERROR_OUT_OF_MEMORY` 0, `PHONE_APP_MESSAGE_ERROR_OUT_OF_STORAGE` 1.

### 6.3 `makeImageRequest()` (API 1.2.0)
```monkeyc
var options = {
    :palette => [ Gfx.COLOR_ORANGE, Gfx.COLOR_DK_BLUE, Gfx.COLOR_BLUE, Gfx.COLOR_BLACK ],
    :maxWidth => 100,
    :maxHeight => 100,
    :dithering => Communications.IMAGE_DITHERING_NONE
};
Communications.makeImageRequest(url, parameters, options, method(:responseCallback));
```
Also `:packingFormat` — `PACKING_FORMAT_DEFAULT` 0, `YUV` 1, `PNG` 2, `JPG` 3. Dithering: `IMAGE_DITHERING_NONE` 1, `IMAGE_DITHERING_FLOYD_STEINBERG` 2. Callback gets a `BitmapResource` / `BitmapReference` / null.

### 6.4 Wi-Fi bulk sync (API 3.1.0+) — relevant for uploading a day's field data
When BLE is too slow, the system tears down your app, relaunches it in **sync mode**, and drives a `Communications.SyncDelegate`:

1. `Communications.startSync()` (or `startSync2({:message => "text"})`) exits the app and enters sync mode.
2. `AppBase.getSyncDelegate()` returns your `Communications.SyncDelegate`.
3. `SyncDelegate.isSyncNeeded()` — return false to skip.
4. `SyncDelegate.onStartSync()` — fire your `makeWebRequest()` / `makeImageRequest()` calls here.
5. `Communications.notifySyncProgress(percentageComplete)` — 0–100.
6. `Communications.notifySyncComplete(errorMessage)` — pass `null` on success.
7. `SyncDelegate.onStopSync()` — user cancelled; you must still call `notifySyncComplete()`.

Wi-Fi status constants if `checkWifiConnection()` fails: `WIFI_CONNECTION_STATUS_LOW_BATTERY` 1, `NO_ACCESS_POINTS` 2, `UNSUPPORTED` 3, `USER_DISABLED` 4, `BATTERY_SAVER_ACTIVE` 5, `STEALTH_MODE_ACTIVE` 6, `AIRPLANE_MODE_ACTIVE` 7, `POWERED_DOWN` 8, `UNKNOWN` 9, `CANNOT_CONNECT_TO_ACCESS_POINT` 10, `TRANSFER_ALREADY_IN_PROGRESS` 11. Sample app: `BulkDownload`.

### 6.5 Phone companion messaging
Conceptual model is a **mailbox**: messages are parcels sent between the watch app and a phone app, and an event fires on arrival.

Watch side:
```monkeyc
Communications.registerForPhoneAppMessages(method(:onPhoneMessage));

function onPhoneMessage(msg) {
    System.println("From phone: " + msg.data);
}
```
```monkeyc
Communications.transmit(content, options, listener);
// listener extends Communications.ConnectionListener → onComplete() / onError()
```
`transmit` content supports primitives, Strings, Arrays, Dictionaries and byte arrays.

Also `Communications.notifyIncomingMessage()` / `PhoneAppMessage` object carrying `.data`.

### 6.6 Mobile SDKs
Three editions: **Android BLE**, **iOS BLE**, **Android ADB** (simulator bridge).

**Android:**
```java
ConnectIQ connectIQ = ConnectIQ.getInstance(ConnectIQ.IQConnectType.WIRELESS);
connectIQ.initialize(context, true, new ConnectIQListener() {
    @Override public void onSdkReady() { }
});
```
Wait for `onSdkReady()` before any other call. Then `getKnownDevices()` / `getConnectedDevices()`, `registerForDeviceEvents()` (CONNECTED / NOT_CONNECTED / NOT_PAIRED), `getApplicationInfo(uuid)`, `openApplication()`, `openStore()`.
```java
List<Object> message = new ArrayList<>("hello pi", 3.14159);
connectIQ.sendMessage(device, app, message, listener);

connectIQ.registerForAppEvents(device, app, new IQApplicationEventListener() {
    public void onMessageReceived(IQDevice device, IQApp app,
        List<Object> messageData, IQMessageStatus status) { }
});
```
Gradle: `implementation "com.garmin.connectiq:ciq-companion-app-sdk:<latest_version>@aar"`.
Type mapping: Java int/long/float/double/boolean/char/String/List/Map → Monkey C equivalents; container elements must also be supported types.

**ADB simulator bridge:** `getInstance(IQCommProtocol.ADB_SIMULATOR)`, optional `setAdbPort(int)` (default **7381**), `initialize()`, then `adb forward tcp:7381 tcp:7381`, then *Connection > Start* (CTRL-F1) in the simulator. It throttles to real Bluetooth speeds, which is the right way to test sync performance.

**iOS:**
```swift
ConnectIQ.sharedInstance().initialize(urlScheme: "exapp-123456", uiOverrideDelegate: self)
ConnectIQ.sharedInstance().showConnectIQDeviceSelection()   // returns via URL scheme
ConnectIQ.sharedInstance().registerForDeviceEvents(device, delegate: self)
let app = IQApp(uuid: UUID(uuidString: "AppID"), device: device)
ConnectIQ.sharedInstance().sendMessage(message, toApp: app, progress: {}, completion: {})
ConnectIQ.sharedInstance().registerForAppMessages(app, delegate: self)
```
Install via Swift Package Manager from the GitHub repo, embed as binary, add `-ObjC` linker flag, set Info.plist URL scheme + Bluetooth usage description + bundle display name. Message types: NSString, NSNumber, NSArray, NSDictionary, NSNull.

### 6.7 OAuth
Two parallel implementations:

| | `Toybox.Communications` (API 1.3.0) | `Toybox.Authentication` (API 3.3.0) |
|---|---|---|
| Handled by | Garmin Connect Mobile app | Connect IQ Store mobile app |
| Redirect URL | `http://localhost` | `connectiq://oauth` |
| Functions | `makeOAuthRequest()`, `registerForOAuthMessages()` | same names |

```
makeOAuthRequest(requestUrl, requestParams, resultUrl, resultType, resultKeys)
```
`resultType` = `OAUTH_RESULT_TYPE_URL` (0). `resultKeys` maps the provider's callback query keys to the keys you'll read off `OAuthMessage.data`. Signing constant: `OAUTH_SIGNING_METHOD_HMAC_SHA1` (0).

```monkeyc
function startOAuth() {
    var params = {
        "client_id" => CLIENT_ID,
        "response_type" => "code",
        "scope" => Communications.encodeURL("user:read"),
        "redirect_uri" => "https://localhost"
    };
    Communications.registerForOAuthMessages(method(:handleOAuth));
    Communications.makeOAuthRequest(
        "https://auth.example.com/authorize", params, "https://localhost/callback",
        Communications.OAUTH_RESULT_TYPE_URL,
        { "code" => "auth_code", "error" => "auth_error" });
}

function handleOAuth(message) {
    if (message.data != null) {
        var code = message.data["auth_code"];
        // exchange code for access token via makeWebRequest
    }
}
```
Flow: app calls `makeOAuthRequest()` → user gets a **phone notification** and logs in there (never on the watch) → device app shows "open your phone" → result returns to `registerForOAuthMessages()`. Results are **cached on-device** if your app closed early, and delivered the next time you register. Combine with `Background.registerForOAuthResponseEvent()` to catch the result in a background service. Store the token in `Application.Storage`, not Properties.

---

## 7. Background services (API 2.3.0+)

### Registration events
| Event | Register with | API |
|---|---|---|
| Temporal (time or interval) | `Background.registerForTemporalEvent()` | 2.3.0 |
| Goal reached | `registerForGoalEvent(goalType)` | 2.3.0 |
| OAuth response | `registerForOAuthResponseEvent()` | 2.3.0 |
| Sleep time | `registerForSleepEvent()` | 2.3.0 |
| Wake time | `registerForWakeEvent()` | 2.3.0 |
| Steps (every 1000 steps) | `registerForStepsEvent()` | 2.3.0 |
| Activity completed | `registerForActivityCompletedEvent()` | 3.1.0 |
| Phone app message | `registerForPhoneAppMessageEvent()` | 3.2.0 |

Each has a matching `delete*Event()` and `get*EventRegistered()` query; plus `getTemporalEventRegisteredTime()`, `getLastTemporalEventTime()`.

### Hard limits
- **Minimum temporal interval: 5 minutes.** *"Temporal events cannot be set to occur less than 5 minutes after the last temporal event occurred."* The restriction resets on app startup for `Moment`-based events.
- **30 second runtime.** Services are terminated automatically if they don't call `Background.exit()` within 30 seconds of opening. They can also be killed at any time to free memory for the foreground.
- **`Background.exit(data)` payload ≈ 8 KB** → `ExitDataSizeLimitException`.
- **`Background.requestApplicationWake(message)` ≤ 255 bytes** → `MessageSizeLimitException`.
- `InvalidBackgroundTimeException` for an interval/Duration under 5 minutes or an event scheduled too soon after the previous one.
- **Memory:** the background memory pool is *"much smaller than what is available for the application"* — often your whole compiled app will not fit. This is the single biggest constraint.

### The `:background` annotation
Only code decorated `(:background)` is compiled into the service. You must annotate the Application class, the ServiceDelegate, and every module/class/function/member they reach — including globals.

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
```monkeyc
const FIVE_MINUTES = new Time.Duration(5 * 60);
var eventTime = Time.now().add(FIVE_MINUTES);
Background.registerForTemporalEvent(eventTime);
```
```monkeyc
(:background)
class BackgroundServiceDelegate extends System.ServiceDelegate {
    function onTemporalEvent() {
        Background.requestApplicationWake("Launch Cool App?");
        Background.exit(null);
    }
}
```
With type-check level `informative` or above the compiler flags background code that reaches non-background symbols. The resource compiler has matching scope levels (see Resources → resource scopes).

### What works in the background
- **`Communications.makeWebRequest()` — yes.** This is the documented way to sync. It requires the `Communications` permission **and** the `Background` permission (the permission table footnotes Communications as requiring Background).
- **`Application.Storage` read/write — yes, API 3.2.0+.** `AppBase.onStorageChanged()` notifies the other process.
- **`Application.Properties.setValue()` — no.** Throws `ObjectStoreAccessException` on older devices; pass data forward via `Background.exit()` instead. `AppBase.deleteProperty()` / `clearProperties()` also blocked.
- **Position in the background:** `Position.enableLocationEvents()` is documented as widget/watch-app only under the Positioning permission; continuous GPS from a 30-second background service is not a supported architecture. Record points in the **foreground** (ideally inside an ActivityRecording session) and use the background only to flush them.
- Data returned by `Background.exit(data)` reaches the foreground via `AppBase.onBackgroundData(data)` — immediately if the app is running, otherwise right after `onStart()`. `Background.getBackgroundData()` reads the pending payload.

### Simulating
Simulator → *Simulation* menu → trigger background services manually. It loads the background service of the most recently run app and fires the chosen `ServiceDelegate` callback regardless of registration.

---

## 8. Permissions (`manifest.xml`)

```xml
<iq:application>
  <iq:permissions>
    <iq:uses-permission id="Sensor"/>
  </iq:permissions>
  <iq:products>
    <iq:product id="round-watch"/>
  </iq:products>
</iq:application>
```
`iq:application` attributes: `id` (128-bit UUID), `entry` (your `AppBase` class), `name` (string resource), `launcherIcon` (bitmap resource), `type`, `minApiLevel`. `barrels` declares library dependencies with exact / greater-or-equal / pessimistic version matching.

**App types:** `watchface`, `datafield`, `widget`, `watch-app`, `audio-content-provider-app`.

| Permission | Unlocks | Watch face | Data field | Widget | App | Audio |
|---|---|---|---|---|---|---|
| `Ant` | `Toybox.Ant` | — | ✓ | ✓ | ✓ | ✓ |
| `Background` | `Toybox.Background` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `BluetoothLowEnergy` | `Toybox.BluetoothLowEnergy` | — | ✓ | ✓ | ✓ | ✓ |
| `Communications` | `Toybox.Communications`, `Toybox.Authentication` | ✓* | ✓** | ✓ | ✓ | ✓ |
| `ComplicationProvider` | `Toybox.Complications` (publish) | — | — | — | ✓ | ✓ |
| `ComplicationSubscriber` | `Toybox.Complications` (subscribe) | ✓ | — | — | — | — |
| `DataFieldAlert` | `WatchUi.DataFieldAlert` | — | ✓ | — | — | — |
| `Fit` | `Toybox.ActivityRecording`, `Toybox.FitContributor` | — | — | — | ✓ | — |
| `PersistedContent` | `Toybox.PersistedContent` | — | — | ✓ | ✓ | ✓ |
| `PersistedLocations` | `Toybox.PersistedLocations` (deprecated) | — | — | ✓ | ✓ | ✓ |
| `Positioning` | `Position.getInfo()`, `Position.enableLocationEvents()` | ✓*** | ✓**** | ✓ | ✓ | ✓***** |
| `Sensor` | `Toybox.Sensor` | — | ✓ | ✓ | ✓ | ✓ |
| `SensorHistory` | `Toybox.SensorHistory` | — | — | ✓ | ✓ | ✓ |
| `SensorLogging` | `Toybox.SensorLogging` | — | — | — | — | — |
| `UserProfile` | `Toybox.UserProfile` | ✓ | ✓ | ✓ | ✓ | ✓ |

\* `Authentication` does not itself require `Background`. \*\* `Communications` requires `Background`. \*\*\*/\*\*\*\*/\*\*\*\*\* only widgets and watch-apps may call `enableLocationEvents()`; other types are limited to `getInfo()`.

**For the tree-mapping app** (type `watch-app`): `Positioning`, `Communications`, `Background`, `Fit` (if recording a FIT), `PersistedContent` (if saving native waypoints), optionally `Sensor` and `UserProfile`. Every added permission is shown to the user at install and is a conversion cost — do not request what you don't use.

---

## 9. Practical gotchas and quotas

**Positioning**
- `Position.Info.position` is **dead-reckoned between fixes** and then freezes. Always store `accuracy` (`Position.Quality`) and `when` (`Time.Moment`) with every captured point, and discard anything with `accuracy < QUALITY_USABLE`.
- `Location` stores radians internally; `toDegrees()` returns `[Double, Double]`. Don't round-trip through Float — you lose metres.
- `hasConfigurationSupport()` before every `:configuration` request; multi-band L1+L5 needs API 3.3.6 and specific hardware.
- `LOCATION_CONTINUOUS` is the battery hog. For discrete tree points, `LOCATION_ONE_SHOT` plus a settle delay, or keep continuous on only while the user is in "capture mode".
- Call `Position.enableLocationEvents(Position.LOCATION_DISABLE, ...)` when done — the GPS does not turn itself off.
- Simulator GPS is unreliable on macOS for activity-type apps (known bug); test on hardware.

**Storage**
- Budget **8 KB per value, 128 KB total**. A tree record of ~60 bytes JSON-ish means roughly 100–150 points per 8 KB value. Chunk: `points_0`, `points_1`, … with an index key, rather than one growing Array — rewriting one huge value on every capture is slow and risks a partial write.
- Arrays/Dictionaries in Storage cannot hold Symbols.
- Old object-store `.STR` data does **not** migrate automatically.
- `Properties.setValue()` on an undeclared key throws; `Storage.setValue()` on any key does not.
- `Storage.setValue()` writes to disk immediately — that is a flash write per call. Batch.

**Web requests**
- **HTTPS only** (`SECURE_CONNECTION_REQUIRED` -1001) and the cert chain must validate through the phone.
- Everything routes through Garmin Connect Mobile over BLE. If GCM is killed or the phone is out of range you get `BLE_CONNECTION_UNAVAILABLE` (-104). **Design for offline-first**: capture to Storage, upload opportunistically, only delete after a 2xx.
- Request bodies are small — `BLE_REQUEST_TOO_LARGE` (-102) bites quickly. Upload in batches of a handful of points, not a whole day.
- `NETWORK_RESPONSE_TOO_LARGE` (-402) and `NETWORK_RESPONSE_OUT_OF_MEMORY` (-403) mean the watch cannot hold the parsed response. Keep server responses tiny (an ack with a count, not echoed data). Use `:responseType => HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN` when you only need a status.
- `BLE_QUEUE_FULL` (-101): don't fire parallel requests. Serialise — one in flight, next one from the callback.
- `responseCode` 200 is not the only success path; always branch on the negative codes separately from HTTP codes.
- `openWebPage()` gives you no success callback at all.
- Throughput over BLE is slow enough that the Android ADB bridge deliberately throttles to match — use it to measure realistic sync times.

**Background**
- 5 minutes minimum, 30 seconds maximum, ~8 KB out. That trio defines your sync architecture: a background temporal event can realistically push one small batch per wake.
- The `(:background)` annotation must decorate a complete transitive closure, including the Application class and globals. Missing one is the most common background build/runtime failure.
- Background memory is far smaller than foreground; keep the service code minimal (no UI, no layouts, no big constants) and let resource scopes exclude assets.
- `Background.exit()` must be called or you are killed at 30s.
- Services can be killed at any moment to free memory — never treat a background run as guaranteed.

**Recording / FIT**
- `fitField id` in resources must equal the `fieldId` in `createField()`.
- Chart (`MESG_TYPE_RECORD`) fields must be numeric and should be set once per second.
- The simulator does **not** auto-start recording for data fields; start it explicitly.
- FIT developer fields are the cleanest path to get structured field data into Garmin Connect and then out via the Connect Developer Program — worth considering as a second, redundant channel alongside your own HTTP upload.

**General**
- Gate everything: `Toybox has :ModuleName` and `Module has :functionName`. Device capability varies enormously across the ~100+ supported products.
- `System.getSystemStats()` gives `freeMemory` / `totalMemory` / `usedMemory` — instrument early; memory, not CPU, is what kills Connect IQ apps.
- `System.getTimer()` rolls over roughly every 50 days after boot.
- Watch faces get almost nothing: no `enableLocationEvents`, no `Fit`. A tree-mapping product must be a `watch-app` (plus optionally a glance view via `AppBase.getGlanceView()`, API 3.1.0).

### Suggested architecture for the tree-mapping app
1. `watch-app` with permissions `Positioning`, `Communications`, `Background`, `Fit`, `PersistedContent`.
2. Foreground: `ActivityRecording.createSession({:sport => Activity.SPORT_HIKING})` running so the track is captured as a FIT file for free; `Position.enableLocationEvents` with the best supported `:configuration`.
3. On each tree capture: read `Position.getInfo()`, require `accuracy >= QUALITY_USABLE`, append `[lat, lon, altitude, accuracy, when, speciesId, notes]` to a chunked `Application.Storage` buffer; optionally `PersistedContent.saveWaypoint()` so the user can navigate back; optionally a `FitContributor` session field for the tree count.
4. Register a temporal background event (5 min or longer). In `onTemporalEvent()`: read the oldest unsent chunk from Storage, `makeWebRequest()` POST JSON to your server, and on success mark it sent via `Storage.setValue()` (allowed from background since 3.2.0) before `Background.exit()`.
5. Offer a manual "Sync now" that calls `Communications.startSync()` with a `SyncDelegate` for a fast Wi-Fi flush of a large backlog.
6. OAuth to your server via `Toybox.Authentication.makeOAuthRequest()`; cache the token in `Application.Storage`; refresh from the background using `registerForOAuthResponseEvent()`.

---

## URLs used

Core topics articles (raw article files — the rendered `/core-topics/` pages are client-side rendered and do not return body text to fetchers):
- https://developer.garmin.com/connect-iq/core-topics/
- https://developer.garmin.com/connect-iq/articles/core-topics/Positioning.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Persisting_Data.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Properties_and_App_Settings.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Activity_Recording.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Sensors.html
- https://developer.garmin.com/connect-iq/articles/core-topics/HTTPS.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Authenticated_Web_Services.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Downloading_Content.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Communicating_with_Mobile_Apps.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Mobile_SDK_for_Android.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Mobile_SDK_for_iOS.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Bluetooth_Low_Energy.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Ant_and_Ant_Plus.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Backgrounding.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Manifest_and_Permissions.html

API docs:
- https://developer.garmin.com/connect-iq/api-docs/
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Position.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Position/Info.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Position/Location.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityRecording.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityRecording/Session.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Activity/Info.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/FitContributor.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Sensor.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/SensorHistory.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/SensorLogging.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Authentication.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AppBase.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Properties.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/PersistedContent.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/PersistedLocations.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/BluetoothLowEnergy.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/UserProfile.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/System.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityMonitor.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Complications.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Cryptography.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Media.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Weather.html

Other:
- https://developer.garmin.com/connect-iq/connect-iq-faq/how-do-i-create-a-connect-iq-background-service/
- https://developer.garmin.com/gc-developer-program/overview/

---

**Caveats.** Two documented numbers conflict on Storage value size (8 KB in the Persisting Data article vs 32 KB on the `Application.Storage` API page) — I flagged both and recommended the conservative one. Per-device background memory ceilings are not published as a single table; they live in the per-device pages of the device reference and vary by product and app type, so confirm against your target device list before committing to a background design. Direct `curl` to developer.garmin.com is blocked by the egress proxy in this environment, so everything above came through the fetch tool; the Bluetooth LE core-topic article covers only nRF52 hardware setup, so the BLE detail above is from the API reference.