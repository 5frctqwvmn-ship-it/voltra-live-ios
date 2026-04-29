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
│   ├── Routing/
│   │   └── WriterRouter.swift     Routes control writes by activeInstance.assignedVoltra (b53)
│   └── Views/
│       ├── LiveCaptureContainer.swift  V1/V2 gate by @AppStorage (b53/b54)
│       ├── LiveCaptureView.swift       V1 — full feature surface, all chain handling
│       └── LiveCaptureViewV2.swift     V2 — 1:1 port of design-system/ui-kit.html (b54)
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

## LiveCapture V1/V2 split (b54)

`LiveCaptureContainer` is the entry point from the rest of the app.
It reads `@AppStorage("liveCaptureUIVersion")` (values: `"v1"`,
`"v2"`, empty = first launch → picker). It renders V2 only when
**both** conditions hold:

1. Exactly one Voltra is paired.
2. `mdm.supersetChain.isEmpty` (no chain entries).

Any other state — 2 Voltras paired, Combined, Superset, ≥1 chain
entry — falls through to V1 regardless of stored preference. V1 is
the full feature surface; V2 is intentionally narrower.

V2 (`LiveCaptureViewV2.swift`) is a 1:1 port of
`design-system/ui-kit.html` from the `design-studio` branch (HEAD
`74d0d3b9` at b54 ship). Layout: header strip → 2×2 tile grid
(REPS / PHASE / FORCE / REST) → HR/KCAL pulse-dot pair →
CompareStripView → force chart card → plan + LOG SET CTA. Uses
VoltraTheme tokens added in b54: `pullWash`, `returnWash`, `fresh`,
`freshStale`. **Any V2 change must re-read the spec verbatim before
coding** — see `00_START_HERE.md` external-spec discipline.

All b53 chain features (per-instance `assignedVoltra` routing, 3-way
L/R/Both picker, header rewrite, SWAP-no-auto-LOAD) live in V1. V2
never sees them by construction.

## Routing source of truth (b53)

`WriterRouter` reads `LoggingStore.activeInstance.assignedVoltra` to
decide which Voltra (`"left"`, `"right"`, `"both"`, `nil`) backs the
next write. The instance is the routing source of truth. The chain
array is UI state only. See `08_SUPERSET.md` for the full picture.

## Build / CI

- `project.yml` is the single source of truth for Xcode config (XcodeGen).
- `xcodegen generate` is run by both CI workflows.
- See `09_RELEASE_AND_SIGNING.md` for the version-bump and tag dance.

## Watch companion (deferred)

`Bridge/PhoneWatchBridge.swift` and `WatchTelemetryMessage` are stubbed
for the deferred Watch app. They round-trip JSON over WatchConnectivity.
Both copies must stay in sync (identical raw `String` enum values) — see
`AGENTS.md` workflow rules.
