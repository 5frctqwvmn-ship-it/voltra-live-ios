# 03_CURRENT_FEATURE_SPEC

> **Active feature (post-b78).** Authoritative Device State +
> Telemetry Collector v2. Spec immediately below.
>
> **Historical (still in force for the live capture screen itself).**
> The V4 LiveCaptureView spec at b58 is preserved further down this
> file under "Historical: V4 LiveCapture spec (b58)" — it is still
> what the screen *does today*, and Telemetry v2 is additive on top
> of it.

---

# Authoritative Device State + Telemetry Collector v2

> Active feature spec. Targets the post-b78 cycle on
> `feat/ui-v4-2-claude`. Docs-first; **no Swift until the user says
> go.** Sacred protocol files
> (`VoltraLive/Protocol/VoltraProtocol.swift`,
> `TelemetryExtractor.swift`, `PacketParser.swift`,
> `FrameAssembler.swift`) are NOT modified by this feature — see
> `04_DECISIONS_AND_CONSTRAINTS.md` ADR **V4-D26**.

## Goal

Ship one coherent fix for two connected problems:

1. The app does not reliably know the machine's true live state.
2. The telemetry collector does not yet make session failures
   obvious, decodable, and easy to debug.

Feature area: **authoritative device state + session
observability**.

## Scope

- New `DeviceState` model that mirrors the live VOLTRA machine
  state (base weight, eccentric, concentric, chains, mode,
  inverse, load state, connection state, last update timestamp,
  last source).
- New shared frame-decoder abstraction that consumes the same
  raw BLE bytes today's `Protocol/` pipeline already parses, but
  emits a **semantic event stream** that drives both UI state
  and Session Recorder output.
- Recorder upgrade: semantic events, complete cause→effect
  chains, dedupe, compressed high-frequency stream frames,
  session summary, incident banner.
- Pending/confirmed write flow with timeout.
- Load/unload/cutout detection with stream-gap heuristics.
- BLE characteristic audit (nRF Connect / LightBlue) before
  decoder assumptions are finalized.

## Product principles

- **Device is source of truth.** Always.
- **App writes are requests, not truth.** Until confirmed by
  decoded device telemetry, an app-issued write is `pending`.
- A write is only considered `confirmed` when echoed back in a
  decoded device-state frame.
- App UI and Session Recorder consume the **same** parsed device
  events. There is one decoder. UI and recorder are two
  consumers of the same stream.
- Raw BLE hex MAY be preserved for debugging, but **semantic
  events are primary** in exports and in the UI binding path.
- Session exports must make incidents (load drop, cutout,
  unconfirmed write, stream gap) obvious on first read.

## Problems being fixed

1. App does not reliably reflect machine-side base-weight
   changes — user adjusts the dial on the machine and the app
   shows the stale number.
2. Eccentric / concentric / chains can drift between hardware
   and the app's in-memory model.
3. Load drop / unload / cutout mid-set is not surfaced to app
   state — the app keeps counting reps as if the cable were
   still loaded.
4. The Session Recorder shipped in b78 captures raw telemetry
   but lacks semantic decoded state changes, incident
   detection, compression of high-frequency stream frames,
   complete cause→effect chains, and session summaries.
5. Duplicate `ble.write.tx` events show up in recorder output.
6. The 1000-event cap fills too quickly in real live capture.
7. Demo-mode "not connected" guard logs as `ble.error` and
   appears before the write event — should become
   `ble.write.skipped` with clearer ordering.
8. Weight / ecc / conc / chains UI controls don't emit
   `ui.tap` / `actionId` instrumentation, breaking the
   cause→effect correlation chain.

## Architecture

Single BLE decode pipeline:

```
BLE notify.rx / write.ack / connection signals
        |
        v
  transport parser  (existing FrameAssembler / PacketParser)
        |
        v
  frame decoder    (NEW — additive, alongside existing TelemetryExtractor)
        |
        v
  semantic event stream
        |
        +--> DeviceState reducer  --> UI re-render
        |
        +--> Session Recorder append/export
```

The new decoder is **additive**. It sits next to the existing
Protocol/ pipeline and consumes the same input bytes. The
existing Protocol/ files are sacred (V4-D26).

## Core models

### DeviceState

Fields:

- `baseWeight` (lb)
- `eccentricWeight` (lb)
- `concentricWeight` (lb)
- `chainsWeight` (lb)
- `mode` (e.g. standard / chains / inverse / superset slot)
- `inverse` (bool)
- `loadState` (`LoadState`, see below)
- `connectionState` (idle / scanning / connecting / connected /
  disconnected)
- `lastUpdatedAt` (timestamp)
- `lastSource` (`DeviceUpdateSource`, see below)

Each machine-facing field also tracks a per-field status:
`confirmed`, `pending`, `stale`, `unknown`. "Stale" means the
field was confirmed at some point but the last device frame
hasn't refreshed it within a configurable window.

### LoadState

`idle` / `armed` / `loaded` / `unloaded` / `fault` / `unknown`.

### DeviceUpdateSource

`appRequestPending` / `appRequestConfirmed` /
`deviceUnsolicited` / `deviceStateFrame` / `inferredFromGap` /
`inferredFromStream`.

## Event model changes

New semantic recorder events:

- `device.state.change` — a field of `DeviceState` changed.
  Payload includes field name, old value, new value, source,
  status.
