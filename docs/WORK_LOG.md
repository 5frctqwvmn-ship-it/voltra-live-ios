# WORK_LOG

Append-only journal. Newest at the bottom. Every meaningful change to the
codebase or to the handoff docs gets one entry here, committed in the same
commit as the change.

## Entry format

```
## YYYY-MM-DD HH:MM UTC — <one-line goal>

- **Files changed:** path/one, path/two
- **What changed:** Short factual description.
- **Verification:** What you ran or observed (build, test, manual on device).
- **Risks:** Anything that could break or that you didn't fully test.
- **Next step:** The next thing the next session should do.
```

Keep entries short. If something needs a long explanation, that explanation
belongs in a handoff doc (`docs/handoff/*.md`) and the WORK_LOG entry just
points at it.

---

## 2026-04-27 17:30 UTC — Establish durable handoff docs

- **Files changed:** `AGENTS.md` (reconciliation), `docs/handoff/00_START_HERE.md`,
  `docs/handoff/01_PROJECT_OVERVIEW.md`, `docs/handoff/02_CURRENT_STATE.md`,
  `docs/handoff/03_ROADMAP.md`, `docs/handoff/04_ARCHITECTURE.md`,
  `docs/handoff/05_BLE_AND_PROTOCOL.md`, `docs/handoff/06_HEALTHKIT.md`,
  `docs/handoff/07_DUAL_VOLTRA.md`, `docs/handoff/08_SUPERSET.md`,
  `docs/handoff/09_RELEASE_AND_SIGNING.md`, `docs/handoff/10_OPEN_QUESTIONS.md`,
  `docs/WORK_LOG.md` (new file).
- **What changed:** Created the durable handoff doc structure. Backfilled
  state from session memory and chat.
- **Verification:** Docs only.
- **Risks:** None to runtime.
- **Next step:** Resume build 30 starting with the drop-set regression.

[...b28-b73 entries preserved in git history...]

## 2026-05-04 04:40 UTC — Chain-centric + inverse-chains fix; full handoff update

- **Files changed:**
  - `VoltraLive/BLE/WriterRouter.swift` — combined-mode chains split
  - `VoltraLive/Logging/Persistence/LoggingStore.swift` — inverse-chains negative payload
  - `VoltraLive/Logging/Model/VoltraDeviceState.swift` — `isInverseChains: Bool = false`
  - `VoltraLive/Logging/Views/ExerciseDetailView.swift` — inverse-chains toggle
  - `docs/handoff/09_NEXT_AGENT_PROMPT.md` — complete clean-start prompt
  - `docs/handoff/CONTEXT_LEDGER.md` — all decisions through 2026-05-03
  - `docs/handoff/PERPLEXITY_TRANSCRIPT_2026-05-03.md` — new
  - `docs/WORK_LOG.md` — this entry
- **What changed:**
  1. `WriterRouter.apply` — when `workoutMode == .combined` AND
     `chainsLb > 0`, split the chains value across both left and right
     writers using the same even-rounding logic as base weight
     (`CombinedParity.roundDownToEven(chainsLb / 2)`).
  2. `VoltraDeviceState` — added `isInverseChains: Bool = false`
     (additive, no SwiftData migration needed).
  3. `LoggingStore` — in `pushUpcomingStateToDevice()`, if
     `upcomingChainsEnabled && state.isInverseChains`, send
     `-upcomingChainsLb` as the chains payload instead of the
     positive value.
  4. `ExerciseDetailView` — added a toggle (``Toggle`` + label
     "Inverse chains") that appears below the chains lb stepper
     when `upcomingChainsEnabled == true`. Binds to
     `logging.upcomingInverseChains` (new `@Published Bool = false`
     on `LoggingStore`, cleared on `endSession()`).
  5. Full handoff docs updated with all decisions from the
     2026-05-03 Perplexity session.
- **Verification:** Static code review only (no Mac). No new unit
  tests added — the chains split math is simple division + round;
  the inverse-chains path is a sign flip. Will add tests when
  Session Recorder lands (P2).
- **Risks:**
  - `isInverseChains` is a local UI flag only; there is no firmware
    telemetry confirming the device received an inverse command. If
    the firmware ignores negative chains values, the behavior will
    be silent. Need on-device verification.
  - Combined-mode chains split rounds DOWN (e.g. 5 lb chain → 2 lb
    per side, not 3/2). Acceptable since combined requires even
    weights.
- **Next step:** Implement Session Recorder (P2). Do NOT ship to
  TestFlight until user says so.
- **Cost:** lite. Four targeted file edits + docs update.
