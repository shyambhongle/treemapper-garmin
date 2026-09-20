# Garmin Connect IQ — Distribution, Permissions, Review, Monetization

> **Sourcing caveat:** most `/core-topics/*`, `/app-review-guidelines/`, `/monetization/*` and `/connect-iq-faq/` pages are client-rendered (Gatsby) and return an empty body to fetchers. This section is reconstructed from sources that *do* render — the Toybox API reference, the Connect IQ Developer Agreement, the Brand Guidelines, `/submit-an-app/`, `/sdk/` — plus the Garmin developer forums and their maintained wiki. Items marked **[UNVERIFIED]** need a human to open the page in a browser. The trick discovered later in the research also applies here: article bodies are served as static HTML at
> `https://developer.garmin.com/connect-iq/articles/<section>/<File_Name>.html`
> so `.../articles/core-topics/Manifest_and_Permissions.html` etc. are readable and should be used to close the gaps below.

---

## 1. Permissions in `manifest.xml`

Declared as `<iq:permissions><iq:uses-permission id="X"/></iq:permissions>`. Edit them via the **VS Code Monkey C manifest editor**, not by hand — hand-editing is the usual cause of "not a valid permission id" build errors.

| Permission ID | Unlocks | Notes |
|---|---|---|
| `Communications` | `Toybox.Communications` — phone-proxied web requests, phone app messaging, mail box | Required for any server sync. On watch faces and data fields it also needs `Background`. |
| `Positioning` | `Toybox.Position` — GPS/GNSS, `enableLocationEvents()`, `getInfo()` | Highest user friction. The Developer Agreement separately requires the app **"does not default to collect location data about users and that users are notified and required to opt in."** `enableLocationEvents()` is only callable from widgets and device apps. |
| `Sensor` | `Toybox.Sensor` — onboard + ANT+ sensor data | |
| `SensorHistory` | `Toybox.SensorHistory` — historical HR, elevation, pressure, temperature, stress, SpO2, Body Battery | Health data, privacy sensitive. |
| `SensorLogging` | `Toybox.SensorLogging` | |
| `UserProfile` | age, gender, weight, height, HR zones, activity history | Privacy sensitive. |
| `Fit` | `Toybox.ActivityRecording` — start/stop/save activity, write FIT | Name mismatch: module is `ActivityRecording`, permission is `Fit`. Holding it also moves the app into the device's **Activities** list rather than the apps list. |
| `FitContributor` | write custom fields into the FIT file | Up to 16 developer metrics per activity. |
| `Background` | `Toybox.Background` — temporal, step, goal, sleep, wake, activity-complete triggers | **Hard limits: 5-minute minimum temporal interval; ~8 KB maximum payload returned from background to foreground; service killed if it does not `Background.exit()` within ~30 s.** |
| `Ant` | raw ANT radio, custom channels | |
| `BluetoothLowEnergy` | watch as BLE central — scan, pair, GATT | For non-Garmin hardware. |
| `PersistedContent` | routes, waypoints, courses, tracks, workouts | |
| `PersistedLocations` | save waypoints into the device's location list | Relevant for field mapping. |
| `Notifications` | `Toybox.Notifications` | API 5.1.0+ |
| `ComplicationProvider` / `ComplicationSubscriber` | publish (apps/ACP) / subscribe (watch faces) complications | API 4.1.0+ |
| `DataFieldAlert` | `WatchUi.DataFieldAlert` | Data fields only; user must also enable Settings → Alerts → Connect IQ. |
| `ActivityPrompts` | intercept auto-detected activity prompts | Data fields only, API 5.2.0+ |

### Modules needing **no** permission
`AntPlus`, `ActivityMonitor`, `Activity`, `Application` (incl. **`Storage` and `Properties`**), `Attention`, `Authentication` (OAuth — but the request rides on `Communications`), `Complications`, `Cryptography`, `Graphics`, `Lang`, `Math`, `Media`, `ScanCode`, `StringUtil`, `System`, `Time`, `Timer`, `WatchUi`, `Weather`.

**Practical consequence:** local on-device persistence via `Application.Storage` is friction-free. Every permission you add is shown to the user in the store before install, so more permissions = higher install drop-off. That, not review, is the main friction.

---

## 2. Getting an app onto a device

### 2a. Simulator
`Monkey C: Run` in VS Code. No account, no review. Debugging, profiling and unit tests are **simulator-only**.

