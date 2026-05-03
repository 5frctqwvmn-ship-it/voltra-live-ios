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

## LiveCapture V1/V2 split (b54 gate, b55 V2 rewrite, b56 V2 mods + V1 restore)

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
in b55 because it didn't match the design handoff. b55 ported
`voltra-v2-preview/index.html` (user-signed-off render).

**b56 V2 mods + rest timer + V1 restore.** b55 had three
problems the user flagged: (a) ECC / CHAIN / INV CHAIN tiles
weren't selectable (the `disabled(onTap == nil)` short-circuited
their taps); (b) V2 was missing the V1 below-the-chart
affordances (pulley chip, added-plates picker, logged-sets list,
Next-exercise / End-session); (c) the rest experience was a
static phase-strip flip rather than the timer the design called
for. b56 restructures V2 as:

- **Header.** End ← button + connection pill + "Bench Press ·
  Set N" + HR / KCAL pulse pills (unchanged from b55).
- **Phase strip OR `RestTimerBarV2`.** When `restElapsedSeconds
  == 0`, render a compact 4pt phase-color strip with phase label
  + SET N. When `restElapsedSeconds > 0`, swap in `RestTimerBarV2`
  — HSL 3-stop sweep `green(140°,70%,45%) → amber(40°,90%,50%) →
  red(0°,80%,50%)`, blink on overtime, header text flips to
  `REST · OVER` and the time label flips to `+MM:SS`.
- **WEIGHT card** (b56-redesigned). Tapping the big mono number
  toggles hardware LOAD/UNLOAD via `ble.sendLoad()` /
  `ble.sendUnload()` (or `mdm.load/unload` if any slot paired);
  number turns `VoltraColor.accent` (green) when `deviceLoaded`.
  Small "✓ LOADED" / "UNLOADED" pill on the label row mirrors
  it. ±5 / ±1 stepper pair on the right. Below the number:
  `NestedModRowV2`s for each ARMED mod (ECC / CHAIN / INV CHAIN
  / DROP, in that fixed order) — inactive mods are HIDDEN, not
  greyed-out. Below the nested rows: 4-up mod tile grid (ALL
  selectable per b56 bug fix). Below the tile grid:
  `ModStepperRowV2`s (−10 / −5 / +5 / +10 per engaged mod) —
  ECC clamps 5–400 lb, CHAIN/INV CHAIN clamp 0–300 lb, DROP
  step clamps to head-5.
- **Small tiles.** REPS, TOTAL VOLUME (unchanged from b55).
- **Force chart.** `ForceChartV2` with new `yAxisMaxLb`
  parameter. Parent computes `max(workingLb, eccEffective) ×
  1.3` (defensive floor 60 lb) and animates rescale on change.
- **`V1RestoreSection`.** Pulley chip + Added-plates picker (V1
  line 1561 `addedWeightSection` + 1648 `addWeightPicker` ported
  verbatim) + LOGGED SETS list (V1 line 1781 `loggedSetsSection`
  using the now file-internal `SwipeableSetRow`) + Bottom
  actions ("Next exercise" `NavigationLink` + "End session"
  button — V1 line 1935).

CHAIN and INV CHAIN are **mutually exclusive** — toggling one
while the other is active disables the other (you can't lighten
and add through the ROM at the same time).

DROP behavior is **finalize-driven** in V2: the DROP tile tap
arms a `manualDropSequence = [head, next]`; each subsequent tap
deepens the step by 5 lb (−5 → −10 → −15 → −20…); long-press
cancels (sets sequence to nil); when the user finalizes the set,
the next weight is pushed on the next set start. This is
distinct from V1's timer-fired `startDropSet` cascade, which
stays V1-only.

Uses VoltraTheme tokens added in b54 plus the existing
`pull` / `returnPhase` / `warn` / `transition` / `idle` / `danger`
set. **Any V2 change must re-read the spec verbatim before coding**
— see `00_START_HERE.md` external-spec discipline. The web
preview at `voltra-v2-preview/index.html` is the b55 source of
truth; the b56 spec lives in WORK_LOG b56 + the screenshot at
`/home/user/workspace/image.jpg`.

