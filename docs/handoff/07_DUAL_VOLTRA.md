# 07 — Dual-VOLTRA Spec

Status: **Independent + Twin Mode shipped in b58** (V4). Initial
plumbing landed in b29/b30 under `.dual-voltra-wip/`; b58 wires it
into the V3 LiveCapture screen.

## Why dual

The user has two VOLTRAs in their gym. They want to:

- Connect to one (existing flow, unchanged).
- Connect to two and use them **independently** (e.g. belt squat on
  one, back extension on the other).
- Connect to two and use them as a **combined virtual machine**
  ("Twin Mode") — single-target weight is split across both sides.

Single-Voltra flow must never regress.

## Connect screen — 3 buttons (unchanged from b30 spec)

`VoltraLive/Views/ConnectView.swift`:

1. **Connect VOLTRA** — single-device path.
2. **Connect Two VOLTRAs** — dual-device path; tap-to-assign
   (1st = Left, 2nd = Right) or "Connect 2 strongest" via RSSI.
3. **Demo Mode** — existing demo controller, unchanged.

## V3/V4 LiveCapture header — b58

When **only one** VOLTRA is connected, the V3 single-side header
renders unchanged (status dot + marquee + V3 watermark).

When **both Voltras are connected** (`bothVoltrasConnected =
mdm.left.connectionState.isConnected && mdm.right.connectionState
.isConnected`), the header swaps to the **dualHeaderCluster**:

```
[ L • ]   [ MERGE ]   [ • R ]              ← when independent
[      [ Twin: L+R ]      ]                ← when twinModeActive
```

- `sideDot(slot:)` — colored dot per side (green = connected,
  amber = connecting, red = dropped). Tapping a dot sets
  `focusedSlot = .left|.right` (independent only).
- `mergeButton` — toggles `mdm.workoutMode` between
  `.independent` and `.combined`. Disabled if either side is
  reconnecting.
- `fusedTwinPill` — replaces the L/MERGE/R cluster while in
  `.combined`. Tap to fall back to independent.

## Independent mode (b58)

- Both sides connected; `mdm.workoutMode == .independent`.
- The V3 LiveCapture screen renders as a single-side view but its
  **focus** follows `focusedSlot` (`@State` in `LiveCaptureViewV2`).
- All telemetry the user sees (weight card, force chart, rep
  count, plates) is sourced from `focusedBle`, where:
  ```
  focusedBle = (focusedSlot == .left) ? mdm.left : mdm.right
  ```
- Writes are scoped via `focusOverrideAssignment`:
  ```
  focusOverrideAssignment = DeviceSlotAssignment(slot: focusedSlot)
  ```
  This is passed to **both** `writerRouter.apply(...)` call sites
  in `LiveCaptureViewV2`, ensuring weight / mod changes only fire
  to the focused side.
- Set-complete detector runs per side via `LoggingStore`'s existing
  per-side cascade state. The non-focused side keeps logging in
  background.

## Twin Mode (b58 — formerly "Combined")

- `mdm.workoutMode == .combined`.
- Single virtual-twin panel (no L/R split tiles).
- TWIN badge appears next to the big weight number in the WEIGHT
  card (`twinModeActive` gate).
- **Pulley control is greyed out** (b58 V4-D5):
  `PulleyAndPlatesBarV3.pulleyChip.disabled = twinModeActive`,
  with `lock.fill` icon overlay and 0.55 opacity. The chip is
  **not hidden** — discoverability preserved. Accessibility label
  reads "Pulley locked in Twin Mode".
- Weight split: target weight halved per side, **left rounds up**
  on odd totals so the sum stays exact. This logic lives in
  `MultiDeviceManager.applyCombined(_:)`.
- Telemetry aggregation: force/reps/power = sum, ROM/velocity =
  average. Unchanged from b30 spec.

## LOAD / UNLOAD buttons

- Independent: per-side LOAD/UNLOAD, scoped via
  `focusOverrideAssignment`.
- Twin: single LOAD and single UNLOAD, fire to both sides via
  `mdm.applyCombined`.
- Payloads: see `05_BLE_AND_PROTOCOL.md#load--unload-payloads-build-30`.

## Twin disconnect watchdog (b30 — unchanged)

If one of the two devices drops mid-session in Twin Mode:

1. Immediately send `UNLOAD` to the survivor.
2. Reconnect attempt with exponential backoff: `0.5 s → 1 s → 2 s
   → 4 s`. Total timeout: 30 s.
3. On reconnect, re-issue the last known device state via
   `VoltraWriter`. Toast: "Reconnected Right".

## Files

| File | Role |
|---|---|
| `BLE/MultiDeviceManager.swift` | Owns 2 BLE managers + 2 writers + watchdog + `workoutMode`. |
| `BLE/DualMode.swift` | `enum WorkoutMode { case independent, combined }`. |
| `BLE/WriterRouter.swift` | `apply(_:mdm:assignment:)` — assignment overrides slot routing in independent focus mode. |
| `BLE/VoltraDiscoveryScanner.swift` | RSSI-sorted scan, tap-to-assign. |
| `BLE/VoltraControlFrames+LoadUnload.swift` | LOAD/UNLOAD payload builders. |
| `Logging/Views/LiveCaptureViewV2.swift` | b58 V4: `focusedSlot`, `bothVoltrasConnected`, `twinModeActive`, `focusedBle`, `focusOverrideAssignment`, `dualHeaderCluster`, `sideDot`, `mergeButton`, `fusedTwinPill`. |
| `Logging/Views/V2/PulleyAndPlatesBarV3.swift` | b58 V4: `@EnvironmentObject mdm`, pulley chip greys out in Twin Mode. |

## Out of scope at b58

- **Per-side history filtering** — today's history view shows both
  sides interleaved chronologically. Filter UI deferred.
- **Per-side HR / kcal attribution** — HealthKit data remains
  global to the session.
- **Superset support** — deferred to b59+ (see `08_SUPERSET.md`).
- **Dropset behavior in Twin Mode** — DROP currently anchors to
  focused side in independent and is undefined for Twin (DROP tile
  is hidden when `twinModeActive`). Spec for Twin DROP TBD.

## Verification checklist (b58)

- [x] Header swaps to dualHeaderCluster when both connected.
- [x] MERGE toggles `mdm.workoutMode`.
- [x] TWIN pill replaces cluster in combined mode.
- [x] TWIN badge appears in weight cell.
- [x] Pulley chip greyed out (lock icon, opacity 0.55) in Twin.
- [x] Pulley chip NOT hidden in Twin.
- [x] `focusedSlot` toggles via L/R dot tap (independent only).
- [x] Both `writerRouter.apply` call sites pass
  `assignment: focusOverrideAssignment`.
- [x] Single-VOLTRA flow unchanged (header reverts to V3 chrome
  when `!bothVoltrasConnected`).
