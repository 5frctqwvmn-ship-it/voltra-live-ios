# Intensity metric — research stub

> Open research item for a future build. Not implemented in b58.

## Goal

A single numeric "intensity" score per set (or per rep) that
reflects how hard the user worked, normalized so values are
comparable across exercises, weights, and modifier
combinations (chains, eccentric, dropset cascades).

## Why now (April 2026)

The force chart already shows shape and peak, and as of b58 it
also visualizes ECC vs CON contribution as separate bands
(Tonal-style). What it still doesn't show is **"was this rep
close to my limit?"** — that requires a ratio against some
kind of personal anchor.

A scalar intensity score would also give us:

- A single column to sort set history by "hardness".
- A signal we can compare across modifier states (e.g.
  "raw 100 lb felt as hard as 80 lb + chains").
- Input to a future progressive-overload coach.

## Candidate definitions

### 1. Peak-vs-1RM

`peakForceLb / estimated1RM` per rep, then `max` per set.

- Pros: cleanest interpretation; matches how powerlifters
  already think.
- Cons: per-exercise 1RM tracking is hard for accessory lifts;
  not all VOLTRA users have a real tested 1RM.
- Implementation cost: medium. Needs a per-exercise PR table
  and a "this set was a true max" flag for ground truth.

### 2. Time-under-tension weighted average

`mean(force) over eccentric phase ÷ working weight` per rep,
averaged across the set.

- Pros: doesn't need a 1RM. Captures "did they really lower
  under control" — which is what eccentric mode is for.
- Cons: doesn't surface peak effort; long slow reps look as
  intense as short heavy ones. Could double-count sets that
  use ECC modifier.
- Implementation cost: low. We already segment phases for the
  b58 force-chart fill.

### 3. Velocity-loss RPE proxy (VBT)

Velocity drop between rep-1 and rep-N inside a set.

- Pros: industry-standard in velocity-based training; we
  already track bar/cable speed for the force curve.
- Cons: only valid above ~70% 1RM; useless for warm-ups; needs
  at least 3 reps to mean anything.
- Implementation cost: low for the math; medium for the UX
  (need to skip the metric on short sets).

### 4. Combined modifier-aware index

`(peakForce × ECC_multiplier × CHAIN_multiplier × tier_factor)
÷ rolling_baseline_peak`, where the multipliers come from
`04_DECISIONS_AND_CONSTRAINTS.md` and `tier_factor` reflects
dropset cascade depth.

- Pros: respects what makes VOLTRA unique (modifiers stack).
- Cons: most opinionated; harder to explain to the user; needs
  validation against perceived effort.
- Implementation cost: medium-high. Calibration is the hard part.

## What changed in b58 that matters here

- Force chart now segments ECC vs CON visually
  (`ForceChartV2.eccConFill`). The same `phaseCentroid` math can
  feed candidate #2 (TUT-weighted average) without new
  instrumentation.
- Dropset state machine is now centralized in `LoggingStore`
  (`startDropSet`, `bumpCascadeTier`, `cascadeTier`). Any
  cascade-aware intensity score (candidate #4) can read
  `cascadeTier` directly instead of reverse-engineering it from
  weight history.
- Twin Mode aggregation rules (force = sum, reps = sum, ROM/vel
  = avg) are now formalized in `07_DUAL_VOLTRA.md`. Whatever
  intensity definition we pick must declare how it aggregates
  across Twin Mode.

## Decision still deferred

We don't have enough longitudinal data to validate any of
these against perceived effort. Recommendation when this
becomes a build: ship candidate #2 (TUT-weighted average)
first as a "soft" indicator, since b58 already gives us the
ECC segmentation for free. Then layer #1 (Peak-vs-1RM) once
the PR table exists.

## Pre-requisites before implementation

- Per-exercise PR/1RM table (separate model object,
  `PRStore.swift` — does not exist yet).
- A "true max effort" flag on `WorkoutSession` for ground
  truth.
- Settings toggle: which definition does the user want
  surfaced (or "auto" — pick by exercise type).
- Twin Mode aggregation rule declared per definition.
- A baseline window for normalization (rolling 30 days?
  rolling 10 sessions?). User-tunable.

## Owner

Unassigned. Open since b57 (April 2026). Refreshed at b58 with
ECC/CON segmentation, dropset cascade state, and Twin Mode
context now in place.