- `load.state.change` — OPTIONAL. If kept, must mirror
  `DeviceState.loadState` exactly. See open question on whether
  this should be a standalone event vs a field of
  `device.state.change`.
- `ble.stream.gap` — emitted when stream cadence violates the
  soft / hard thresholds.
- `incident.loadDropped` — high-priority incident, drives the
  in-app banner and the export summary.
- `write.confirmation.timeout` — a `pending` app write was not
  echoed back within the timeout window.
- `write.request.overridden` — device reported a value
  different from the value the app requested. Emitted when the
  decoded confirmation does not match the pending request.

## Decoder requirements

- One decoder. It feeds both `DeviceState` and the Session
  Recorder. UI and recorder must never read different decoder
  outputs.
- Raw hex preserved alongside semantic events for debugging.
- **Base-weight confirmations** appear in notify payloads
  with tails like `863e5f=95`, `863e14=20`, `863e0f=15`. These
  are **observed**, not sacred protocol — must be pinned by
  fixture before the decoder relies on them, and must be
  re-validated against `BLE characteristic audit` results.
- **`553404ac` status frames** include a byte that
  transitioned `0x02 → 0x03` around the load-cutout event
  observed in chat. Treat `0x03` as a **hypothesis / candidate**
  only until hardware-confirmed against multiple sessions.
  Do not promote `0x03` to a named constant in the decoder
  until validated.
- **`553a0470` stream frames** include a byte near
  `2b000100` vs `2b010100` that **may** represent phase /
  tension state. Hypothesis only. Same validation gate.
- Eccentric / concentric / chains byte positions are **unknown**
  pending hardware tests. The decoder must surface
  "received frame I cannot decode" rather than silently
  guessing.
- **Sacred files are NOT modified.** All decoding additions
  live in new files alongside `Protocol/` (e.g.
  `VoltraLive/Decode/SemanticDecoder.swift` — exact path TBD
  during implementation).

## Source-of-truth rules

- Device-confirmed value is canonical for every machine-facing
  field.
- App-requested value is canonical only for `appRequestPending`
  status. Once a confirmation arrives, the device value
  replaces it.
- The UI binds to `DeviceState`. The recorder appends
  semantic events derived from the same updates. The UI does
  not bind directly to BLE frames; the recorder does not
  bind directly to UI state.

## Conflict resolution

**Latest device-confirmed value wins.**

If the app requests `baseWeight = 80` but the device reports
`70`, canonical state becomes `70` and the recorder emits
`write.request.overridden` with payload `{requested: 80,
observed: 70}`. The UI updates to `70`.

## Load / unload behavior

- `loaded → unloaded`: pause rep detector, show in-app banner,
  stop assuming weight is stable, tag the in-progress set
  `interrupted=true reason=unloaded_mid_set`.
- `loaded → fault`: pause rep detector, surface fault, emit
  `set.aborted` event in the recorder.
- `unloaded → loaded`: do **not** auto-resume rep counting.
  Offer the user "continue set" or "start new set".
- `unknown`: grey live metrics (do not show stale numbers as if
  fresh). If still `unknown` after 2 s, treat as `unloaded`.

## Weight / mode sync requirements

- App must reflect machine-side base-weight changes without
  manual refresh, within the cadence of the next
  `device.state.change` after the user moves the dial.
- App must reflect machine-side eccentric / concentric / chains
  changes after the decoder has been validated for those byte
  positions on hardware. Until then, the UI greys those fields
  and emits `device.state.change(field=..., status=unknown)` so
  the recorder shows we saw the frame but couldn't decode it.
- Mode changes (chains on/off, inverse) propagate via the same
  semantic event path.

## Telemetry recorder improvements

- **De-dupe duplicate `ble.write.tx` events.** Same payload
  within a small window collapses to one event with a
  `coalescedCount` field.
- **Complete correlation chain** for every user action that
  touches the device:
  `ui.tap (actionId=X) → write.request → write.tx → write.ack
  → device.state.change → ui.commit`.
  All entries share the same `actionId` UUID via the existing
  `ActionScope` `@TaskLocal`.
- **Instrument weight / ecc / conc / chains controls** with
  `ui.tap` and an `actionId` so the chain begins at the user's
  finger.
- **Compress repeated identical high-frequency stream frames**
  in the human-readable `.txt` export. Show the first frame,
  then a single `… (×N over Tms)` line, then the next
  divergent frame. Preserve full fidelity in the JSON export.
- **Session summary** appended at the end of each export:
  - duration
  - total events
  - semantic events (count by category)
  - incidents
  - stream gaps (count, max duration)
  - load transitions
  - unconfirmed writes
  - last confirmed machine values for each field
- **Incident banner** in the recorder viewer when the session
  contains a `incident.loadDropped` or any `set.aborted`.

## Constants

- **Write confirmation timeout:** 750 ms. After this, the
  pending write becomes `write.confirmation.timeout` and the
  field reverts to its last `confirmed` value.
- **Stream gap soft threshold:** 500 ms during LiveCapture —
  emit `ble.stream.gap` and set `LoadState = unknown` unless a
  stronger signal exists.
- **Stream gap hard threshold:** 2000 ms — escalate to
  `unloaded` / `fault` candidate.
