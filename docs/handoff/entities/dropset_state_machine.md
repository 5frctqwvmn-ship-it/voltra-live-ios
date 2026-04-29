# Entity: Dropset State Machine

> Atomic concept doc for the V2 LiveCapture DROP tile cascade. Read
> this BEFORE editing `LoggingStore.swift` drop-set methods or the
> `tapDropTile` / `dropProgressBar` code in `LiveCaptureViewV2.swift`.
>
> Linked from:
> - [03_CURRENT_FEATURE_SPEC.md](../03_CURRENT_FEATURE_SPEC.md) §3 (DROP tile)
> - [04_DECISIONS_AND_CONSTRAINTS.md](../04_DECISIONS_AND_CONSTRAINTS.md) V4-D1, V4-D5
> - [06_KNOWN_ISSUES.md](../06_KNOWN_ISSUES.md) KI-7, KI-8, KI-9, KI-10
>
> First seeded **b60 (2026-04-29)** as part of the KI-9 arm-only
> refactor. Prior cascade history is in
> `docs/WORK_LOG.md` under build entries b22 / b23 / b24 / b25 / b38
> / b45 / b56 / b58.

## States

| State | `dropSetArmed` | `dropSetActive` | Meaning |
|---|---|---|---|
| `idle` | false | false | No DROP tile interaction. Default. |
| `armed.waiting` | true | false | User tapped DROP. Anchor + push-bridge captured. Lift is still active (`forceLb > 3 lb`); no countdown running. |
| `armed.countdown` | true | false | User tapped DROP. Lift has gone idle. `dropArmedFiresAt` is set 2 s in the future. When wall-clock crosses it, engage. |
| `active.cascading` | false | true | First cascade drop has fired. `nextDropFiresAt` ticks every 2 s, dropping by the current `cascadeTier` step (5 / 10 / 15 lb). |
| `active.bottom` | false | true | Cascade hit the 5 lb device floor. `cascadeAtFloor = true`. No further drops; the 10 s no-movement watchdog will finalize. |

## Transitions

```
                   tap DROP                   2 s of forceLb ≤ 3 lb
       idle ─────────────────────► armed.waiting ──────────────────► armed.countdown ──► active.cascading
        ▲                                │                                     │                    │
        │                                │ tap DROP / long-press               │ tap DROP / long-press
        │                                │ (cancelArmedDropSet)                │ (cancelArmedDropSet)
        │                                ▼                                     ▼                    │
        │                              idle                                  idle                   │
        │                                                                                            │
        │                                                            ┌───── tap DROP ─────┐         │
        │                                                            │                    ▼         │
        │                                       active.cascading ◄───┘             active.cascading │
        │                                       (bumpCascadeTier rolls 1→2→3→1)                     │
        │                                                                                            │
        │                                                                       cascadeAtFloor=true  │
        │                                                                              ▼             │
        │                                                                       active.bottom        │
        │                                                                              │             │
        │                                  10 s no rep increment                       │             │
        └──────────────────────────────────────────────────────────────────────────────┘             │
                                                                                                      │
                                            long-press (cancelDropSet)                                │
                                            ──────────────────────────────────────────────────────────┘
```

## Engine

All state transitions live in `LoggingStore.swift`.

| Method | Effect |
|---|---|
| `armDropSet(startingLb:pushWeight:)` | `idle → armed.waiting`. Captures anchor + writer bridge. Does NOT touch the cable, does NOT call `beginDropChain`, does NOT start any timers. Refuses while `dropChainArmCooldownUntil` is in the future. |
| `noteTelemetryActivity(forceLb:)` | Per-packet driver. While `armed.waiting`: above-floor force (`> 3 lb`) keeps `dropArmedFiresAt = nil`. While `armed.countdown`: sub-floor force lets the deadline elapse; once `Date() >= dropArmedFiresAt`, calls `engageArmedDropSet`. While `active`: resets `nextDropFiresAt` and `dropFinalizeAt` on any above-floor sample. |
| `engageArmedDropSet()` (private) | `armed → active`. Re-delegates to `startDropSet` with the captured anchor + writer, which fires drop #2, starts the recurring 2 s `cascadeTimer`, and starts the 10 s `idleWatchdog`. |
| `startDropSet(startingLb:pushWeight:)` | Now invoked ONLY by `engageArmedDropSet`. Pre-b60 it was the public entry point and the b58 `tapDropTile` called it directly — that path is gone. Kept as the "active" state initializer because all the snapshot / parity / floor logic lives here. |
| `bumpCascadeTier()` | `active → active`. Tier rolls 1 → 2 → 3 → 1. Re-anchors to the most recently dropped weight, resets `cascadeStepIndex = 0`, restarts the 2 s fuse. Does NOT fire a step (preview-only since b30 / `aff322f`). |
| `cancelArmedDropSet()` | `armed → idle`. Clears arm flags, anchor, push-bridge. Sets 1.5 s arm cooldown. NOT a SessionStore boundary — the chain hasn't started so there's nothing to roll back. |
| `cancelDropSet()` | `active → idle`. Restores anchor weight on the device via the captured writer. Calls `sessionStore.endDropChainModeOnly()`. Sets 1.5 s arm cooldown. |
| `finalizeCascade()` (private) | `active → idle` via `forceFinalizeCurrentSet`. Restores anchor weight on the device, then triggers SessionStore's normal finalize path which logs the parent set + Drop rows. |

