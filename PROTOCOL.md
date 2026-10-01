# Watch to phone protocol, version 1

The contract between the TreeMapper GPS watch app and the TreeMapper phone app.
Implement the phone side against this. Nothing here needs the server.

---

## The constraint that shapes everything

`Position.enableLocationEvents()` is limited to **device apps and widgets**. A
Connect IQ background service can receive a phone message, but it cannot turn
the GNSS receiver on, so it could only ever return a stale cached position.

**Therefore the watch app must be running in the foreground to produce a fresh
fix.** The phone cannot silently pull an accurate coordinate from a sleeping
watch. That is a platform limit, not a design choice.

A cold multi-band fix takes tens of seconds under canopy. So the model is:

> The person opens the watch app when they reach the plot and leaves it running.
> The receiver stays warm for the session. Every request is then answered from
> an already converged fix, in milliseconds.

The phone can still call `openApplication()` to launch the watch app if it is
not running, but that costs the acquisition wait.

---

## Transport

Connect IQ Mobile SDK, over Bluetooth, via Garmin Connect Mobile.

- **Android**: `ConnectIQ.sendMessage()` / `registerForAppEvents()`
- **iOS**: `ConnectIQ.sharedInstance().sendMessage()` / `registerForAppMessages()`
- **Watch**: `Communications.transmit()` / `Communications.registerForPhoneAppMessages()`

Every message is a **Dictionary** (Map on Android, NSDictionary on iOS).

### Garmin Connect Mobile: required, but differently on each platform

This is verified against Garmin's own SDK articles. The two platforms are not
the same, which matters for what TreeMapper has to tell the user.

**Android. Hard runtime dependency for everything.**

> "In order for your companion application to communicate with a Connect IQ
> device the user must also install Garmin Connect Mobile onto their phone."
>
> "All communication for companion applications running on Android goes through
> a Garmin Connect Mobile service to reach the device."
>
> "When initializing the SDK with a wireless connection type this requirement is
> checked and initialization will fail if Garmin Connect Mobile is not
> installed."

Passing `true` as the `autoUI` argument to `initialize()` makes the SDK show the
user a prompt to install or upgrade Garmin Connect, with a link to the Play
Store. The demo app does this.

**iOS. Required for discovery and install, not for messaging.**

> "Unlike the Mobile SDK for Android, apps created with the Mobile SDK for iOS
> are standalone apps and do not directly rely on Garmin Connect Mobile (GCM) to
> communicate with a wearable device. They do, however, require GCM to initially
> discover Connect IQ-compatible devices that are available for communication,
> or to install Monkey C applications on the wearable device."

So on iOS, GCM is needed at least once, for the device picker and to install the
watch app, and the two apps hand off through the iOS URL scheme. After that,
messaging is direct Bluetooth and GCM does not have to be running.

**There is no way around it.** A phone cannot reach the watch outside this path:
`Toybox.BluetoothLowEnergy` "provides access to Generic BLE communication
functionality in the central role" only. The watch can scan for and connect to
BLE peripherals; it cannot advertise as one, so a phone cannot connect to it
directly.

**What this means for TreeMapper:** Garmin Connect must be installed on both
platforms before any of this works, and on Android it must stay installed. When
it is missing the failure is silent from the user's point of view, so detect it
and say so rather than showing an empty device list.

---

## Messages

### Phone to watch

| Message | Meaning |
|---|---|
| `{"c":"hello"}` | Identify and ask for current state. Answered with `ready`. |
| `{"c":"fix","r":<Number>}` | Send one point now, tagged with request id `r`. |
| `{"c":"ping"}` | Keepalive. Answered with `ready`. |

### Watch to phone

**`ready`** — sent on app start and in answer to `hello` or `ping`.

```json
{"t":"ready","v":1,"q":3,"gps":1,"mb":1,"buf":0}
```

