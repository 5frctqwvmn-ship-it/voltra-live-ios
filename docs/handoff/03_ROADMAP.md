# 03 — Roadmap

## Build 30 (in progress) — v0.4.8

Locked-in priority order:

1. **Drop-set fix.** ✅ DONE. Real bug was UX, not math: every tap on the
   active tile was both bumping the tier AND firing a drop, because
   `bumpCascadeTier()` called `fireNextCascadeStep()`. Fixed by making
   tier-bump preview-only; the 4s fuse remains the sole drop trigger.
   Cascade math was already anchor-correct. Regression tests pin the new
   behavior in `VoltraLiveTests/DropSetCascadeTests.swift`.
2. **Live HealthKit streaming.** ✅ DONE. Real cause was missing
   `enableBackgroundDelivery` — the anchored query was already wired,
   but without background delivery the iPhone wasn't woken for samples
   the Watch wrote. Added `.immediate` background delivery for both
   `.heartRate` and `.activeEnergyBurned`, called once after auth
   succeeds (idempotent on every start).
3. **Pulsing data indicator.** ✅ DONE. `PulseDot` view at
   `VoltraLive/Logging/Views/PulseDot.swift` pulses green at ~1.4 Hz
   while data is fresh (≤8s since last sample), fades to faint grey
   when stale. Wired into HR + KCAL tiles via the `tile()` helper's new
   `freshnessIndicator` parameter.
4. **Warmup phase.** ✅ DONE. `SetLogView.prefillIfNeeded()` now detects
   the first-set-of-instance condition (`isFirstSetOfActiveInstance`) and
   auto-selects Warm-Up mode + label. Weight comes from
   `LoggingStore.lastWarmup(for:)`; if the user has never logged a warmup
   for that exercise, falls back to 50% of `lastWorkingSet(for:)` rounded
   to nearest 5 lb. No new schema — reuses existing `LoggedSet.mode ==
   .warmUp`. Telemetry-detected peak force still wins over the warmup
   default; user can always tap Working to override.
5. **Dual-Voltra.** Restore from `.dual-voltra-wip/`, ship the 3-button
   Connect screen, scanner picker, `MultiDeviceManager`, Independent +
   Combined modes. See `07_DUAL_VOLTRA.md` for the spec.
6. **Workout-creation Group dropdown.** Existing tags ("Back Day", "Chest
   Day", "Leg Day") + ability to create a new group inline.

After all six land:

- Bump 0.4.7/29 → 0.4.8/30 in the **three places** (see `02_CURRENT_STATE.md`).
- Tag `v0.4.8-build30`, push tag to trigger TestFlight release.

## Build 31 — Superset

See `08_SUPERSET.md` for the full spec. Summary:

- "+" button on existing workout screens to add the configured workout
  (weight, reps, Voltra-assignment) to an in-progress superset.
- Persistent superset tray chip: `Superset · N steps · [Start] [Clear]`.
- Each step bound to a specific Voltra (Left/Right).
- Auto-advance using existing 4s/10s drop-cascade detection; pre-load
  next step's weight in the background.
- Logged in history as one superset block.

## Beyond build 31 (parking lot)

- **CloudKit sync re-enablement.** See `09_RELEASE_AND_SIGNING.md` for the
  exact procedure. Wait until the fresh store has been stable across at
  least a couple of releases.
- **Old-store import.** Build 29 abandoned the old SwiftData store at
  `Application Support/<old store path>`. If the user wants old logs back,
  add a one-shot importer that reads the legacy store with a separate
  `ModelContainer` and copies rows into the v2 store. Confirm with user
  before doing this.
- **Apple Watch companion (v1.2).** See `AGENTS.md` "Deferred / known
  follow-ups" — strategy is a separate Xcode project, not a Watch target
  in the same project.
- **`altool` migration to `notarytool`.** Apple is deprecating altool.
  Still works in Xcode 26 but should migrate before they remove it.

## Ordering rationale

- Drop-set first because it produces wrong numbers in user-visible logs
  every session. That is the highest-cost regression.
- HR/kcal streaming next because it's the most common in-session feedback
  the user looks at. Snapshot HR is near-useless.
- PulseDot in the same build as HR/kcal because the test for "is streaming
  working?" is easier with the indicator wired in.
- Warmup is small but blocked on a user answer — surface the question
  early so it doesn't gate the build.
- Dual-Voltra last in build 30 because it's the largest and most isolated
  change (new files, new mode), so it can ship in parallel with the
  smaller fixes if needed.
- Group dropdown is workout-creation only — independent of all the above.
- Superset deferred because it depends on dual-Voltra working in
  Independent mode (each step is bound to a side).
