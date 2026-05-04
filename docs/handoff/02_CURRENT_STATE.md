# 02 — Current State

_Last updated: 2026-05-03 (b78 SHIPPED to TestFlight; docs-only alignment commit on top — current focus is **Authoritative Device State + Telemetry Collector v2** spec prep, no Swift changes in this commit.)_

> **Maintenance rule:** this file is overwritten on every ship. The
> append-only history lives in `docs/WORK_LOG.md`. If you're updating
> this file, replace the relevant sections wholesale instead of appending.
>
> Per `00_START_HERE.md:135`, this file and `01_PROJECT_OVERVIEW.md`
> together fulfill the Karpathy `01_PROJECT_STATE` role and **must be
> updated together** on any version bump or cycle change.

## Latest shipped build

**v0.4.52 / build 81** — label "KI-20 topology fix + RC-01 dark" —
shipped 2026-05-04 03:20 UTC. Tag `v0.4.52-build81` at commit
`7da4ef2` on `feat/ui-v4-2-claude`.
release.yml run 25299344681. 5-gate altool: ALL PASS.
Delivery UUID `08ffc5e4-ca3e-4aba-81a7-6a06bef011ae`.

**KI-20 CLOSED** after build 81 A1 hardware retest.
Session `EA473194-40BF-4580-BEEE-8C6033535923`.
Base weight device→UI now works for single-MDM-slot sessions.

**KI-21 decoder implemented** (chains `0x3E87`, eccentric `0x3E88`,
inverse `0x53B0`) — pending TestFlight ship + hardware retest.
HEAD is now one commit ahead of `278865e`.

**Coaching (RC-01/SC-01)** is present in the binary but feature-flagged
OFF (`FeatureFlags.coachingCardEnabled = false`). No coaching UI visible.

---

*Previous: v0.4.51 / build 78 — label "Session Recorder (launch fix)" —*
*shipped 2026-05-03 03:17 UTC. Tag `v0.4.51-build78` at merge*
*commit `32f9300` on `feat/ui-v4-2-claude`.* Tag-triggered
[`release.yml` run 25268455532](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25268455532)
green in 7m40s. 5-gate altool verify per `09_RELEASE_AND_SIGNING.md`:
ALL PASS. altool wall-clock 28s, success markers
`UPLOAD SUCCEEDED with no errors` and
`No errors uploading archive at 'build/export/VoltraLive.ipa'`.
**Delivery UUID `3433cd79-fb4a-48db-9c70-b3e0289740e1`**.
Awaiting Apple processing.

Ships the B74-F11 launch-crash fix: b77 shipped a SwiftUI
`EnvironmentObject.error()` crash on launch because
`SessionRecorderToggle`, mounted at the app root via
`.overlay { ... }`, could not resolve its
`@EnvironmentObject SessionRecorder` even though
`.environmentObject(recorder)` was applied to the modifier chain
above. Root cause: `.overlay { content }` creates a composite where
`content` is a SIBLING of the modified view — env-objects on the
modifier chain do NOT propagate to the overlay's content. Fix:
re-inject `recorder` directly on `SessionRecorderToggle()` inside
the overlay closure in `VoltraLiveApp.swift` (~lines 346-348). New
`VoltraLiveTests/RecorderLaunchSmokeTests.swift` (3 tests) pins the
fix by mounting the same root-overlay shape via `UIHostingController`
and forcing layout — removing the fix crashes the test process.
Pre-tag verification: `build.yml` run 25267980973 green in 1m18s;
`release.yml dry_run=true` runs 25267981601 (4m52s) and 25268181409
(4m28s post-bump) green; `xcodebuild test` exercised the new smoke
tests and they passed. See KI-13 (b78) entry in
`06_KNOWN_ISSUES.md`. Pre-b78 shipped state: **v0.4.50 / build 77**
("Session Recorder", B74-F11) — pulled from TestFlight due to
launch crash.

### Verification status (post-b78)

- **5-gate altool verify (CI-side):** PASS — confirmed in chat
  immediately after the tag-triggered run completed.
- **Recorder QA passes A–G** per `SESSION_RECORDER_SPEC.md`
  "Verification Contract" (Ubiquity, Lifecycle, Semantic log,
  Correlation, Loud guards, Share, HealthKit truthfulness):
  awaiting per-pass entries in `docs/handoff/QA_LOG.md`.
