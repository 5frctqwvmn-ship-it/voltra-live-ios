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

---

## CHECKPOINT — 2026-05-04 03:15 UTC — Perplexity Computer session

- **Branch:** `feat/ui-v4-2-claude`
- **HEAD:** `ad3c11b`
- **Working tree:** CLEAN
- **Version/build in repo:** 0.4.52 / build 80
- **Last shipped TestFlight:** v0.4.52-build80 (tag `v0.4.52-build80` → `51908f2`)
- **HEAD is N commits AHEAD of shipped tag:** 2 commits ahead
  (`9788d49` focusedBle fix + `ad3c11b` RC-01)

---

### What happened this session (in order)

1. **KI-20 initial visual bridge fix** (`08a8b7c`)
   Added `@Published deviceOriginatedBaseWeightUpdate` to
   `VoltraBLEManager`. `LiveCaptureViewV2` observes it via
   `.onChange` + `.onAppear` reconciliation. Recorder emits
   `ui.deviceBaseWeightApplied`. Shipped in build 80.

2. **KI-20 event-based patch** (`a46d45f`)
   Added `deviceOriginatedBaseWeightUpdateID` monotonic counter so
   repeated same-lb events still fire onChange. Shipped in build 80.

3. **Build 80 shipped** (`51908f2` tag `v0.4.52-build80`)
   TestFlight release.yml run 25292365029 — SUCCESS.
   Delivery UUID: `1d4a639d-542a-4a3b-93ec-d640459da0cd`.

4. **A1 hardware test on build 80 — FAILED visual, telemetry PASSED**
   Session `51674E4E-CBF6-4814-9AED-185826D053E2`.
   `device.state.change source=deviceUnsolicited to=20/30/35` present.
   `ui.deviceBaseWeightApplied` MISSING.
   Root cause discovered via read-only audit: `focusedBle` returned the
   standalone `ble` manager when only MDM left was connected
   (`bothVoltrasConnected = false`). `ble` never receives MDM BLE
   notifications. `deviceOriginatedBaseWeightUpdateID` on `ble` was
   always 0.

5. **KI-20 focusedBle topology fix** (`9788d49`)
   Replaced `if !bothVoltrasConnected { return ble }` with topology
   switch on `(mdm.left.connectionState.isConnected, mdm.right…)`.
   Routes to `mdm.left` / `mdm.right` / `focusedSlot` / `ble` by
   connection state only — no peripheral names used.
   CI run 25293501073 — SUCCESS. NOT yet in any TestFlight build.

6. **RC-01/SC-01 coaching card + Smart Coach** (`ad3c11b`)
   16 new files. Feature-flagged OFF by default
   (`FeatureFlags.coachingCardEnabled = false`).
   Zero visible change in current TestFlight builds.
   See `docs/specs/RC-01_COACHING_CARD.md` for full spec.

---

### KI-20 current status

**OPEN — pending hardware retest on build 81.**

The topology fix (`9788d49`) has never been in a shipped TestFlight
build. Build 81 must be shipped and retested with:
- Set app to 20 lb.
- Change physical VOLTRA dial to 15 lb.
- Expected: tile updates to 15 lb.
- Expected logs: `device.state.change source=deviceUnsolicited to=15`
  + `ui.deviceBaseWeightApplied to=15`.

Do NOT mark KI-20 closed until MJ confirms.

---

### What is NOT yet done (next agent must do)

1. **Bump build 81 + ship TestFlight** (project.yml exception required,
   same approval as build 80 — lines 65+93 only: `80` → `81`).
   Tag: `v0.4.52-build81`.
   Commit message: `chore(release): bump to 0.4.52 / build 81 — KI-20 topology fix + RC-01 scaffold`

2. **Hardware retest A1** — physical VOLTRA 20→15 lb.
   Confirm tile updates. Confirm `ui.deviceBaseWeightApplied` log present.

3. **Close KI-20** in `06_KNOWN_ISSUES.md` only after A1 passes.

4. **RC-01 compile verification** — build 81 CI is the first compile
   check. If CI fails, the failure is most likely in `LiveCaptureViewV2`
   (`forceChartCard` panel switch uses `AnyView` type erasure). Check
   that first.

5. **Enable coaching card for build 82** (`coachingCardEnabled = true`)
   only after KI-20 passes and coaching behavior has been reviewed on
   device.

6. **CoachingEngineTests** — placeholder only. Must be filled before
   coaching is enabled in any TestFlight build.

---

### Active open issues

| ID | Status | Summary |
|---|---|---|
| KI-20 | OPEN — pending retest | Machine-side weight tile not updating. Fix in `9788d49`, not yet shipped. |
| RC-01 | IMPLEMENTED — flagged off | Coaching card. Enable after KI-20 passes. |
| SC-01 | IMPLEMENTED — flagged off | Smart Coach engine. Same gate as RC-01. |

---

### Sacred files (never touch without explicit user approval)

- `VoltraLive/Protocol/VoltraProtocol.swift`
- `VoltraLive/Protocol/TelemetryExtractor.swift`
- `VoltraLive/Protocol/PacketParser.swift`
- `VoltraLive/Protocol/FrameAssembler.swift`
- `.github/workflows/build.yml`
- `project.yml` (except build-number lines 65+93 during releases,
  with explicit per-release user approval)

---

### Key file locations

| Topic | File |
|---|---|
| Spec: session recorder | `docs/handoff/SESSION_RECORDER_SPEC.md` |
| Spec: coaching card | `docs/specs/RC-01_COACHING_CARD.md` |
| Feature flags | `VoltraLive/FeatureFlags.swift` |
| KI-20 bridge | `VoltraLive/BLE/VoltraBLEManager.swift` (lines 69–80, 300–310) |
| focusedBle topology fix | `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` (lines 1437–1451) |
| Coaching engine | `VoltraLive/Coaching/Services/CoachingEngine.swift` |
| Snapshot adapter | `VoltraLive/Coaching/Services/SetSnapshotBuilder.swift` |
| Historical fetch | `VoltraLive/Logging/Persistence/LoggingStore.swift` (`allExerciseInstances(for:)`) |

---

### Context health: DEGRADING → resetting via this checkpoint