- **Recorder buffer strategy:** ring buffer, **5000 events
  minimum** (up from b78's 1000).
- **Retry:** one auto-retry for non-destructive scalar fields
  (e.g. `baseWeight`). **No auto-retry** for ambiguous or
  destructive ops.

## Export requirements

- `.txt` (AI-readable, human-readable): chronological semantic
  events with compressed stream frames. Includes session
  summary at the end. Includes incident banner at the top if
  any incident was recorded.
- `.json` (structured, full fidelity): every event, every raw
  hex frame, every actionId chain. Schema version bumped from
  the b78 `schemaVersion=1` to `schemaVersion=2` with backward
  compatibility for readers (additive fields only).
- Both exports retain the b78 redaction rules (peripheral
  name → UUID; free text → `<redacted:len=N>`; `unsafeRaw`
  opt-in only for `HKSource.name` / `bundleIdentifier`).

## UX requirements

- Live UI greys metrics whose `DeviceState` field is `unknown`
  or `stale`.
- Banner in `LiveCaptureViewV2` when `loadState` transitions to
  `unloaded` mid-set: "Load dropped — set marked interrupted."
- Banner in `LiveCaptureViewV2` when `loadState` transitions to
  `fault`: "Hardware fault detected — set aborted."
- After `unloaded → loaded`, present a two-button choice in
  place of the normal active-set chrome: "Continue this set" /
  "Start new set". Default tap-target: "Start new set" (safer).
- Recorder viewer shows the incident banner at the top of the
  timeline when present.
- All UI copy lives in one place (TBD during implementation —
  see open question on exact copy).

## BLE characteristic audit requirement

Before decoder assumptions are finalized, the user runs
**nRF Connect** or **LightBlue** against a paired Voltra and
documents:

- Every service UUID and every characteristic UUID under it.
- The properties bitmask for each characteristic
  (read/write/writeWithoutResponse/notify/indicate).
- The descriptors on each characteristic (CCCD presence in
  particular).
- Whether the iOS app currently subscribes to that
  characteristic.
- **Flag any notify-capable characteristic the app does NOT
  currently subscribe to.** Those are the most likely sources
  of the unsolicited machine-side updates the app is missing.

Results land in `05_BLE_AND_PROTOCOL.md` under "BLE
characteristic audit (post-b78)". The decoder must not
finalize byte-position assumptions before the audit is in.

## Migration notes

- The existing `SessionRecorder.shared` 10,000-event FIFO
  actor buffer (b77/b78) becomes a **5000-event ring buffer**
  in v2. Sessions running across the upgrade will lose the
  oldest events first; nothing on disk needs migrating because
  the buffer is in-memory.
- The b78 `Application Support/SessionRecorder/last_session.json`
  file uses `schemaVersion=1`. v2 writes `schemaVersion=2`.
  Readers must handle both. Older sessions on disk are read-
  only and the viewer surfaces them with a "v1 capture" tag.
- Existing UI bindings to in-memory `WriterState` /
  `MultiDeviceManager` / `LoggingStore` keep working. The new
  `DeviceState` is **introduced first as a read-only mirror**
  of decoded events, and the UI binding path migrates one
  field at a time (base weight first — see implementation
  order).

## Open hypotheses and constraints

- `0x03` in `553404ac` status frames means "load dropped /
  cutout" — hypothesis from a single observation. Needs
  multi-session corroboration.
- `2b010100` vs `2b000100` in `553a0470` stream frames is a
  phase / tension flag — hypothesis only.
- Eccentric / concentric / chains byte positions: unknown.
- There may be a notify-capable characteristic the app does
  not currently subscribe to that carries device-state
  updates. The BLE characteristic audit will tell us.
- All hypotheses above must be validated on hardware and
  pinned by fixture in `VoltraLiveTests/ProtocolGoldenTests.swift`
  (or a new sibling test file for the additive decoder)
  before being promoted to named constants.

## Acceptance criteria

- App reflects machine-side base-weight changes without manual
  refresh.
- App reflects machine-side eccentric / concentric / chains
  changes after decoder validation.
- App detects and reacts to unload / cutout mid-session per the
  Load / unload behavior section.
- Rep / session logic responds appropriately (set marked
  `interrupted=true` on unload mid-set; rep counting paused on
  `loaded → unloaded`; no auto-resume on `unloaded → loaded`).
- Recorder exports state transitions and incidents in plain
  language at the top of the `.txt` export.
- Duplicate `ble.write.tx` events removed from output.
- Real sessions fit without premature truncation under the new
  5000-event ring buffer.
- One shared parser powers both UI state and recorder output.
- `0x03` remains a candidate constant until validated, or is
  renamed only after hardware evidence.
- No sacred protocol file is modified by this feature.
- BLE characteristic audit results are recorded in
  `05_BLE_AND_PROTOCOL.md`.

## Recommended implementation order

1. **BLE characteristic audit** (no Swift; user runs nRF
   Connect / LightBlue and pastes results). ✅ **DONE** —
   reference-only audit at `docs/handoff/artifacts/ble_characteristic_audit_2026-05-03.md`,
   committed at `2636b49`.
2. **Shared frame decoder abstraction** — additive scaffold
   alongside `Protocol/`. ✅ **DONE (first slice).** Lives in
   `VoltraLive/BLE/Decoder/{VoltraBLEFrameDecoder,
   VoltraDecodeTable, VoltraDecodedEvent}.swift`. Pattern
   table is data-driven so adding eccentric / chains / mode
   in a follow-up is a one-line addition.
3. **`DeviceState` model + reducer** — ✅ **DONE (base-weight
   only).** `VoltraLive/BLE/State/DeviceState.swift` with
   `ConfirmedValue<T>` carrying `(value, source, at)` and a
   pure `DeviceStateReducer.apply(_:to:)`. Eccentric /
   chains / mode fields are intentionally absent until their
   confirmation patterns are pinned.
4. **Bind UI to `DeviceState` for base weight first** —
   ⏳ **NEXT.** `VoltraBLEManager` now publishes
   `@Published var deviceState: DeviceState`; LiveCaptureView
   needs to read `deviceState.baseWeightLb?.value` and
   reconcile against the user's UI requested value. Out of
   scope for the first slice so this commit can ship
   independently.
5. **Pending / confirmed write flow + 750 ms timeout.**
   🟡 **PARTIAL.** `PendingWriteTracker` lives in
   `VoltraBLEFrameDecoder.swift` with a 2 s default window
   (more conservative than the 750 ms target while we
   validate cadence). The writer registers outbound
   base-weight writes via `onOutboundParam`. Other params
   are not yet registered. `pending` UI status is not yet
   surfaced — only the source attribution
   (`appRequestConfirmed` vs. `deviceUnsolicited`) is
   recorded today.
6. **`LoadState` + stream-gap detection** at the 500 / 2000 ms
   thresholds. ⏳ Deferred.
7. **Semantic recorder events + export summary + incident
   banner.** 🟡 **PARTIAL.** New `RecorderCategory.device`
   case. `device.state.change` event emitted on every real
   transition with `field / from / to / source / rawHex`
   metadata. Export summary + incident banner deferred.
8. **Remove duplicate `ble.write.tx` events.** ⏳ Deferred
   (writer-level + manager-level write.tx still both fire).
9. **Expand decoder coverage** to eccentric / concentric /
   chains once the audit + hardware tests have validated byte
   positions. ⏳ Deferred.
10. **Validate on hardware** and revise the decode table.
    Promote validated hypotheses (e.g. `0x03`) to named
    constants. ⏳ Deferred.

## Non-goals

- Unrelated workout UX redesign.
- Cloud sync redesign.
- Backend analytics changes.
- Firmware changes.
- AI coaching.

## Decision summary

- ADR **V4-D26** in `04_DECISIONS_AND_CONSTRAINTS.md`: the new
  decoder is additive and sits alongside the existing Protocol/
  pipeline; sacred protocol files are not modified.
- Recorder schema bump `1 → 2` is additive (readers handle
  both).
- Buffer policy: `5000-event ring buffer` (was 10,000-event
  FIFO in b78; effective capacity in real sessions per the
  hardware verification observation in chat).
- Conflict resolution: latest device-confirmed value wins;
  app-requested values are `pending` until echoed.

---

# Historical: V4 LiveCapture spec (b58)

> The section below is the V4 LiveCaptureView spec at the
> **b58** ship. It is still the authoritative description of
> what the live capture screen *does today*. Telemetry v2
> (above) is additive on top of it; it does not replace this
> content. Edits to LiveCapture behaviour still belong here
> until/unless a future cycle supersedes it.
>

> **V4 (b58) summary.** Four user-visible changes on top of V3 (b57):
>
> 1. **Dropsets are time-driven again.** First DROP tap fires an
>    immediate −5 lb drop and starts the b22-era cascade state
>    machine in `LoggingStore`. The b56 finalize-driven
>    `manualDropSequence` path is deprecated.
> 2. **Force chart goes Tonal-style.** Dual-band ECC / CON gradient
>    fill under the curve; CHAIN mirrors the gradient; the most
>    recent rep is annotated with inline ECC / CON kerned captions.
> 3. **Weight cell auto-fits.** Single-line, 60% min font scale,
>    soft right-edge fade so 3-digit + TWIN never overlaps the
>    steppers.
> 4. **Dual-Voltra surfaced in V3 layout.** When both Voltras are
>    paired, the header swaps to `[● L bpm] [⇄ MERGE] [● R bpm]
>    kcal`. Independent mode binds the screen's mod controls to the
>    focused side; Twin (combined) mode mirrors writes to both,
>    fuses the side pills into `[● L+R bpm]`, adds a `TWIN` badge
>    next to the weight number, and **greys (does not hide)** the
>    pulley toggle.

## V4 Live Capture screen — top-to-bottom

### §1. Header strip

- **Leading:** ← End button.
- **Inline:** small "V3" build watermark (kept for visual
  continuity; CI-injected build tag is a still-open known issue).
- **Center:** exercise-name marquee. 5s pause → scroll left → 1s
  pause at end → reset → loop. If name fits, no scroll.
- **Trailing — single Voltra (unchanged from b57):** telemetry
  cluster `[● 118 bpm · 42 kcal]`. The leading dot is the BLE
  connection status (green = connected, amber = scanning/
  connecting, grey = idle, red = disconnected). Tapping the dot
  opens a popover with full BLE state text.
- **Trailing — dual Voltra (NEW in b58):** when MDM reports
  both `.left` and `.right` connected the cluster swaps to a
  unit-selector strip. See §8.
- **No top dial.** The V2 dial is removed entirely.

### §1a. Phase strip OR Dropset Progress Bar OR Rest Timer Bar

> **b60 change vs b58:** the phase strip slot now morphs across
> **three** states (was two). Priority order on conflict: rest >
> dropset > phase.

- **Active set, no DROP arm/engage:** compact phase strip with
  PUSH/PULL/IDLE color band.
- **DROP armed or active (b60, KI-8):** unified
  `dropProgressBar`. Labels: `DROP · ARM` (armed, lift active,
  no countdown yet) → `DROP · IN` (armed, lift idle, 2 s
  countdown to first drop) → `DROP · NEXT` (active cascade,
  2 s tier-to-tier countdown) → `DROP · BOTTOM` (cascade hit
  the 5 lb floor, full bar, no further drops). Sweep tied to
  `nextDropFiresAt` / `dropArmedFiresAt`; reuses the ambient
  2 Hz blink republish.
- **Post-finalize rest:** `RestTimerBarV2` HSL sweep green →
  amber → red over the rest preset, blinks 1 Hz once over
  preset.

### §2. WEIGHT card (the big number)

- Big number shows **effective** weight (device frame ×
  pulleyMultiplier).
- Tap the number to toggle hardware LOAD / UNLOAD.
- Pill in upper-right shows LOADED / UNLOADED.
- **Stepper grid:** −5 / −1 / +1 / +5 (lb). Same shape as all four
  nested mod rows.

### §3. Mod tile row + nested mod rows

Four tiles: ECC, CHAIN, INV CHAIN, DROP. Tapping any tile
arms/disarms the mod. Nested rows expand below the tile row, one
row per armed mod.

**Increment grid (all four):** `−5 / −1 / +1 / +5`. ECC range
5–400, CHAIN/INV CHAIN range 0–300.

**DROP tile (b60 V4 §2 — arm-only, port of b22 / aff322f, KI-9 refactor):**

> **b60 change vs b58:** tap is now arm-only. The cable holds
> the working weight until the lift goes idle for 2 s, then the
> first cascade drop fires automatically. See
> [entities/dropset_state_machine.md](entities/dropset_state_machine.md)
> for the full state diagram.

- **First tap (inactive):** arms the cascade via
  `LoggingStore.armDropSet(startingLb:pushWeight:)`. Captures
  the anchor + writer bridge but DOES NOT touch the cable.
  `dropSetArmed = true`; the unified progress bar shows
  `DROP · ARM`.
- **Lift goes idle (force ≤ 3 lb for ≥ 2 s):** engine engages
  the cascade. `engageArmedDropSet` re-delegates to
  `startDropSet` which fires drop #2 at the current tier and
  starts the recurring 2 s `cascadeTimer` + 10 s no-movement
  watchdog. `dropSetArmed` clears, `dropSetActive` flips on.
  ECC / CHAIN / INV CHAIN flags from the parent set are
  inherited automatically.
- **Tap while armed (not yet engaged):** `cancelArmedDropSet`
  clears arm state with a 1.5 s cooldown. The cable was never
  moved so no device write is needed.
- **Tap while active:** `bumpCascadeTier` rolls 1 → 2 → 3 → 1
  (5 / 10 / 15 lb step). Fires an immediate drop at the new tier
  AND resets the 4-second next-fire fuse.
- **Telemetry-driven:** `forceLb > 3 lb` calls
  `noteTelemetryActivity` which resets BOTH the 4-second fuse
  (so the cable doesn't auto-drop mid-rep) and the 10-second
  no-movement watchdog. 10 seconds of idle finalizes the chain;
  SessionStore line 146 already checks the dropset boundary
  callback BEFORE finalizing to a normal set, so the rest-timer
  hand-off is correct.
- **Long-press (0.5 s):** `cancelDropSet` — restores the anchor
  weight on the device and starts the 1.5 s arm-cooldown so the
  same touch-up doesn't re-arm.
- **Step buttons:** ±1 are greyed (no micro-drops). ±5 cycles
  the tier forward (+5) or backward (−5) by calling
  `bumpCascadeTier` once or twice.
- **Nested DROP row:** shows `head → next` where `head` is the
  last anchored device-frame weight (effective = ×pulley) and
  `next` is the LoggingStore preview at the current tier.
  Floor = 5 lb device (`cascadeAtFloor` flips on; subsequent
  drops are no-ops).
- **DEPRECATED:** the b56 `manualDropSequence` finalize-driven
  path. `dropArmed` now reads `logging.dropSetActive`, NOT the
  manual sequence. The legacy property is left declared so a
  future build can revive it without diff churn.

**Mutual exclusion:** CHAIN and INV CHAIN cannot be armed at the
same time — arming one disarms the other.

### §4. Pulley + Added-plates bar (above the force chart)

Two compact dial controls, sitting directly above the force
chart (same width as the chart):

- **Pulley:** 1× / 2× toggle. Default **1×**. Multiplies the
  effective force the user feels relative to the device cable
  load. UI side multiplies *display*; BLE side does NOT multiply
  (the device sees the device-frame value).
- **Added plates:** integer 0…N, default **1 lb**, increments
  of 1 lb.

**Pulley math (CRITICAL — verified b57):**

- `LoggingStore.pendingPlannedWeightLb` = device frame.
- WEIGHT card big number, force chart Y axis, log storage all
  use `× pulleyMultiplier`.
- BLE write (`pushUpcomingStateToDevice`) does **not** multiply.
- Under 2× pulley, displayed ±1 lb may snap by 2 lb — this is
  documented in `06_KNOWN_ISSUES.md`.

### §5. Force chart (b71 V4-D20 — V1 ForceChartView is canonical)

**Renderer.** `VoltraLive/Views/ForceChartView.swift` (the V1
chart). Mounted by **both** `LiveCaptureView` (V1 screen) and
`LiveCaptureViewV2.forceChartCard` (V2 screen). The b58/b67-10
`ForceChartV2` (parametric `sin(π · t)` half-sine lobes) is
retained on disk for rollback safety but is **no longer mounted
anywhere** — see the SUPERSEDED banner at the top of
`VoltraLive/Logging/Views/V2/ForceChartV2.swift`.

The user's verbatim rationale (2026-04-30): _"the V1
ForceChartView is the one that displays the force curve correctly
in practice. Replace or wrap V2's force panel so LiveCaptureViewV2
uses the V1 ForceChartView behavior/data path."_ This decision
supersedes the b67-10 polyline-vs-sine reasoning captured in ADR
V4-D13. See ADR **V4-D20** in `04_DECISIONS_AND_CONSTRAINTS.md`.

**Inputs.** V2's `forceChartCard` is a thin V1-input adapter that
reproduces the same builder block V1 uses:

- `samples = session.currentSet?.samples ?? session.lastFinalizedSamples`
  — keeps the chart filled through the rest window instead of
  blanking on finalize.
- `peakLb = session.currentSet?.peakLb ?? session.lastFinalizedPeakLb`.
- `forceMultiplier = logging.pulleyMultiplier` — displayed values
  are EFFECTIVE (what the user feels), matching `LoggedSet`
  storage.
- `plannedCeilingLb = ((pendingPlannedWeightLb ?? 0) + upcomingEccLb) × m + (upcomingAddedLoadLb ?? 0)`
  — anchors the y-axis to planned + 15% headroom (or observed
  peak + 15%, whichever is greater); 12-lb floor inside-session.
- Superset secondary trace: when `mdm.hasActiveSupersetChain` is
  true and the active and next chain entries name different
  exercises, the chart pulls the OTHER exercise's most-recent
  finalized force trace from `SessionStore.lastFinalizedByExercise`
  and renders it as a dimmed dashed line behind the primary
  phase-colored trace, with both exercise labels surfaced in the
  legend.

**Rendering.** Phase-colored line segments (pull / return /
transition / idle), Catmull-Rom interpolation, 3-sample moving-
average smoothing pre-multiplied by `forceMultiplier`, X-domain
spans the whole set (no 30-second rolling window). Five horizontal
grid lines (0 / 25 / 50 / 75 / 100 % of ymax) labeled in lb. Peak
label `peak XX.X lb` rendered in the chart header alongside the
legend.

**Chrome ownership.** `ForceChartView` paints its own header,
legend, peak readout, padding, `bgElev` background, border, and
rounded-corner clip. The V2 call site does NOT wrap it in V2-only
card chrome — stacking would produce double headers / double
borders / nested cards. The previous b58 V2 wrapper (`FORCE · 30 S`
sibling header + outer rounded-rect card) was removed in b71.

**Removed in b71 (along with the V2 mount):**

- `LiveCaptureViewV2.computedYAxisMaxLb()` helper — no longer
  needed; V1's chart computes its own y-axis from
  `plannedCeilingLb` + observed peak.
- The V2-only `eccBandActive` / `chainMirrorActive` plumbing into
  the chart — dual-band ECC / CON fill, CHAIN mirrored gradient,
  and inline `ECC` / `CON` centroid labels were features of the
  superseded `ForceChartV2`. They are NOT present in V1's
  `ForceChartView` and are intentionally NOT carried forward; the
  user has accepted V1's rendering as the correct user-facing
  shape.
- The b57/b58 rep-history overlay (8-rep log-decay fade) and the
  1.5 s y-axis rescale ease — same reason. Both lived only in
  `ForceChartV2`.

If any of those features are reintroduced later, the future ADR
must add them to V1's `ForceChartView` (so V1 and V2 stay in
sync), not by re-mounting `ForceChartV2`.

### §6. Rest timer (b57 V3 §6)

First-engage miss is fixed (b57). Idle detector now accepts
`cs.peakLb > 10` alongside `cs.reps > 0` — the very first rep
of the session no longer slips through the arm-check.

### §7. V1 restore section

Bottom of scroll view: logged sets list + bottom-actions row
(End Set, etc.). Pulley + plates were lifted out of this
section in b57 (now lives above the chart per §4).

### §8. Dual-Voltra header + Twin Mode (NEW in b58)

**When the cluster appears.** Only when MDM reports both
`mdm.left.connectionState.isConnected` AND
`mdm.right.connectionState.isConnected`. Single-Voltra sessions
stay on the b57 cluster.

**Independent mode (default after both pair).**

- Layout: `[● L bpm] [⇄ MERGE] [● R bpm] [● kcal]`.
- Each side dot is a tap-target. Tapping focuses that side —
  the screen's mod controls (weight / ECC / CHAIN / INV CHAIN /
  DROP) bind to the focused unit only.
