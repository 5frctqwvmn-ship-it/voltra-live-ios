# 04 — Architecture

High-level map of how the app is laid out and how data flows. For wire
format details see `05_BLE_AND_PROTOCOL.md`. For HealthKit see `06_HEALTHKIT.md`.

## Module map

```
VoltraLive/
├── Protocol/                      SACRED — wire format, do not modify
│   ├── VoltraProtocol.swift       Service UUIDs, BOOTSTRAP_WRITES (9 of them)
│   ├── TelemetryExtractor.swift   0xAA decode → telemetry struct
│   ├── PacketParser.swift         Frame parser
│   └── FrameAssembler.swift       Stream defragmenter
│
├── BLE/
│   ├── VoltraBLEManager.swift     Single-peripheral connect/discover
│   └── VoltraWriter.swift         Diff-based control writes (weight, ecc, chains, mode)
│
├── Health/
│   └── HealthKitStore.swift       HR + active calories (BUG: snapshot only, see 06)
│
├── Session/
│   ├── DropBoundary.swift         Drop-set detection (BUG: anchoring regression)
│   └── ...                        Set boundary heuristics, rest tick
│
├── Logging/
│   ├── Persistence/
│   │   └── LoggingStore.swift     SwiftData store, pulleyMode/pulleyMultiplier
│   ├── Analytics/
│   │   └── SetSuggestionEngine.swift   anchorLb (intended drop-set anchor)
│   └── Views/
│       └── LiveCaptureView.swift  Live tiles + Pulley UI (lines ~820–850)
│
├── Views/
│   └── ConnectView.swift          Single Connect button (build-30: replace with 3 buttons)
│
├── Bridge/
│   └── PhoneWatchBridge.swift     WatchTelemetryMessage (Watch deferred to v1.2)
│
├── Assets.xcassets/               App icon (3 nested teal triangles, #00d4aa on #0a0e0c)
├── Info.plist
└── VoltraLiveApp.swift            App entry, ModelContainer setup (build 29 fix lives here)
```

## SwiftData store

- Container URL: `Application Support/voltra-live-v2.store` (build 29+).
- Configuration: explicit `ModelConfiguration("voltra-live-v2", schema:, url:, allowsSave: true, cloudKitDatabase: .none)`.
- Old store at the legacy URL is **left on disk** untouched. A future
  importer can read from it; for now it's effectively orphaned.
- In-memory fallback if the new URL fails to open.

## Data flow during a live session

```
VOLTRA hardware (BLE)
    │
    ▼
FrameAssembler ──► PacketParser ──► TelemetryExtractor
    │                                   │
    │                                   ▼
    │                          telemetry stream (force, reps, phase, ROM, velocity, power)
    │                                   │
    │                                   ▼
    │                          DropBoundary  ──► set-complete events
    │                                   │
    │                                   ▼
    │                          LoggingStore (SwiftData)
    │                                   │
    │                                   ▼
    │                          LiveCaptureView (tiles)
    │                                   ▲
    │                                   │
    └─────────────► HealthKitStore (HR, kcal) ──► same view tiles
```

Control writes flow the other direction: UI → `VoltraWriter` → BLE
characteristic write → device. See `05_BLE_AND_PROTOCOL.md#control-writes`.

## Build / CI

- `project.yml` is the single source of truth for Xcode config (XcodeGen).
- `xcodegen generate` is run by both CI workflows.
- See `09_RELEASE_AND_SIGNING.md` for the version-bump and tag dance.

## Watch companion (deferred)

`Bridge/PhoneWatchBridge.swift` and `WatchTelemetryMessage` are stubbed
for the deferred Watch app. They round-trip JSON over WatchConnectivity.
Both copies must stay in sync (identical raw `String` enum values) — see
`AGENTS.md` workflow rules.