### 2b. Sideloading over USB
- Build produces a **`.prg` per device product**; copy it to `GARMIN/APPS` over USB/MTP.
- On modern devices the `.prg` is **immediately moved into inaccessible storage** on connect/sync and disappears from `/GARMIN/Apps` (on FR255/955/965, fēnix 7/7 Pro, fēnix 8 it lands in `apps/media`, hidden). Sideloading still works; the file just vanishes from view.
- **Uninstalling a sideloaded app requires a computer** (Garmin Express) or the on-device Connect IQ "Installed" list. Not manageable from the phone app.
- **Phone-side app settings do not work for sideloaded apps.** Workarounds: generate a `.SET` file from the simulator, edit it, drop it into `/GARMIN/Apps/SETTINGS` with a filename matching the `.prg`; or configure in-app; or fetch config from your own server at runtime.
- If a store app shares the app ID, the sideloaded copy gets a randomly generated display name.
- macOS: newer music-capable watches do not mount in Finder — an MTP tool is needed.

### 2c. Beta apps
- Mark an app beta in the developer dashboard. Beta apps are **not reviewed** and never get "approved" — that is normal.
- **Only the developer account that owns the app can install it.** No tester invites, no allowlist. Open feature request since 2017–2018, unimplemented.
- To install your own beta: take the app identifier from the dashboard, open `https://apps.garmin.com/en-US/apps/<identifier>` on the phone so the Connect IQ app handles it. Links from the newer `apps-developer.garmin.com` dashboard **do not** open in the Connect IQ app (its intent filter only knows the old domain) — acknowledged bug CIQQA-3722.

### 2d. Connect IQ Store submission
1. Declare every supported product in `manifest.xml`.
2. **Monkey C: Export Project** → produces the **`.iq`** bundle (one `.prg` per product). The wizard also lets you update the supported-language list.
3. Upload the `.iq` at `apps.garmin.com/developer/dashboard` (newer instance `apps-developer.garmin.com`). Once validated, add description and screenshots. Garmin: *"Be very specific in your description."*
4. Review. While pending, the app is hidden but the developer can preview and install it.

**Review timeline: no published SLA.** Observed in forums: updates to an approved app can clear in a couple of hours; new apps commonly take days, with threads reporting 10–11+ days. Plan 1–2 weeks for a first submission. Recourse is the forum or the developer contact form.

### 2e. Common rejection reasons
Garmin's stated grounds: inappropriate content or behaviour; apps that do not function or crash; GPS data used in a way that violates the developer terms; trademarked or copyrighted content without permission.

Categorical exclusions from the Garmin-maintained forum wiki ("App Approval Exceptions"):
- **Extreme sports** — scuba, free diving, skydiving, base-jumping, extreme flight sports will not be listed.
- **Aviation** — allowed except watch faces, and only with the disclaimer *"WARNING: The app is intended only as an in-flight aid and should not be used as a primary information source."*
- **Safety awareness** — incident detection and Varia radar integration blocked.
- **Medical** — may need FDA clearance; otherwise the listing must state it is *"not intended to be used for the purposes of medical treatment and is intended for educational purposes only."*
- **Chinese national flag** cannot appear in apps rendered on Garmin devices.
- Also rejected in practice: anchor-alarm / geofence-alert apps, radar apps.

The same wiki notes developers **may distribute rejected apps outside the Connect IQ Store** — Garmin's own words acknowledge off-store distribution as legitimate.

---

## 3. Review rules that actually bite

- **Functionality** — crashes and non-functioning apps are a stated rejection ground.
- **Content** — explicit sexual content prohibited, including linking to it. User-generated content must be moderated by you. A Garmin employee approved a Wikipedia-browser concept on the basis that the upstream service's own terms align with Garmin's guidelines, i.e. external content is judged by the upstream service's terms rather than banned outright.
- **GPS** — must not violate the developer terms; no default collection, explicit opt-in.
- **Privacy** — the Agreement requires a privacy policy complying with applicable law if you collect user data; no retention beyond necessity without consent; **you may not sell or transfer user data received from Garmin**; immediate notification of unauthorised access.
- **Trademarks** — no Garmin name, logo or marks in your app without permission. After approval you may promote compatibility, following the brand guidelines. No press release claiming a Garmin partnership without written consent.
- **Connect IQ brand assets** — do not alter them. Approved colours: Connect IQ blue `#109AD7`, black `#000000`, white `#FFFFFF`.
- **Payment** — nothing readable prohibits external payment/unlock flows; Garmin's own trial mechanism is built around a developer-supplied unlock URL. Markedly more permissive than Apple. **[UNVERIFIED]** whether the guidelines page adds restrictions.
- **Battery** — no explicit editorial rule found. Enforcement is architectural: 5-minute background minimum, ~8 KB background payload, watchdog kills long-running foreground code.

---

## 4. Monetization

