# 07 — FILE_MAP

> Authored 2026-05-02 to satisfy the Karpathy `07_FILE_MAP` wiki role
> flagged as "(not yet authored) — author when next significant feature
> lands" in `00_START_HERE.md`. Initial scope is intentionally narrow:
> the `## Project layout` block in `AGENTS.md` (and `04_ARCHITECTURE.md`)
> remains the canonical, full-tree map. This file owns **per-feature
> placeholder entries** that need to be discoverable before the code
> they describe lands — starting with the Session Recorder (B74-F11).

## Conventions

- One section per feature. Sections sort by feature label
  (`B74-F11`, `B74-F8`, …) descending by recency, not strictly
  alphabetic.
- Each row records: file path, status (`PLACEHOLDER` / `EXISTS` /
  `DELETED`), one-line role, and the spec / ADR / commit that owns
  the file.
- `PLACEHOLDER` entries describe files the spec calls for that have
  not yet been created in code. They become `EXISTS` in the
  implementation PR that lands them, in the same commit as the file
  appears.
- This file is **not** append-only. Sections move from `PLACEHOLDER`
  to `EXISTS` in place; sections for completed features can be
  trimmed once the feature has shipped and been QA'd.

## B74-F11 — Session Recorder (EXISTS)

Spec: [`SESSION_RECORDER_SPEC.md`](SESSION_RECORDER_SPEC.md). ADR:
[`04_DECISIONS_AND_CONSTRAINTS.md`](04_DECISIONS_AND_CONSTRAINTS.md)
V4-D25. Bug-queue entry:
[`B74_BUG_QUEUE.md`](B74_BUG_QUEUE.md) B74-F11.

**Status:** IMPLEMENTED on `feat/b77-session-recorder` across three
commits (core engine, root overlay + viewer + tags, instrumentation +
loud guards). All source paths below are `EXISTS`.

### Source

| Path | Status | Role |
|---|---|---|
| `VoltraLive/Recorder/SessionRecorder.swift` | EXISTS | Single shared `ObservableObject`. Owns `isRecording`, `sessionId`, `start`/`end`, FIFO ring buffer, `ActionScope` task-local plumbing. Injected at app root via `.environmentObject`. `record(...)` is thread-safe (NSLock-protected mirror state + actor-backed buffer). `start()`/`stop()`/`toggle()`/`action()` are `@MainActor`. |
| `VoltraLive/Recorder/RecorderEvent.swift` | EXISTS | `RecorderEvent: Codable, Identifiable` plus `RecorderCategory` (`CaseIterable`), `RecorderValue` (single-value JSON encoding with `"hex:"` prefix), `RecorderErrorRecord`, `BLESubrecord`, `BLESubrecordKind`. |
| `VoltraLive/Recorder/RecorderBuffer.swift` | EXISTS | `actor RecorderBuffer` — 10,000-event FIFO ring buffer with O(1) wrap (head/size cursors). |
| `VoltraLive/Recorder/RecorderRedactor.swift` | EXISTS | Per-recorder peripheral-name → UUID map (NSLock-protected); free-text → `<redacted:len=N>`; `unsafeRaw` opt-in passthrough used only for `HKSource.name` and `HKSource.bundleIdentifier`. |
| `VoltraLive/Recorder/RecorderExporter.swift` | EXISTS | Pure builders: `.json` envelope (`schemaVersion=1`) and `.txt` AI-readable report (header + actionId-grouped timeline + errors/guards + BLE transcript). No disk I/O. |
| `VoltraLive/Recorder/ActionScope.swift` | EXISTS | `@TaskLocal currentActionId: UUID?`. Inherited by `Task { }` children automatically. |
| `VoltraLive/Recorder/SessionRecorderToggle.swift` | EXISTS | 24×24 pt root-overlay dot. Hidden until `VOLTRARecorderUnlocked`. Tap = toggle, long-press = viewer sheet, 1 Hz red pulse via `TimelineView(.animation)` while recording, faint `VoltraColor.textFaint` while idle. Sits with extra bottom padding so it does not collide with the build-badge chip. |
| `VoltraLive/Recorder/SessionRecorderViewer.swift` | EXISTS | Long-press sheet. Filter chips per category, event timeline (newest first), `ShareLink` exporting both `.txt` and `.json` payloads via temp files, reload button. |
| `VoltraLive/Recorder/View+RecorderScreen.swift` | EXISTS | `.recorderScreen("ScreenName")` modifier wrapping `.onAppear` / `.onDisappear`. Calls `SessionRecorder.shared` directly so SwiftUI previews don't crash. |

