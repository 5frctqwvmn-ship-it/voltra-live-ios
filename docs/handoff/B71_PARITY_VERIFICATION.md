# b71 V1↔V2 parity verification (V4-D21 part 3 follow-up; Step 6)

> Pre-ship code-level audit run on 2026-04-30 after V4-D21 parts 1-3
> committed (b93b4fe / 2488484 / c7427ce). Sandbox is Linux with no
> Xcode toolchain — every item below is verified by reading source,
> not by running the app. On-device QA happens post-TestFlight per
> the standing 5-gate ship discipline and is captured in QA_LOG.md.
>
> Scope: the eight items called out in the b71 mandate
> ("LOAD/UNLOAD, ±5/±1 nudgers, Combined dual-fire, 4-row live
> grid, HR/KCAL, rest/idle, force chart live + lastFinalizedSamples,
> chain routing through V2"). Each row records V1 source location,
> V2 source location, equivalence verdict, and a one-line note.

## Result summary

All 8 items: **parity confirmed at source level** (verbatim port,
behavioral equivalent, or documented intentional V2 redesign that
preserves the user-visible behavior). No genuine blockers. No b71
scope item deferred.

| # | Item | V1 location | V2 location | Verdict |
|---|------|-------------|-------------|---------|
| 1 | LOAD / UNLOAD opcode routing | `LiveCaptureView.sendLoad` (lines 972-980), `sendUnload` (1016+) | `LiveCaptureViewV2.toggleHardwareLoad` (1653+) | **Verbatim** |
| 2 | ±5 / ±1 nudgers | `LiveCaptureView.weightNudgerRow` (uses `CombinedParity.smallStepLb` / `largeStepLb`) | `LiveCaptureViewV2.weightCard` stepper row (`smallStepLb` / `largeStepLb` at lines 936-937) | **Verbatim port (b71 V4-D21 part 1)** |
| 3 | Combined dual-fire | V1 routes through `WriterRouter.combined → mdm.applyCombined` | V2 has same `WriterRouter` graph + `focusOverrideAssignment` (line 1422+); Twin/Combined returns nil to fall through to `.combined` branch | **Verbatim — same router graph** |
| 4 | 4-row live grid | V1's 2×4 `tileGrid` (LiveCaptureView.swift:391+): RESISTANCE / LOAD / REPS / DROP / FORCE / REST / HR+KCAL / TOTAL VOL | V2 redistributes the eight tiles across canonical surfaces (see § 4 below) | **Documented redesign — every tile mapped** |
| 5 | HR / KCAL | V1 `healthDualTile` (in tile grid row 4) | V2 `headerStrip` HR + KCAL pulse pills (line 411+) and `dualHeaderCluster` for paired-Voltra mode (line 540+) | **Behavioral equivalent** |
| 6 | Rest / idle bar | V1 REST tile (tap-to-reset) + IDLE_GRACE in REPS tile | V2 `phaseOrRestBar` (line 719+) keys on `session.restActive` and renders the same bar | **Verbatim port (b66 P1-2)** |
| 7 | Force chart live + `lastFinalizedSamples` | V1 `ForceChartView` mounted in `LiveCaptureView.forceChart` (~line 1052) with sample fallback `currentSet?.samples ?? lastFinalizedSamples` | V2 `forceChartCard` (line 1294+) — same `ForceChartView` instance, same sample fallback, same secondary-trace overlay | **Verbatim (b71 V4-D20)** |
| 8 | Chain routing through V2 | V1 `LiveCaptureView` lifecycle hooks (242-248, 264-268, 283-288) + `SupersetSwitcherBanner.swap` simple mirror | V2 wires the three V1 hooks verbatim + `SupersetSwitcherBanner.swap` rewritten as the V1 7-step flow (force-finalize → unload → flip → switchInstance → restore weight + cascade re-anchor → onAfterSwap) | **Verbatim port (b71 V4-D21 part 2)** |

## 1. LOAD / UNLOAD

**V1.** `LiveCaptureView.sendLoad` (LiveCaptureView.swift:972) calls
`autoEngageDemoIfNeeded` then `mdm.load()` if `mdm.state != .idle`
else `ble.sendLoad()`. `sendUnload` mirrors the same pattern.

**V2.** `LiveCaptureViewV2.toggleHardwareLoad`
(LiveCaptureViewV2.swift:1653) does the same routing in the same
order. The V2 toggle additionally pre-pushes upcoming state via
`pushUpcomingStateToDevice()` immediately before `sendLoad` so the
device matches the screen — V1's tile path also pre-publishes
because the user only taps LOAD after the same screen state is
already on the wire.

**Verdict.** Verbatim path through the same `mdm.load` / `mdm.unload`
/ `ble.sendLoad` / `ble.sendUnload` opcodes.

## 2. ±5 / ±1 nudgers

**V1.** `weightNudgerRow` builds the four buttons by reading
`CombinedParity.smallStepLb(for: mdm.workoutMode)` and
`largeStepLb(...)` so Combined mode advertises ±2 / ±6 instead of
±1 / ±5.

**V2.** `LiveCaptureViewV2.weightCard` stepper row at lines 936-937
reads the exact same two functions. Mode-aware step sizes shipped
in V4-D21 part 1 (b93b4fe) — see WORK_LOG entry 2026-04-30 (Step 5
commit) for the verbatim diff.

**Verdict.** Verbatim port, mode-aware in both views.

## 3. Combined dual-fire

**V1.** Combined mode writes route through
`WriterRouter.combined → mdm.applyCombined`, which fans the value
to both `mdm.left` and `mdm.right` writers in one call. V1
`tileGrid` `resistanceNudgerTile` writes `pendingPlannedWeightLb`
which the WriterRouter consumes.

**V2.** Same `WriterRouter` instance (the singleton lives on the
shared environment). `LiveCaptureViewV2.focusOverrideAssignment`
(line 1422+) returns nil for Twin / Combined modes, which causes
the router to fall through to its `.combined` branch and call
`mdm.applyCombined`. V2's WEIGHT card stepper writes through the
same `pendingPlannedWeightLb` pathway as V1.

**Verdict.** Combined dual-fire is a router-level behavior, not a
view-level one. Both views feed the same router. No divergence.

## 4. 4-row live grid

**V1 design (b46).** 2 columns × 4 rows = 8 tiles laid out via
`LazyVGrid` in `LiveCaptureView.tileGrid` (line 391+):

| Row | Left | Right |
|-----|------|-------|
| 1 | RESISTANCE ± nudger | LOAD / UNLOAD toggle |
| 2 | REPS (with inline phase + idle bar) | DROP SET (button or cascade progress) |
| 3 | FORCE | REST (tap-to-reset) |
| 4 | HR + KCAL dual | TOTAL VOLUME |

**V2 design (b54+).** The same 8 affordances are surfaced across
the canonical V2 layout, intentionally not as a 2×4 grid:

| V1 tile | V2 surface | Notes |
|---------|------------|-------|
| RESISTANCE ± | WEIGHT card big number + ±step nudgers | b71 V4-D21 part 1 wired mode-aware steps. |
| LOAD / UNLOAD | Big-number tap on WEIGHT card + LOADED/UNLOADED pill | Same opcode path (item 1). |
| REPS | `smallTileRow` REPS tile (line 1239) | Inline phase moved to header phase strip. |
| DROP SET | `dropCancelChipV2` between forceChartCard and V1RestoreSection (b71 V4-D21 part 1) + cascade UI inside `V1RestoreSection`'s drop-set section | Drop cascade visualization is now on-chart via mod tile + chart legend, not a tile. |
| FORCE | The force chart itself (V1 `ForceChartView` per V4-D20) | Live force value is the chart, not a number tile. User-visible win: a curve replaces a single number. |
| REST | `phaseOrRestBar` (line 719+) | Renders the same data; tap-to-restart preserved via `session.tapRestTile()`. |
| HR + KCAL | `headerStrip` HR + KCAL pills (line 411+) | Moved to top-of-screen for at-a-glance read; pulse-dot freshness preserved. |
| TOTAL VOLUME | `smallTileRow` TOTAL VOLUME tile (line 1240) | Same calc (`pendingPlannedWeightLb × pulleyMultiplier × reps + ecc + plates`). |

**Standing rule.** "Do not restore the b46 4×2 grid unless I
explicitly ask for that rollback." V2's redistributed surface area
is the canonical post-b54 layout per the design-studio source-of-
truth (`design-system/ui-kit.html`, commit 74d0d3b9). V4-D21
part 1 confirmed every V1 affordance is reachable in V2; V4-D21
part 2 added the chain banner that the grid never carried.

**Verdict.** Documented intentional redesign. Every V1 tile maps to
a V2 surface with identical behavior. No data lost.

## 5. HR / KCAL

**V1.** `healthDualTile` (LiveCaptureView.swift, row 4 left of the
tile grid) renders two pulse pills, one for HR (`health.currentHR`),
one for kcal (`health.sessionKcal`), each with its own freshness
pulse-dot tied to its own HK sample stream.

**V2.** The same pulse-dot pair is mounted in two places depending
on mode:

- Single-Voltra: `headerStrip` (line 370 onward) renders
  `[← End] [V3] ····· [● bpm · kcal]` with the same dual pulse-dot
  logic.
- Dual-Voltra (Combined / Independent): `dualHeaderCluster`
  (line 540+) renders `[● L bpm] [⇄ MERGE] [● R bpm] kcal` so each
  side gets its own HR readout while kcal stays a session-wide
  trailing pill.

`HealthKitStore.start()` is called on V2 onAppear (line 257) and
`HealthKitStore.stop()` on onDisappear (line 347), matching V1's
b71 V4-D21 part 1 lifecycle ports.

**Verdict.** Behavioral equivalent. V2 surfaces HR / KCAL more
prominently (top of screen vs row 4 of an 8-tile grid) but feeds
off the same `HealthKitStore` data.

## 6. Rest / idle bar

**V1.** REST tile (tile grid row 3 right) renders `restFormatted`
when `session.restActive` and is tap-to-restart via
`session.tapRestTile()`. IDLE_GRACE countdown lives on the REPS
tile (an inline 4s bar that ticks once telemetry quiesces).

**V2.** `phaseOrRestBar` (line 719+) renders identical content; the
b66 P1-2 refactor changed it to key on `session.restActive` rather
than a derived `phase` so the mount state is honest to
`finalizeSet()` and `tapRestTile()`. The IDLE_GRACE countdown is
on the same bar (V2 phase strip absorbed both V1 affordances).

**Verdict.** Verbatim port, plus the b66 honesty fix.

## 7. Force chart live + `lastFinalizedSamples`

**V1.** `LiveCaptureView.forceChart` mounts `ForceChartView` with
`samples: session.currentSet?.samples ?? session.lastFinalizedSamples`
so the chart KEEPS displaying the rep pattern through the rest
period instead of blanking. Secondary trace is pulled from
`session.lastFinalizedByExercise[other.exerciseName]` when an
active chain has 2+ entries.

**V2.** `LiveCaptureViewV2.forceChartCard` (line 1294+) — same
`ForceChartView` mount, same sample fallback, same
`lastFinalizedByExercise` lookup, same dashed-dimmed secondary
overlay rules. The V2-only header / legend chrome was deliberately
removed in V4-D20 (commit 92cac54) because `ForceChartView` paints
its own.

**Verdict.** Verbatim. ADR V4-D20 documents the supersession of
the b67-10 parametric `ForceChartV2` (retained on disk as a
SUPERSEDED rollback artifact, not mounted anywhere).

## 8. Chain routing through V2

**V1.** Three lifecycle hooks (LiveCaptureView.swift:242-248,
264-268, 283-288): onAppear chain restore (switch active instance,
set planned weight, re-anchor cascade, push device state); onChange
`session.currentSet != nil` → `mdm.lockSupersetTag()`; onChange
`mdm.supersetActiveSlot` → `switchActiveInstanceByExerciseName`
guarded by `session.currentSet == nil`. SWAP itself was a simple
weight-mirror in `SupersetSwitcherBanner.swap`.

**V2.** All three lifecycle hooks ported verbatim (LiveCaptureViewV2.swift
lines 287-293, 316-320, 337-342) per V4-D21 part 2.
`SupersetSwitcherBanner.swap` rewritten as the V1 7-step flow:
`session?.forceFinalizeCurrentSet()` → save outgoing weight →
`mdm.unload(target: outgoing)` → `mdm.flipSupersetActiveSlot()` →
`logging.switchActiveInstanceByExerciseName(incoming)` → restore
chain weight + `reanchorCascadeIfActive` → `onAfterSwap?()` (host's
`pushUpcomingStateToDevice`).

B53 safety preserved: no auto-LOAD on incoming side. Banner gate
widened from `supersetTag && bothPaired` to
`(supersetTag && bothPaired) || mdm.hasActiveSupersetChain` so
chain-only sessions surface the banner without requiring legacy
two-side flow.

**Verdict.** Verbatim port. V2 is now the canonical chain UX per
V4-D21 part 3 (commit c7427ce); V1 is retained on disk as a
rollback artifact reachable via the
`liveCaptureUIVersion = "v1"` kill switch.

## What this audit is NOT

- This is not on-device QA. The sandbox cannot run the app. The
  user runs the post-build QA checklist on TestFlight and records
  the result in `QA_LOG.md` per the b58 process.
- This is not a behavior-change manifest. The user-visible delta
  vs b70 is captured in the final b71 summary (next message in
  the conversation thread) plus the `02_CURRENT_STATE.md` "five
  unshipped commits" section.
- This is not a guarantee that the build compiles. Compilation is
  the CI `build.yml` job's responsibility on push; a brace /
  paren / bracket balance check was run on each touched file at
  commit time but does not catch type errors.

## Outstanding b71 work after this audit

- Final commit: version bump v0.4.43/70 → v0.4.44/71 in
  `project.yml`, `Info.plist`, `01_PROJECT_OVERVIEW.md`,
  `02_CURRENT_STATE.md`. Bot identity. No push, no altool until
  explicit user approval per the b71 mandate.
- Final summary back to the user with every commit SHA, every
  user-visible change, risks, and routing/V1 deprecation file
  list.

No b71 scope item is deferred.
