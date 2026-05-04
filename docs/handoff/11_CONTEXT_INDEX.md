# Context Index — 2026-05-04

## Must-read (every agent, every session)
- AGENTS.md
- docs/handoff/00_START_HERE.md
- docs/handoff/09_NEXT_AGENT_PROMPT.md
- docs/WORK_LOG.md (last 20 entries only)

## Skim if needed
- docs/handoff/03_CURRENT_FEATURE_SPEC.md
- docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md
- docs/handoff/06_KNOWN_ISSUES.md
- docs/handoff/10_OPEN_QUESTIONS.md

## Full session transcript archive
- docs/handoff/artifacts/perplexity-thread-2026-05-04.md
  (674 KB Markdown export — search this only if something is unclear)

---

## Current state (2026-05-04 10:00 AM CDT)

| Item | Value |
|---|---|
| Branch | feat/ui-v4-2-claude |
| Latest good commit | ba8d3ef |
| WORK_LOG | Restored — 187431 bytes, starts with `# WORK_LOG` |
| Build shipped | v0.4.52 / build 81 — KI-20 topology fix + RC-01 dark code |
| KI-20 status | **OPEN** — hardware A1 retest required before close |
| RC-01 / SC-01 | Code exists in repo, all feature flags default FALSE |

---

## Next work (in order)

1. **KI-20 A1 hardware retest** (user action required)
   - Install build 81 on physical device
   - Change VOLTRA base weight 20 lb → 15 lb
   - Confirm tile updates AND log shows `ui.deviceBaseWeightApplied`
   - Both must pass before any coaching flag is enabled

2. **KI-21: @Published bridges for chains/eccentric/inverse**
   - Same 4-step pattern as KI-20 baseWeight:
     1. Decoder event → VoltraDecodedEvent
     2. Device state field → DeviceState
     3. Manager @Published bridge → VoltraBLEManager / DualMultiDeviceManager
     4. LiveCaptureViewV2 .onChange wiring

3. **Replace CoachingEngineTests.swift placeholder**
   - Source: docs/incoming/CoachingEngineTestsv4.swift
   - Target: VoltraLiveTests/CoachingEngineTests.swift
   - Run xcodebuild test to confirm

4. **Enable coachingCardEnabled=true for build 82**
   - Only after KI-20 A1 passes AND tests green
   - Keep smartCoachEnabled=false until card is device-tested

5. **Enable smartCoachEnabled=true**
   - Only after coaching card passes on device
   - Validate all fatigue gate branches (green/yellow/red) on hardware

---

## What was already built (commit ad3c11b)

16 new files created in ad3c11b:
- `VoltraLive/FeatureFlags.swift` — all 5 flags default FALSE
- `VoltraLiveCoaching/CoachingConstants.swift`
- `VoltraLiveCoaching/Models/SetPerformanceSnapshot.swift`
- `VoltraLiveCoaching/Models/ExerciseSessionCursor.swift`
- `VoltraLiveCoaching/Models/HistoricalSetMatch.swift`
- `VoltraLiveCoaching/Models/CoachingRecommendation.swift`
- `VoltraLiveCoaching/Services/HistoricalWorkoutMatcher.swift`
- `VoltraLiveCoaching/Services/CoachingEngine.swift`
- `VoltraLiveCoaching/Services/SetSnapshotBuilder.swift`
- `VoltraLiveCoaching/Views/CoachingCardView.swift`
- `VoltraLiveCoaching/Views/CoachingCardButtonRow.swift`
- `VoltraLiveCoaching/Views/FatigueIndicatorView.swift`
- `VoltraLiveTests/CoachingEngineTests.swift` ← **PLACEHOLDER ONLY**
- `docs/specs/RC-01_COACHING_CARD.md`
- `docs/incoming/VoltraCoachingv3.swift`
- `docs/incoming/CoachingEngineTestsv4.swift`

Key design decisions locked:
- Button taps route through `adjustWeight(delta:)`, NOT direct `pendingPlannedWeightLb` write
- Rest panel trigger: `session.restActive` onChange, 1.5s debounce
- `allExerciseInstances(for:)` filters in Swift (avoids SwiftData predicate issues)
- AnyView type erasure for ForceChart/CoachingCard two-branch switch
- Fatigue gate is `.unknown` for ALL sets until per-rep telemetry lands (correct, intentional)
- `coachingCardEnabled` defaults false — no visible TestFlight behavior until flipped

---

## Critical DO-NOT rules

1. **Do NOT use MCP/API file-write tools for docs/WORK_LOG.md or large files**
   Both MCP write paths silently truncated WORK_LOG to ~1.5 KB in this session.
   Use normal git: edit locally → git add → git commit → git push.

2. **Do NOT enable any coaching flag until KI-20 A1 hardware retest passes**

3. **Do NOT close KI-20 without physical hardware confirmation**

4. **Do NOT force-push**

5. **Do NOT amend published commits**

6. **Do NOT commit .claude/**

7. **Do NOT ship TestFlight without explicit user instruction**

8. **Do NOT modify project.yml, CI workflows, entitlements, or signing config without explicit approval**

---

## Smart Coach guardrails (locked — do not change)

| Gate | Condition | Behavior |
|---|---|---|
| Green | drop-off < 15% | Recommend anchor ± delta; aggressive allowed if confidence high |
| Yellow | 15–30% | Conservative only; no aggressive |
| Red | > 30% | Hold/reduce; no increase |
| Unknown | No per-rep data | Suppress aggressive; confidence low |

Hard limits:
- No recommendation > +10% unless gate is green
- Never exceed +25% over today's session max
- Never exceed +15% over historical max for that exercise
- Round weights to nearest 5 lb
- HR recovery = warning/log only, never hard lock
- No-history case shows "Pick a starting weight", not "Recommended 0 lb"
- Always tap-to-apply — never auto-change weight
- Always show reason string
- Always provide: primary recommended, last-time anchor, repeat-current fallback

---

## WORK_LOG rule

After ANY meaningful change, append to docs/WORK_LOG.md:
- date/time, goal, files changed, what changed, verification result, risks, next step

Then commit it with the related code change in the same commit.
Do NOT use MCP/API file writes for this file.