### Mounts (existing files touched in implementation PR)

| Path | Status | Role |
|---|---|---|
| `VoltraLive/VoltraLiveApp.swift` | EXISTS | `@StateObject SessionRecorder.shared`, `@Environment scenePhase`, `.environmentObject(recorder)`, root `.overlay(alignment: .bottomTrailing) { SessionRecorderToggle() }`, `scenePhase` observer emits `lifecycle.appBackground`/`lifecycle.appForeground` and calls `recorder.persist()` on background/inactive. |
| `VoltraLive/Views/BuildBadgeOverlay.swift` | EXISTS | Triple-tap gesture (declared before existing single-tap so disambiguation prefers it) flips `UserDefaults["VOLTRARecorderUnlocked"] = true`. Existing single-tap grid cycle preserved. |

### Screen tags (`.recorderScreen("Name")`)

13 top-level screens tagged: `LoggingHomeView`, `LiveCaptureView`,
`LiveCaptureViewV2`, `LiveCaptureContainer`, `ConnectView`,
`DashboardView`, `DebugView`, `ExerciseDetailView`,
`ExerciseStartView`, `ExercisePickerView`, `SetLogView`,
`ExportSheet`, `UnifiedConnectSheet`.

### Instrumentation sites (Commit 3)

| File | Recorder calls |
|---|---|
| `VoltraLive/BLE/VoltraBLEManager.swift` | 14 emits across `ble.discovery` / `ble.connect` / `ble.disconnect` / `ble.write.tx` / `ble.write.ack` / `ble.notify.rx` / `ble.error`. |
| `VoltraLive/BLE/VoltraWriter.swift` | 2 emits: writer-level `ble.write.tx` with `label` + `cmd` metadata, and `ble.error` on payload-build failure. |
| `VoltraLive/BLE/Dual/MultiDeviceManager.swift` | 5 emit-site groups across `ble.connect` / `ble.disconnect` / `state.modeChange` / `ble.error` / `async.taskStart`/`.taskEnd`/`.taskError` (reconnect lifecycle). |
| `VoltraLive/Health/HealthKitStore.swift` | 6 emit groups: `state.flagChange` for auth attempt + result, `lifecycle.healthkit.start`/`.stop`, `state.flagChange` per HR/kcal sample arrival with `HKSource.name` + `bundleIdentifier`. |

### Persistence target

| Path | Status | Role |
|---|---|---|
| `Application Support/SessionRecorder/last_session.json` | RUNTIME | Single JSON file written on app background / kill via the scenePhase observer in `VoltraLiveApp.swift`. **No** other disk writes anywhere in this feature. |

### Tests

| Path | Status | Role |
|---|---|---|
| `VoltraLiveTests/RecorderBufferTests.swift` | EXISTS | Wrap behavior at small + 10,000 cap; thread-safety under concurrent writers; clear + reuse. |
| `VoltraLiveTests/RecorderRedactorTests.swift` | EXISTS | Stable peripheral mapping; per-instance independence; free-text length-only; `unsafeRaw` passthrough; concurrent lookups. |
| `VoltraLiveTests/RecorderExporterTests.swift` | EXISTS | JSON round-trip; `schemaVersion` invariant; hex `"hex:"` prefix round-trip; `.txt` header + actionId grouping + ambient section + guards + BLE transcript. |
| `VoltraLiveTests/ActionScopeTests.swift` | EXISTS | Nil ambient; nested scope shadowing; `Task { }` inheritance; async chain propagation. |