| Field | Meaning |
|---|---|
| `v` | Protocol version. Currently 1. |
| `q` | Current fix quality, 0 to 4. See the table below. |
| `gps` | 1 when the receiver is running. |
| `mb` | 1 when this device gave a multi-band (L1 + L5) solution. |
| `buf` | Always `0`. Kept for wire compatibility; the watch holds nothing. |

**`pt`** — a point.

```json
{"t":"pt","n":48,"r":17,"src":"phone",
 "lat":12.3456789,"lon":77.1234567,"alt":812.4,
 "q":4,"ts":1789412345,"spd":0.2}
```

| Field | Type | Meaning |
|---|---|---|
| `n` | Number | Sequence number, from 1, counting from when the app opened. Not stable across restarts. |
| `r` | Number or null | The request id this answers, or null when the watch button started it. |
| `src` | String | `"phone"` or `"watch"`. |
| `lat`, `lon` | **Double** | Degrees. See the precision warning below. |
| `alt` | Float or null | Metres above mean sea level. |
| `q` | Number | `Position.Quality`, 0 to 4. |
| `ts` | Number | **GPS** epoch seconds of the fix, not the watch clock. |
| `spd` | Float or null | Metres per second. Useful for spotting a moving user. |

**`err`**

```json
{"t":"err","r":17,"code":"no_position"}
```

| Code | Meaning |
|---|---|
| `no_position` | The receiver has never produced a position. Not a quality judgement. |

`queue_full` was retired when the outbox was removed. A phone built against an
earlier draft can keep handling it; the watch will never send it.

---

## Two rules worth stating plainly

### The watch never filters on quality

Every point goes out with `q` attached, whatever it is. The watch refuses only
when there is literally no position to send. **The phone owns the policy** on
what is good enough to keep.

| `q` | Constant | Meaning |
|---|---|---|
| 0 | `QUALITY_NOT_AVAILABLE` | no fix |
| 1 | `QUALITY_LAST_KNOWN` | stale cached position |
| 2 | `QUALITY_POOR` | 2D fix, few satellites |
| 3 | `QUALITY_USABLE` | 3D fix, marginal precision |
| 4 | `QUALITY_GOOD` | 3D fix, good precision |

There is **no metric accuracy**. Connect IQ reports this enum and nothing else,
unlike Android which gives metres. Store `q` as its own column and flag the
point's source, per `DESIGN.md` section 9.

### Coordinates are Doubles

`lat` and `lon` are 64-bit. A 32-bit float carries about 7 significant digits,
which is not enough for `12.3456789`. **Make sure the phone side deserialises
them as `double`, not `float`.** This is the easiest thing to get wrong here and
the hardest to notice: the data looks plausible and is quietly wrong by metres.

---

## Optional fields are absent, not null

`alt`, `spd` and `r` are omitted entirely when they have no value, rather than
sent as null. Read a missing key as null on the phone.

This is not cosmetic. A Dictionary carrying null values has to be serialised
into a Java `Map` across the link, and that path is a prime suspect for
simulator crashes on transmit. The watch strips nulls before every send.

---

## If the simulator crashes when the watch transmits

**Most likely cause: the phone is not listening, and cannot be.** Over the
tethered (ADB) transport the Connect IQ simulator stamps outbound messages with
an **empty application id** instead of the one in `manifest.xml`. The Android
SDK routes by that id, so `registerForAppEvents(device, IQApp(<real id>))` is
never called. The watch transmits, is never acknowledged, retries into a socket
nobody reads, and the simulator dies with `Socket Error in packet header 0`.

The fix is one line on the phone: register a second listener for `IQApp("")`.
The demo app does this in `WatchLink.listenForMessages()`. The same transport
also reports `getApplicationInfo()` as `UNKNOWN` for an app that is running, so
never gate the listener on it.

Reported at
<https://forums.garmin.com/developer/connect-iq/f/discussion/379720/android-mobile-sdk---tethered-connection---app-status-unknown>.

Nothing in the watch code causes this and nothing in the watch code can fix it.

---

If it still crashes after that, the rest of this section applies.

