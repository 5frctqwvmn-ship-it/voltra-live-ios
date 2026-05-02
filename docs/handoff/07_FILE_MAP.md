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

## B74-F11 — Session Recorder (PLACEHOLDER)

Spec: [`SESSION_RECORDER_SPEC.md`](SESSION_RECORDER_SPEC.md). ADR:
[`04_DECISIONS_AND_CONSTRAINTS.md`](04_DECISIONS_AND_CONSTRAINTS.md)
V4-D25. Bug-queue entry:
[`B74_BUG_QUEUE.md`](B74_BUG_QUEUE.md) B74-F11.

**Status:** SPEC ONLY in this commit. All paths below are
`PLACEHOLDER` and will be created in the implementation PR.

### Source

| Path | Status | Role |
|---|---|---|
| `VoltraLive/Recorder/SessionRecorder.swift` | PLACEHOLDER | Single shared `ObservableObject`. Owns `isRecording`, `sessionId`, `start`/`end`, FIFO ring buffer, `ActionScope` task-local. Injected at app root via `.environmentObject`. |
| `VoltraLive/Recorder/RecorderEvent.swift` | PLACEHOLDER | `RecorderEvent: Codable, Identifiable` and the `Value`, `ErrorRecord`, `BLESubrecord` types described in the spec's Event Schema. |
| `VoltraLive/Recorder/RecorderBuffer.swift` | PLACEHOLDER | Thread-safe 10,000-event FIFO ring buffer (serial queue or `actor`). |
| `VoltraLive/Recorder/RecorderRedactor.swift` | PLACEHOLDER | PII rules per the spec's Redaction section. Default-redact path + explicit `unsafeRaw` API. |
| `VoltraLive/Recorder/RecorderExporter.swift` | PLACEHOLDER | `.txt` AI-readable report + `.json` full structured export. Writes nothing to disk; output is data passed to `ShareLink`. |
| `VoltraLive/Recorder/ActionScope.swift` | PLACEHOLDER | Task-local `UUID` plumbing. UI actions mint a new `actionId` and downstream events auto-inherit it. |
| `VoltraLive/Recorder/SessionRecorderToggle.swift` | PLACEHOLDER | The 24×24 pt root-overlay dot. Tap = toggle, long-press = open viewer, red 1 Hz pulse via `TimelineView(.animation)` while armed. |
| `VoltraLive/Recorder/SessionRecorderViewer.swift` | PLACEHOLDER | Long-press sheet. Renders the in-memory timeline + share affordance. |
| `VoltraLive/Recorder/View+RecorderScreen.swift` | PLACEHOLDER | `.recorderScreen("ScreenName")` modifier wrapping `.onAppear` / `.onDisappear` to emit `nav.screenAppear` / `nav.screenDisappear`. |

### Mounts (existing files touched in implementation PR)

| Path | Status | Role |
|---|---|---|
| `VoltraLive/VoltraLiveApp.swift` | EXISTS | Add `.environmentObject(SessionRecorder.shared)` and `.overlay(alignment: .bottomTrailing) { SessionRecorderToggle() }` at app root. No other change. |
| Build-badge chip view (file TBD by implementation agent) | EXISTS | Add a triple-tap gesture that flips `UserDefaults.standard.set(true, forKey: "VOLTRARecorderUnlocked")`. Visual chrome unchanged. |

### Persistence target

| Path | Status | Role |
|---|---|---|
| `Application Support/SessionRecorder/last_session.json` | RUNTIME | Single JSON file written on app background / kill, read on init. **No** other disk writes anywhere in this feature. |

### Tests

| Path | Status | Role |
|---|---|---|
| `VoltraLiveTests/RecorderBufferTests.swift` | PLACEHOLDER | Wrap behavior at 10,000 events; thread-safety under concurrent writers. |
| `VoltraLiveTests/RecorderRedactorTests.swift` | PLACEHOLDER | Positive / negative cases for every PII rule in the spec; `unsafeRaw` opt-in passes through unchanged. |
| `VoltraLiveTests/RecorderExporterTests.swift` | PLACEHOLDER | `.txt` + `.json` round-trip; schema-version invariant; non-empty outputs. |
| `VoltraLiveTests/ActionScopeTests.swift` | PLACEHOLDER | Task-local propagation across `Task { }` boundaries; nested scopes; ambient-event nil case. |

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
