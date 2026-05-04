# RC-01 — Rest-State Coaching Card + SC-01 Smart Coach

> Status: **IMPLEMENTED — feature-flagged OFF by default.**
> Branch: feat/ui-v4-2-claude. First commit in bundled build 81+ TBD.
> Do not enable in TestFlight until KI-20 hardware retest passes.

---

## Overview

When the user finishes a set and the device becomes unloaded, LiveCapture
replaces the ForceChart panel with a Coaching Card that recommends the
weight for the next set, based on today's session performance vs. historical
data from prior sessions.

**Nothing writes to the device automatically. All weight changes require
an explicit user tap.**

---

## Feature flags

All flags default `false`. Set to `true` to enable.

| Flag | Default | Effect |
|---|---|---|
| `coachingCardEnabled` | `false` | Shows the coaching card panel on rest |
| `smartCoachEnabled` | `false` | Enables CoachingEngine recommendations |
| `aggressiveRecommendationsEnabled` | `false` | Shows "Push X lb" aggressive option |
| `hrRecoveryHardLockEnabled` | `false` | Hard-blocks set start on HR — do not enable until threshold is tuned |
| `telemetryDebugExportEnabled` | `false` | Adds coaching inputs/outputs to recorder JSON export |

Source: `VoltraLive/FeatureFlags.swift`

---

## Panel switch behavior

| State | Panel shown |
|---|---|
| Device loaded (set active) | ForceChartView (unchanged) |
| Device unloaded < 1.5 s | ForceChartView (debounce suppresses flicker) |
| Device unloaded ≥ 1.5 s + exercise selected | CoachingCardView |
| Device unloaded ≥ 1.5 s + NO exercise selected | ForceChartView (card suppressed) |
| `coachingCardEnabled = false` | ForceChartView always |

Trigger: `session.restActive` (set synchronously in `finalizeSet()` / `tapRestTile()`).
Debounce: 1.5 s `DispatchWorkItem`. Cancelled immediately on re-load.
Transition: `.easeInOut(duration: 0.25)` opacity crossfade.

---

## Smart Coach rules (SC-01)

All rules are deterministic and explainable. No LLM/AI runtime.

### Fatigue gates (gate classification)

| Gate | Condition | Effect |
|---|---|---|
| `.green` | force/power drop-off < 15% | Progression allowed |
| `.yellow` | 15% ≤ drop-off < 30% | Max +5% increase |
| `.red` | drop-off ≥ 30% | No increase; no aggressive option |
| `.unknown` | per-rep data unavailable | Moderate confidence; no aggressive |

Drop-off = `(bestRepForceLb - lastRepForceLb) / bestRepForceLb × 100%`.
**Currently always `.unknown`** — `LoggedSet` stores only `peakForceLb` +
`avgForceLb`, not per-rep values. Per-rep telemetry is a Telemetry v2
follow-up (OQ-T series).

### Recommendation rules (in priority order)

| Rule | Condition | Output |
|---|---|---|
| 0 — no history | No prior data for exercise | Repeat current; `no_history_repeat_current` guardrail |
| 1 — no sets today | `completedSetsToday` empty | Last session's next-set weight; `start_at_anchor` guardrail |
| 2 — red gate | gate == `.red` | Hold weight; no increase; no aggressive |
| 3 — yellow gate | gate == `.yellow` | ≤ min(anchor, current×1.05); no aggressive |
| 4 — delta > 15% | today's set > 15% above last-session same-set | Anchor + offer aggressive |
| 5 — delta 0–15% | small positive delta | Anchor × 1.05 (conservative bump) |
| 6 — default | delta ≤ 0 or no delta | Match anchor |

### Progression guardrails

| Guardrail | Cap |
|---|---|
| Session jump cap | +25% above today's best completed set |
| Historical max cap | +15% above all-time historical max for exercise |
| Anchor floor | Never lower recommended below anchor (caps cannot reduce below baseAnchor) |
| Aggressive floor | Aggressive must exceed primary by ≥ 5% |

### Weight rounding

