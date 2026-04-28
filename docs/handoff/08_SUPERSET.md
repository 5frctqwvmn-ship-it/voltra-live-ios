# 08 — Superset (b49 unified flow)

**Status as of b49:** Independent and Superset are no longer separate
modes. Superset is a TAG, like a rolling dot, that the user toggles on
during a session. The flow is unified: pair Voltras → day tile →
exercise screen, no mode picker. WorkoutMode is auto-derived from the
paired-device count (1 paired → singleLeft/singleRight; 2 paired →
independent). Combined stays as a same-bar use case, surfaced via a
"Merge" button on the exercise screen.

This doc supersedes the b46–b48 description of Superset as a distinct
WorkoutMode the user picked at session start.

## Why we changed this

After b48 hands-on testing the user said: "Independent mode and
Superset are functionally identical when there are 2 paired Voltras.
Superset is just a TAG, like a rolling dot. Don't make me pick a
mode." The pre-b49 flow forced a 3-way mode pick (Independent /
Superset / Combined) at session start, which:

1. Had no functional difference between Independent and Superset for
   the BLE/telemetry/logging code path.
2. Made SWAP feel like a separate feature rather than the natural
   "I'm done with this side, move to the other one" gesture.
3. Made it impossible to add a second exercise mid-session without
   re-picking the mode.

## How Superset works in b49

The Superset tag lives on `MultiDeviceManager`:

- `supersetTag: Bool` — toggle exposed in the exercise screen's top
  panel as a small dot. User taps to turn on / off.
- `supersetTagLocked: Bool` (private set) — flips true the first time
  a set starts (`session.currentSet != nil` becomes true). Once locked,
  the tag is read-only for the rest of the session, so the user can't
  accidentally toggle it off mid-workout.
- `lockSupersetTag()` — called from
  `LiveCaptureView.onChange(of: session.currentSet != nil)`.

The tag is purely metadata. It does not change BLE routing, telemetry
slicing, set logging, or anything else underneath. It exists so the
post-workout summary, history view, and analytics can flag the session
as "performed as a superset" without changing how the user records.

At session end, `LiveCaptureView` stamps the SwiftData WorkoutSession
with `supersetTag = mdm.supersetTag` right before calling
`logging.endSession()`. The `WorkoutSession.supersetTag` SwiftData
field is additive and defaults to false, so old sessions are
unaffected.

## How the chain works (still here from b48)

The chain itself — adding a second exercise to swap between mid-set —
is unchanged from b48. Two paired Voltras, two exercises, each with a
slot assignment, swap moves the active focus between them.

`MultiDeviceManager.supersetChain: [SupersetChainEntry]` holds the
chain. Helpers:

- `appendSupersetEntry(name:slot:weightLb:)` — called from
  `ExerciseDetailView.commitStartButton` when both Voltras are paired.
  Idempotent on `(name, slot)` so re-tapping Start doesn't duplicate.
- `hasActiveSupersetChain: Bool { supersetChain.count >= 2 }` —
  controls when the in-session banner + 2-trace force chart light up.
- `activeSupersetEntry` — the entry the user is currently lifting on.
- `nextSupersetEntry` — the entry SWAP will land on. With 2 entries,
  this is the other one.
- `advanceSupersetIndex()` — called from SWAP. Increments
  `supersetChainIndex` modulo chain count and points
  `supersetActiveSlot` at the new entry's slot.

Same exercise on both sides is now allowed (b49). The chain is
keyed by `(name, slot)`, so "Bench Press LEFT" and "Bench Press RIGHT"
are two distinct entries.

## SWAP (full exercise-context swap, b49)

`LiveCaptureView.swapSupersetSide()` rewrites b48's partial swap. When
the user taps SWAP mid-set, the app does six things in one gesture:

1. **Force-finalize the in-flight set** if one is active, so the
   completed-set logger fires and the LoggedSet attributes correctly
   to the OUTGOING exercise's instance.
2. **UNLOAD the outgoing side** (sends `0 lb` to the outgoing Voltra).
3. **Flip `supersetActiveSlot`** to the other side via
   `advanceSupersetIndex()`.
4. **Switch the LoggingStore active instance** to the incoming
   exercise via `LoggingStore.switchActiveInstanceByExerciseName(_:)`.
   This is what makes the next set's LoggedSet attribute to the right
   ExerciseInstance.
5. **Restore the incoming side's stored weight** from its
   `SupersetChainEntry.weightLb`.
6. **LOAD the incoming side** at the restored weight, so the user
   doesn't have to tap LOAD before starting their next set.

Net effect: one tap moves the entire exercise context from one side to
the other.

## The 2-trace force chart (b49)

When `hasActiveSupersetChain` is true, the in-session force chart
shows two distinct labeled traces — one per exercise — so the user can
compare the rep patterns side by side without leaving the live view.

How the secondary trace gets there:

- `LoggingStore.autoLogTelemetrySet` runs each time a set finalizes.
  At the end of that method, it stashes the finalized samples into
  `SessionStore.lastFinalizedByExercise[name] = telemetry.samples`,
  keyed by the active instance's exercise name. Refreshed each set, so
  the dict always holds the most-recent trace per exercise.
- `LiveCaptureView.forceChart` checks `mdm.hasActiveSupersetChain` and
  pulls `lastFinalizedByExercise[nextSupersetEntry.exerciseName]` as
  the secondary trace.
- `ForceChartView` got optional `secondarySamples` + `primaryLabel` +
  `secondaryLabel` parameters in b49. The secondary renders as a
  dimmed dashed line behind the primary phase-colored trace, with both
  exercise names in the legend.

The legend swaps from "Pull / Return" to the two exercise names when a
secondary trace is active, so the user can tell the traces apart.

## Top-of-exercise-screen panel (b49)

`ExerciseDetailView.dualVoltraTopPanel` — shown whenever both Voltras
are paired (renamed from b48's `superset slot picker`). Three controls:

1. **L / R slot picker** — which side this exercise targets.
2. **Merge button** — collapses both sides onto this exercise as a
   Combined virtual twin (b47 math, unchanged underneath).
3. **Superset tag dot** — the toggle described above.

`addAnotherExerciseButton` (renamed from b48's
`addAnotherSupersetButton`) is shown below the Start button. Tapping
it pops the user back to the day-tile screen so they can pick a second
exercise; on commit, that exercise auto-assigns the unused slot.

## What the user sees end-to-end

1. Pair 2 Voltras.
2. Tap a day tile (e.g. LEG DAY).
3. Pick an exercise (e.g. Back Squat). Land on the exercise screen.
4. Top panel shows L/R picker + Merge + Superset tag dot. L is
   pre-selected.
5. Optionally tap the Superset tag dot to mark this session as a
   superset.
6. Tap "Add Another Exercise." App pops to day tiles.
7. Pick a second day tile + exercise (e.g. Back Day → Bent-Over Row).
   R auto-selected.
8. Tap Start set 1. Land on live grid. Banner shows the active +
   next exercise names. Superset tag locks (read-only after this).
9. Lift. Reps + force display live. After IDLE_GRACE finalizes the
   set, REST starts immediately.
10. Tap SWAP. Set is force-finalized, app navigates to the other
    exercise's live grid, the new side auto-LOADs.
11. Lift the other exercise. Force chart now shows both traces with
    exercise names in the legend.
12. Tap End Session. SwiftData WorkoutSession.supersetTag = true.
