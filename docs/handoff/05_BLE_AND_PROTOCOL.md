# 05 — BLE and Protocol

## Source of truth

Reverse-engineered protocol reference (Apache-licensed):
<https://github.com/dylanmaniatakes/Beyond-Power-Voltra-Android>

Use this repo to look up payload values. Do **not** introduce protocol
constants from anywhere else without citing them.

## Wire-format facts

- BLE service UUID: `e4dada34-0867-8783-9f70-2ca29216c7e4`
- 9 (not 10) `BOOTSTRAP_WRITES` are sent on connect. Byte-identical to
  the official iPad app capture.
- 0xAA telemetry layout:
  - phase @ offset 2
  - setCount @ offset 3
  - repCount: uint16 **big-endian** at offsets 4–5
  - forceTenthsLb: uint16 **little-endian** at offset 11
- Set-complete heuristic:
  `phase == .idle AND force < 5 AND reps > 0 AND idle ≥ 4000ms`
  (4 s short rest, 10 s drop-cascade — used by drop-set detection).

## Sacred files

Off-limits without explicit user approval:

- `VoltraLive/Protocol/VoltraProtocol.swift`
- `VoltraLive/Protocol/TelemetryExtractor.swift`
- `VoltraLive/Protocol/PacketParser.swift`
- `VoltraLive/Protocol/FrameAssembler.swift`

If a feature genuinely needs a protocol change:

1. Surface the assumption to the user before coding.
2. Add or update a fixture-pinning test in
   `VoltraLiveTests/ProtocolGoldenTests.swift`.
3. Run `xcodebuild test -scheme VoltraLive` locally before pushing.

## Control writes — current policy (April 2026)

The original policy was strict read-only. **As of April 2026 the user
has explicitly approved control writes**, gated through `VoltraWriter`.
This section is the new contract.

### Approved write surface

All writes go through `VoltraLive/BLE/VoltraWriter.swift`, which is
diff-based: it compares the desired `VoltraDeviceState` against the last
known device state and emits the minimum set of writes required.

- Weight (target load)
- Eccentric multiplier
- Chains (on/off + count)
- Mode (e.g. concentric/eccentric/standard)
- **LOAD / UNLOAD** (build 30, see below)

The 9 `BOOTSTRAP_WRITES` remain byte-identical and untouched.

### LOAD / UNLOAD payloads (build 30)

From the Android reference repo (`dylanmaniatakes/Beyond-Power-Voltra-Android`):

| Action  | Frame type        | Param ID  | Value    |
|---------|-------------------|-----------|----------|
| LOAD    | `CMD_PARAM_WRITE` | `0x3E89`  | `0x0005` |
| UNLOAD  | `CMD_PARAM_WRITE` | `0x3E89`  | `0x0004` |

These are wired into `.dual-voltra-wip/VoltraControlFrames+LoadUnload.swift`
and must be reviewed before merging into `VoltraLive/`.

### Rules for new writes

- **Never** modify the sacred protocol files. Add new payload builders in
  new files (e.g. `VoltraControlFrames+<Feature>.swift`).
- **Never** auto-issue a write the user didn't trigger (no "background
  optimizations" that touch device state).
- **Always** log the write at debug level so failed sessions can be
  reconstructed.
- **Always** keep a single-Voltra path that works without writes — the
  read path must never depend on the write path succeeding.

### Multi-device writes (build 30)

`MultiDeviceManager` is the coordinator for dual-Voltra writes:

- **Independent mode:** each side gets its own `VoltraWriter` instance,
  no cross-talk.
- **Combined mode:** writes are mirrored to both sides simultaneously
  (weight = TOTAL/2, Left rounds up; eccentric/chains/mode mirrored).
- **Combined disconnect watchdog:** if one side drops mid-session, send
  `UNLOAD` to the survivor and try to reconnect the dropped side with
  exponential backoff (0.5 s → 1 s → 2 s → 4 s, 30 s total timeout).

See `07_DUAL_VOLTRA.md` for the full mode spec.

## BLE characteristic audit (post-b78)

**Status:** PLAN — no audit run yet. Step 1 of the Telemetry v2 cycle.
Tracked as KI-26 in `06_KNOWN_ISSUES.md` and resolves OQ-T4 in
`10_OPEN_QUESTIONS.md`.

