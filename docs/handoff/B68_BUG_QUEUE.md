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
| B68-01  | Demo mode should auto-engage in Live View when no Voltra is connected | SHIPPED v0.4.41 / build 68 | `408db2e` |
| B68-02  | Auto-enter **Simulation Mode** when weights are loaded in Demo Mode with no Voltra connected | IN PROGRESS — root cause found | (next commit) |

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

**SHIPPED in v0.4.41 / build 68** via run
[`25138837190`](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25138837190),
Delivery UUID `bb7425ca-c619-4db3-b961-15ac5fc83928`. 5-gate
altool verify: PASS (57 s, success markers present, blocklist
clean).

---

## B68-02 — Auto-enter **Simulation Mode** when weights are loaded in Demo Mode with no Voltra connected

**Reported:** Apr 29 2026, 19:05 CDT (≈ 2 minutes after b68 ship
verify, before TestFlight processing could surface build 68
to a device).

**User report (verbatim):**

> **Title:** Auto-enter Simulation Mode when weights are loaded
> in Demo Mode with no Voltra connected
>
> **Type:** Bug / Regression
>
> **Summary.** When the user is in Demo Mode with no Voltra
> device connected and loads weights from the Live View screen,
> the app should automatically transition into Simulation Mode
> — running as if real equipment were in use. This currently
> does not happen.
>
> **Previous Behavior.** Simulation Mode used to engage
> automatically when entering Demo Mode from the original start
> screen. That start-screen entry point was removed in the
> latest update, and the simulation trigger was lost along with
> it.
>
> **Expected Behavior.**
> 1. User is in Demo Mode with no Voltra paired/connected
> 2. User opens Live View and loads weights
> 3. App detects "Demo Mode + no device + weights loaded" →
>    automatically enters Simulation Mode
> 4. Live View behaves as if the user were actually using the
>    equipment
>
> **Actual Behavior.** Loading weights in Demo Mode with no
> Voltra connected does nothing — Simulation Mode never
> engages, and there's no longer any path to reach it from a
> cold start.
>
> **Suggested Fix.** Re-hook the Simulation Mode trigger to
> fire on the "weights loaded + no device connected" state
> inside Live View, instead of relying on the deprecated
> start-screen entry point.

### Possible interpretation conflict with B68-01 (CRITICAL)

B68-01 (just shipped in build 68) hooked
`autoEngageDemoIfNeeded()` into
`LiveCaptureViewV2.toggleHardwareLoad()` such that **tapping a
weight with no device connected calls `demo.enter(source:
.prePair, onTelemetry: DemoTelemetryBridge.shared.handler)`**.
`DemoController.enter(.prePair)` already starts a
`SyntheticTelemetryGenerator` that pushes synthetic frames
through the same `telemetryHandler` closure the real BLE
manager uses (verified at
`VoltraLive/VoltraLiveApp.swift:148–174`,
`VoltraLive/Demo/DemoController.swift:135–142`).

