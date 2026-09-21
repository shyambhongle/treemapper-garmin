# Testing on real hardware

Two separate exercises. The first proves the link works. The second proves the
watch is actually more accurate than a phone, which is the only reason this
project exists. Do them in that order, but do not skip the second: if the
accuracy gain is not there, the link working is irrelevant.

---

## 0. What to buy

One watch is enough to start. Two lets you compare.

The requirement is **multi-band GNSS (GPS L1 + L5)**. Single-band Garmin watches
will not reliably beat a good phone under canopy, so buying one would prove
nothing. At the time of writing that means roughly:

fēnix 7 Pro / 7X Pro, fēnix 8, epix Pro (Gen 2), Forerunner 955, Forerunner 965,
Enduro 3, Instinct 2X Solar, quatix 7 Pro, tactix 7.

**Do not trust that list, or the marketing page.** Verify on the actual unit:
the watch reports its own GNSS capability, and the demo app prints it. The
`ready` message carries `mb`, and the app shows **multi-band** or
**single-band** on the watch status line. If a new watch says single-band,
return it.

You also need an Android phone with **Garmin Connect Mobile** installed and
signed in. That is not optional for a real watch; see `PROTOCOL.md`.

---

## 1. Bench test: does the link work

About thirty minutes, indoors except for the last two steps.

### Set up

1. **Pair the watch in Garmin Connect Mobile.** Pairing in Android's Bluetooth
   settings is not enough; Garmin Connect holds the pairing.
2. **Build the watch app for that exact device.** In VS Code run
   `Monkey C: Edit Products`, select your model, then
   `Monkey C: Build for Device`. You get a `.prg`.
3. **Copy the `.prg` into `GARMIN/APPS` on the watch** over USB.

   On macOS, newer music-capable watches (epix, fēnix 7/8, FR955/965) **do not
   mount in Finder**. You need an MTP client: OpenMTP or Android File Transfer.
   This surprises everyone once.

   The file will vanish from `GARMIN/APPS` after you disconnect. That is normal
   on current firmware: the app is moved into storage you cannot browse. Check
   the watch's Connect IQ app list instead.

4. **Install the demo app** (`android-demo/`) on the phone, and leave the
   "ADB simulator" switch **OFF**. That is the real-watch mode.

### Run, in order, and stop at the first thing that fails

| # | Action | Expect | If it fails |
|---|---|---|---|
| 1 | **Find watch** | device name, `CONNECTED` | Watch asleep, or not paired in Garmin Connect |
| 2 | (automatic) | app line shows `installed vN` | The sideload did not take, or the app id does not match `manifest.xml` |
| 3 | **Hello** | `ready` arrives; watch line shows quality and **multi-band** | Nothing arrives: the watch app is not running. Open it on the wrist and retry |
| 4 | **Open watch app** | app launches on the wrist | See the note below, this is a real open question |
| 5 | **Request GPS point** | a point, round trip under ~1 s | Watch outdoors yet? Indoors there may be no fix at all |
| 6 | Press START **on the watch** | point arrives unprompted, `from watch` | |
| 7 | Walk 30 m away, press START twice | watch shows a backlog, nothing lost | |
| 8 | Walk back | backlog flushes automatically | |

### Two things to record while you are there

**Does `openApplication()` prompt the user?** Watch the wrist during step 4. The
documentation does not say, and the answer decides whether the TreeMapper modal
needs a "check your watch" state. This is the single most important unknown
left in the design.

**What type do the coordinates arrive as?** The point card prints a `type` line.
Right now the watch sends them as text (`SAFE_COORDS = true` in
`GpsService.mc`), a workaround for the simulator crashes. On real hardware, set
it to `false`, rebuild, and check whether `type` says `Double`. If it does, the
crashes were a simulator problem and you can keep the cleaner numeric form.

---

## 2. Field test: is the watch actually more accurate

This is the one that decides whether to buy fifty watches. It needs a plot with
canopy, because open sky is where phones already do fine.

### Method

Pick **20 to 30 trees** in a plot you can revisit, and mark each physically, with
tape or a peg, so you return to the same spot.

Record each tree **three times**:

1. TreeMapper on the Android device that shows poor accuracy today
2. TreeMapper on a good Android device
3. The watch, via the demo app

Then **walk the plot a second time** and record all three again. You now have
two independent readings per method per tree.

### What to compute

You probably have no surveyed ground truth, so use **repeatability** as the
measure: the distance between the two readings of the same tree by the same
method. Lower is better, and it needs no reference points.

| Method | Median repeatability | Worst case |
|---|---|---|
| Problem Android | | |
| Good Android | | |
| Watch | | |

If the watch's median is not clearly better than the good Android, the hardware
is not the answer and the problem is software. Check whether TreeMapper uses the
fused location provider rather than raw GNSS, and whether it waits for the fix
to converge, before spending on hardware.

### Also record

- **Time to first fix**, cold, under canopy. This is what the person waits for.
  A brand new watch downloads satellite data on its first outdoor use and can
  take several minutes; that is one-off, do not measure it as typical.
- **Battery over a full session**, receiver running continuously. The design
  assumes roughly a working day. Confirm it and publish the real number to field
  teams rather than a specification sheet figure.
- **Quality distribution**: how often the fix is `GOOD` versus `USABLE` under
  your canopy. If it sits at `USABLE` all day, the warn-below setting should
  default accordingly.

---

## 3. What the simulator can never tell you

For reference, so nobody re-litigates this:

- Real Bluetooth timing and dropouts. The ADB transport is a TCP socket.
- Real GNSS. Simulated position comes from a menu.
- Whether `openApplication()` prompts on the wrist.
- The Garmin Connect dependency, which TETHERED bypasses entirely.
- Battery.

The simulator is for protocol and interface work. Everything above needs a
watch on a wrist, outdoors.