- **Demo-mode recorder verification (claimed in chat, not yet
  formalized to QA_LOG):** recorder produced valid `.txt` and
  `.json` exports on a 33-event session covering lifecycle,
  navigation, UI-tap, and BLE event categories.
- **Hardware-mode recorder verification (claimed in chat, not
  yet formalized to QA_LOG):** recorder captured a 1000-event
  live VOLTRA session including a real BLE
  `write.tx → write.ack → notify.rx` chain, base-weight changes
  observed live, the live-stream events, and a probable
  load-cutout transition. These observations are inputs to the
  next feature (see Active cycle below); they are NOT a
  signed-off pass against the Verification Contract until they
  are written to `QA_LOG.md` per-pass.

### Pre-b78 (b77) — pulled, do not install

**v0.4.50 / build 77** — label "Session Recorder" — tag
`v0.4.50-build77` pushed at the b77 ship commit on
`feat/ui-v4-2-claude`. Ships B74-F11 (PR #10 merged via `88a4eaf`):
local-only AI-readable debug recorder. Hidden 24×24 dot under a
single root-level `.overlay(alignment: .bottomTrailing)` — unlocked
by triple-tapping the build-badge chip
(`UserDefaults["VOLTRARecorderUnlocked"] = true`). Tap toggles
recording (red 1 Hz `TimelineView` pulse while armed; faint
`textFaint` while idle). Long-press opens
`SessionRecorderViewer` (event timeline + category filter chips +
`ShareLink` exporting both `.txt` AI-readable report and `.json`
structured envelope, schemaVersion=1). Singleton
`SessionRecorder.shared` (`ObservableObject`, non-`@MainActor`)
owns a 10,000-event FIFO actor buffer, a `RecorderRedactor`
(peripheral-name → UUID; free text → `<redacted:len=N>`;
`unsafeRaw` opt-in only for `HKSource.name` /
`bundleIdentifier`), and an `ActionScope` `@TaskLocal UUID` so
downstream events auto-inherit `actionId` for cause→effect chains.
Persists current session to
`Application Support/SessionRecorder/last_session.json` on
background / inactive (scenePhase observer). Additive
instrumentation across BLE chokepoints
(`VoltraBLEManager` 14 emits, `VoltraWriter` 2 emits,
`MultiDeviceManager` 5 emit groups) and HealthKit sample arrivals
(`HealthKitStore` 6 emit groups, read-only). 9 user-visible silent
guards converted to `recorder.guardTrip(...)`. `.recorderScreen`
tags on 13 top-level screens. Pre-b77 shipped state: **v0.4.49 /
build 76** ("Health signal indicator", B74-F8).

## Active cycle

**Authoritative Device State + Telemetry Collector v2** —
docs-first, no Swift yet. Branch: `feat/ui-v4-2-claude`.

This cycle fixes two linked problems surfaced by the b78
recorder shipping to a real hardware session:

1. **Runtime state correctness.** The app does not reliably
   know the machine's true live state. Machine-side base-weight
   changes do not reliably update the app; eccentric /
   concentric / chains can drift between hardware and the app's
   in-memory model; load drop / unload / cutout mid-set is not
   surfaced to app state.
2. **Observability.** The Session Recorder shipped in b78
   captures raw telemetry but does not yet produce semantic
   decoded state changes, incident detection, compression of
   high-frequency stream frames, complete cause→effect chains,
   or session summaries that make incidents obvious on first
   read.

Full spec: `03_CURRENT_FEATURE_SPEC.md` ("Authoritative Device
State + Telemetry Collector v2") — includes goal, architecture,
core models, decoder requirements, conflict resolution,
load/unload behavior, telemetry recorder improvements, BLE
characteristic audit requirement, acceptance criteria, and
recommended implementation order. Architectural constraint
recorded in `04_DECISIONS_AND_CONSTRAINTS.md` ADR **V4-D26**:
the new decoder is **additive** and sits alongside the existing
Protocol/ pipeline; sacred protocol files
(`VoltraProtocol.swift`, `TelemetryExtractor.swift`,
`PacketParser.swift`, `FrameAssembler.swift`) are not modified.

Step 1 of implementation: BLE characteristic audit. Step 2:
shared frame-decoder abstraction. No Swift code is written
until the user explicitly says go. **No code changes in this
docs commit.**

## Last cycle (b78, just shipped) — Session Recorder launch-crash fix

**b78 / v0.4.51 / build 78** — single-line SwiftUI fix in
`VoltraLiveApp.swift` re-injecting the `SessionRecorder`
environment object directly on `SessionRecorderToggle()` inside
the root `.overlay` closure, plus a new
`VoltraLiveTests/RecorderLaunchSmokeTests.swift` regression test
(3 tests) that mounts the same root-overlay shape via
`UIHostingController` and forces layout. Tag
`v0.4.51-build78` at merge SHA `32f9300`.
Run [25268455532](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25268455532)
green in 7m40s. Delivery UUID
`3433cd79-fb4a-48db-9c70-b3e0289740e1`. Closes the b77
launch-crash hotfix loop opened by KI-13 (b78) in
`06_KNOWN_ISSUES.md`.

## Cycle before that (b73) — debug grid SCROLL-ANCHOR fix

**b73 / v0.4.46 / build 73** — debug grid SCROLL-ANCHOR fix.
Single-feature ship per the one-feature-per-build convention. The
b72 grid was viewport-anchored on both axes, so the row coordinate of a
UI element changed when the user scrolled. b73 splits the coordinate
system: column letters stay viewport-pinned (no horizontal scroll, so
that's correct already) and row numbers anchor to the ScrollView's
content coordinate space via a new `.debugGridContent()` modifier and a
`DebugGridContentMetricsKey` PreferenceKey. Result: "C10" identifies
the same UI element regardless of scroll position. See ADR
**V4-D23** in `04_DECISIONS_AND_CONSTRAINTS.md`.

Files touched (single commit):
- `VoltraLive/Views/DebugGridOverlay.swift` — split renderer (vertical
  lines viewport-pinned, horizontal lines + row labels content-pinned
  via `contentMinY` translation). New public modifier
  `.debugGridContent()`. Backward compatible: screens without scroll
  default to viewport-pinned rows, matching b72.
- 10 page-badge screens with ScrollView gain `.debugGridContent()` on
  their inner content stack: `LoggingHomeView`, `LiveCaptureView`,
  `LiveCaptureViewV2`, `ExerciseDetailView`, `ExerciseStartView`,
  `DebugView`, `DashboardView`, `ExercisePickerView`, `SetLogView`,
  `ExportSheet`. Non-scrolling screens (`ConnectView`,
  `LiveCaptureContainer`) intentionally untouched.
- `project.yml`, `VoltraLive/Info.plist` — version bump to
  v0.4.46 / 73; `VOLTRAFeatureLabel` = "Grid scroll fix".
- `docs/handoff/01_PROJECT_OVERVIEW.md`, this file,
  `03_CURRENT_FEATURE_SPEC.md`, `04_DECISIONS_AND_CONSTRAINTS.md`
  (V4-D23 ADR), `06_KNOWN_ISSUES.md`, `docs/WORK_LOG.md`.
- `docs/handoff/screenshots/b73/grid_scroll_invariant.png` — visual
  validator showing LEG DAY at content row 10 in both before- and
  after-scroll panels.
- `scripts/render_b73_grid_diagram.py` — the renderer that produced
  the validator diagram.

## Recent shipped (history)

- **b77 / v0.4.50 / build 77** — shipped 2026-05-03 ~01:00 UTC on
  `feat/ui-v4-2-claude`. Label "Session Recorder" (B74-F11). Tag
  `v0.4.50-build77`. **PULLED** — launch-crashed on first body
  evaluation (SwiftUI EnvironmentObject.error() in
  SessionRecorderToggle); fix shipped in b78.
- **b76 / v0.4.49 / build 76** — shipped 2026-05-01 ~22:50 UTC on
  `feat/ui-v4-2-claude`. Label "Health signal indicator" (B74-F8).
  Release-only ship; implementation merged at `713a851` via PR #8.
- **b75 / v0.4.48 / build 75** — shipped before b76. Label
  "L/R auto-connect" (B74-F1). Auto-connect L/R buttons by Voltra
  advertised name (substring "left" / "right", case-insensitive).
- **b74 / v0.4.47 / build 74** — label "Grid scroll fix v2".
  V4-D24 debug grid TRUE content-space layer.
- **b73 / v0.4.46 / build 73** — label "Grid scroll fix". V4-D23
  scroll-anchor fix.
- **b72 / v0.4.45 / build 72** — shipped 2026-05-01 02:41 UTC, run
  [25199600713](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25199600713),
  HEAD `bea7243`. Replaced 9-anchor debug overlay with
  progressive-density grid (V4-D22, 5 states 0–4, base 32 pt).
- **b71 / v0.4.44 / build 71** — shipped 2026-04-30 23:43 UTC, run
  [25194880211](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25194880211),
  HEAD `26af534`. V2 canonical live capture, V1 chain UI ported, force
  chart canonical, page-badge hotfix.
- **b70 / v0.4.43 / build 70** — shipped 2026-04-30 16:27 UTC, run
  [25176969283](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25176969283),
  Delivery UUID `fc2f3148-6f9e-484e-b83c-23534bcc1582`,
  HEAD `e10b428`. Demo entry source connection-aware + page registry +
  initial debug grid overlay (V4-D18 9-anchor markers; superseded by
  b72).

**Historical (pre-b72):** Seven unshipped b71 commits sat on top
of the b70 ship tag before the b71 cycle landed:
- b70 page-badge double-render hotfix (commit `34ba63e`, 2026-04-30 22:02 UTC).
- b71 force-chart canonicalization — V1's `ForceChartView` is now mounted
  inside `LiveCaptureViewV2.forceChartCard`; the b67-10 parametric-sine
  `ForceChartV2` is retained on disk as a SUPERSEDED rollback artifact
  but is no longer mounted anywhere. See ADR **V4-D20** in
  `04_DECISIONS_AND_CONSTRAINTS.md` (supersedes V4-D13). The user's
  verbatim rationale: "the V1 ForceChartView is the one that displays
  the force curve correctly in practice." Commit `92cac54`.
- b71 below-chart parity port (V4-D21 part 1 of 3) — V2 now matches V1's
  `upcomingSetCard` / `dropSetSection` / `loggedSetsSection` /
  `bottomActions` surface area: `SetMode` chips picker, `Target N reps`
  chip, visible drop-cascade cancel chip, mode-aware ±step nudgers (V1
  Combined parity ±2 / ±6), full onAppear writer-cache wipe + workout-
  mode + Combined-parity hooks, onChange `mdm.workoutMode`, onDisappear
  `health.stop()`. Required before the Step 3 routing flip so chain
  users routed through V2 still see every below-chart affordance.
  Equivalence documented for `upcomingSetCard` chrome and load/unload
  pair (V2 surfaces both via `weightCard` + `toggleHardwareLoad`).
  See ADR **V4-D21**. Commit `b93b4fe`.
- b71 chain / superset UI port into V2 (V4-D21 part 2 of 3) — full V1
  SWAP semantics now live in `SupersetSwitcherBanner` (force-finalize
  current set → unload outgoing → flip slot → switch active instance →
  restore chain weight + re-anchor cascade → host pushes device state),
  and V2 wires the three V1 lifecycle hooks: onAppear chain restore
  (LiveCaptureView.swift:242-248), onChange `currentSet` flip →
  `mdm.lockSupersetTag()` (264-268), onChange `mdm.supersetActiveSlot`
  → `switchActiveInstanceByExerciseName` (283-288). B53 "no auto-LOAD
  on incoming" safety preserved verbatim. Commit `2488484`.
  See ADR **V4-D21 part 2**.
- b71 routing flip: V2 is canonical (V4-D21 part 3 of 3) —
  `LiveCaptureContainer.shouldUseV2` collapsed from the three-stage
  conditional cascade (`hasChain → V1` / `bothPaired → V2` / else
  preference) to a single line `return uiVersion != "v1"`. V2 now
  renders for every session shape; `@AppStorage("liveCaptureUIVersion")`
  is an emergency rollback kill switch only. The pre-b71 `"Should V2
  become the default?"` open question (10_OPEN_QUESTIONS) is resolved
  and moved to Recently closed. 08_SUPERSET routing section rewritten
  to reflect the new policy. V1 source code is retained on disk as a
  verbatim rollback artifact — deletion is deferred to a future build
  (b75+ at the earliest, after 2 clean V2 ships). Commit `c7427ce`.
  See ADR **V4-D21 part 3**.
- b71 V1↔V2 parity verification audit (Step 6) — source-level
  audit of all eight items in the b71 mandate (LOAD/UNLOAD,
  ±5/±1 nudgers, Combined dual-fire, 4-row live grid, HR/KCAL,
  rest/idle, force chart live + `lastFinalizedSamples`, chain
  routing through V2). All eight pass; six are verbatim ports,
  one (HR/KCAL) is a behavioral equivalent, one (4-row grid) is
  a documented intentional V2 redesign. Full table in
  `docs/handoff/B71_PARITY_VERIFICATION.md`. Commit `c797d7f`.
- b71 version bump v0.4.43/70 → v0.4.44/71 — `project.yml`,
  `VoltraLive/Info.plist`, `01_PROJECT_OVERVIEW.md`, this file.
  Final commit per the b71 mandate (after all six scope items
  landed). Bot identity. NO push. NO altool.

Version bump committed in this cycle as the FINAL commit per the
b71 mandate (after all six scope items landed: hotfix retention,
force chart, below-chart parity, chain UI port, V1 fallback
removal, parity audit). Push and TestFlight ship are pending
explicit user approval per the standing constraint.

## What works today

> **b71 V4-D21 part 3 routing note:** as of b71 V2 is the canonical
> live capture view for every session shape. The bullets below that
> historically read "V1 only" or "V1 fallback" describe the runtime
> view as **V2** post-b71. V1 source remains on disk as an emergency
> rollback artifact reachable via the `liveCaptureUIVersion = "v1"`
> kill switch, but is not on the default render path.

- Live capture (V2, canonical post-b71) — full feature set including
  drop-set cascade, weight nudges, added-plates, expanded set rows,
  superset chain SWAP, dual-Voltra Independent / Combined.
  V2 layout: header → phase strip OR rest-timer bar →
  `SupersetSwitcherBanner` (chain-aware) → WEIGHT card with
  hardware-load tap on big number + nested mod rows + 4-up mod tile
  grid + per-engaged-mod stepper rows + `Target N reps` chip +
  `SetMode` chips row → REPS / TOTAL VOLUME tiles → force chart
  (V1's `ForceChartView` raw-sample phase-colored polyline +
  Catmull-Rom smoothing + secondary-trace superset overlay, per ADR
  V4-D20) → drop-cascade cancel chip (self-hides unless cascade is
  live) → V1RestoreSection (pulley chip + added-plates picker +
  LOGGED SETS swipeable list + Next-exercise + End-session).
  ±step nudgers are mode-aware via `CombinedParity`.
- Live capture (V1, retained as rollback artifact) — unchanged from
  b70. Same feature set, reachable only via the kill switch.
- Dual-Voltra Independent + Combined modes — Twin Mode pill cluster
  with focus-aware mod routing (b58/V4-D9), now rendering through V2.
- Superset chain — per-instance `assignedVoltra` routing source-of-
  truth (b53), 3-way Left/Right/Both picker, SWAP-no-auto-LOAD
  safety, now rendering through V2 via `SupersetSwitcherBanner`'s
  V1-verbatim swap flow + V2's three V1 lifecycle hooks (b71
  V4-D21 part 2).
- HealthKit HR + active calories streaming with PulseDot freshness
  indicators.
- Session export with sessionVitalsCard (AVG HR / KCAL / TOTAL VOL /
  DUR) and comparisonCard vs prior session of same dayTypeRaw.
- Markdown export with fixed-width table.
- **Demo Mode** with synthetic telemetry pump (b59/V4.6.3, b68 V4-D16
  auto-engage on weight-tap LOAD, b70 V4-D17 connection-aware entry on
  every live call site + cold-launch rehydration + root demo→live
  handoff observers).
- Cold-launch routes unconditionally to LoggingHomeView (b67/V4.3 Bug 01
  flip). ConnectView is reserved for legacy onboarding deeplinks only.
- Shared PairingCoordinator (b67/V4-D15) — single sheet presenter for
  any tap-to-pair gesture from any screen.
- VoltraUnitHeader (b67/V4-D14) — single canonical L/R unit-status row
  on Workout, Live, and Detail screens; replaces VoltraAssignmentPanel
  + telemetryPulsePill + connectionPill chrome.
- Page-name badge with **stable numeric IDs** via `PageRegistry` (b66
  + b70/V4-D18). Render format: `"NN · ScreenName"`.
- **Debug grid overlay** (b70/V4-D18 → b72/V4-D22) — five-state
  progressive-density spreadsheet-style grid (off / base 32pt /
  half 16pt / quarter 8pt / max + region outlines) toggled by
  tapping the build-version chip; persisted via
  `@AppStorage("debugGridMode")`. Replaces the b70 9-anchor
  marker overlay; legacy `DebugGridMode` enum retained behind a
  `// SUPERSEDED` marker for rollback.

## Live capture mode handling matrix

| Scenario                                     | Renders |
|----------------------------------------------|---------|
| 1 Voltra paired, no chain, V1 chosen         | V1 |
| 1 Voltra paired, no chain, V2 chosen         | **V2** |
| 1 Voltra paired, chain has ≥1 entry          | V1 (b54 tightened gate) |
| 2 Voltras paired, Independent                | V1 |
| 2 Voltras paired, Combined                   | V1 |
| 2 Voltras paired, Superset chain             | V1 (b53 chain fixes apply) |

V2 is single-Voltra-no-chain only by design. `LiveCaptureContainer`
at `VoltraLive/Logging/Views/LiveCaptureContainer.swift` enforces this gate.

## V2 design source

V2 is a port of the b55 sign-off render at `voltra-v2-preview/index.html`
PLUS the b56 spec dump (3-state rest-timer screenshot + spec text).
The b55-era layout note ("1:1 port of design-system/ui-kit.html") is
OBSOLETE — the actual layout-of-truth has been the web preview since
b55, and now also the b56 spec.

**Before changing V2, re-read the WORK_LOG b55 + b56 entries and
`voltra-v2-preview/index.html`.** Do not rely on prose summaries.

## Demo Mode contract (b70 / V4-D17)

Live UI MUST select `DemoEntrySource` from the connection state at
call time:

```
let source: DemoEntrySource = anyDeviceConnected ? .postPair : .prePair
demo.enter(source: source, onTelemetry: handler)
```

`anyDeviceConnected = ble.connectionState.isConnected
  || mdm.left.connectionState.isConnected
  || mdm.right.connectionState.isConnected`

`.settingsRestore` is **legacy** and MUST NOT appear in any live call
site. Lint gate: `rg "source:\s*\.settingsRestore" VoltraLive` → 0.
The case is retained in `DemoEntrySource` for trace-replay
compatibility only.

Cold-launch rehydration (`VoltraLiveApp.swift`) calls
`demo.enter(source: .prePair, ...)` when `demo.settingsToggleOn` was
left on across a launch. ContentView's `.onChange` observers on the
three connection-state sources call `demo.exit()` when an active
prePair session sees a real device come up.

`DemoController.enter(...)` self-heals if a session is active but
the synthetic pump is missing AND `entrySource == .prePair`. The
self-heal branch reads `entrySource` (the controller's published
source-of-truth), NOT the incoming `source` parameter.

## Known issues / not yet built

1. No Settings toggle to switch back from V2 to V1 after picking V2
   in the first-launch picker. Tracked for a future build.
2. V2 has no chain affordances by design. If a user tries to add a
   second exercise while on V2, the container falls back to V1.
3. `swapSupersetSide` is no-auto-LOAD by design. After a SWAP, the
   user must tap LOAD to arm the new side. Document in any
   user-facing release note.
4. b56 V2 DROP is finalize-driven (advances `manualDropIndex` when
   the next set starts). The legacy V1 timer-cascade `startDropSet`
   still exists for V1 and is not wired into V2.
5. Architect's H1/H2/H4 demo hypotheses are not falsified yet but
   were de-prioritized in b70 (only H3 fixed). Re-evaluate post-b70
   if the user reports any residual demo-mode symptoms.

## Key files (quick map)

| Concern | File |
|---|---|
| Live capture V1 | `VoltraLive/Logging/Views/LiveCaptureView.swift` |
| Live capture V2 | `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` |
| V1/V2 routing | `VoltraLive/Logging/Views/LiveCaptureContainer.swift` |
| Per-instance Voltra assignment | `VoltraLive/BLE/Dual/DualMode.swift` (`DeviceSlotAssignment`) |
| Routing logic | `VoltraLive/BLE/WriterRouter.swift` |
| Chain state | `VoltraLive/BLE/Dual/MultiDeviceManager.swift` |
| Session/instance models | `VoltraLive/Logging/Model/LoggingModels.swift` |
| Export sheet | `VoltraLive/Logging/Views/ExportSheet.swift` |
| HealthKit + session snapshot | `VoltraLive/Health/HealthKitStore.swift` |
| Demo controller | `VoltraLive/Demo/DemoController.swift` |
| Pair sheet coordinator (b67) | `VoltraLive/Coordinators/PairingCoordinator.swift` |
| Unit-status header (b67) | `VoltraLive/Views/VoltraUnitHeader.swift` |
| Page registry (b70) | `VoltraLive/Views/PageRegistry.swift` |
| Debug grid overlay (b70 → b72 → b73 → b74) | `VoltraLive/Views/DebugGridOverlay.swift` (b74 splits into a viewport-pinned `.debugGridOverlay()` for vertical lines + column letters + region overlay, and a content-space `.debugGridContentLayer()` attached via `.background(...)` on each ScrollView's inner content stack for horizontal lines + row labels). |
| Page badge (b66, edited b70) | `VoltraLive/Views/PageBadgeOverlay.swift` |
| Build badge (edited b70 for tap) | `VoltraLive/Views/BuildBadgeOverlay.swift` |
| Design system spec | `design-system/` on branch `design-studio` |
| Design tokens (Swift) | `VoltraLive/Views/VoltraTheme.swift` |

## Repository facts

- Canonical local path: `/home/user/workspace/voltra-ios`
- Working branch: `feat/ui-v4-2-claude` (no merge to `main` per agent
  operating rules — keep open).
- HEAD at last summarization: TBD post-b70 commit
- Working tree: clean post-b70-ship
- CI runner: `macos-26`, Xcode `26.2`, iPhoneOS `26.2.sdk`
- Bot identity for commits:
  `git -c user.name="VOLTRA Live Bot" -c user.email="bot@voltralive.app"`
- GitHub repo: <https://github.com/5frctqwvmn-ship-it/voltra-live-ios>
- Apple Team: `588XUZGNNS`, App Store Connect App ID `6763798738`.

## Recent tags

- `v0.4.42-build69` — B68-01 demo auto-engage V1 + V2 (current shipped)
- `v0.4.41-build68` — B68-01 V2 hook only (superseded by b69's V1 hook)
- `v0.4.40-build67` — B67 7-bug execution (cold-launch flip, header
  unification, PairingCoordinator, ForceChart per-rep sine wave)
- `v0.4.34-build56` — V2 mods + rest timer + V1 restore
- `v0.4.33-build55` — V2 single-Voltra LiveCapture (signed-off
  web-preview port)
- `v0.4.32-build54` — V2 spec match (superseded by b55)
- `v0.4.31-build53` — V2 preview + chain fixes (V2 was broken,
  superseded)

## Apple's version-component rule

`CFBundleShortVersionString` must be ≤ 3 components (e.g. `0.4.43`,
not `0.4.43.1`). Use `CFBundleVersion` (build number) for finer
granularity.

## Three places to bump on every release

1. `VoltraLive/Info.plist` → `CFBundleShortVersionString` and
   `CFBundleVersion`
2. `project.yml` settings block (lines ~64-65): `MARKETING_VERSION`
   and `CURRENT_PROJECT_VERSION`
3. `project.yml` `info.properties` block (lines ~92-93):
   `CFBundleShortVersionString` and `CFBundleVersion`

Plus `VOLTRAFeatureLabel` in both files when it should be set. All
must agree or signing fails.

## Doc bumps on every release

Per `00_START_HERE.md:135`, the Karpathy `01_PROJECT_STATE` role
maps to BOTH:

- `docs/handoff/01_PROJECT_OVERVIEW.md` — update the "Current
  shipping build" line at the top.
- `docs/handoff/02_CURRENT_STATE.md` — overwrite the "Latest shipped
  build" + "Active cycle" lines and any sections whose content has
  drifted since the last ship.

Both must update together. Do NOT touch `docs/WORK_LOG.md` history
(append-only) or any file under `docs/handoff/_tmp/` or
`docs/handoff/archive/`.
