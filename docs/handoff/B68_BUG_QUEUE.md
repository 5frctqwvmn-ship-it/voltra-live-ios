# B68 Bug Queue — opened Apr 29 2026 (PDT)

> Cycle target: v0.4.41 / build 68. Branch:
> `feat/ui-v4-2-claude` (no PR merge). Bot identity:
> `VOLTRA Live Bot <bot@voltralive.app>`.
>
> b67 (v0.4.40 / build 67) shipped to TestFlight via run
> `25137426370`, Delivery UUID
> `db338dcf-9c67-4d47-8853-c415bf62797a`. See
> `docs/WORK_LOG.md` for the close-out narrative.

## Status table

| ID      | Title                                                  | Status | Closing commit |
|---------|--------------------------------------------------------|--------|----------------|
| B68-01  | Demo mode should auto-engage in Live View when no Voltra is connected | FIXED  | (this commit)  |

---

## B68-01 — Demo mode should auto-engage in Live View when no Voltra is connected

**Reported:** Apr 29 2026 (immediately after b67 ship verify).

**User report (verbatim):**

> Demo mode should auto-engage in Live View when no Voltra is
> connected — When a user enters the Live View screen with no
> Voltra device connected and then loads weights, the app should
> automatically engage demo mode... Regression introduced when
> the original start screen (which housed the direct demo-mode
> entry) was removed... Suggested fix: hook the demo-mode trigger
> into the Live View "weights loaded + no device" state rather
> than relying on the deprecated start-screen path.

**Regression source.** B67-01 made `LoggingHomeView` the
unconditional cold-launch surface and demoted `ConnectView` to a
legacy/deeplink-only screen. The `DemoModeButton(source: .prePair)`
at `VoltraLive/Views/ConnectView.swift:165–168` is still in the
file but is no longer reachable from the root flow, so a
fresh-install user with no Voltra has no path to demo mode and
the LIVE screen just sits at zero force when weights are loaded.

**Expected behavior (per user spec).** On `LiveCaptureViewV2`,
when **no Voltra device is connected** AND **the user loads
weights** (taps a weight cell / hardware LOAD path), the app
should **automatically engage demo mode** so the force chart and
rep counter respond to the simulated load instead of staying
inert.

**Suggested fix (per user).** Hook the demo trigger into the
LIVE screen's "weights loaded + no device" state rather than
relying on the deprecated start-screen path.

### Evidence / inventory (already grepped)

| File | Line | Note |
|------|------|------|
| `VoltraLive/VoltraLiveApp.swift` | 15 | `@StateObject private var demo = DemoController()` — root owner, env-injected |
| `VoltraLive/Views/ContentView.swift` | 41 | env-injects `DemoController` (preview only post-B67-01) |
| `VoltraLive/Views/ConnectView.swift` | 9, 159–168 | `DemoModeButton(source: .prePair)` — **UNREACHABLE post-B67-01** (regression source) |
| `VoltraLive/Logging/Views/LoggingHomeView.swift` | 18, 159–162 | `DemoModeButton(source: .postPair)` — still mounted on home |
| `VoltraLive/Logging/Views/DebugView.swift` | 16, 88–93 | manual demo toggle in debug screen |
| `VoltraLive/Demo/DemoController.swift` | — | `enter(_:)`, `exit()`, `isActive` lives here |
| `VoltraLive/Demo/DemoModeUI.swift` | — | `DemoModeButton`, `DemoModeOverlay` |
| `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` | ~1423–1488 | `// MARK: - Hardware LOAD/UNLOAD` (b56) — proposed hook point: weight-tap binding right before `writerRouter.apply(state, …)` |

### Proposed implementation sketch

In `LiveCaptureViewV2.swift`, inside the LOAD/weight-tap path
(around line ~1423–1488), before `writerRouter.apply(...)`:

```swift
// Auto-engage demo mode when user loads weight with no device connected.
let anyDeviceConnected =
    ble.connectionState.isConnected
    || mdm.left.connectionState.isConnected
    || mdm.right.connectionState.isConnected
if !anyDeviceConnected && !demo.isActive {
    demo.enter(.prePair)   // exact source case TBD per Q1 below
}
```

`demo` would be added as `@EnvironmentObject` on
`LiveCaptureViewV2` (mirroring `LoggingHomeView` /
`ExerciseDetailView`). The trigger fires once per LOAD event;
existing `DemoController.exit()` paths (manual toggle, BLE
connection) are unchanged.

### Held questions — user answers (Apr 29 2026, PDT)

- **Q1 — trigger granularity.** → **Any weight tap, no device.**
  Hooked into `toggleHardwareLoad()` on `LiveCaptureViewV2`
  (the WEIGHT NUMBER tap path from b56).
- **Q2 — auto-disengage on connect.** → **Auto-exit, hand off to
  real device.** `.onChange` observers on all three connection
  states fire `handleConnectionChange()` which exits demo
  whenever `entrySource == .prePair` and any device flips to
  connected.
- **Q3 — `LoggingHomeView` postPair button.** → **Keep as manual
  entry.** No change to home; postPair demo is still
  user-engageable when a device is already paired.
- **Q4 — visual indicator.** → **Silent.** Existing
  `DemoModeOverlay` is the only signal; no banner / toast added.
- **Q5 — `ConnectView` cleanup.** → deferred (not asked; not
  blocking). The orphaned `DemoModeButton(.prePair)` at
  `ConnectView:165–168` remains in-tree but unreachable; revisit
  in a later cycle if `ConnectView` is fully retired.

### Acceptance criteria (draft, pending Q answers)

1. Fresh install, no Voltra paired → user lands on
   `LoggingHomeView` (b67 invariant) → enters
   `LiveCaptureViewV2` → taps a weight → demo engages
   automatically; force chart animates per rep; chart never
   sits at zero with weight loaded.
2. With a Voltra paired and connected → tapping a weight does
   **not** engage demo (real telemetry only).
3. Manual `DemoModeButton(.postPair)` on home (if Q3 = keep)
   continues to work, idempotent with auto-engage.
4. Lint-gate grep invariants from b67 still return zero matches
   outside the two known doc/copy exceptions.
5. 5-gate altool verify on `release.yml dry_run=false`
   passes (UPLOAD SUCCEEDED, ≥20s, exit 0, no blocklist
   markers).

### Implementation (landed in this commit)

`VoltraLive/Logging/Views/LiveCaptureViewV2.swift`:

1. Added `@EnvironmentObject var demo: DemoController` next to the
   existing `pairing` injection (root-injected from
   `VoltraLiveApp:119`).
2. New `private var anyDeviceConnected: Bool` derives from the
   three connection-state paths (`ble`, `mdm.left`, `mdm.right`).
3. New `private func autoEngageDemoIfNeeded()` — idempotent;
   reads `DemoTelemetryBridge.shared.handler`, records a button-tap
   trace event for parity with `LoggingHomeView`, then
   `demo.enter(source: .prePair, onTelemetry: handler)`. Called at
   the top of `toggleHardwareLoad()` so every WEIGHT NUMBER tap
   covers the auto-engage gate.
4. New `private func handleConnectionChange()` — guarded by
   `demo.isActive` + `entrySource == .prePair`; calls
   `demo.exit()` when any device flips to connected. postPair
   demo (manually engaged from home) is intentionally untouched.
5. Three `.onChange(of: …connectionState)` modifiers on the body
   forward to `handleConnectionChange()`.

### Status

**FIXED.** Awaiting `release.yml dry_run=false` ship verify.
Will ship as v0.4.41 / build 68.