- Focused side: dot tints accent, pill border highlights.
- Routing: `WriterRouter.apply(state, mdm:, assignment:)` is
  called with `DeviceSlotAssignment(slot: focusedSlot)` so writes
  land on exactly one side.

**Twin Mode (combined).**

- `mdm.workoutMode = .combined`. The MERGE button reads
  pressed (accent fill).
- The two side pills fuse into a single `[● L+R bpm]` pill.
- A `TWIN` badge appears inline next to the WEIGHT card big
  number.
- The Pulley toggle is **greyed (NOT removed)** — a lock icon
  appears on the chip and the tap handler is a hard no-op.
- Routing: `assignment` is nil so WriterRouter falls through
  to its `.combined` branch and broadcasts via
  `mdm.applyCombined(state)` (which respects CombinedParity
  rounding for odd totals).
- Cascade writes (drop-set step pushWeight callback) also use
  the focus-aware override, so a drop in Twin mode mirrors to
  both sides.

**MERGE button.**

- Tap toggles `mdm.workoutMode` between `.independent` and
  `.combined`. Renders pressed (accent background, bg-color
  text) only when `twinModeActive`.

## What the screen does **not** have

- ❌ Top dial (removed in V3).
- ❌ Micro-drops (DROP must always be a multiple of 5 lb).
- ❌ Simultaneous CHAIN + INV CHAIN.
- ❌ Hidden pulley in Twin Mode (greyed, never hidden).
- ❌ Per-set L/R weight independence in Twin Mode (mirror only —
  for asymmetric loading the user must switch to Independent).