**Goal.** Produce a complete, documented map of every advertised
service and characteristic on the VOLTRA peripheral, so the Telemetry
v2 decoder can be designed against ground truth instead of inferred
behavior. Several of the open hypotheses (OQ-T1 = `0x03` status byte,
OQ-T3 = `2b010100` phase flag, OQ-T5 = force decodability) may
collapse to deterministic reads if a dedicated status / device-state
characteristic exists that we are not currently subscribed to.

**Procedure.**

  1. **Discover.** With a paired VOLTRA, log every entry of
     `peripheral.services` and, for each service, every entry of
     `service.characteristics`. Capture: service UUID, characteristic
     UUID, properties bitmask (`read` / `write` / `writeWithoutResponse`
     / `notify` / `indicate`), and any descriptor list.
  2. **Compare to current subscriptions.** Diff the discovered set
     against the characteristics our pipeline currently subscribes to
     (whatever `FrameAssembler` / the connection layer wires up
     today). Flag any characteristic that is `notify` or `indicate`
     and **not** subscribed — those are the most likely candidates
     for an unmissed device-state channel.
  3. **Probe candidates.** For each flagged candidate, subscribe in a
     scratch session (no Swift edit to the production path — use a
     temporary debug toggle gated behind a build-time flag) and log
     all bytes received during a controlled load-engage / load-drop
     /  weight-change sequence.
  4. **Cross-reference.** Pair the candidate-channel byte log against
     the existing `553404ac` and `553a0470` frame stream from the
     same session. If a candidate channel emits a clean state value
     where our hypothesis byte is currently inferred, that channel
     becomes the source of truth and the hypothesis collapses.
  5. **Write up.** Land the audit table as a new subsection here
     ("BLE characteristic audit results") with: service UUID,
     characteristic UUID, properties, current-subscription status,
     observed payload shape, recommended action (subscribe / leave /
     write-only), and hypothesis resolutions.

**Out of scope.** No edits to sacred files
(`VoltraProtocol.swift`, `TelemetryExtractor.swift`,
`PacketParser.swift`, `FrameAssembler.swift`). The audit may produce
recommendations that motivate the Telemetry v2 additive decoder; the
existing pipeline is not edited to act on the audit's findings.

**Definition of done.**

  - Audit table committed to this file.
  - OQ-T4 closed in `10_OPEN_QUESTIONS.md` (same commit as the audit
    write-up).
  - Any of OQ-T1, OQ-T3, OQ-T5 that the audit deterministically
    resolves are also closed in the same commit.
  - `WORK_LOG.md` entry summarizing the audit run, hardware
    conditions, and resolved hypotheses.

## BLE characteristic audit results — 2026-05-03

> **Method caveat.** This audit was conducted **without a live
> on-device BLE scan.** It is a paper audit cross-referencing this
> repo's `VoltraProtocol.swift` against the public reference
> implementations by the same reverse-engineering author (Android
> controller and Home Assistant integration). Full source list,
> per-row sources, and verbatim file paths are in
> `docs/handoff/artifacts/ble_characteristic_audit_2026-05-03.md`.
> The "What remains unknown" section there enumerates what only
> hardware can answer.

### Service / characteristic table

VOLTRA service UUID `e4dada34-0867-8783-9f70-2ca29216c7e4`
(unchanged from `VoltraProtocol.swift` line 12). All three reference
clients (this iOS app, the Android controller, the HA integration)
agree on the same 4 characteristic UUIDs and the same 3-of-4
subscription pattern.

| # | Characteristic UUID | Role | Properties | Subscribed in iOS? | Notes |
|---|---|---|---|---|---|
| C1 | `55ca1e52-7354-25de-6afc-b7df1e8816ac` | `cmdChar` / VOLTRA_COMMAND | Write + Notify | yes | Command writes + response notifications |
| C2 | `ca94658c-0525-5046-e78b-5391b65f47ad` | `notifyChar` / VOLTRA_NOTIFY | Notify | yes | High-rate telemetry stream (0xAA frames) |
| C3 | `a010891d-f50f-44f0-901f-9a2421a9e050` | `transport` / VOLTRA_TRANSPORT | Read + Write + Notify | yes (when notify property present) | Bootstrap writes + parameter reads/responses |
| C4 | `19de84ed-0a69-482c-a8a6-c75cb5bb4389` | `justWrite` / VOLTRA_JUST_WRITE | Write Without Response | no (write-only) | No subscribe possible |

