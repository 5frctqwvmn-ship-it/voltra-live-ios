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