- ❌ The b56 `manualDropSequence` finalize-driven dropset path
  (deprecated; legacy state field retained for future revival).

## §9. Debug surfaces (NEW in b70)

### Page badge

Every screen with `.pageBadge("ScreenName")` renders
`"NN · ScreenName"` at bottom-leading, where `NN` is the 2-digit
ID assigned to that screen by `VoltraLive/Views/PageRegistry.swift`.
Color: `VoltraColor.textFaint`. Font: 9pt monospaced. Always
visible — no debug-build gate (per b66 user ask, retained in b70).
Unknown screen names render `-- · ScreenName` so the badge still
serves its identification purpose; that's the signal to add the
name to the registry.

**Mounting rule (b70 hotfix, V4-D19): containers must not own a
`.pageBadge`.** `PageBadgeOverlay` is implemented as a SwiftUI
`.overlay(alignment: .bottomLeading)`, which **propagates** to
every descendant in the same overlay context (NavigationStack
pushes, plain child views). If a parent container that wraps
other screens mounts a `.pageBadge`, both the parent's and the
child's badges render at the same anchor and visibly overlap as
garbled stacked text. Only **leaf, user-visible screens** may
carry `.pageBadge`. Sheet- and fullScreenCover-presented surfaces
are fine because they get a fresh overlay context. The shipped
b70 binary mounted `.pageBadge("ContentView")` on the root
container; it was removed in the b70 hotfix — see V4-D19 in
`04_DECISIONS_AND_CONSTRAINTS.md`.