- Become an onboarded **merchant**, then sell paid apps in the store.
- **Cost: non-refundable annual fee of USD 100 plus 15 % commission** on the tax-exclusive price (figures from developer reports and a secondary write-up — the Agreement itself only says "in the amounts specified in the Documentation"). Garmin absorbs card processing; digital service taxes and currency conversion are deducted from payouts.
- Payout schedule and minimum threshold **[UNVERIFIED]**. Refunds are handled by holding funds or offsetting future payments. Tax documentation required.
- **Price points** are a fixed ladder chosen in the dashboard. Exact tiers **[UNVERIFIED]**.
- **Device support is a real constraint** — paid apps only work on newer devices with monetization support; older watches (e.g. FR945) are excluded.
- **Switching a free app to paid** re-triggers review, temporarily removes it from the store, and **existing users must repurchase**. Garmin supplies promotion codes to migrate customers.
- **Trial apps** — `AppBase.allowAppTrial()`, `getTrialDaysRemaining()`, `isTrial()` (SDK 2.3.0+). Configured via "App Trial Information" in the manifest editor including an unlock URL. Officially thin documentation; possibly aimed at Garmin Partners. **Genuinely under-documented.**
- **Third-party payment is tolerated** — developers run their own storefronts with unlock codes. One reports the alternative edition generated ~5 % of in-store volume; discovery, not policy, is the limiting factor.

---

## 5. Store listing assets

| Asset | Spec |
|---|---|
| Store app icon | **500 × 500 px**, max **300 KB**. Simple; avoid black or transparent backgrounds, descriptive text, clip art, fine detail. No Garmin branding without permission. |
| Cover image | 500 × 500 px, max 300 KB |
| Screenshots | max **150 KB** each. Pixel dimensions and count **[UNVERIFIED]**; forum consensus is the limits are dated and produce blurry listings on modern phones. |
| Hero image | **1440 × 720 px**; separate version per language if it contains text |
| On-device launcher icon (in the bundle) | **128 × 128 px**; full-colour for AMOLED, low-colour constrained to a **64-colour palette** for memory-in-pixel displays |
| Description | Free text. *"Be very specific."* Required disclaimers (medical, aviation) go here. Character limits **[UNVERIFIED]**. |
| Supported devices | Driven by `<iq:products>`; the `.iq` carries one `.prg` per product |
| Languages | Set during Monkey C: Export Project; must also be declared in the manifest or jungle `lang` overrides are silently ignored |

---

## 6. Enterprise / internal distribution — for deploying to field staff

**Garmin has no enterprise or MDM channel for Connect IQ, and no private or unlisted store listing.** No equivalent of Apple Custom Apps or Managed Google Play private tracks.

**Not possible:**
- Unlisted, private, invite-only or org-scoped store listings. Apps are either public or developer-only beta, nothing in between.
- Inviting colleagues to a beta — only the owning account can install.
- Per-organisation signing, provisioning profiles, device enrolment. None exist.
- Remote install/update to staff devices without either the public store or a physical USB connection.

**Possible, ranked for a field-data deployment:**

1. **Sideload over USB to each device.** No account, no review, no public exposure. The honest answer for 5–50 devices. Costs: physically touch each device for install and every update; build and copy the right `.prg` per model; phone-side settings do not work so configuration must be in-app, in a manually placed `.SET`, or fetched from your own server; uninstall needs a computer. Garmin's own wiki acknowledges off-store distribution, and the Agreement's redistribution ban is worded against *"the Program Materials"* (the SDK), not your compiled app. **Legally vague** — the Agreement also appoints Garmin as your distribution agent for the store and is not explicit about off-store distribution of your own app. For a large or contractual deployment, get this confirmed in writing via Garmin's developer contact form.

2. **Publish publicly, gate functionality behind a credential.** Require a key you email out, or org SSO via `Toybox.Authentication` (OAuth through the Connect IQ phone app) plus `Communications`. Upside: normal store install, over-the-air updates, working phone-side settings, no USB. Downsides: the app and its description are publicly visible and searchable; review takes days to weeks and a GPS field-data app invites scrutiny; confused non-staff users can leave low ratings. Mitigate with a blunt description ("Internal tool for [org] field staff; requires an organisation account").

3. **Beta app per developer account.** Only works if every staff member shares one Garmin account, which the Agreement forbids and which breaks per-user data attribution. **Do not build on this.**

4. **Ask Garmin.** An OEM/Partner track appears to exist (trial apps seem gated to Partners). Nothing about enterprise deployment is documented publicly. **[UNVERIFIED]**

**Recommended shape:** sideload for pilot and small teams; if the fleet outgrows USB, publish publicly with an org-account gate and drive configuration from your own server rather than Connect IQ app settings. Architect around the two hard limits regardless — background events no more often than every 5 minutes, ~8 KB per background-to-foreground handoff. Bulk data should go straight from the background web request to your server, never through the foreground app. `Application.Storage` is permission-free, so buffering observations on-device costs nothing in user friction.

---

## 7. Accounts, agreement, support

