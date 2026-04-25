# VALIDATION.md — First TestFlight Run

> **Run this against your real VOLTRA the first time you install the TestFlight build.**
>
> This is a **declarative success criteria** checklist (Karpathy-style). Each line is a
> verifiable assertion. Report the results back as `PASS` / `FAIL` / `SKIP` per number —
> do **not** describe what you saw in prose. Pass/fail per line is the contract.

---

## Setup (one-time)

- [ ] **S1.** TestFlight installed VOLTRA Live successfully (no install error)
- [ ] **S2.** Watch companion auto-installed on paired Apple Watch (or manually installed from Watch app on phone)
- [ ] **S3.** Bluetooth permission granted to VOLTRA Live on first launch
- [ ] **S4.** Phone is within ~3 meters of the VOLTRA cable machine
- [ ] **S5.** VOLTRA cable machine is powered on and **not** currently connected to any other phone/iPad

## Connection

- [ ] **C1.** VOLTRA appears in the in-app device list within 10 seconds of opening the app
- [ ] **C2.** Tapping the device shows "Connecting…" then "Connected"
- [ ] **C3.** **Stays connected for at least 30 seconds** (validates the 9 BOOTSTRAP_WRITES handshake — if this fails, the device disconnects with status 19 around the 5-second mark)
- [ ] **C4.** Watch screen transitions from "Phone Disconnected" to the live dashboard within 5 seconds of phone connecting

## Live telemetry — REPS

> Pull the cable to do **5 deliberate reps**. Pause between each so the rep counter has time to register.

- [ ] **R1.** Rep counter on phone increments from 0 → 1 on the first rep (not from 0 → 256, not stuck at 0)
- [ ] **R2.** Rep counter reaches **exactly 5** after 5 reps (not 4, not 6, not 1280)
- [ ] **R3.** Watch rep counter mirrors the phone rep counter (allow up to 1-second lag)
- [ ] **R4.** Watch haptic ticks once per rep (`.click` haptic — short)

## Live telemetry — PHASE

> The phase tile color must change as the cable cycles through the rep.

- [ ] **P1.** Phase tile is **gray (Idle)** when cable is at rest
- [ ] **P2.** Phase tile turns **teal (Pull)** during the concentric pull
- [ ] **P3.** Phase tile turns **orange (Return)** during the eccentric return
- [ ] **P4.** Phase tile briefly turns **blue (Transition)** at the top/bottom of the rep (may be brief — count as PASS if you see it once across the 5 reps)
- [ ] **P5.** Watch phase indicator dot color matches phone phase tile color (allow up to 1-second lag)

## Live telemetry — FORCE

> Pull the cable steadily and read the FORCE tile.

- [ ] **F1.** FORCE tile shows a **non-zero number in pounds (lb)** while pulling
- [ ] **F2.** Number is in a **plausible range** for your set load (within ±20% — e.g., a 50-lb load reading 40–60 lb is PASS, reading 8000 lb or 0.0001 lb is FAIL)
- [ ] **F3.** Number drops to **<5 lb** when you let go of the cable
- [ ] **F4.** Watch FORCE tile mirrors the phone FORCE tile (allow up to 200-ms lag — Watch updates at ~5 Hz)

## Set completion

> After your 5th rep, set the cable down and **wait 5 seconds without touching it**.

- [ ] **SC1.** Phone "set complete" indicator fires within ~5 seconds of last rep + cable at rest
- [ ] **SC2.** Watch fires the **success haptic** (`.success` — distinct double-tap pattern) on set completion
- [ ] **SC3.** Rest timer starts on the Watch and ticks up at 1 Hz (1, 2, 3, 4… seconds)
- [ ] **SC4.** Starting a new rep resets the rest timer to 0 and clears the set-complete indicator

## Reconnection

- [ ] **RC1.** Lock the phone screen, wait 30 seconds, unlock. App is still connected and reps still counting.
- [ ] **RC2.** Walk out of range (~10 m), wait until "Disconnected" appears. Walk back. App auto-reconnects within 15 seconds without a force-quit.
- [ ] **RC3.** Force-quit the app, reopen. Reconnects to the same VOLTRA without re-pairing.

---

## How to report

Reply with **just the line IDs and PASS/FAIL/SKIP**, like:

```
S1 PASS
S2 PASS
S3 PASS
S4 PASS
S5 PASS
C1 PASS
C2 PASS
C3 FAIL — disconnected after 6 seconds
C4 SKIP — Watch not paired yet
R1 PASS
R2 PASS
R3 FAIL — Watch shows 4, phone shows 5
…
```

For any FAIL, one short sentence of context is enough. **Do not** debug live — collect the
full pass/fail set first, then we triage together. That keeps the regression surface
isolated to specific assertions.

## What each failure category means

| Failure category | Likely root cause | Where to look |
|---|---|---|
| **C3** (disconnect at ~5s) | BOOTSTRAP_WRITES regression | `VoltraLive/Protocol/VoltraProtocol.swift` line 24 — should be exactly 9 frames |
| **R1/R2** (rep count wrong by ×256) | Rep count endianness flipped | `TelemetryExtractor.swift` line 74 — must be big-endian shift |
| **F1/F2** (force shows 0 or huge number) | Force endianness flipped or offset wrong | `TelemetryExtractor.swift` line 89 — must be little-endian, offset 11 |
| **P1–P4** (phase tile never changes color) | Phase byte offset wrong | `VoltraProtocol.swift` `TELEMETRY_REP_PHASE_OFFSET` — must be 2 |
| **R3/P5/F4** (Watch lags or mismatches phone) | WatchConnectivity bridge issue, NOT protocol | `VoltraLive/Bridge/PhoneWatchBridge.swift` |
| **SC1** (set complete never fires) | Heuristic threshold | `phase == .idle AND force < 5 AND reps > 0 AND idle ≥ 4000ms` |

If C3, R1/R2, F1/F2, or P1–P4 fail, the protocol golden tests in
`VoltraLiveTests/ProtocolGoldenTests.swift` should have caught it in CI — file a bug
that the test coverage missed the regression.