### Debug grid overlay (b72 / V4-D22 → b73 / V4-D23 → b74 / V4-D24)

A five-state progressive-density spreadsheet-style grid behind
`@AppStorage("debugGridMode")`. Replaces the b70/V4-D18
four-state 9-anchor marker overlay (C-TL / M-T / F-CTR / …)
because anchor markers were not precise enough for design
feedback. Lives in `VoltraLive/Views/DebugGridOverlay.swift`.

**b74 / V4-D24 update — TRUE content-space layer.** The b73
PreferenceKey/`contentMinY` translation path failed on device:
the grid still rendered viewport-pinned under scroll. b74
abandons that path entirely and splits the grid into two
physical layers:

- **Vertical gridlines + column letters (A, B, C…)** stay
  VIEWPORT-pinned via `.debugGridOverlay()` on the screen body.
  There is no horizontal scroll, so column coordinates are
  stable in screen space.
- **Horizontal gridlines + row numbers (1, 2, 3…)** physically
  live INSIDE the scrollable content via
  `.debugGridContentLayer()` attached as a `.background(...)`
  on the inner content stack of each page-badged ScrollView.
  SwiftUI's `.background(...)` sizing makes the layer's frame
  equal to its host's intrinsic frame, so the layer covers the
  full content extent and scrolls with it natively — the layer
  is genuinely a sibling of the content, not an overlay above
  it. Row 1 sits at the top of content; "C10" identifies the
  same UI element regardless of scroll offset.

