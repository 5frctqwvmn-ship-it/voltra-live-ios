# BLE characteristic audit — VOLTRA I — 2026-05-03

> **Source caveat (read first).** This audit was produced **without
> running an iOS BLE scanner against a live VOLTRA I.** The agent had
> no Bluetooth radio, no iOS device, and no VOLTRA hardware. Every
> entry below is taken from public reference implementations (the
> Android controller and Home Assistant integration by the same
> reverse-engineering author) cross-checked against the iOS repo's
> own Swift constants. **Each row is explicitly labeled with its
> source.** This is not a substitute for an on-device nRF Connect /
> LightBlue scan — it is a paper audit grounded in the best
> independent source available. The unknowns section calls out every
> thing this approach cannot answer.

## Sources

| Tag | Source | Path / file | Commit-time access |
|---|---|---|---|
| **iOS** | This repo | `VoltraLive/Protocol/VoltraProtocol.swift` lines 11-17 | HEAD `6a3162b` |
| **iOS-BLE** | This repo | `VoltraLive/BLE/VoltraBLEManager.swift` lines 423-455 | HEAD `6a3162b` |
| **AND** | dylanmaniatakes / Beyond-Power-Voltra-Android (Apache-licensed reverse engineering) | `core/protocol/.../VoltraUuidRegistry.kt` | branch `main`, fetched 2026-05-03 |
| **AND-CL** | Same repo | `device/ble/.../AndroidVoltraClient.kt` (subscription set, lines 3950-3956) | same |
| **AND-BS** | Same repo | `core/protocol/.../VoltraOfficialReadOnlyBootstrap.kt` (10 bootstrap packets) | same |
| **HA** | dylanmaniatakes / Beyond-Power-HomeAssistant (HACS integration) | `custom_components/voltra/const.py` | branch `main`, fetched 2026-05-03 |

All three independent implementations agree on the **same 4
characteristic UUIDs and the same VOLTRA service UUID.** No reference
implementation documents a 5th characteristic on the VOLTRA service.

## Service / characteristic table — observed across all reference sources

Service UUID `e4dada34-0867-8783-9f70-2ca29216c7e4`. Properties are
the **author-documented role**, not GATT descriptor bits read from a
live device. Properties marked with † come from Swift comments in
`VoltraProtocol.swift` plus subscription behavior; they are not a
direct read of `characteristic.properties` from a CoreBluetooth scan.

| # | Characteristic UUID | Role / declared name | Properties (from sources) | iOS subscribes? | iOS uses for | Sources | Notes |
|---|---|---|---|---|---|---|---|
| C1 | `55ca1e52-7354-25de-6afc-b7df1e8816ac` | `cmdChar` / `VOLTRA_COMMAND` | Write + Notify (for command responses) † | **Yes** (`setNotifyValue(true)`) | Command writes, response notifications | iOS, AND, HA | Both Android and iOS subscribe to notify on this char. HA classifies it as one of `NOTIFY_CHARACTERISTIC_UUIDS`. |
| C2 | `ca94658c-0525-5046-e78b-5391b65f47ad` | `notifyChar` / `VOLTRA_NOTIFY` | Notify only † | **Yes** (`setNotifyValue(true)`) | Async telemetry stream (0xAA frames live here) | iOS, AND, HA | Pure notify channel. This is the high-rate stream the existing pipeline parses. |
| C3 | `a010891d-f50f-44f0-901f-9a2421a9e050` | `transport` / `VOLTRA_TRANSPORT` | Read + Write + Notify | **Yes** (only when `.notify` property present) | Bootstrap writes (handshake), parameter reads, parameter responses | iOS, AND, HA | iOS gates subscription on `char.properties.contains(.notify)`. Android always subscribes when role match. HA classifies it as `NOTIFY_CHARACTERISTIC_UUIDS` and `CONFIRMED_RESPONSE_CHARACTERISTIC_UUIDS`. |
| C4 | `19de84ed-0a69-482c-a8a6-c75cb5bb4389` | `justWrite` / `VOLTRA_JUST_WRITE` | Write Without Response | **No** (cannot subscribe — write-only) | Currently declared but no observed sends in iOS bootstrap path | iOS, AND, HA | All three reference impls treat this as write-no-response only. Whether iOS *uses* it for any control write is a code-review item flagged in OQ-T7 territory. |

### Cross-implementation subscription matrix

| Char | iOS (`VoltraBLEManager`) | Android (`AndroidVoltraClient` `VOLTRA_OFFICIAL_NOTIFY_ROLES`) | HA (`NOTIFY_CHARACTERISTIC_UUIDS`) |
|---|---|---|---|
| C1 cmdChar | subscribes | subscribes | subscribes |
| C2 notifyChar | subscribes | subscribes | subscribes |
| C3 transport | subscribes (when notify property present) | subscribes | subscribes |
| C4 justWrite | does not subscribe (no notify) | does not subscribe | does not subscribe |

**All three clients subscribe to the same three characteristics.** No
reference implementation documents an additional notify or indicate
channel on the VOLTRA service that any of them subscribe to but iOS
does not.

