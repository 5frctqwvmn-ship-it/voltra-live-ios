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
│       ├── LiveCaptureViewV2.swift     V2 — design-handoff render port (b55)
│       └── V2/                         V2 component subviews (b55)
│           ├── TopBannerV2.swift            phase strip + optional rest row
│           ├── DropSetBannerV2.swift        warn-tinted banner above WEIGHT
│           ├── DropRowV2.swift              DROP row inside WEIGHT card
│           ├── ForceChartV2.swift           sparse-idle / empty-rest / active polyline
│           └── DropSetConfigureSheet.swift  tap-to-configure FROM/TO/STEP
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

## LiveCapture V1/V2 split (b54 gate, b55 V2 rewrite)

`LiveCaptureContainer` is the entry point from the rest of the app.
It reads `@AppStorage("liveCaptureUIVersion")` (values: `"v1"`,
`"v2"`, empty = first launch → picker). It renders V2 only when
**both** conditions hold:

1. Exactly one Voltra is paired.
2. `mdm.supersetChain.isEmpty` (no chain entries).

Any other state — 2 Voltras paired, Combined, Superset, ≥1 chain
entry — falls through to V1 regardless of stored preference. V1 is
the full feature surface; V2 is intentionally narrower.

**b55 V2 rewrite.** The b54 V2 was a 2x2 tile grid (REPS / PHASE
/ FORCE / REST + HR/KCAL pills + CompareStrip). It was discarded
in b55 because it didn't match the design handoff. The new V2 is a
port of `voltra-v2-preview/index.html` (the user-signed-off render)
and maps to `screenshots/A1-states.png` + `A1-drop2.png`. Layout:

- **Header.** End ← button + connection pill + "Bench Press ·
  Set 2" + HR / KCAL pulse pills.
- **Top banner.** Always-visible phase strip (PULL teal full /
  RETURN orange full / IDLE under-rest dim half-fill / IDLE
  over-rest WARN orange full); optional rest row beneath with
  1px hairline divider when `restElapsedSeconds > 0`.
- **DROP-SET banner.** Visible only when `manualDropSequence` is
  armed (V2-only manual drop list, distinct from V1 timer-fired
  cascade). Sits between header and WEIGHT card.
- **WEIGHT card.** WEIGHT label + LOADED chip, big mono number,
  ±5 / ±1 stepper pair, embedded DROP row when armed.
- **Mod tile row.** ECC / CHAIN / INV / DROP, 4-up grid. DROP
  tile is tap-to-configure (opens `DropSetConfigureSheet`).
- **Small tiles.** REPS, TOTAL VOLUME.
- **Force chart.** `ForceChartV2` — ACTIVE polyline / RESTING
  empty / IDLE-NO-DATA sparse 5-sample up-tick.

Uses VoltraTheme tokens added in b54 plus the existing
`pull` / `returnPhase` / `warn` / `transition` / `idle` / `danger`
set. **Any V2 change must re-read the spec verbatim before coding**
— see `00_START_HERE.md` external-spec discipline. The web preview
at `voltra-v2-preview/index.html` is the source of truth; do not
rebuild it from screenshots without re-rendering and getting a new
sign-off.

**V2-only `LoggingStore` state (b55).**
`manualDropSequence: [Double]?` (nil when no drop armed; descending
step list otherwise) and `manualDropIndex: Int = 0`. Cleared on
`endSession()` and `cancelDropSet()`. Distinct from
`dropChainPlannedLb` which is the V1 timer-fired cascade.

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
