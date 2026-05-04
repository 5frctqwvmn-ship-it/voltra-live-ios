# Next Agent Prompt — Updated 2026-05-03

> **Paste this entire file as your first message when starting a new chat
> for this project. It is the self-contained boot prompt. The repo is the
> source of truth; this file is how you orient to it.**

---

## Who you are and what you are doing

You are a senior iOS/SwiftUI engineer continuing work on **VOLTRA Live**,
an iPhone app that pairs with VOLTRA resistance-training hardware over BLE,
logs workouts, and provides a real-time force/telemetry display.

The repo is:
`github.com/5frctqwvmn-ship-it/voltra-live-ios`
Active branch: `feat/ui-v4-2-claude`

**Before writing a single line of code, read these files in order:**

1. `AGENTS.md` — sacred files, cost convention, role rules, version-bump
   procedure.
2. `docs/handoff/00_START_HERE.md` — index of all handoff docs.
3. `docs/handoff/02_CURRENT_STATE.md` — what ships, what's broken.
4. `docs/handoff/03_CURRENT_FEATURE_SPEC.md` — full spec for every
   in-flight feature.
5. `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` — every ADR (V4-D1…).
6. `docs/handoff/06_KNOWN_ISSUES.md` — KI-tracked items (don't fix
   unilaterally without a KI entry).
7. `docs/handoff/B74_BUG_QUEUE.md` — current open bug queue.
8. `docs/handoff/CONTEXT_LEDGER.md` — compact decisions ledger
   (supplement to the full ADR doc).
9. `docs/WORK_LOG.md` — append-only change journal, last 10 entries.

Summarise what you find before changing anything. The user will confirm
or correct before you write code.

---

## Current build state (as of 2026-05-03 CDT)

- **Last shipped build:** v0.4.46 / build 73 ("Grid scroll fix")
- **Active branch:** `feat/ui-v4-2-claude`
- **Next build slot:** b74 (NOT yet assigned — user has not said "ship b74")
- **TestFlight status:** b73 is live. b74 is NOT shipped. User said
  explicitly: *"I don't want to ship anything to test flight yet."*

---

## What happened in the last Perplexity session (2026-05-03)

This context is NOT in the repo handoff docs yet (it was generated in
a Perplexity chat). Everything below should be treated as confirmed
user intent:

### Chain-centric routing fix (DO IMPLEMENT — no TestFlight ship)

The user identified that chain-centric mode (`workoutMode == .combined`
when both Voltras share a single exercise) and inverse-chains
(the chains overlay on the resistance tile using the eccentric
motor in reverse/assist direction) were both routing incorrectly:

**Chain-centric (`combined` mode) bug:**
- When in `combined` mode with 2 Voltras, `WriterRouter.apply` was
  splitting weight evenly (CombinedParity) but the chain
  (`upcomingChainsLb`) overlay was NOT being split — only one Voltra
  received the chains command.
- **Fix required:** In `WriterRouter.apply`, when `workoutMode == .combined`,
  also split `upcomingChainsLb` across both sides using the same
  even-weight split logic as the base weight. Both sides should receive
  `totalChainsLb / 2` rounded to nearest 2 lb.

**Inverse-chains bug:**
- Inverse chains (where the chains motor assists rather than resists,
  used for accommodating resistance inversion on exercises like good
  mornings) was toggling the chains overlay but sending the SAME
  payload as normal chains — no inversion. The firmware expects the
  `eccentricLb` field to be set to a NEGATIVE value to signal
  inverse/assist mode, OR a separate control frame parameter.
- **Fix required:** In `LoggingStore`, when `upcomingChainsEnabled == true`
  AND the exercise's `isInverseChains: Bool` flag is set, send
  `-upcomingChainsLb` as the chains payload value (negative = assist).
  The `VoltraDeviceState` struct needs `isInverseChains: Bool = false`
  added (additive, no migration needed). `ExerciseDetailView` needs a
  toggle for this when in chain-overlay mode.

### Session Recorder spec was reviewed and approved

- The spec in `docs/handoff/SESSION_RECORDER_SPEC.md` was reviewed.
- User confirmed: "Do the Session Recorder. It will help debug these
  routing bugs."
- **This is the top implementation priority after the chain-centric /
  inverse-chain fix.** However, do NOT ship it to TestFlight until
  the user explicitly says so.

### Coaching / weight-suggestion feature spec was discussed

