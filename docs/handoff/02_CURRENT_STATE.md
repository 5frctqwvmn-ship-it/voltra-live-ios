# 02 — Current State

_Last updated: 2026-04-30 (b70 cycle, in flight)._

> **Maintenance rule:** this file is overwritten on every ship. The
> append-only history lives in `docs/WORK_LOG.md`. If you're updating
> this file, replace the relevant sections wholesale instead of appending.
>
> Per `00_START_HERE.md:135`, this file and `01_PROJECT_OVERVIEW.md`
> together fulfill the Karpathy `01_PROJECT_STATE` role and **must be
> updated together** on any version bump or cycle change.

## Latest shipped build

**v0.4.42 / build 69** — tag `v0.4.42-build69`, label "B68-01 demo
auto-engage on V1 + V2 LOAD" (shipped 2026-04-29). 5-gate altool verify
passed; Delivery UUID `7e036a7d-7060-4682-8212-c253b815118a`,
[run 25140763953](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25140763953)
duration 52s.

**Active cycle:** b70 / v0.4.43 / build 70. In flight on
`feat/ui-v4-2-claude`. Targets the b69 user-reported regression
"Demo simulation broken." See `WORK_LOG` 2026-04-30 entry and
ADRs V4-D17 + V4-D18 in `04_DECISIONS_AND_CONSTRAINTS.md` for the
complete plan and justification. Pending altool ship at the time
this file was written.

## What works today

- Single-Voltra capture (V1) — full feature set including drop-set
  cascade, weight nudges, added-plates, expanded set rows.
- Single-Voltra capture (V2) — opt-in via first-launch picker, falls
  back to V1 the moment a chain entry exists or both Voltras pair.
  V2 layout: header → phase strip OR rest-timer bar → WEIGHT card with
  hardware-load tap on big number + nested mod rows + 4-up mod tile
  grid + per-engaged-mod stepper rows → REPS / TOTAL VOLUME tiles →
  force chart with parent-driven Y-axis → V1RestoreSection (pulley
  chip + added-plates picker + LOGGED SETS swipeable list +
  Next-exercise + End-session).
- Dual-Voltra Independent + Combined modes (V1 only); Twin Mode pill
  cluster with focus-aware mod routing (b58/V4-D9).
- Superset chain (V1 only) with per-instance `assignedVoltra` routing
  source-of-truth (b53), 3-way Left/Right/Both picker, SWAP-no-auto-LOAD
  safety.
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
- **Debug grid overlay** (b70/V4-D18) — four-state grid (off / corners
  / midlines / full) toggled by tapping the build-version chip;
  persisted via `@AppStorage("debugGridMode")`.

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
| Debug grid overlay (b70) | `VoltraLive/Views/DebugGridOverlay.swift` |
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
