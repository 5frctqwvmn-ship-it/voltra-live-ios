# tasks/todo.md — active task plan

> Plan-first working file for the **current** task only.

---

## Active task

RC-01 / SC-01 — Rest-state Coaching Card + Smart Coach integration

## Repo state at task start

- Branch: feat/ui-v4-2-claude
- HEAD: 9788d49 (focusedBle topology fix — NOT yet in TestFlight)
- Working tree: clean
- Version/build: 0.4.52 / build 80 (build 80 shipped; build 81 not yet bumped)
- KI-20: OPEN — pending hardware retest on build 81

## Key constraints discovered

1. `LoggedSet` has `peakForceLb` + `avgForceLb` only — NO per-rep force/power
   fields. SetSnapshotBuilder must use `peakForceLb` as proxy for
   `bestRepForceLb` and treat `lastRepForceLb` as nil. Fatigue gate will
   be `.unknown` for all sets until per-rep telemetry lands (acceptable for
   RC-01 beta).
2. Coaching buttons MUST call `adjustWeight(_:)`, NOT write directly to
   `pendingPlannedWeightLb`. `adjustWeight` enforces CombinedParity and
   reanchor. Buttons compute the delta: `Int(targetLb.rounded()) - cur`.
3. `session.restActive` is the correct panel-switch trigger (set
   synchronously in `finalizeSet()` and `tapRestTile()`).
4. `setNumberForCurrentInstance` is 1-based next-set ordinal.
   `nextSetIndex` (0-based) = `setNumberForCurrentInstance - 1`.
5. `WorkoutSession.id` is the `currentWorkoutSessionID` for the cursor.
6. All feature flags start `false` in production — `coachingCardEnabled`
   must be `false` by default so this ships dark.

## Plan

- [x] Read all required docs — done
- [x] Write plan to tasks/todo.md — done
- [ ] Create docs/incoming/ staging files
- [ ] Split into 11 target app files
- [ ] Write SetSnapshotBuilder (adapts LoggedSet → SetPerformanceSnapshot)
- [ ] Wire LiveCaptureViewV2:
      - isDeviceRestingDebounced state + DispatchWorkItem
      - panel switch (ForceChart ↔ CoachingCard)
      - snapshot builder calls
      - HistoricalWorkoutMatcher init
- [x] Create docs/specs/RC-01_COACHING_CARD.md
- [x] Update handoff docs
- [x] Commit

## Review

All 11 target files created. LiveCaptureViewV2 panel switch wired behind
`FeatureFlags.coachingCardEnabled` (default false). `allExerciseInstances(for:)`
added to LoggingStore. Staging files in docs/incoming/. Spec at
docs/specs/RC-01_COACHING_CARD.md. All docs updated.

Key constraint: fatigue gate always .unknown until per-rep telemetry lands.
Feature ships dark — no TestFlight visible change until flag enabled.
Next: commit, push, CI. Then build 81 hardware retest for KI-20.
