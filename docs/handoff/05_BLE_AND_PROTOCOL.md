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
