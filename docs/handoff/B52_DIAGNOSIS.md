# b52 — root-cause diagnosis (pre-implementation)

Status: diagnosis complete, awaiting user sign-off before code edits.
Date: 2026-04-28
Source: b51 hands-on testing (5 issues + summary-telemetry feature).

## The 5 issues, traced to code

### Issue A — "Reps from one exercise log under the wrong exercise"

**Root cause:** `LoggingStore.activeInstance` is a single pointer
(`LoggingStore.swift:25`). `autoLogTelemetrySet` and `logSet` both attach
the new `LoggedSet` to whatever `activeInstance` is at the moment the
telemetry boundary fires (`LoggingStore.swift:261`, `1151`).

When 2 Voltras are paired in a chain, the user's PHYSICAL side
(`mdm.supersetActiveSlot`) and the LOGGING side (`activeInstance`) are
two separate pointers. They are kept in sync ONLY via
`switchActiveInstanceByExerciseName` (`LoggingStore.swift:1055`), which
is called from exactly one place: the manual SWAP button
(`LiveCaptureView.swift:860`).

Therefore, whenever the user advances the chain by **any** route other
than tapping SWAP — backing out to home and re-entering, the chain
auto-advance not yet wired, the user manually re-picking from the
picker — `activeInstance` lags behind the real side. Sets the user
performs on slot A get committed under instance B (or vice versa).

### Issue B — "Both Voltras auto-load with the first exercise's settings"

**Root cause:** `WriterRouter.apply` (`WriterRouter.swift:55–94`) routes
writes based on chain-state-first, falling back to `workoutMode`:

```swift
if mdm.hasActiveSupersetChain { /* active slot only */ }
else { switch mdm.workoutMode { case .independent: BOTH SIDES } }
```

`hasActiveSupersetChain` requires **chain.count ≥ 2**
(`MultiDeviceManager.swift:191`). When the user starts their FIRST
exercise:

1. `commitChainEntryFromCurrentState` runs in `startButton` (only when
   `showsDualVoltraPanel`, i.e. 2 Voltras paired) → chain has 1 entry
2. `hasActiveSupersetChain` returns `false` (count < 2)
3. `workoutMode` is `.independent` (auto-derived in b49)
4. Router falls through to "broadcast both sides"

Result: BOTH Voltras get loaded with A's planned weight even though A
is bound to slot Left. The same path applies again when the user adds
exercise B — the planned weight push during B's pre-start screen
broadcasts to both, clobbering A's standing weight on Left.

### Issue C — "Summary missing per-exercise telemetry"

**Root cause:** intentional gap, not a bug. The `WorkoutSession`
SwiftData model has aggregate computed properties (`totalSets`,
`totalReps`, `peakLb`) but no per-exercise rollup. There is no field
for: HR-during-exercise, kcal-during-exercise, peak/avg force trend,
total volume (weight × reps × sets) per exercise.

`LoggedSet` already stores `peakForceLb` and `weightLb`, so per-set
data is present. What's missing is:

- A summary view that groups sets by `ExerciseInstance`
- Time-window queries against `HealthKitStore` to slice HR + kcal
  over each instance's `[startedAt, endedAt]` window
- Per-instance totals (volume, peak force, avg peak across sets)
- Session-level rollups across instances

User picked **peak force per set + average peak across sets** as the
force metric.

### Issue D — "Chain pre-start defaults to last-selected exercise"

**Root cause:** when the user backs out of LiveCapture to add a second
exercise, `mdm.requestSupersetReturnToHome()` pops the nav stack
(`ExerciseDetailView.swift:582`). The home screen tile-picker remembers
its `@State` selection across navigations. When the user lands back on
ExerciseStartView for the second exercise, then navigates AWAY without
finishing the chain entry (e.g. peeks at home), the picker's @State
re-enters showing whatever was last picked — typically B, not A.

Concretely: the source of truth for "which exercise is in flight" is
`mdm.supersetChain[supersetChainIndex]` (the active entry). The
pre-start screen does not re-read this on appear; it reads its own
`@State`. b51's `appendSupersetEntry` correctly snaps `chainIndex = 0`
to A when count ≥ 2, but the pre-start view doesn't reflect that.

