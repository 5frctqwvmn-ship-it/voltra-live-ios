# 07 — Dual-VOLTRA Spec

Status: **planned for build 30**. Source files for the implementation
are stashed in `.dual-voltra-wip/` (gitignored) — restore into
`VoltraLive/` before resuming this work.

## Why dual

The user has two VOLTRAs in their gym. They want to:

- Connect to one (existing flow, unchanged).
- Connect to two and use them **independently** (e.g. belt squat on one,
  back extension on the other).
- Connect to two and use them as a **combined** virtual machine
  (single-target weight is split across both sides).

Single-Voltra flow must never regress.

## Connect screen — 3 buttons

Replaces the existing single Connect button in `VoltraLive/Views/ConnectView.swift`:

1. **Connect VOLTRA** — single-device path.
   - If exactly one VOLTRA is in range, auto-connect.
   - If two or more are in range, show a picker (no regression vs today).
2. **Connect Two VOLTRAs** — dual-device path.
   - Scanner shows discovered devices.
   - Tap-to-assign: first tap = Left, second tap = Right.
   - "Connect 2 strongest" button as a one-tap shortcut (uses RSSI).
3. **Demo Mode** — existing demo controller, unchanged.

## Dual-screen header

After dual connect succeeds, the live screen has a segmented control in
the header:

- **Independent** (default)
- **Combined**

Mode is sticky for the session but can be switched mid-session.

## Independent mode

- Both sides render side-by-side.
- Each side has its own telemetry tiles, weight controls, and logs to
  `LoggingStore` independently.
- Common case: different exercises on each side. The set-complete
  detector runs per side.
- All `VoltraWriter` writes are scoped to the side they target.

## Combined mode

- Single virtual-twin panel, not two side-by-side panels.
- Weight: target weight is split — each side receives `TOTAL/2`.
  - **Left rounds up** when `TOTAL` is odd, so the sum stays exact.
- Eccentric, chains, mode: mirrored across both sides.
- Telemetry aggregation:
  - Force: **sum** of both sides.
  - Reps: **sum** of both sides (assumes synchronized — see watchdog below).
  - Power: **sum** of both sides.
  - ROM: **average** of both sides.
  - Velocity: **average** of both sides.

## LOAD / UNLOAD buttons

New tiles on the live screen, **same size** as the existing Drop Set tile.

- **Independent mode:** per-side LOAD and UNLOAD.
- **Combined mode:** single LOAD and single UNLOAD that fire to both
  sides simultaneously.
- Payloads: see `05_BLE_AND_PROTOCOL.md#load--unload-payloads-build-30`.

## Combined disconnect watchdog

If one of the two devices drops mid-session in Combined mode:

1. Immediately send `UNLOAD` to the survivor (don't leave a half-loaded rig).
2. Start a reconnect attempt to the dropped side with exponential backoff:
   `0.5 s → 1 s → 2 s → 4 s`.
3. Total timeout: **30 s** before giving up and surfacing an error.
4. On reconnect, re-issue the last known device state via `VoltraWriter`
   (weight, ecc, chains, mode). User-visible toast: "Reconnected Right".

## Files (from `.dual-voltra-wip/`)

| File | Role |
|---|---|
| `DualMode.swift` | `enum DualMode { case independent, combined }` and helpers. |
| `MultiDeviceManager.swift` | Coordinator that owns 2 BLE managers + 2 writers, plus the watchdog. |
| `VoltraDiscoveryScanner.swift` | Scans, surfaces RSSI-sorted candidates, supports tap-to-assign. |
| `VoltraControlFrames+LoadUnload.swift` | LOAD/UNLOAD payload builders. |

`VoltraBLEManager.swift` had a `connectKnown(identifier:fallback:)` helper
added during build-29 stash work — that edit was reverted before commit.
Re-add it cleanly in build 30 if `MultiDeviceManager` needs it.

## Out of scope for build 30

- Superset support is **deferred to build 31** (see `08_SUPERSET.md`).
- Per-side history filtering (today's history view will show both sides
  in chronological order).
- Per-side HR / kcal attribution — HealthKit data is global to the session.