All output weights rounded to nearest `weightIncrementLb` (5.0 lb).

### No BLE writes

Coaching buttons call `adjustWeight(delta:)` in `LiveCaptureViewV2`.
`adjustWeight` enforces `CombinedParity` and reanchor. No new BLE write
commands are introduced by RC-01/SC-01. Device write only happens via
the existing +/- tap path.

---

## Data flow

```
session.restActive → onChange → onDeviceBecameUnloaded()
    → 1.5s debounce → coachingCardVisible = true
    → forceChartCard renders CoachingCardView

CoachingCardView rendered with:
    cursor  = buildCoachingCursor(...)
              ← logging.activeInstance → SetSnapshotBuilder.buildAll
    history = buildCoachingHistory(...)
              ← logging.allExerciseInstances(for:) → SetSnapshotBuilder
              → DefaultHistoricalWorkoutMatcher.mostRecentMatch
    recommendation = CoachingEngine().recommend(cursor, history)

Button tap → adjustWeight(delta) → pendingPlannedWeightLb → pushUpcomingStateToDevice()
```

---

## File map

| File | Purpose |
|---|---|
| `VoltraLive/FeatureFlags.swift` | All feature flags, default false |
| `VoltraLive/Coaching/CoachingConstants.swift` | Tunable constants |
| `VoltraLive/Coaching/Models/SetPerformanceSnapshot.swift` | Immutable set value type |
| `VoltraLive/Coaching/Models/ExerciseSessionCursor.swift` | Current session cursor |
| `VoltraLive/Coaching/Models/HistoricalSetMatch.swift` | Prior session lookup result |
| `VoltraLive/Coaching/Models/CoachingRecommendation.swift` | Engine output |
| `VoltraLive/Coaching/Services/HistoricalWorkoutMatcher.swift` | Protocol + default implementation |
| `VoltraLive/Coaching/Services/CoachingEngine.swift` | Rule engine |
| `VoltraLive/Coaching/Services/SetSnapshotBuilder.swift` | LoggedSet → SetPerformanceSnapshot adapter |
| `VoltraLive/Coaching/Views/CoachingCardView.swift` | Card UI |
| `VoltraLive/Coaching/Views/CoachingCardButtonRow.swift` | Action buttons |
| `VoltraLive/Coaching/Views/FatigueIndicatorView.swift` | Colored fatigue dot |
| `VoltraLive/Logging/Persistence/LoggingStore.swift` | Added `allExerciseInstances(for:)` |
| `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` | Panel switch + debounce + snapshot helpers |
| `VoltraLiveTests/CoachingEngineTests.swift` | Test placeholder (implement before build 82) |
| `docs/incoming/VoltraCoaching_v3.swift` | Original single-file staging artifact |
| `docs/incoming/CoachingEngineTests_v4.swift` | Test staging artifact |

---

## Known limitations (RC-01 beta)

1. **Fatigue gate always `.unknown`** — per-rep force data not in `LoggedSet`.
   Gate will resolve to green/yellow/red once Telemetry v2 per-rep fields land.
2. **`allExerciseInstances(for:)` fetches ALL instances** then filters in Swift.
   Acceptable for ≤ 88 sessions. Add a SwiftData index on `exercise.name` if
   session count grows beyond ~500.
3. **Test body is a placeholder.** `CoachingEngineTests.swift` must be filled
   before SC-01 is enabled in TestFlight.
4. **No per-set HR.** `heartRateAvgBpm`/`heartRateMaxBpm` are nil in
   `SetPerformanceSnapshot` until HealthKit per-set windowing is added.

---

## Open questions

- OQ-RC-01-A: What is the right debounce for aggressive mode (currently no
  extra debounce — same 1.5 s as card mount)?
- OQ-RC-01-B: Should the card dismiss immediately on weight tap or wait until
  the user picks up the cable (device loaded)?
- OQ-RC-01-C: Should `CoachingEngine` be a `@StateObject` or rebuilt each
  card render? Currently rebuilt each render (cheap, stateless).

---

*Last updated: 2026-05-03 — initial implementation.*
