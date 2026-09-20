# Garmin Connect IQ — Research Index

Compiled 20 September 2026 from `developer.garmin.com`. Current SDK at time of writing: **Connect IQ 9.2.0** (released 25 August 2026).

## Files

| File | Covers |
|---|---|
| `01-monkeyc-sdk.md` | Monkey C language, Monkey Types, memory model, project structure, manifest, jungles, barrels, build tooling, simulator, debugging, unit tests, profiler, 40 gotchas |
| `02-app-types-ui-devices.md` | The five app types, glances, complications, background services, the whole UI layer (views, Dc, layouts, resources, menus, input), device diversity and UX guidelines |
| `03-sensors-data-comms.md` | Toybox module inventory, activity recording and FIT, Position/GPS, sensors, persistence, web requests, OAuth, background sync, phone companion SDKs — written with a GPS field-data app in mind |
| `04-distribution-permissions-store.md` | Permission list, sideloading, beta apps, store submission, review rules, monetization, listing assets, and what is and is not possible for internal org deployment |

## The one trick worth remembering

The docs site is a Gatsby SPA — nav URLs return an empty body to anything that is not a browser. The real article text is static HTML at:

```
https://developer.garmin.com/connect-iq/articles/<section>/<File_Name>.html
```

e.g. `articles/core-topics/Manifest_and_Permissions.html`, `articles/monkey-c/Monkey_Types.html`.
Discover the filename via `https://developer.garmin.com/page-data/<path>/page-data.json` → `pageContext.fileName`.

The API reference at `developer.garmin.com/connect-iq/api-docs/` is ordinary static JSDoc and always readable.

## The ten facts that shape any Connect IQ project

1. **Five app types only** — `watchface`, `datafield`, `widget`, `watch-app`, `audio-content-provider-app`. The type decides which Toybox modules exist for you. Using one outside your type is a runtime **Symbol Not Found**, not a compile error.
2. **Memory is the binding constraint.** Roughly 28 KB for a data field, ~92 KB for a watch face on a mid-range device, **32 KB for a glance**. Peak usage kills the app, not average.
3. **Reference counting, not garbage collection.** Circular references leak permanently. `Lang.Method` holds a strong reference to its owner, so timers and callbacks are the classic leak.
4. **Background services**: minimum 5-minute temporal interval, must `Background.exit()` within ~30 s, and can hand only about **8 KB** back to the foreground app. Bulk data must go straight from the background web request to your server.
5. **Persistence**: `Application.Storage` needs no permission — 8 KB per key/value, 128 KB total per app.
6. **Web requests are proxied through the phone** (or Wi-Fi on capable devices). No direct radio to the internet from the watch.
7. **Debugging works only in the simulator.** On hardware you get `System.println` into a log file you create yourself, plus `CIQ_LOG.YAML` on crash — and logs rotate at 5 KB.
8. **Guard every newer API with `has`** (`Graphics has :createBufferedBitmap`, `dc has :setAntiAlias`). That is how one codebase spans device generations.
9. **There is no private or enterprise distribution.** Apps are public in the store or sideloaded over USB one device at a time. Beta builds install only on the developer's own account.
10. **Guard the developer key.** Lose the RSA 4096 private key and you can never update your published app.

## Immediate next steps for building

1. Install the **Connect IQ SDK Manager** (needs JRE 11+) and the **Monkey C** VS Code extension, then run `Monkey C: Verify Installation`.
2. `Monkey C: New Project` → type `watch-app`, pick target devices.
3. Set typecheck level to **gradual or higher** — the extension's IntelliSense and error checking depend on it.
4. Turn on compiler warnings (`-w`); they are off by default.
5. Run in the simulator with **Ctrl/Cmd+F5**, and watch **File → View Memory** from day one.

## Open questions worth settling before committing to a design

- Which Garmin devices will actually be in the field? That fixes the memory tier, screen shape, API level, and whether touch or buttons.
- Does data need to leave the watch while offline in the field, or can it buffer locally and sync when a phone is in range? This decides the whole sync architecture.
- Public store listing with an account gate, or USB sideload to a known fleet? See `04-...md` section 6.
