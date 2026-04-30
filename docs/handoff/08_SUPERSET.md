# 08 — Superset (b53 per-instance routing)

**Status as of b53/b54:** Chain routing is now driven by a per-instance
`ExerciseInstance.assignedVoltra` field stamped at exercise-add time,
not by predicate evaluation against `supersetChain` membership. This
doc supersedes the b49 "unified flow" description.

The b49 baseline still applies for the parts that didn't change:
Independent and Superset are no longer separate modes; Superset is a
TAG. The flow is unified — pair Voltras → day tile → exercise screen,
no mode picker. WorkoutMode is auto-derived from paired-device count.
Combined stays as a same-bar use case via the "Merge" button.

## What changed in b53

Three structural changes plus one safety fix:

1. **Per-instance Voltra assignment.** `ExerciseInstance` got an
   additive SwiftData field `assignedVoltra: String?` (values: `"left"`,
   `"right"`, `"both"`, or `nil` for legacy/single-device sessions).
   Stamped when the user adds an exercise via the per-exercise picker.
2. **3-way Left / Right / Both picker.** Replaces b49's binary L/R
   slot picker. Surfaced on `ExerciseDetailView.dualVoltraTopPanel` at
   exercise-add time. "Both" is the merged/Combined virtual-twin path.
3. **WriterRouter routes by `activeInstance.assignedVoltra`** instead
   of by `mdm.hasAnySupersetChainEntry(for: name)`. The chain array is
   no longer the routing source of truth; it's a UI-state list. The
   instance is the source of truth.
4. **SWAP no longer auto-LOADs.** Sends `weight=0` (UNLOAD) to the
   newly-active Voltra, then re-arms — but does not push the stored
   weight back. The user must tap LOAD before their next set. This
   fixes a footgun where SWAP would silently re-load weight on a side
   the user expected to be quiet.

The b49-era helpers `hasActiveSupersetChain`, `activeSupersetEntry`,
`nextSupersetEntry`, `advanceSupersetIndex()` still exist and still
drive the live UI (banner, 2-trace chart, swap button). What changed
is **routing** — which Voltra a given write goes to — not chain
state-machine plumbing.

## Why we changed this (b53)

Pre-b53, the writer asked `mdm.hasAnySupersetChainEntry(for: name)`
to decide which Voltra to address. This had two failure modes:

1. **Two exercises with the same name on opposite sides** (legitimate
   in b49+) collided on the predicate, so writes leaked to the wrong
   side.
2. **Adding a third exercise mid-session** required mutating the chain
   to update routing — which meant routing decisions and UI state were
   tangled.

Storing the assignment on the instance itself decouples the two: the
chain becomes a pure UI list of "what's in this superset," and the
instance owns "which device backs me."

## How routing works in b53

```
User logs a set
    │
    ▼
LoggingStore.activeInstance ──► instance.assignedVoltra
    │                                   │
    │                                   ▼
    │                           WriterRouter.route(instance:)
    │                                   │
    │                                   ▼
    │                  ┌────────────────┼────────────────┐
    │                  ▼                ▼                ▼
    │              "left"            "right"           "both"
    │                  │                │                │
    │                  ▼                ▼                ▼
    │           VoltraWriter.L    VoltraWriter.R   both writers
    │                                                (Combined math)
    │                  │                │                │
    │                  └────────────────┼────────────────┘
    │                                   ▼
    │                           BLE control writes
    │
    ▼
LoggedSet attributes to instance (correct, by construction)
```

`nil` `assignedVoltra` (legacy / single-Voltra sessions) falls through
to the single connected Voltra, matching pre-b53 behavior exactly.

## Header rewrite (b53)

When `mdm.supersetTag == true` AND the chain has at least one entry,
the live header reads:

```
Superset · {head} · HR {bpm} · {day}
```

Where `{head}` is the active exercise name and `{day}` is the day-tile
label (e.g. "LEG DAY"). The HR segment is dropped if HealthKit hasn't
delivered a sample yet. Implementation: `LiveCaptureView.headerStrip`
checks `mdm.supersetTag && !mdm.supersetChain.isEmpty` and assembles
the string; otherwise falls back to the b49 single-exercise header.

The same string is used in the export markdown header, so session
exports and the live screen agree.

## Session-level rollups (b53)

`WorkoutSession` got four additive SwiftData fields:

- `avgHRSession: Double?` — mean HR across all live samples.
- `kcalSession: Double?` — sum of HealthKit active-energy deltas.
- `exerciseCountSession: Int?` — distinct ExerciseInstance count.
- `priorSessionRef: PersistentIdentifier?` — link to the most recent
  prior session matching the same day-tile, used for comparison.

Stamped at `endSession()` from data already in `SessionStore`. Fields
are nullable — old sessions are unaffected. Surfaced in `ExportSheet`
as a session-header card above the per-exercise cards (see 02 for the
b53 export layout fix).

## SWAP — what it does and doesn't do (b53)

`LiveCaptureView.swapSupersetSide()` in b53:

1. **Force-finalize the in-flight set** if active, so the LoggedSet
   attributes to the OUTGOING instance.
2. **UNLOAD the outgoing side** (sends `0 lb` to its Voltra).
3. **UNLOAD the incoming side** (sends `0 lb` — the b53 safety add).
4. **Flip `supersetActiveSlot`** via `advanceSupersetIndex()`.
5. **Switch `LoggingStore.activeInstance`** to the incoming exercise
   via `LoggingStore.switchActiveInstanceByExerciseName(_:)`.