**V2-only `LoggingStore` state (b55 + b56).**
`manualDropSequence: [Double]?` (nil when no drop armed; head +
next pair otherwise) and `manualDropIndex: Int = 0`. b56 adds
`upcomingInverseLb: Double = 0` and `upcomingInverseEnabled:
Bool = false` for INV CHAIN. Cleared on `endSession()` and
`cancelDropSet()`. Distinct from `dropChainPlannedLb` which is
the V1 timer-fired cascade.

**INV CHAIN protocol mapping (b56).** `VoltraModifiers.inverse`
was already in the wire format. There is no separate
`VoltraWeights.inverseLb` field — the inverse weight is written
to `chainsLb` AND `inverse: true` is set, so the device
interprets the offset as thru-ROM lightening rather than
at-top heavying. CHAIN ↔ INV CHAIN sharing one weight slot is
why they're mutually exclusive at the UI layer.

**`SwipeableSetRow` access change (b56).** V1's
`SwipeableSetRow` was promoted from `private` to file-internal
so V2's `V1RestoreSection` can reuse it instead of duplicating
~250 lines. The view itself is unchanged.

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

## Telemetry v2 decoder (additive, post-b78)

The Telemetry Collector v2 / Authoritative Device State module
(spec in `03_CURRENT_FEATURE_SPEC.md`, ADR V4-D26 in
`04_DECISIONS_AND_CONSTRAINTS.md`) is **additive**. It lives in a new
module alongside the existing `VoltraLive/Protocol/` pipeline and
subscribes to the same byte stream `FrameAssembler` already exposes.
It does **not** replace, fork, or shadow any sacred file
(`VoltraProtocol.swift`, `TelemetryExtractor.swift`,
`PacketParser.swift`, `FrameAssembler.swift`,
`.github/workflows/build.yml`).

The legacy pipeline keeps emitting exactly what it emits today; the
v2 decoder layers richer typed events (`device.state.change`,
`load.state.change`, semantic rep markers, etc.) on top. Conflict
resolution between the two outputs is documented in the spec; neither
side is silenced. Hypothesis bytes (OQ-T1, OQ-T3 in
`10_OPEN_QUESTIONS.md`) are round-tripped raw and flagged as
hypothesis on the emitted event until hardware evidence promotes
them. The export schema advances 1 → 2 additively so existing
consumers keep working.

### Telemetry v2 UI bridge (post-A1 fix)

The full path from physical device button press to visible tile update:

```
BLE notify (device-side dial)
    │
    ▼
VoltraBLEManager.handleNotification → VoltraBLEFrameDecoder.decode
    │
    ▼
DeviceStateReducer.apply → DeviceState.baseWeightLb (updated)
    │  AND (when source == .deviceUnsolicited AND field == .baseWeight)
    ▼
VoltraBLEManager.deviceOriginatedBaseWeightUpdate (@Published)
    │
    ▼
LiveCaptureViewV2.focusedDeviceOriginatedBaseWeightUpdateValue
(SwiftUI .onChange observer OR .onAppear reconciliation)
    │
    ▼
LiveCaptureViewV2.applyDeviceOriginatedBase(_:)
    │  (guards: source == .deviceUnsolicited, 0≤lb≤500, != current)
    ▼
LoggingStore.pendingPlannedWeightLb + reanchorCascadeIfActive
    │  (also emits ui.deviceBaseWeightApplied recorder event)
    ▼
WeightCard tile renders: pendingPlannedWeightLb × pulleyMultiplier
```

App `+/-` taps bypass this path entirely (they write directly to
`pendingPlannedWeightLb` and then to the device). The
`deviceOriginatedBaseWeightUpdate` bridge is NOT set for
`appRequestConfirmed` echoes, so confirmation races cannot clobber
rapid user taps.

