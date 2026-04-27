# 10 — Open Questions

Things blocked on the user. Resolve before the dependent task can ship.

> When you answer one of these, **delete it from this file in the same
> commit** as the code change that uses the answer. Don't let stale
> questions accumulate.

## Build 30

### Drop-set regression — need precise reproduction

Status: **needs user repro before any code fix.**

Static analysis of `54b33b3` (build 29) shows the production cascade math
is anchor-correct — see `02_CURRENT_STATE.md` for the full investigation
and the regression tests now in
`VoltraLiveTests/DropSetCascadeTests.swift` that pin that behavior. The
`100 → 80 → 64` ladder the user reported is reproducible only by calling
the unused helper `cascadeNextWeight(from:tier:)` with `tier=4`, which
shouldn't be reachable from any UI path (`bumpCascadeTier` caps at 3).

Questions to ask the user:

1. What was the build number visible on screen when this happened?
   (Build numbers are required on every screen — should be 29 if it's
   the latest TestFlight.)
2. Exact tap sequence: did they tap DROP SET once, then watch it
   auto-cascade, or did they keep tapping?
3. Did the **logged set's drops** show those weights (in History) or did
   the **tile preview** show them while still active?
4. Could they capture a short screen recording of one cascade attempt?
   The tile shows DROP N + the current weight + the next-2 preview —
   that's enough to reconstruct what the state machine fired.

### Old-store import

Status: **needs user answer before any importer code is written.**

Build 29 abandoned the old SwiftData store at the legacy URL. The user's
prior session logs are still on disk but not visible in the app. Do they
want them imported, or is the fresh start fine?

If yes: write a one-shot importer that opens the legacy store with a
separate `ModelContainer`, reads all sets, writes them into the v2 store,
then sets a "imported" flag so it doesn't run again.

## Build 31 (Superset)

(Defer until build 30 ships.) See `08_SUPERSET.md` "Open questions for
build 31" — copy them here when build 31 begins.

## Process

### "Should we auto-update CloudKit re-enablement?"

Not a user question — a self-imposed gate. Don't re-enable CloudKit until
the v2 store has been stable across at least 2 releases past build 29.
Track the count: `0 / 2` after build 30 ships, `1 / 2` after build 31, etc.

(Move this to a tracker once we have 2+ open process gates.)