### Descriptors

The Android client references the standard `CCCD_UUID =
00002902-0000-1000-8000-00805f9b34fb` (Client Characteristic
Configuration Descriptor) when enabling notifications
(`AndroidVoltraClient.kt` line ~3949 in the constants block;
`writeDescriptor` at lines 3166 and 3177). On iOS, CCCD writes are
implicit in `setNotifyValue(true)` and not visible in app code. No
reference implementation documents any other GATT descriptors for the
VOLTRA service.

## Candidate unobserved notify / indicate channels

**Result: zero candidates from this paper audit.**

Reasoning:

  - All three independent reference implementations enumerate exactly
    the same 4 VOLTRA-service characteristics (C1–C4 above).
  - Of those, exactly the same 3 are subscribed to (C1, C2, C3).
  - The only unsubscribed VOLTRA-service characteristic (C4
    `justWrite`) is documented as `WRITE_NO_RESPONSE` only in all
    three sources — it is not a notify/indicate target.
  - The Android registry includes a separate 26-UUID set
    (`knownPm5Uuids`, prefixed `CE060…`) for **Concept2 PM5 rower**
    cross-classification. These are a different device family,
    surfaced only when scanning detects a non-VOLTRA peripheral. They
    are **not** characteristics on the VOLTRA service and are not
    candidates for VOLTRA telemetry.

### Caveat — what this paper audit cannot rule out

This audit cannot prove the VOLTRA peripheral does not advertise
**additional services or characteristics outside the
`e4dada34-…c7e4` service** that none of the three clients have
discovered. iOS's service discovery is currently filtered to
`VoltraUUID.service` only (`VoltraBLEManager.swift` line 418) and
characteristic discovery is filtered to the 4 known UUIDs
(`VoltraBLEManager.swift` line 424). If the firmware advertises a
DIS (`0x180A`), Battery Service (`0x180F`), or vendor-specific
diagnostic service, **none of the three reference clients would
notice** and this paper audit cannot see it either. **Resolving this
requires a hardware scan with `discoverServices(nil)` followed by
`discoverCharacteristics(nil, …)` per service.**

## Implications for Telemetry v2 decoder

**The existing notify stream + bootstrap response path is the only
documented source of truth.** The additive Telemetry v2 decoder
(ADR V4-D26) must therefore work from:

  1. **C1 cmdChar notifications** — command-response correlations
     (frame ACKs, parameter-read responses).
  2. **C2 notifyChar stream** — high-rate telemetry (0xAA frames with
     phase / setCount / repCount / forceTenths layout already pinned
     in this repo).
  3. **C3 transport notifications** — bootstrap response payloads,
     parameter-read responses for mode / weight state.

There is no fourth notify channel to subscribe to (per current
reference evidence), so the decoder design must close the
DeviceState / LoadState gap by:

  - **(a) Better use of `CMD_PARAM_READ` responses on C3 transport.**
    The Android bootstrap packet 10 (`read mode feature state`)
    issues a single `CMD_PARAM_READ` for **19 parameters at once**,
    including:
    - `PARAM_BP_BASE_WEIGHT`
    - `PARAM_BP_CHAINS_WEIGHT`
    - `PARAM_BP_ECCENTRIC_WEIGHT`
    - `PARAM_FITNESS_INVERSE_CHAIN`
    - `PARAM_BP_SET_FITNESS_MODE`
    - `PARAM_FITNESS_WORKOUT_STATE`
    - `PARAM_ISOMETRIC_MAX_FORCE`
    - `PARAM_BP_RUNTIME_POSITION_CM`
    - `PARAM_QUICK_CABLE_ADJUSTMENT`
    - … plus 10 others (resistance band, isokinetic, damper).
    This **directly addresses OQ-T2** (ecc/conc/chains byte
    positions). Authoritative values for ecc, conc, and chains are
    available as `CMD_PARAM_READ` responses on the transport
    characteristic — they do not have to be inferred from stream
    frame byte offsets.
  - **(b) Gap inference on the C2 notify stream.** The decoder still
    needs gap-based load-state inference (per `03_CURRENT_FEATURE_SPEC.md`
    constants: 500 ms / 2000 ms stream gap thresholds) because the
    stream is the only signal during a live set.
  - **(c) Hypothesis bytes (OQ-T1, OQ-T3, KI-23, KI-24) remain
    hypothesis.** No reference implementation publicly documents the
    `0x03` byte in `553404ac` status frames or the `2b010100` byte in
    `553a0470` stream frames as a known semantic. Both stay flagged
    as hypothesis until a hardware experiment or the Android
    `VoltraNotificationParser.kt` ([reviewed but 2005 lines] —
    candidate for follow-up) confirms a meaning.

### Relevant Android-reference cross-reference for follow-up

  - `core/protocol/.../VoltraNotificationParser.kt` (2005 lines) is
    the most-likely public source for byte-level semantics including
    OQ-T1 and OQ-T3. Worth a focused read before designing the v2
    decoder; not done in this audit pass.
  - `core/protocol/.../VoltraControlFrames.kt` defines
    `PARAM_*` constants — useful for picking the v2 collector's
    `CMD_PARAM_READ` set.