No PreferenceKey, no named coordinate space, no translation
pass. The previous `DebugGridContentMetricsKey`,
`.debugGridContent()` modifier, and `"debugGridViewport"`
coordinate space are removed.

Screens currently wired with `.debugGridContentLayer()` (b74
coverage — same 10 as b73): `LoggingHomeView`,
`LiveCaptureView`, `LiveCaptureViewV2`, `ExerciseDetailView`,
`ExerciseStartView`, `DebugView`, `DashboardView`,
`ExercisePickerView`, `SetLogView`, `ExportSheet`. Adding the
modifier is a one-line change and is the expected pattern for
any future page-badged ScrollView. Non-scrolling screens
(`ConnectView`, `LiveCaptureContainer`, `ContentView`) simply
omit it — there is no scroll content to anchor to and the
viewport-pinned column/letters layer is sufficient.

Density cases (`enum DebugGridDensity`):

- `.off` (default) — invisible; no overlay rendered.
- `.base` — 32pt graph-paper grid. Vertical + horizontal lines
  every 32pt at ~30 % opacity. Spreadsheet-style column letters
  `A, B, C, …, Z, AA, AB, …` across the top margin strip; row
  numbers `1, 2, 3, …` down the leading margin strip. Margin
  strips sit inside the safe area so labels never disappear
  under the iOS status bar / home indicator.