## Timer constants

| Constant | Value | Reason |
|---|---|---|
| `cascadeArmIdleSec` | 2.0 s | b60 (KI-9). Time the lift must be idle (sub-floor force) AFTER arming before the first drop fires. Matches `cascadeIntervalSec` so arm-to-fire and tier-to-tier feel like the same beat. |
| `cascadeIntervalSec` | 2.0 s | b45 tightened from 4 s → 2 s. Drives the recurring `cascadeTimer` between tiers and the published `nextDropFiresAt` deadline. The b58 → b59 QA item KI-7 ("user wants 2 s") was already satisfied in code by b45 — the KI doc was stale. |
| `cascadeIdleFinalizeSec` | 10.0 s | No-movement watchdog. After this many seconds without a rep increment AND without an above-floor sample, the cascade finalizes the parent set. |
| `cascadeIdleForceFloorLb` | 3.0 lb | Threshold below which a sample counts as "lift is idle" for both the arm gate and the per-tier fuse. Prevents machine jitter from holding either timer open indefinitely. |
| `dropChainArmCooldownUntil` | now + 1.5 s on cancel | Prevents a long-press cancel + simultaneous SwiftUI button tap from re-arming the cascade in the same gesture. |

## Telemetry contract

`VoltraLiveApp.swift` wires every BLE telemetry packet to
`LoggingStore.noteTelemetryActivity(forceLb:)`. That method is the
ONLY place the arm gate can engage and the ONLY place active-cascade
fuses get reset. Never short-circuit it.

The `SessionStore.handleLiveSample(...)` path is the second consumer of
the same packets — it owns the set-complete heuristic
(`phase == .idle && forceLb < 5 && (reps > 0 || peakLb > 10)`). When
`dropSetMode` is true on SessionStore, its idle finalize defers to the
`onDropBoundary` callback set by `startDropSet`. The b60 arm gate runs
BEFORE `dropSetMode` is set on SessionStore (since `beginDropChain`
isn't called until `engageArmedDropSet → startDropSet`), so the
SessionStore idle path cannot accidentally fire a cascade tier on the
last rep before the drop. This is by design — pre-b60 the user
reported a phantom `−5 lb` weight drop during reps when DROP was not
engaged (KI-10); the leading hypothesis is exactly the path that the
arm-gate refactor blocks.

## UI binding

`LiveCaptureViewV2.swift`:

- `tapDropTile()` branches on the three drop states (active, armed,
  idle) and calls the appropriate engine entry point.
- `cancelArmedDrop()` (long-press handler) branches similarly.
- `dropArmed` computed property = `dropSetActive || dropSetArmed` so
  the nested DROP row + 4-up tile render the armed visual without
  caring which sub-state is in play.
- `phaseOrRestBar` morphs across **rest > dropset > phase** with the
  new `dropProgressBar` component. Labels: `DROP · ARM` →
  `DROP · IN` → `DROP · NEXT` → `DROP · BOTTOM`.

## What this state machine intentionally does NOT do

- It does not retroactively record a "drop" when the user taps DROP
  but cancels before the engage. The chain has zero entries until
  `engageArmedDropSet` runs.
- It does not auto-engage in Twin Mode without the user re-arming.
  Twin DROP is currently undefined; the V2 view hides the tile in
  Twin (see `07_DUAL_VOLTRA.md` "Out of scope").
- It does not write to BLE on `armDropSet`. The cable holds working
  weight; only `engageArmedDropSet → startDropSet → fireNextCascadeStep`
  emits the first device frame change.

## Test plan (hardware QA)

| Scenario | Expected |
|---|---|
| Tap DROP mid-rep, keep lifting | Tile shows armed; weight unchanged; no countdown bar yet (label "DROP · ARM"). |
| Tap DROP, finish rep, rack the cable | Bar morphs to "DROP · IN" with 2 → 1 → 0 countdown. At 0, weight drops by tier 1 step (5 lb). |
| In active cascade, tap DROP | Tier rolls 1→2→3→1; "DROP · NEXT" countdown resets. |
| Active cascade reaches 5 lb floor | Bar shows "DROP · BOTTOM"; no further drops. After 10 s of no rep increment, set finalizes and rest timer engages. |
| Tap DROP, then tap DROP again before lift goes idle | Arm clears; weight unchanged; cooldown prevents immediate re-arm. |
| Long-press DROP while armed | Same as tap-to-disarm; haptic. |
| Long-press DROP while active | Cascade cancels; cable returns to anchor weight. |
| Adjust weight (`±` stepper) while armed | `pendingPlannedWeightLb` updates; `reanchorCascadeIfActive` (b60) also re-anchors `chainAnchorLb` while `dropSetArmed`, so the engage path uses the user's latest working weight rather than the value captured at tap. |