## Bootstrap-write count discrepancy (incidental finding)

The audit task brief listed "9 BOOTSTRAP_WRITES, not 10" as a known
fact. The iOS code matches: `BOOTSTRAP_WRITES` in
`VoltraProtocol.swift` lines 24-40 has **9 entries**. The Android
reference has **10** (`VoltraOfficialReadOnlyBootstrap.kt`); the
extra packet is `read mode feature state`, a `CMD_PARAM_READ` for the
19 mode/weight parameters listed above. iOS does not currently
issue this read on bootstrap. This is **not a bug in the audit
brief** — the brief documents iOS behavior — but it is a **finding
relevant to Telemetry v2**: iOS could obtain authoritative
ecc / conc / chains / mode state at connect by adding a 10th bootstrap
read (or by issuing the same `CMD_PARAM_READ` lazily later). Filing
this as a v2 design input, not as a sacred-file edit.

## What remains unknown

These questions cannot be answered from public reference code and
require **on-device** experimentation:

  1. **Are there additional services on the VOLTRA peripheral beyond
     `e4dada34-…c7e4`?** Standard candidates: Device Information
     Service (`0x180A`), Battery Service (`0x180F`), Generic Access
     (`0x1800`), Generic Attribute (`0x1801`). None of the three
     reference clients use unfiltered service discovery, so none
     would have noticed. **Requires `peripheral.discoverServices(nil)`
     scratch test, or nRF Connect / LightBlue scan.**
  2. **Does the VOLTRA service expose any additional characteristics
     beyond C1–C4?** Same blind spot — iOS uses
     `discoverCharacteristics([…], for: service)` with a 4-UUID
     filter (`VoltraBLEManager.swift` line 424), so even if a 5th
     characteristic exists, the iOS app never sees it. **Requires
     `discoverCharacteristics(nil, for: service)` scratch test, or
     an iOS-side BLE scanner.**
  3. **Live `properties` bitmask for each characteristic.** This
     audit infers properties from author comments and subscription
     behavior. The actual `CBCharacteristicProperties` returned by
     CoreBluetooth on a paired VOLTRA have not been logged. **An
     iOS-side debug log of `char.uuid` + `char.properties.rawValue`
     immediately after `didDiscoverCharacteristicsFor` would close
     this in 5 minutes** without modifying sacred files (the log is
     in `VoltraBLEManager.swift`, which is not sacred).
  4. **Indicate vs Notify on each subscribed char.** Today's iOS
     code calls `setNotifyValue(true)` which CoreBluetooth resolves
     to whichever the characteristic supports. Whether any of C1 /
     C2 / C3 advertise INDICATE specifically (which would change
     ACK semantics) is unverified. Same fix as #3.
  5. **OQ-T1 `0x03` status byte and OQ-T3 `2b010100` phase flag.**
     Neither is named in the Android registry or the HA constants.
     The Android `VoltraNotificationParser.kt` is 2005 lines and may
     or may not contain a meaning — **not exhaustively read in this
     audit**. Still hypothesis.
  6. **OQ-T5 force / tension scale and zero-point.** The `forceTenthsLb
     uint16-LE @ offset 11` layout is pinned in this repo's facts,
     but the zero-point and what happens when load is released
     (does force go to 0, or to a sentinel value?) is not pinned.
     Hardware-only.
  7. **Whether the firmware ever emits indications on a
     subscribed-but-quiet characteristic.** E.g. C1 cmdChar might
     emit error indications during a malformed write that none of
     the three reference clients have triggered. Hardware-only.

## Recommended next actions

1. **Run an on-device scanner** (nRF Connect for iOS, or LightBlue)
   against the VOLTRA I and export the full service / characteristic
   tree to `docs/handoff/artifacts/ble_scan_<date>.json` (or
   `.txt`). That export, dropped into this artifacts directory, would
   close unknowns #1, #2, #3, #4 in one shot. **This audit already
   prepared the artifact directory.**
2. **Read `core/protocol/.../VoltraNotificationParser.kt`** (Android,
   2005 lines) end-to-end before designing the Telemetry v2 decoder.
   It is the single best public source for byte-level semantics that
   may resolve OQ-T1, OQ-T3, and parts of OQ-T5 without hardware.
   Defer to Step 2 of the cycle (shared decoder abstraction) per
   `09_NEXT_AGENT_PROMPT.md`.
3. **Design v2 collector to issue `CMD_PARAM_READ` for the 19-param
   mode/weight set on the C3 transport characteristic**, as in the
   Android bootstrap packet 10. This is the cleanest path to closing
   OQ-T2 (ecc / conc / chains drift) without inferring byte offsets.
4. **Add a temporary debug log** of `characteristic.uuid` +
   `characteristic.properties.rawValue` in
   `VoltraBLEManager.swift` (non-sacred) after the connect-only
   scratch experiment lands. Closes unknowns #3 and #4 from app code
   alone. **Not done in this commit (release-only mode, no Swift).**