- `.half` — adds a gridline halfway between each base line
  (16pt density), thinner / lower opacity. Half labels (`A.5`,
  `10.5`) appear interior on the margin strips at reduced weight.
- `.quarter` — adds gridlines at every quarter (8pt density),
  even more subordinate. **Quarter labels are MARGIN-ONLY** —
  `.25` and `.75` labels appear in the top + leading strips, NOT
  inside the screen body, so the body stays readable. (Per
  V4-D22.)
- `.max` — everything in `.quarter` PLUS a region-outline layer.
  Translucent rectangles with their Swift identifier name are
  drawn around major UI sections of the current screen. Region
  outlines render at ~40 % opacity in `VoltraColor.accent`.
  Region label sits at the top-leading inside corner of the
  region in 8pt monospaced. Screens publish their regions via
  `.debugRegion("name")`; screens that haven't been instrumented
  render the grid only at `.max` with no regions (graceful
  degradation).

**Spacing locked at 32pt.** On a 390pt-wide device this yields
~12 columns (A–L) and ~26 rows on an 844pt-tall body — the
balance the user picked between graph-paper feel and label
legibility at quarter-step density.

All labels are monospaced (`8pt` base / `7pt` half / `6pt`
quarter), mint (`VoltraColor.textFaint`) at 0.85 / 0.55 / 0.45
opacity respectively. Mounted automatically by the page-badge
modifier so any screen with a page badge participates. The grid
is the LAST modifier in `PageBadgeOverlay`'s chain so it renders
ABOVE both the page badge and the build badge in z-order; margin
labels remain legible over those badges.

### Toggle gesture

Tapping the bottom-trailing build badge cycles the density:
`.off` → `.base` → `.half` → `.quarter` → `.max` → `.off`. State
is persisted in `@AppStorage("debugGridMode")`. Persisted legacy
`DebugGridMode` raw values (`corners` / `midlines` / `full`)
migrate to `.base` on next read via `DebugGridDensity.from(_:)`.
No other UI surface exposes the toggle.

### Region instrumentation (State 4 / `.max`)

State 4 region overlay is opt-in per screen. Screens publish
named regions to the State 4 layer via the `.debugRegion("name")`
view modifier:

```swift
HStack { /* … */ }
    .debugRegion("headerPillRow")
```

Names must match the Swift view/section identifier used in code
(e.g. `tileGrid`, `forceChartCard`, `upcomingSetCard`,
`dropSetSection`, `loggedSetsSection`, `bottomActions`,
`headerPillRow`). Where there is no obvious name, use the
nearest enclosing view. Implementation uses `anchorPreference`
so it does not change layout and does not intercept hits.

Instrumentation is partial as of b72 — see `06_KNOWN_ISSUES.md`
entry KI-12 for the current screen coverage list and the planned
follow-up work.

### Demo Mode toggle (DebugView)

Existing toggle behavior is unchanged from b66 (still labeled
"Demo Mode is active / off", still in the `DEMO MODE` section
of `DebugView`). What changed in b70 is the entry source: the
toggle now derives `.prePair` vs `.postPair` from
`anyDeviceConnected` at tap time so flipping it on with no
Voltra paired starts the synthetic telemetry pump (which was
the user-reported b69 bug). See `04_DECISIONS_AND_CONSTRAINTS.md`
ADR V4-D17 for the connection-aware contract.

### Demo Mode button (LoggingHomeView)

Same connection-aware rule as the Debug toggle. Button stays
visible regardless of pairing — only hidden when demo is
already active. Per V4-D17, no live call site uses
`source: .settingsRestore`; that case is retained in
`DemoEntrySource` for trace-replay compatibility only.

## §10 Session Recorder (B74-F11)

Local-only AI-readable debug recorder. Hidden until the user
**triple-taps the build-badge chip**, which flips
`UserDefaults["VOLTRARecorderUnlocked"] = true`. After unlock, a
**24×24 pt dot** lives in a single root-level
`.overlay(alignment: .bottomTrailing)` (mounted in
`VoltraLiveApp.swift`, never per-screen).

- **Tap** → toggle recording. Red 1 Hz `TimelineView(.animation)`
  pulse while armed; faint `VoltraColor.textFaint` while idle.
- **Long-press** → present `SessionRecorderViewer` sheet (event
  timeline + category filter chips + `ShareLink` exporting both
  `.txt` and `.json`).
- **scenePhase** observer in `VoltraLiveApp.swift` emits
  `lifecycle.appBackground` / `lifecycle.appForeground` and calls
  `recorder.persist()` on background / inactive.

Single shared `SessionRecorder.shared` (`ObservableObject`,
non-`@MainActor`) owns a 10,000-event FIFO actor buffer, an
`ActionScope` task-local UUID, and the redactor. `record(...)` is
thread-safe and callable from any context.

Persistence: on background / kill, current session JSON is written
to `Application Support/SessionRecorder/last_session.json`. No other
disk writes; no network; no analytics.

Authoritative spec: [`SESSION_RECORDER_SPEC.md`](SESSION_RECORDER_SPEC.md).
Per-file map: [`07_FILE_MAP.md`](07_FILE_MAP.md) "B74-F11 — Session
Recorder (EXISTS)".