6. **Stop.** No automatic LOAD. The user taps LOAD when they want
   weight on the bar.

Net effect: one tap clears both sides and switches focus. The user
re-arms intentionally.

> Open question (see 10): document the no-auto-LOAD change in the
> in-app help / first-run hint. Behavior change from b49 — users who
> learned the old SWAP may find the bar quiet on their first b53 swap.

## The chain itself (mostly unchanged from b49)

`MultiDeviceManager.supersetChain: [SupersetChainEntry]` still holds
the chain. Helpers still exist:

- `appendSupersetEntry(name:slot:weightLb:)` — called from
  `ExerciseDetailView.commitStartButton`. Idempotent on `(name, slot)`.
- `hasActiveSupersetChain: Bool { supersetChain.count >= 2 }` —
  controls the in-session banner + 2-trace force chart.
- `activeSupersetEntry`, `nextSupersetEntry`, `advanceSupersetIndex()`
  — unchanged.

What's no longer used: `hasAnySupersetChainEntry(for:)` for routing
decisions. The method still exists (UI uses it for banner labels) but
WriterRouter no longer calls it.

## The 2-trace force chart (b49, still current)

Unchanged from b49. `LoggingStore.autoLogTelemetrySet` stashes
finalized samples into
`SessionStore.lastFinalizedByExercise[name]`. `LiveCaptureView.forceChart`
pulls `lastFinalizedByExercise[nextSupersetEntry.exerciseName]` as
the secondary trace when `mdm.hasActiveSupersetChain` is true.
`ForceChartView` renders the secondary as a dimmed dashed line.

## Top-of-exercise-screen panel (b53 update)

`ExerciseDetailView.dualVoltraTopPanel` — shown whenever both Voltras
are paired. Three controls (b53 changed #1):

1. **L / R / Both picker** — 3-way (was binary in b49). Stamps
   `instance.assignedVoltra` on commit. "Both" engages Combined math.
2. **Merge button** — kept for backward compatibility, equivalent to
   picking "Both."
3. **Superset tag dot** — unchanged from b49.

`addAnotherExerciseButton` is unchanged.

## V1/V2 routing interaction (b54, updated b71 V4-D21 part 2)

**Pre-b71 behavior (b54).** `LiveCaptureContainer` gates V1 vs V2:

- V2 renders only when **single Voltra paired AND
  `mdm.supersetChain.isEmpty`**.
- Any chain entry (≥ 1) → V1 renders, regardless of V2 preference.
- 2 Voltras → V1 always.

**As of b71 V4-D21 part 2 (this commit).** The chain UI is now ported
into V2 verbatim — `SupersetSwitcherBanner` hosts the full V1 SWAP
flow (force-finalize → unload outgoing → flip slot → switch active
instance → restore chain weight + re-anchor cascade → host pushes
device state) and `LiveCaptureViewV2` wires the three V1 lifecycle
hooks: onAppear chain restore, onChange `currentSet` flip →
`mdm.lockSupersetTag()`, onChange `mdm.supersetActiveSlot` →
`switchActiveInstanceByExerciseName`. The B53 "no auto-LOAD on
incoming" safety is preserved.

The `LiveCaptureContainer.shouldUseV2` predicate still routes
`hasChain → V1` at the time of this commit — the routing flip lands
in V4-D21 part 3 (Step 3 of the b71 stack). After part 3, V2 will
be the canonical chain UX and V1 will only render via the
emergency `@AppStorage("liveCaptureUIVersion")` kill switch.

Until part 3 ships, **all chain / superset behavior described in
this doc still lives in V1 at runtime**, but the V2 implementation
is structurally complete and reachable by setting the kill switch
to `"v2"` on a build with the V1-fallback branch removed.

## What the user sees end-to-end (b53)

1. Pair 2 Voltras.
2. Tap a day tile (e.g. LEG DAY).
3. Pick an exercise (e.g. Back Squat). Land on the exercise screen.
4. Top panel shows L / R / Both picker + Merge + Superset tag dot.
   L pre-selected.
5. Pick "L" (or "R" or "Both"). `instance.assignedVoltra` stamps now.
6. Optionally tap the Superset tag dot.
7. Tap "Add Another Exercise." App pops to day tiles.
8. Pick a second day tile + exercise (e.g. Bent-Over Row). The unused
   side ("R") is pre-selected; user can change to Both.
9. Tap Start set 1. Live grid. Header reads "Superset · Back Squat ·
   HR {bpm} · LEG DAY" once HR arrives. Superset tag locks.
10. Lift. Reps + force display live. IDLE_GRACE finalizes the set.
11. Tap SWAP. Set force-finalizes, both sides UNLOAD, focus switches
    to Bent-Over Row. **Bar is quiet.** User taps LOAD when ready.
12. Lift the second exercise. Force chart shows both traces.
13. Tap End Session. `WorkoutSession.supersetTag = true`,
    `avgHRSession` / `kcalSession` / `exerciseCountSession` stamp,
    `priorSessionRef` links to the prior LEG DAY session.

## Migration notes

- `assignedVoltra` is additive + nullable. Existing instances read as
  `nil` and route to the single connected Voltra. No migration needed.
- `WorkoutSession` rollup fields are additive + nullable. Existing
  sessions display dashes in the export header card.
- `supersetChain` array shape unchanged; existing in-flight sessions
  (extremely unlikely across upgrades) keep working because the
  routing fallback for `nil assignedVoltra` matches old behavior.