This is a known rough edge, not something you are doing wrong. Garmin's own
forums carry unresolved reports around phone messaging and the tethered
transport, including an Android SDK bug where one send fires both a SUCCESS and
a FAILURE_UNKNOWN callback. The watch code works around what it can.

To find which part is at fault, bisect by payload. The two message types differ
in exactly the ways that matter:

| | `ready` | `pt` |
|---|---|---|
| Null values | none | had three before the fix |
| `Double` values | none | `lat`, `lon` |
| Sent from | a timer tick | a timer tick |

So press **Hello** in the demo app first.

- **`ready` arrives, `pt` crashes it** — the problem is in the point payload.
  Nulls are already stripped, so the next suspect is `Double`. Try sending
  `lat`/`lon` as Strings and parsing them on the phone. That keeps full
  precision and sidesteps numeric serialisation entirely.
- **`ready` crashes it too** — the transport itself is the problem, not the
  data. Test on a real watch before spending more time on it.
- **Neither crashes** — it was the null values, now fixed.

Two structural rules the watch already follows, both worth keeping if you
rewrite this:

1. **Never transmit from inside the receive callback.** Sending from within
   `onPhoneMessage` re-enters the comms stack. Commands set a flag and the next
   tick does the work.
2. **Never transmit from `AppBase.onStart`.** Too early; no view, no settled
   link. The first tick sends the opening `ready`.

---

## Delivery

**The watch stores nothing.** There is no outbox and no session record. One fix
exists at a time, in memory, from the moment the user asks to send it until the
phone acknowledges it at the transport level. The watch then forgets it.

The watch sends one parcel at a time, because the BLE link returns
`BLE_QUEUE_FULL` when several are pushed at once.

If a send fails, the fix stays in hand and the watch says `NOT SENT` on screen.
The **user** decides what happens next: press again to retry the same fix, or
restart and take a new one. There is no automatic retry on a timer, precisely
so a fix the user has given up on cannot arrive later on its own.

What this means for the phone:

- **Nothing accumulates while you are out of range.** A fix taken with the
  phone unreachable is not kept. The person has to be in range to record a
  tree, and the watch tells them so.
- **Duplicates are still possible**, if an acknowledgement is lost after the
  phone already stored the point and the user then retries. Deduplicate on `n`,
  which counts from 1 each time the watch app opens.
- **`n` is not a durable identifier.** It resets whenever the app restarts, so
  pair it with your own arrival timestamp if you need a stable key.

---

## Suggested phone flow for the modal

```
user taps "Get GPS from watch"
  → modal opens
  → ConnectIQ.initialize(), wait for onSdkReady
  → getConnectedDevices()
       none? "No Garmin watch paired" and stop
  → getApplicationInfo(APP_UUID)
       not installed? openStore(APP_UUID)
  → registerForAppEvents()
  → sendMessage({"c":"hello"})

       ready arrives with gps=1 and q>=3
         → sendMessage({"c":"fix","r":<n>})
         → pt arrives, modal closes

       ready arrives with gps=0, or nothing arrives in ~2s
         → openApplication()
         → show "starting watch receiver", keep polling with ping
         → show live q from each ready message
         → once q >= 3, send the fix request
```

Two states worth designing for in the modal, because they are the ones that
happen in the field:

- **Watch app not running.** `openApplication()` then a wait that can run to a
  minute. Show the live quality from `ready` so the wait is legible.
- **Quality below 3.** Do not block. Offer the point with a warning, since the
  person may be under canopy where 3 is the best available all day.

---

## Testing without a watch

The Android SDK has a simulator transport:

```
ConnectIQ.getInstance(IQCommProtocol.ADB_SIMULATOR)   // port 7381
adb forward tcp:7381 tcp:7381
```

Then *Connection > Start* (Ctrl-F1) in the Connect IQ simulator. It throttles to
real Bluetooth speeds, which is the right place to test the modal's timing and
its reconnect behaviour.
