# Context Ledger

Append-only rolling context summaries for Voltra Brain / Claude
sessions. Prevents large one-time transcript backfills. Every 10
turns, or sooner if context health is degrading / dangerous, append a
summary here.

Authoritative sources remain:

- `AGENTS.md`
- `docs/handoff/00_START_HERE.md`
- `docs/handoff/SESSION_RECORDER_SPEC.md`
- `docs/handoff/CONVERSATION_LOG.md`
- `docs/WORK_LOG.md`

## Entry format

```
## YYYY-MM-DD HH:MM UTC — entry N — <one-line headline>

- **Branch / head:** <branch> @ <short SHA>
- **Active goal:** <one line>
- **Decisions since last summary:**
  - <decision>
- **Files changed or planned:**
  - <path> (status)
- **Commands run / awaiting approval:**
  - <command or pending approval>
- **Blockers / risks:**
  - <blocker>
- **Next exact action:**
  - <step>
- **Context health:** good | degrading | dangerously low
```

## Ledger entries

## 2026-05-02 17:55 UTC — entry 1 — B74-F11 Commit 2 ready to land

- **Branch / head:** `feat/b77-session-recorder` @ `0903d2b` (about
  to add Commit 2).
- **Active goal:** B74-F11 Session Recorder Commit 2 — root overlay +
  viewer + share + screen tags.
- **Decisions since last summary:**
  - Triple-tap on the build-badge chip declared BEFORE the existing
    single-tap so SwiftUI's gesture disambiguation prefers it; single
    tap still cycles the debug grid with a ~250 ms delay.
  - Added `CaseIterable` to `RecorderCategory` (Commit 1 file edit) so
    the viewer's filter chips can iterate categories. Single-line,
    backwards-compatible.
  - Recorder dot bottom padding set to 36 pt so it does not collide
    with the existing build-badge chip in the same bottom-trailing
    safe area.
  - `SessionRecorderViewer.prepareShare()` writes both `.txt` and
    `.json` to the temp dir on viewer open so `ShareLink` is enabled
    immediately; reload button regenerates.
- **Files changed or planned:**
  - NEW: `VoltraLive/Recorder/SessionRecorderToggle.swift`,
    `VoltraLive/Recorder/SessionRecorderViewer.swift`.
  - EDIT: `VoltraLive/VoltraLiveApp.swift` (root injection + overlay
    + scenePhase persist), `VoltraLive/Views/BuildBadgeOverlay.swift`
    (triple-tap unlock), `VoltraLive/Recorder/RecorderEvent.swift`
    (`CaseIterable`).
  - EDIT (13 screens, 1 line each): `LoggingHomeView`, `LiveCaptureView`,
    `LiveCaptureViewV2`, `LiveCaptureContainer`, `ConnectView`,
    `DebugView`, `DashboardView`, `ExerciseDetailView`,
    `ExerciseStartView`, `ExercisePickerView`, `SetLogView`,
    `ExportSheet`, `UnifiedConnectSheet`.
  - DOCS: `docs/WORK_LOG.md` (entry pending), `docs/handoff/00_START_HERE.md`
    (state update pending), `docs/handoff/CONVERSATION_LOG.md`
    (CaseIterable note pending), this file.
- **Commands run / awaiting approval:**
  - User pre-approved `git add` of named paths and the Commit 2 commit.
  - `VoltraLiveApp.swift` and `BuildBadgeOverlay.swift` edits were
    explicitly approved one at a time.
- **Blockers / risks:**
  - Cannot run `xcodebuild` (Windows host); compile + UI exercise
    deferred to CI / TestFlight.
  - SwiftUI single-tap delay introduced by triple-tap disambiguation
    needs QA verification on device.
- **Next exact action:** Stage 18 source/doc files (no `.claude/`,
  no `git add -A`), commit Commit 2 with bot identity, then proceed to
  Commit 3 (instrumentation + loud guards).
- **Context health:** good

## 2026-05-02 18:30 UTC — entry 2 — B74-F11 Commit 3 ready to land

- **Branch / head:** `feat/b77-session-recorder` @ `2ee81be` (about
  to add Commit 3).
- **Active goal:** B74-F11 Session Recorder Commit 3 — additive BLE
  + HK instrumentation, loud-guard sweep, ActionScope wrapping for
  user actions, all required doc updates.
- **Decisions since last summary:**
  - Pause gates 1–6 (BLE manager, writer, MDM, HK, guard sweep,
    VoltraLiveApp lifecycle extension) all individually approved.
  - Approved 9 user-visible loud-guard conversions; left 6 internal
    invariants (programmer-facing delta clamp, onAppear /
    onChange observers, attach/writer-init invariant, two
    VoltraWriter cooperative-cancellation guards) silent per spec
    wording.
  - For ActionScope wrapping, chose the smaller-diff approach:
    wrap function bodies via `SessionRecorder.shared.action(...)`
    helper but DO NOT re-indent the inner body. Swift tolerates the
    misindentation; the diff stays surgical.
  - V1 (`LiveCaptureView`) `sendLoad`/`sendUnload` were wrapped for
    parity with V2 even though V1 is the rollback artifact —
    cheap, small functions.
  - Layered `ble.write.tx` events from VoltraWriter (intent) +
    VoltraBLEManager (bytes) are by design; both stay.
- **Files changed or planned:**
  - EDIT (Swift, additive): `VoltraBLEManager.swift` (14 emits),
    `VoltraWriter.swift` (2 emits),
    `Dual/MultiDeviceManager.swift` (5 groups),
    `Health/HealthKitStore.swift` (6 groups),
    `VoltraLiveApp.swift` (lifecycle events on scenePhase),
    `LoggingHomeView.swift` (action wrap × 2 + 2 loud guards),
    `LiveCaptureViewV2.swift` (action wrap × 2 + 4 loud guards),
    `LiveCaptureView.swift` (action wrap × 2 + 3 loud guards).
  - DOCS: `07_FILE_MAP.md` (PLACEHOLDER → EXISTS),
    `03_CURRENT_FEATURE_SPEC.md` (§10 added),
    `09_NEXT_AGENT_PROMPT.md` (status appended),
    `00_START_HERE.md` (Commit 3 done line),
    `CONVERSATION_LOG.md` (Commit 3 entry),
    this file, `WORK_LOG.md`.
- **Commands run / awaiting approval:**
  - User pre-approved staging + commit + push + PR open. PR uses
    spec-required description.
- **Blockers / risks:**
  - Cannot run `xcodebuild` on Windows; compile + tests deferred to
    CI.
  - 10k buffer overflow at high BLE rates is by design but will
    surprise users debugging long sessions.
  - Triple-tap disambiguation delay on the build-badge chip needs
    on-device QA verification.
- **Next exact action:** Stage 14 source/doc files (no `.claude/`,
  no `git add -A`), commit Commit 3 with bot identity, push branch,
  open PR against `feat/ui-v4-2-claude` with spec-required
  description.
- **Context health:** good