### Anti-paths (must NOT be created or modified)

- `VoltraLive/Info.plist` — no recorder-related plist entries.
- `project.yml` — no scheme / target / config changes.
- `*.entitlements` — no entitlement changes.
- `.github/workflows/release.yml` / `.github/workflows/build.yml` — no
  workflow changes.
- `VoltraLive/Protocol/*` — sacred. The recorder reads from BLE
  chokepoints; it does not touch wire format.
- Any new server / network surface — explicitly forbidden by the spec.

## How to extend this file

1. When a new feature lands a spec PR, add a section with the same
   shape: spec / ADR / queue cross-refs at the top, then `Source`,
   `Mounts`, `Tests`, and (if applicable) `Anti-paths` tables.
2. When the implementation PR lands, flip `PLACEHOLDER` rows to
   `EXISTS` in the same commit as the file is created.
3. When a feature has shipped and passed QA in `QA_LOG.md`, the
   feature's section may be trimmed to a one-line pointer at the
   `EXISTS` table in `04_ARCHITECTURE.md` or `AGENTS.md`'s project
   layout block — whichever owns the file long-term.

---

## RC-01 / SC-01 — Smart Coach Coaching Card (2026-05-04)

| File | Status | Notes |
|---|---|---|
| `VoltraLive/FeatureFlags.swift` | EXISTS | `coachingCardEnabled` + `smartCoachEnabled` computed from `UserDefaults("VOLTRASmartCoachUnlocked")`. `aggressiveRecommendationsEnabled` static false. |
| `VoltraLive/Views/BuildBadgeOverlay.swift` | EXISTS (UPDATED) | 4-tap gesture added before 3-tap + 1-tap. Toggles `smartCoachUnlocked` via `@AppStorage`. |
| `VoltraLive/Coaching/CoachingConstants.swift` | EXISTS | Debounce (1.5 s), transition (0.25 s), fatigue thresholds (15%/30%), weight caps (+25%/+15%), rounding (5 lb). |
| `VoltraLive/Coaching/Models/SetPerformanceSnapshot.swift` | EXISTS | Immutable value type for one completed set. per-rep force nil until Telemetry v2. |
| `VoltraLive/Coaching/Models/ExerciseSessionCursor.swift` | EXISTS | Current session cursor (nextSetIndex, completedSetsToday). |
| `VoltraLive/Coaching/Models/HistoricalSetMatch.swift` | EXISTS | Prior session lookup result. |
| `VoltraLive/Coaching/Models/CoachingRecommendation.swift` | EXISTS | Engine output (headline, historyLine, deltaLine, reasonLine, weights, fatigueGate). |
| `VoltraLive/Coaching/Services/HistoricalWorkoutMatcher.swift` | EXISTS | Groups by workoutSessionID. Excludes current session. |
| `VoltraLive/Coaching/Services/CoachingEngine.swift` | EXISTS | 7 rules, 5 guardrails, fully explainable. No BLE writes. |
| `VoltraLive/Coaching/Services/SetSnapshotBuilder.swift` | EXISTS | LoggedSet → SetPerformanceSnapshot adapter. bestRepForceLb nil until per-rep telemetry. |
| `VoltraLive/Coaching/Views/CoachingCardView.swift` | EXISTS | Rest-state card. minHeight = cardMinHeight. |
| `VoltraLive/Coaching/Views/CoachingCardButtonRow.swift` | EXISTS | Load/Push/Last/Repeat buttons. All route through adjustWeight(delta:). |
| `VoltraLive/Coaching/Views/FatigueIndicatorView.swift` | EXISTS | 12pt colored dot (green/yellow/red/gray). |
| `VoltraLiveTests/CoachingEngineTests.swift` | EXISTS (placeholder) | Placeholder — fill before enabling coaching in TestFlight. |