- A full spec was drafted in this Perplexity session for a
  **"Coaching Card" feature** — an AI-readable weight-suggestion engine
  that reads the last 88 sessions of SwiftData history and surfaces
  a 3-button weight picker (Safe / Repeat / Aggressive) on the
  `ExerciseDetailView` pre-workout screen.
- **This spec lives in this prompt file** (section below).
  It was NOT yet implemented.
- The user said: *"Let's write the exact spec, logic, and everything
  that I may need to give to the coding model."* This section IS that
  spec. Hand it to the implementation agent as-is.
- **Do NOT implement the coaching card until the chain-centric fix
  and Session Recorder are in.**

---

## COACHING CARD — Full Spec (hand to implementation agent)

### Overview

A non-modal, inline card that appears on `ExerciseDetailView` (the
pre-workout screen where the user picks an exercise and sees set
history). The card shows:
- What weight the user used last time for this exercise at this set
  number.
- A 3-button row: **Safe** (hold or slight drop), **Repeat** (same
  as last time), **Aggressive** (small bump).
- A **fatigue indicator dot** (green / yellow / red) derived from
  force-drop-off % in the most recent session.
- A **one-line coaching copy** (e.g. "Last time: 185 lb × 8 reps").

### Trigger logic

| State | View shown |
|---|---|
| No BLE telemetry, pre-workout (user hasn't started the set) | **CoachingCardView** |
| BLE telemetry streaming (set is live or just finished) | **ForceChartView** (existing, no change) |
| Less than 1.5 s since last telemetry packet | Hold current view (debounce, no flash) |

### Data model

```swift
struct SetPerformanceSnapshot {
    var exerciseId: String       // exercise.name (or persistent ID)
    var setNumber: Int           // 1-indexed
    var plannedWeightLb: Double
    var peakForceLb: Double
    var repCount: Int
    var avgHR: Double?
    var kcal: Double?
    var dropOffPct: Double?      // (set1_peak - thisSet_peak) / set1_peak
}

struct ExerciseSessionCursor {
    var exerciseName: String
    var setNumberForCurrentInstance: Int   // how many sets done today
}

struct HistoricalSetMatch {
    var sessionDate: Date
    var setNumber: Int
    var weightLb: Double
    var peakForceLb: Double
    var repCount: Int
    var dropOffPct: Double?      // if available
}

struct CoachingRecommendation {
    var anchorLb: Double              // "last time" weight
    var safeWeightLb: Double          // hold or -5%
    var repeatWeightLb: Double        // same as anchor
    var aggressiveWeightLb: Double    // +5-10%
    var fatigueDotColor: FatigueDot   // .green / .yellow / .red
    var coachingCopyLine: String      // "Last time: 185 lb × 8"
    var confidenceLevel: Int          // 0-3 (0 = no history, 3 = full)
}

enum FatigueDot { case green, yellow, red }
```

### Historical lookup (Phase 1 — read-only, SwiftData)

- Query: fetch the most recent `WorkoutSession` that contains an
  `ExerciseInstance` with matching `exerciseName`, sorted by
  `startedAt` descending, `fetchLimit: 1`.
- From that session, pull all `LoggedSet`s for the matching instance,
  sorted by `setNumber` ascending.
- Map to `[HistoricalSetMatch]`.
- No new SwiftData fields needed for Phase 1.

### Coaching rule stack (evaluate in order, first match wins)

```
Rule 0: history == nil || history.isEmpty
  → anchor = today's first-set weight (or last planned weight)
  → safe = anchor, repeat = anchor, aggressive = anchor + 5
  → dot = .green, copy = "No history — set your own target"

Rule 1: todaySetsCount == 0 (haven't started yet)
  → anchor = history[0].weightLb (last session's Set 1)
  → safe = anchor * 0.95 rounded to 5
  → repeat = anchor
  → aggressive = anchor * 1.05 rounded to 5
  → dot = derived from history[0].dropOffPct (see table)
  → copy = "Last time: {anchor} lb × {history[0].repCount} reps"

Rule 2: dropOffPct > 0.30 (RED fatigue gate)
  → hold weight — no increase offered
  → aggressive = repeat = safe = anchor (all same)
  → dot = .red
  → copy = "High fatigue detected — holding weight"

Rule 3: dropOffPct 0.15-0.30 (YELLOW gate)
  → safe = anchor * 0.95, repeat = anchor, aggressive = anchor + 5
  → dot = .yellow
  → copy = "Moderate fatigue — small bump available"

Rule 4: dropOffPct < 0.15 AND anchor within 5% of history anchor
  → safe = anchor, repeat = anchor, aggressive = anchor * 1.10 rounded to 5
  → dot = .green
  → copy = "On track — push it if feeling good"

Rule 5: dropOffPct < 0.15 AND today > history by > 5%
  → safe = history anchor, repeat = anchor, aggressive = anchor * 1.10
  → dot = .green
  → copy = "Stronger than last time — nice work"
```

**Hard caps (override any rule above):**
- `aggressiveWeightLb` ≤ `todaySessionMax * 1.25`
- `aggressiveWeightLb` ≤ `allTimeHistoricalMax * 1.15`

**Fatigue dot from dropOffPct:**

| dropOffPct | dot |
|---|---|
| nil or < 0.15 | .green |
| 0.15 – 0.30 | .yellow |
| > 0.30 | .red |

### UI layout (CoachingCardView)

```
┌─────────────────────────────────────────┐
│ ● [fatigue dot]  Last time: 185 lb × 8  │  ← coaching copy line
│                                         │
│  [SAFE: 175]   [REPEAT: 185]   [PUSH: 200] │  ← 3 buttons
│                                         │
│  (small grey) Set 2 · Leg Day · 3 days ago │  ← context line
└─────────────────────────────────────────┘
```

- Card appears BELOW the existing exercise header, ABOVE the
  existing set-history list.
- Tapping a button: sets `logging.pendingPlannedWeightLb` to that
  value, sends haptic (`.selection`), pushes state to device via
  `WriterRouter`, shows a checkmark badge on the tapped button for
  1.5 s.
- Card animates in with `.transition(.move(edge: .top).combined(with:
  .opacity))` when switching from `ForceChartView` to `CoachingCardView`.
- Falls back to a minimal "No history" state (Rule 0) when history
  is nil — never hides entirely.

### Fallback states

| Condition | Card behavior |
|---|---|
| No history for this exercise | Rule 0 copy, all buttons = current weight |
| VOLTRA disconnected | Buttons still tappable (sets planned weight in UI, pushes when reconnected) |
| First-ever exercise in app | Rule 0 |
| SwiftData context nil | Card hidden entirely |

### Weight application flow (tap button)

1. Haptic: `.UIImpactFeedbackGenerator(style: .medium).impactOccurred()`
2. `logging.pendingPlannedWeightLb = tappedWeight`
3. `writerRouter.apply(logging.upcomingDeviceState, mdm: mdm)`
4. Optionally: `logging.logCoachingSelection(rule: matchedRule, weight: tappedWeight)`
   (for future analytics — do NOT send to any network)
5. Checkmark on button for 1.5 s, then back to weight label.

### Phase rollout

- **Phase 1 (implement first):** Historical anchor only.
  - Rule 0 + Rule 1 only.
  - No fatigue dot (always .green).
  - No drop-off calculation.
  - Just shows "Last time: X lb × N reps" with Repeat + slight nudge.
  - Testable with zero new infrastructure.
- **Phase 2:** Add deltas and Rules 2-5.
- **Phase 3:** Add force/power drop-off fatigue gating (dot goes live).

### Files to create / modify

| File | Change |
|---|---|
| `VoltraLive/Logging/Views/CoachingCardView.swift` | NEW |
| `VoltraLive/Logging/Persistence/LoggingStore.swift` | Add `historicalSetLookup(exercise:setNumber:)` |
| `VoltraLive/Logging/Views/ExerciseDetailView.swift` | Insert card between header and set list |
| `VoltraLive/Session/CoachingEngine.swift` | NEW — pure rule engine, no SwiftUI |

### Sacred files — do NOT touch
`VoltraProtocol.swift`, `TelemetryExtractor.swift`,
`PacketParser.swift`, `FrameAssembler.swift`.

---

## Open items the new agent must address (in priority order)

### P1 — Chain-centric + inverse-chains fix (no TestFlight ship)

See "Chain-centric routing fix" section above. Fix the two routing
bugs and commit to `feat/ui-v4-2-claude`. **Do not bump version or
ship to TestFlight.** User wants to verify locally first.

**Expected deliverable:** PR or direct commit with:
- `WriterRouter.swift` — combined-mode chains split
- `LoggingStore.swift` — inverse-chains negative payload
- `VoltraDeviceState` or equivalent — `isInverseChains: Bool = false`
- `ExerciseDetailView.swift` — inverse-chains toggle
- Test: at least one unit test for the chains split math
- `WORK_LOG.md` entry

### P2 — Session Recorder implementation

Spec is at `docs/handoff/SESSION_RECORDER_SPEC.md`. Implement per
the spec. Do NOT ship to TestFlight until user says so.

### P3 — B74 bug queue

Work through `docs/handoff/B74_BUG_QUEUE.md` items in order:
F1 → F2/F3 (need semantic confirmation) → F4 → F5/F6 (blocked on F1+F3)
→ F8 (code exists on branch `feat/b74-f8-watch-presence-indicator`).

### P4 — Coaching card (Phase 1)

After P1+P2 are done. Use the spec in this file.

---

## Process rules (persistent — applies to every agent every session)

1. **Read before writing.** Summarise what you found before changing code.
2. **Append WORK_LOG.md** after every meaningful change (code, decision,
   bug confirmed, build shipped). Same commit as the change.
3. **Update the relevant handoff doc** in the same commit as the code
   change when architecture, spec, or known-issues changes.
4. **Sacred files are READ-ONLY.** See AGENTS.md for the list.
5. **Version bumps: 3 places.** `Info.plist` + `project.yml` target
   settings + `project.yml` info.properties. Never bump without a
   build label change.
6. **One TestFlight build = one feature label.** The feature label
   goes in `Info.plist` key `VOLTRAFeatureLabel` AND `project.yml`.
7. **Cost convention.** Flag every medium-or-heavier action as
   lite / medium / heavy / very heavy with a one-line callout.
8. **Never ship to TestFlight** unless the user explicitly says
   "ship build N" or "push to TestFlight."
9. **Chain-first routing.** Any write that happens while
   `mdm.hasAnySupersetChainEntry == true` must route to
   `mdm.supersetActiveSlot` only, regardless of `workoutMode`.
10. **Combined-mode even-weight invariant.** In `.combined` mode,
    `pendingPlannedWeightLb` must always be an even integer. Enforce
    via `CombinedParity.enforce(...)` at every write site.

---

## Version bump procedure reminder

Always bump in ALL THREE places in the same commit:

```yaml
# project.yml — two places:
settings:
  MARKETING_VERSION: "0.4.XX"
  CURRENT_PROJECT_VERSION: "YY"
info:
  properties:
    CFBundleShortVersionString: "0.4.XX"
    CFBundleVersion: "YY"
    VOLTRAFeatureLabel: "Feature name"
```

```xml
<!-- VoltraLive/Info.plist -->
<key>CFBundleShortVersionString</key><string>0.4.XX</string>
<key>CFBundleVersion</key><string>YY</string>
<key>VOLTRAFeatureLabel</key><string>Feature name</string>
```

---

*This file was last updated: 2026-05-03 23:40 CDT by Perplexity session.*
*Commit it to the repo in the same push as CONTEXT_LEDGER.md update.*

---

## Update: 2026-05-04 — Post Smart Coach Unlock Commit

**Current HEAD (pre-ship):** new commit on top of `7c02c59` — hidden Smart Coach unlock.
**TestFlight:** build 81 is latest shipped. Build 82 pending after CI passes on this commit.

**What to verify on physical device (build 82 TestFlight):**

1. **Version badge tap contract:**
   - 4 taps → toggles Smart Coach (no visible badge change). Verify by entering LiveCapture rest state.
   - 3 taps → unlocks SessionRecorder (red dot appears).
   - 1 tap → cycles debug grid.

2. **Smart Coach off by default:**
   - Fresh install: no coaching card visible in rest state.

3. **Smart Coach unlocked:**
   - 4-tap version badge → start session → complete one set → rest state.
   - After ~1.5 s debounce: CoachingCardView appears where ForceChart was.
   - Tap "Load X lb" → weight tile updates. No BLE write unless user taps +/-.

4. **KI-21 verification:**
   - Change chains/ecc/inverse on physical VOLTRA.
   - Session recorder must show `device.state.change source=deviceUnsolicited` for each field.
   - Session recorder must show `ui.deviceChainsApplied`, `ui.deviceEccentricApplied`, `ui.deviceInverseApplied`.

5. **KI-20 regression check:**
   - Base weight device→UI must still work (20→15 lb tile update).

**If hardware tests pass:** close KI-21, close KI-SC-01. Plan coaching card
feature expansion (per-rep fatigue gate, `aggressiveRecommendationsEnabled`).

**Open questions before closing KI-SC-01:**
- Does card dismiss on weight tap, or wait for device re-load?
- Correct debounce duration on aggressive mode?