The user's wording for B68-02 ("Demo Mode + no device + weights
loaded → automatically enters Simulation Mode") frames Demo
Mode and Simulation Mode as **two distinct states**, with
Simulation Mode being the downstream behavior ("Live View
behaves as if the user were actually using the equipment").
B68-01's code engages Demo Mode on weight tap; whether it also
delivers the "behaves as if real equipment" result depends on
whether "Simulation Mode" is:

- **Interpretation A.** A user-facing label for the
  observable side-effect of `DemoController.enter(.prePair)` —
  i.e. synthetic telemetry already drives the chart and rep
  counter through `telemetryHandler`. If true, B68-01 already
  closes B68-02 functionally, and the report is the user
  rephrasing the same regression in different language ~2 min
  before build 68 could possibly be on their device.
- **Interpretation B.** A *separate* code path that the old
  start screen invoked alongside `DemoController.enter`, lost
  when `ConnectView` was demoted in B67-01 — e.g. a
  `SimulationMode` flag on `LoggingStore` / `SessionStore`,
  pulley + mode plumbing, ECC/CHAIN behavior, rep-detection
  thresholds, or a writer-router fake. Symbol search for
  `Simulation`, `simulator`, `SimMode`, `simMode`,
  `isSimulating` in `VoltraLive/` returns **only one match**
  (`HealthKitStore.swift:411` — unrelated parity stub for
  Xcode preview/simulator builds), strongly suggesting there
  was no separate Swift-symbol Simulation Mode and the user is
  using the term colloquially. But the user is the
  authoritative source of truth for product naming — do not
  assume.

### Held questions (per HR#2 + HR#3 — ask after user says "done")

- **Q1 — Is "Simulation Mode" the same observable state that
  `DemoController.enter(.prePair)` already produces (synthetic
  telemetry through `telemetryHandler`), or a separate state?**
  If same: please test build 68 once TestFlight processes it;
  the fix may already cover this. If separate: what is the
  product surface called and where in the old start-screen
  flow did it live?
- **Q2 — If separate, what specific behaviors should Simulation
  Mode produce that B68-01's auto-engage does not?** E.g.
  pulley multiplier mock, ECC/CHAIN simulated tension, rep
  cadence pacing, weight-vs-band mode switch, writer-router
  no-op vs fake — which of these (if any) used to trigger?
- **Q3 — Should this gate require Demo Mode to *already* be
  active** (entered manually from `LoggingHomeView`'s
  postPair button or DebugView toggle), as the user's wording
  suggests, **or fire on "no device + weights loaded" alone**
  as B68-01 implements? The phrasing "User is in Demo Mode
  with no Voltra paired" reads like a precondition.
- **Q4 — Is build 68 already on the user's device?** If not,
  please install and re-test before any code changes — this
  may be a duplicate of B68-01 reframed, and writing more code
  on a misread risks breaking the working B68-01 wiring.

### Evidence trace (already grepped)

| File | Line | Note |
|------|------|------|
| `VoltraLive/Demo/DemoTelemetryBridge.swift` | full file | singleton holds canonical `(Telemetry) → Void` handler; set once at app launch |
| `VoltraLive/VoltraLiveApp.swift` | 148–174 | `telemetryHandler` closure assigned to `bleManager.onTelemetry` AND to `DemoTelemetryBridge.shared.handler` so synthetic + real telemetry route identically |
| `VoltraLive/Demo/DemoController.swift` | 135–142 | on `.prePair`, spins up `SyntheticTelemetryGenerator(onTelemetry: { telem in onTelemetry(telem); logger?.recordTelemetry(telem) })` and calls `gen.start()` |
| `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` | 1452–1495 | B68-01 hooks `autoEngageDemoIfNeeded()` at top of `toggleHardwareLoad()` |
| Symbol search `Simulation\|simulator\|SimMode\|simMode\|isSimulating` | — | exactly one match (`HealthKitStore.swift:411`, unrelated preview/simulator parity stub). No first-class "Simulation Mode" symbol in the codebase. |

### Root cause found (Apr 29 2026, after user confirmed b68 didn't fix it)

User tested build 68 on device and confirmed Demo Mode
engaged but the simulation didn't run — chart inert, reps
stuck, force at zero.

**Root cause: B68-01 patched the wrong file.**
`VoltraLive/Logging/Views/LiveCaptureContainer.swift:43–91`
is a router that picks between **V1 (`LiveCaptureView`)** and
**V2 (`LiveCaptureViewV2`)**:

```swift
if hasChain { return false }                  // V1
if bothPaired { return true }                  // V2
return uiVersion == "v2"                       // user pref
```

The `liveCaptureUIVersion` `@AppStorage` defaults to `""` and
the first-launch picker recommends **V1**. So the production
default for a fresh-install single-Voltra (or no-Voltra) user
is V1. **B68-01's `autoEngageDemoIfNeeded()` lives in V2 and
never runs for V1 users.**

Grep evidence:

- `VoltraLive/Logging/Views/LiveCaptureView.swift:54–86` — V1
  has its own `@EnvironmentObject` graph + local `deviceLoaded`
  state.
- `LiveCaptureView.swift:953–969` — V1 has clean
  `private func sendLoad()` and `sendUnload()` (MDM-or-BLE
  router) used by `loadUnloadTile` (line 740–757).
- `LiveCaptureView.swift:1462` — a second debug LOAD button
  bypasses `sendLoad()` and calls `ble.sendLoad()` directly.
- V1 has no `toggleHardwareLoad()` central wrapper; LOAD
  routing lives in `sendLoad()`.

### Fix plan (landing in next commit)

Mirror B68-01's V2 pattern onto V1:

1. Add `@EnvironmentObject var demo: DemoController` to
   `LiveCaptureView`.
2. Add `private var anyDeviceConnected: Bool` (same derivation
   as V2: `ble || mdm.left || mdm.right`).
3. Add `private func autoEngageDemoIfNeeded()` — reads
   `DemoTelemetryBridge.shared.handler`, records button-tap
   trace, calls `demo.enter(source: .prePair, onTelemetry:
   handler)`.
4. Add `private func handleConnectionChange()` — guards on
   `demo.isActive && entrySource == .prePair`, calls
   `demo.exit()` on real-device pair.
5. Call `autoEngageDemoIfNeeded()` at the top of `sendLoad()`
   so both V1 LOAD button sites (`loadUnloadTile` and the
   debug button at line 1462, after promoting it through
   `sendLoad()`) are covered.
6. Add three `.onChange(of: …connectionState)` modifiers on V1
   body for prePair auto-handoff parity.
7. Promote line 1462's direct `ble.sendLoad()` to call
   `sendLoad()` so the debug button also auto-engages demo.

Rationale for `sendLoad()` as the hook (vs weight-cell tap or
`pendingPlannedWeightLb` setters): the user's wording "loads
weights from the Live View screen" matches the explicit LOAD
command — not weight stepping. V1 has no "tap weight number"
binding; the equivalent intent gesture is the LOAD button.

### Held questions (all answered Apr 29 2026, PDT)

- **Q1.** "Simulation Mode" = the observable result of
  `DemoController.enter(.prePair)`. Not a separate code path.
  User confirmed b68 engaged Demo Mode — the missing piece is
  it engaging on the **default V1 screen too**.
- **Q2.** No additional behaviors needed beyond what B68-01
  already wires (synthetic chart + rep counter + force).
- **Q3.** No Demo Mode precondition required — fire on "no
  device + LOAD pressed" alone, matching B68-01's V2 gate.
- **Q4.** User confirmed b68 was tested. Bug is real, not a
  duplicate — V1 wasn't patched.

### Status

**IN PROGRESS.** Fix landing now. Will ship as v0.4.42 /
build 69.