### First-slice files (post-b78, this commit)

```
VoltraLive/BLE/Decoder/
  VoltraDecodedEvent.swift     // Event + Source enums
  VoltraDecodeTable.swift      // Pattern table (data-driven)
  VoltraBLEFrameDecoder.swift  // decode(_:) + PendingWriteTracker
VoltraLive/BLE/State/
  DeviceState.swift            // DeviceState + reducer + ConfirmedValue<T>
VoltraLiveTests/
  VoltraBLEFrameDecoderTests.swift  // Golden + reducer + correlator
```

The decoder is invoked from `VoltraBLEManager.handleNotification(...)`
immediately AFTER the existing `ble.notify.rx` recorder hook and
BEFORE `parsePacket(...)`. The legacy pipeline (PacketParser →
TelemetryExtractor → mergeTelemetry) is unchanged — the decoder runs
in parallel and writes only to the new `@Published deviceState`.

Outbound app-issued param writes register with
`PendingWriteTracker` via the new `VoltraWriter.onOutboundParam`
callback, wired in both `WriterRouter` (single-device) and
`MultiDeviceManager` (per side). Confirmation source attribution:

- `appRequestConfirmed` — the next matching `(field, lb)` confirmation
  arrives within the 2 s window (configurable per `PendingWriteTracker`
  init).
- `deviceUnsolicited` — no matching pending entry. Most common cause:
  user pressed the +/- buttons on the machine itself.
- `unknownOrigin` — reserved; not emitted in this slice.

Unknown frames produce `.candidate(rawHex:prefix:)` events and are
currently dropped at the BLE manager. Sampled candidate-trace recorder
emission is a follow-up.

Pattern coverage today: **base weight only**
(`PARAM_BP_BASE_WEIGHT = 0x3E86`, uint16-LE pounds). Adding eccentric,
chains, mode, etc. is a one-row append to `VoltraDecodeTable.all`.

### UI bridge: `LiveCaptureViewV2` → `LoggingStore`

A single observer in `LiveCaptureViewV2` mirrors machine-originated
base-weight changes into the local planned weight that drives the
WEIGHT card. The bridge is intentionally minimal:

- **Source.** `focusedBle.deviceState.baseWeightLb` — the
  `ConfirmedValue<Int>` published by `VoltraBLEManager` on the
  currently focused unit (`focusedBle` already disambiguates
  single-Voltra vs. dual-Voltra Independent vs. Twin sessions; in
  Twin mode left is canonical because writes mirror).
- **Trigger.** `.onChange(of: focusedConfirmedBaseWeightValue)`
  where the keypath is `baseWeightLb?.value` (an `Int?`) so the
  observer is `Equatable`-stable. The full `ConfirmedValue` is
  read inside the handler so the source filter still applies.
- **Filter.** `confirmed.source == .deviceUnsolicited` only.
  `appRequestConfirmed` echoes are dropped — the local
  `pendingPlannedWeightLb` is already authoritative for app-issued
  edits, and we must not let a confirmation race clobber a
  follow-up `+/-` tap. `unknownOrigin` is reserved and currently
  unused.
- **Sink.** `LoggingStore.pendingPlannedWeightLb` (and
  `reanchorCascadeIfActive(toLb:)` so an in-progress drop-set
  cascade re-anchors). The WEIGHT card then renders normally
  through its existing `pendingPlannedWeightLb × pulleyMultiplier`
  formula — display path is unchanged.
- **Why not bind display directly to `deviceState`.** Driving the
  big number directly off `deviceState.baseWeightLb?.value` would
  introduce a perceptible lag on every `+/-` tap (write → device
  echo → decoder → reducer → publish). Mirroring into the
  existing local store keeps tap responsiveness while still
  letting machine-side dial moves win when nothing app-side is
  in flight.

This is the binding referenced in plan item 4 of the Telemetry v2
spec, and the resolution path for **KI-20** (machine-side weight
changes not reaching the app).