### Issue E — "Chain summary only records the LAST exercise; sets unlabeled"

**Two separate sub-bugs collapsed into one symptom:**

E1 — Same root cause as Issue A. Sets that should attach to instance
A end up on instance B because `activeInstance` is the wrong pointer
when telemetry boundaries fire. From the user's perspective: A's sets
appear to "vanish" because they were never recorded against A.

E2 — Even when sets DO attach to the right instance, the post-session
summary view (path TBD — needs a code read of ExportSheet /
SetSummary) does not render `ExerciseInstance.exercise.name` next to
each set group. Sets render as a flat list with no per-exercise label.

## What the fix looks like (per-issue)

### A + E1 — auto-resync activeInstance to the active chain slot

The fix is to add **one onChange observer in LiveCaptureView**:

```swift
.onChange(of: mdm.supersetActiveSlot) { _, _ in
    if let entry = mdm.activeSupersetEntry {
        logging.switchActiveInstanceByExerciseName(entry.exerciseName)
    }
}
```

Plus the same call inside the auto-advance-on-set-end path if/when we
add it. This makes `activeInstance` track `supersetActiveSlot`
automatically rather than relying on the SWAP button being the only
source of switching.

Risk: if `switchActiveInstanceByExerciseName` runs DURING a set
boundary, the order matters — the set must commit against the OLD
instance, then switch. Current SWAP impl already handles this via
`session.forceFinalizeCurrentSet()` BEFORE the slot flip
(`LiveCaptureView.swift:836–860`). The onChange path needs the same
guard or it must only fire when `session.currentSet == nil` (rest
between sets).

### B — fix `WriterRouter` to honor a 1-entry chain

Two viable fixes; I recommend the second.

**Option B1 (minimal):** change `MultiDeviceManager.hasActiveSupersetChain`
to return `true` when chain.count ≥ 1 instead of ≥ 2. Side effects:
banner UI also reads `hasActiveSupersetChain` — would need to verify
no regression there.

**Option B2 (cleaner, recommended):** add
`MultiDeviceManager.hasAnySupersetChainEntry` (count ≥ 1) and use it
in `WriterRouter` only. Existing `hasActiveSupersetChain` (count ≥ 2)
keeps its current name and meaning for the chain-traversal UI logic.
The router checks "is there ANY entry at all? If so, route to that
entry's slot." This matches the user's mental model: "I picked this
exercise for the LEFT Voltra — why is the right one moving?"

### C — summary telemetry

New work, not a bug-fix. Plan:

1. Add per-instance computed properties on `ExerciseInstance`:
   - `totalReps` — `sum(sets.reps)`
   - `totalVolumeLb` — `sum(weightLb × reps)` per set, aggregated
   - `peakForceLb` — `max(sets.peakForceLb)`
   - `avgPeakForceLb` — `mean(sets.peakForceLb)`
   - `duration` — `endedAt - startedAt`

2. Snapshot HR + kcal windows. Two paths:
   - **Snapshot at instance end** (recommended for v1): in
     `finalizeActiveInstance`, call into `HealthKitStore` to compute
     average HR over `[startedAt, endedAt]` and active kcal over the
     same window. Store as new optional fields on `ExerciseInstance`:
     `avgHRDuringInstance: Double?`, `kcalDuringInstance: Double?`.
     Additive SwiftData migration.
   - Alternative: store nothing, query at render time. Slower to
     render but no schema change. Going with snapshot for cheap reads.

3. Update `ExportSheet` (or whatever the post-session summary view is
   — needs read) to render groups by `ExerciseInstance` with:
   - Exercise name + equipment + duration
   - Sets list (numbered, with weight × reps + peak force)
   - Per-instance totals row
   - HR + kcal during this instance
   - Session-level rollups at the top

### D — pre-start view re-reads chain head on appear

In ExerciseStartView (and any other pre-start view), add:

```swift
.onAppear {
    if let head = mdm.supersetChain.first {
        // Force the picker to show the chain head, not the @State.
        selectedExercise = ... lookup by head.exerciseName
    }
}
```

Also: when `mdm.supersetChain.count >= 2` and the user is navigating
into the pre-start view to START the chain (not to add another), the
view should be locked to the chain head and the user shouldn't be
able to change it from this screen. They picked it already.

### E2 — summary labels each set with its exercise

This falls out of fix C automatically (groups sets by instance).
Without C: at minimum, render `set.instance?.exercise?.name` next to
each set in the existing flat list.

## Proposed b52 build plan

All five issues + summary feature in one build (user's choice).

**Files I expect to touch:**

1. `VoltraLive/BLE/Dual/MultiDeviceManager.swift` — add
   `hasAnySupersetChainEntry`. (Issue B fix.)
2. `VoltraLive/BLE/WriterRouter.swift` — use the new predicate.
   (Issue B fix.)
3. `VoltraLive/Logging/Views/LiveCaptureView.swift` — add the
   `onChange(supersetActiveSlot)` resync. (Issues A + E1 fix.)
4. `VoltraLive/Logging/Views/ExerciseStartView.swift` — re-read chain
   head onAppear when chain non-empty. (Issue D fix.)
5. `VoltraLive/Logging/Model/LoggingModels.swift` — add new optional
   fields to `ExerciseInstance` (`avgHRDuringInstance`,
   `kcalDuringInstance`) + computed totals. Additive migration.
   (Issue C feature.)
6. `VoltraLive/Logging/Persistence/LoggingStore.swift` —
   `finalizeActiveInstance` snapshots HR + kcal from HealthKitStore.
   (Issue C feature.)
7. `VoltraLive/Logging/Views/ExportSheet.swift` — restructure the
   summary to group sets by instance with per-exercise rollups +
   exercise labels next to each set. (Issues C + E2 fix.)
8. `VoltraLive/Info.plist` + `project.yml` — bump to 0.4.30/52,
   label "Chain logging + summary".
9. `docs/WORK_LOG.md` — b52 entry.

**Sacred files untouched:** VoltraProtocol.swift, TelemetryExtractor.swift,
PacketParser.swift, FrameAssembler.swift, build.yml.

**Cost:** medium. 7 source files including a SwiftData migration (optional
new fields, default nil — no version bump risk on existing rows) and
new HealthKit queries.

**Risk:**

- The `onChange(supersetActiveSlot)` resync could double-attribute
  a set if it fires during a live set boundary. Guard: only fire when
  `session.currentSet == nil`. Add a unit-test stub if practical, or
  rely on hands-on test plan.
- HealthKit windowed queries may return zero-samples during short
  exercises. Render as `—` not `0`.
- ExportSheet restructure is the biggest UI change in this build.
  Risk of regressing existing single-exercise summaries. Mitigation:
  run the new layout for both single and chain cases; single just
  has one group.

**Test plan after install:**

1. Pair both Voltras. Pick exercise A, slot Left. Tap Start → ONLY
   the left Voltra loads. (Issue B.)
2. Do 2 sets on left. Tap Add Another Exercise. Pick exercise B, slot
   Right. Tap Start → ONLY right Voltra loads now (left holds A's
   weight). Pre-start screen shows EXERCISE B (not A or whichever was
   last selected). (Issues B + D.)
3. Do 2 sets on right (no SWAP yet). Tap SWAP → returns to left at
   A's weight. Sets done on right: attributed to B's instance.
   (Issue A.)
4. End session → summary screen shows TWO groups: A with 2 sets, B
   with 2 sets. Each set labeled by its exercise. Per-exercise totals
   shown (peak force, avg peak, total volume). HR + kcal columns
   populated per exercise. (Issues C + E2.)
5. Repeat without SWAP at all (only Add-Another-Exercise to advance):
   sets still attribute correctly — relies on Issue A fix.

If any of these regress on b52, revert the specific file rather than
patching forward. Per AGENTS.md: protocol layer is more important
than any feature.

## Open question for the user before I implement

None blocking. Proceeding with the plan above on green light.