- **Garmin Developer Account** — free. Must be 18+, register accurately, keep the account in good standing, **not share credentials**. Downloading the SDK signifies acceptance of the Agreement.
- **Dashboard** — `apps.garmin.com/developer/dashboard`, newer instance `apps-developer.garmin.com`. Log into the Garmin forum first. The two domains are not interchangeable for install links.
- **Connect IQ Developer Agreement** — limited, non-exclusive, revocable SDK licence for development and testing only; no redistributing or sublicensing the Program Materials; you appoint Garmin as your distribution agent and grant a royalty-free licence to use your app for testing and distribution; **Garmin may refuse or remove any app without explanation**; SDK "as is"; either party may terminate on 30 days' notice; on termination your app is pulled but **copies already downloaded keep working**.
- **Support** — `forums.garmin.com/developer/` (Garmin staff do answer; the maintained wiki carries the approval exceptions), news/blog at `forums.garmin.com/developer/connect-iq/b/news-announcements`, plus the developer contact form. No ticketed SLA.
- **Current SDK: Connect IQ 9.2.0**, released 25 August 2026. SDK Manager for Windows, macOS, Linux; VS Code Monkey C extension is the primary toolchain. Mobile SDKs: Android via Maven Central, iOS via GitHub.

---

## Gaps to close in a browser (or via the `/articles/` static paths)

1. `articles/core-topics/Manifest_and_Permissions.html` — canonical permission table and app-type compatibility.
2. `/app-review-guidelines/` — the numbered rule set. Section 3 above is reconstructed.
3. `articles/core-topics/Publishing_to_the_Store.html` — exact screenshot dimensions, description limits, listing fields.
4. `articles/core-topics/Beta_Apps.html` and `Trial_Apps.html` — whether tester invites have shipped since the forum threads.
5. `/monetization/price-points/`, `/app-sales/`, `/merchant-onboarding/`, `/account-management/` — confirm $100 / 15 %, payout threshold and schedule, eligible merchant countries.

---

## URLs used

**Docs**
- https://developer.garmin.com/connect-iq/ · /overview/ · /sdk/ · /submit-an-app/ · /compatible-devices/ · /core-topics/ · /reference-guides/
- https://developer.garmin.com/connect-iq/app-review-guidelines/ (body not renderable)
- https://developer.garmin.com/connect-iq/connect-iq-faq/ (body not renderable)
- https://developer.garmin.com/connect-iq/core-topics/manifest-and-permissions/ · /publishing-to-the-store/ · /beta-apps/ · /trial-apps/ (bodies not renderable)
- https://developer.garmin.com/connect-iq/monetization/ · /app-sales/ · /price-points/ · /merchant-onboarding/ · /account-management/ (bodies not renderable)
- https://developer.garmin.com/brand-guidelines/connect-iq/
- https://developer.garmin.com/downloads/connect-iq/sdks/agreement.html

**API reference (permission evidence)**
- https://developer.garmin.com/connect-iq/api-docs/ and the Toybox pages for Communications, Position, UserProfile, Sensor, SensorHistory, SensorLogging, FitContributor, ActivityRecording, Background, Ant, AntPlus, BluetoothLowEnergy, PersistedContent, PersistedLocations, Notifications, ActivityPrompts, ActivityMonitor, Complications, Media, ScanCode, Weather, Authentication, Cryptography, Attention, Application

**Forums**
- https://forums.garmin.com/developer/connect-iq/w/wiki/10/app-approval-exceptions
- https://forums.garmin.com/developer/connect-iq/f/discussion/220791/publish-apps-and-make-them-private-non-searchable
- https://forums.garmin.com/developer/connect-iq/f/discussion/337712/is-there-no-way-to-share-beta-versions-of-my-app-without-just-asking-users-to-manually-install-rpg-file
- https://forums.garmin.com/developer/connect-iq/i/bug-reports/installing-beta-apps-is-almost-impossible-now
- https://forums.garmin.com/developer/connect-iq/f/discussion/429848/solved-settings-connect-iq-app-for-sideloaded-app---is-this-possible
- https://forums.garmin.com/developer/connect-iq/f/discussion/367718/sideload-prg-file-no-longer-working
- https://forums.garmin.com/developer/connect-iq/f/discussion/391547/where-do-the-app-prg-files-go-now-on-the-devices
- https://forums.garmin.com/developer/connect-iq/f/connect-iq-web-store/428068/app-approval-process-taking-longer-than-usual-10-days
- https://forums.garmin.com/developer/connect-iq/f/discussion/426202/connect-iq-monetization-system-vs-own-payment-system---increase-in-sales
- https://forums.garmin.com/developer/connect-iq/f/discussion/7222/trial-apps-documentation
- https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/monetizing-your-apps