iOS subscription path: `VoltraBLEManager.swift` lines 423–455.
Android equivalent: `AndroidVoltraClient.kt` `VOLTRA_OFFICIAL_NOTIFY_ROLES`
(set of `{ VOLTRA_COMMAND, VOLTRA_NOTIFY, VOLTRA_TRANSPORT }`).
HA equivalent: `const.py` `NOTIFY_CHARACTERISTIC_UUIDS`
(same three UUIDs).

### Candidate unobserved notify / indicate channels

**Zero candidates** identified by this paper audit. None of the three
independent reference implementations document a 5th characteristic
on the VOLTRA service. The only unsubscribed VOLTRA-service
characteristic (C4 `justWrite`) is `WRITE_NO_RESPONSE` only and is
not a notify/indicate target.

The Android registry's `knownPm5Uuids` set (26 UUIDs prefixed
`CE060…`) is for **Concept2 PM5 rower** cross-classification —
unrelated to the VOLTRA service.

**Limit of this method.** The iOS app uses
`peripheral.discoverServices([VoltraUUID.service])` filtered to one
service UUID and `peripheral.discoverCharacteristics([4-UUID list],
…)` filtered to the four known UUIDs (`VoltraBLEManager.swift`
lines 418, 424). All three reference clients have the same blind
spot. **This audit cannot rule out additional services or
characteristics that all three clients filter past.** Resolving that
requires `discoverServices(nil)` + `discoverCharacteristics(nil, …)`
in a hardware scratch session, or an iOS-side scanner export.

### Implications for Telemetry v2 decoder

  1. The additive decoder (per ADR V4-D26) must work from C1 / C2 /
     C3 — the same three notify channels the existing pipeline
     already consumes. There is no fourth channel to subscribe to
     under current evidence.
  2. **OQ-T2 has a non-hardware path.** The Android bootstrap packet
     10 (`read mode feature state` —
     `VoltraOfficialReadOnlyBootstrap.kt` lines 55–81) issues a
     single `CMD_PARAM_READ` for 19 params including
     `PARAM_BP_BASE_WEIGHT`, `PARAM_BP_CHAINS_WEIGHT`,
     `PARAM_BP_ECCENTRIC_WEIGHT`, `PARAM_FITNESS_INVERSE_CHAIN`,
     `PARAM_BP_SET_FITNESS_MODE`, `PARAM_FITNESS_WORKOUT_STATE`.
     Authoritative ecc / conc / chains values are available via
     parameter responses on C3 transport — they do not have to be
     inferred from stream-frame byte offsets. iOS currently has
     **9** bootstrap writes (`VoltraProtocol.swift` lines 24-40);
     the Android reference has 10. The 10th is this read.
  3. **OQ-T1 and OQ-T3 remain hypothesis.** Neither the Android
     `VoltraUuidRegistry` nor the HA constants name the `0x03`
     status byte or the `2b010100` phase flag. The Android
     `VoltraNotificationParser.kt` (2005 lines) is the most-likely
     public source for byte-level semantics and was **not
     exhaustively read** in this audit pass — flag it for the
     v2-decoder design step.

### What remains unknown

These cannot be answered from public reference code and require
on-device evidence:

  1. Additional services beyond `e4dada34-…c7e4` (DIS, Battery,
     vendor-specific). All three reference clients filter to the
     VOLTRA service only.
  2. Additional characteristics on the VOLTRA service beyond C1–C4.
     iOS filters to the 4 known UUIDs.
  3. Live `CBCharacteristicProperties` bitmask per char on a paired
     VOLTRA — closeable via a non-sacred debug log in
     `VoltraBLEManager.swift`; not done in this commit.
  4. Whether C1 / C2 / C3 advertise INDICATE specifically (vs
     NOTIFY).
  5. OQ-T1 `0x03` semantic, OQ-T3 `2b010100` semantic, OQ-T5 force
     scale / zero-point.
  6. Whether subscribed-but-quiet characteristics ever emit error
     indications in conditions the three reference clients have not
     triggered.

The full unknowns list with proposed resolution paths is in
`docs/handoff/artifacts/ble_characteristic_audit_2026-05-03.md`.
