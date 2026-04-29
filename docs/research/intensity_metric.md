# Intensity metric — research stub

> Open research item for a future build. Not implemented in b57.

## Goal

A single numeric "intensity" score per set (or per rep) that
reflects how hard the user worked, normalized so values are
comparable across exercises, weights, and modifier
combinations.

## Why now

The force chart already shows shape and peak. What it doesn't
show is "was this rep close to my limit?" — that requires a
ratio against some kind of personal anchor.

## Candidate definitions (rough)

1. **Peak-vs-1RM.** `peakForceLb / estimated1RM`. Requires per-
   exercise 1RM tracking. Cleanest interpretation but the 1RM
   estimate is hard for accessory lifts.
2. **Time-under-tension weighted average.** `mean(force)` over
   the eccentric phase ÷ working weight. Captures "did they
   really lower under control" without needing a 1RM.
3. **RPE proxy.** Velocity-loss between reps within a set.
   Industry-standard in VBT (velocity-based training); needs
   bar/cable speed which we already track for the force curve.

## Decision deferred

We don't have enough longitudinal data yet to validate any of
these against perceived effort. Stub left here so the next
agent has a starting point when the user prioritizes this.

## Pre-requisites before implementation

- Per-exercise PR/1RM table (separate model object).
- A way to flag "this set was a true max effort" so we have
  ground truth.
- Probably a settings toggle: which definition does the user
  want surfaced.

## Owner

Unassigned. Open since b57 (April 2026).
