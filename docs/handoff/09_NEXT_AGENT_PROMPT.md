# 09 — Next Agent Prompt

> Read this first. Cold-start prompt for the next agent picking
> up VOLTRA Live iOS. Skim, then read the docs in the order at
> the bottom.

## Where things stand (b82, v0.4.52)

**Last shipped:** v0.4.52 build 82. Tag `v0.4.52-build82` pushed.
TestFlight upload confirmed 2026-05-04.
Delivery UUID: `496678a7-ab0b-4a7d-b08a-d1077c315fb7`.

**Next build: 83.**

## Active task for build 83

Fix two BLE bugs discovered from hardware Session Recorder sessions on 2026-05-04:

### BUG-A: Inverse Chains always writes `inverse=false`

Every weight-mode config sequence sends `inverse=false` even when Inverse Chains is selected in the UI. The device therefore runs normal Chains, not Inverse Chains.

Session evidence (Session 3, id `02ADAB2A-CFC8-4B02-BE0B-1D2F77A4C336`):
- App writes `mode→weight`, then `inverse=false`, then `base=45`, `ecc=0`, `chains=0`.
- Later chains ladder: `chains=30`, `chains=25` … all preceded by `inverse=false`.
- This is wrong when user selected Inverse Chains.

Fix direction:
- Find the BLE command builder / weight config writer.
- Add `isInverseChains` / `chainsType` to canonical device config model.
- Ensure apply / replay / reconnect / live-capture-start paths send `inverse=true` when Inverse Chains is selected.
- Stop default config replay from blindly writing `inverse=false`.

### BUG-B: Manual VOLTRA weight changes do not update app UI

App updates UI only from `appRequestConfirmed` events. Unsolicited device-side weight changes (user adjusting weight directly on VOLTRA) produce BLE notify frames that are never decoded into app state.

Session evidence (Session 4, id `BA0A92DE-13D4-4C0C-AD75-649A5666C91E`):
- Rapid base writes: `base=45`, `base=40`, `base=35`, `base=30`, `base=25`.
- Device confirmed `50→45`, `45→30`, `30→25` — intermediate values coalesced.
- UI can get stuck on stale intermediate value.
- Unsolicited notify frames observed: `5513040310aaff07...893e04` and `5513040310aa0708...893e05` — these are not decoded into UI state.

Fix direction:
- Decode unsolicited device-originated parameter updates for:
  - baseWeight / param `0x86`
  - chainsWeight / param `0x87`
  - eccentricWeight / param `0x88`
  - inverse / param `0x89` (verify from code)
- Promote decoded values into live UI state even when no pending app request exists.
- Source metadata: use `deviceNotification` or `unsolicitedDeviceUpdate` (not `appRequestConfirmed`) for these events.
- Add Session Recorder events: `device.state.change {source="deviceNotification"}`.
- Final decoded device state wins over rapid-write intermediate states.

### Known packet patterns

```
mode→weight:   551204c7aa10....2000110100b04f01
inverse=false: 551204c7aa10....2000110100b05300
base=N:        55130403aa10....2000110100863eNN
chains=N:      55130403aa10....2000110100873eNN
eccentric=N:   55130403aa10....2000110100883eNN
```

## Hard rules (do not violate)

1. **Sacred files — DO NOT MODIFY:** `VoltraProtocol.swift`, `TelemetryExtractor.swift`, `PacketParser.swift`, `FrameAssembler.swift`. New protocol-adjacent code goes in new files only.
2. **5-gate ship verification.** CI green is not enough. Pull the run log, confirm altool ≥20s, `UPLOAD COMPLETED SUCCESSFULLY` marker, zero ERROR lines.
3. **`gh` CLI for GitHub.** Bot identity: `git -c user.name="VOLTRA Live Bot" -c user.email="bot@voltralive.app"`
4. **`docs/WORK_LOG.md` is append-only.**
5. **No micro-drops.** DROP must always be a multiple of 5 lb.
6. **CHAIN and INV CHAIN are mutually exclusive** at the UI layer.
7. **User has no Mac for local builds.** All signing is CI-only. (Note: user now has a 2019 MacBook Pro with Xcode 15 being set up — but CI remains the authoritative build path until confirmed working.)
8. **Preserve all previous builds.** `git log --all` and `git tag` before asking where old code is.
9. **One TestFlight build per V-spec.**
10. **Commit every 10 Q&A turns** to prevent sandbox loss.

## Karpathy method

Before you start, repeat the user's request back to them so they can confirm you're getting it correct.

## Read order for cold start

1. `AGENTS.md` (repo root)
2. `00_START_HERE.md`
3. `02_CURRENT_STATE.md`
4. `03_CURRENT_FEATURE_SPEC.md`
5. `04_DECISIONS_AND_CONSTRAINTS.md`
6. `05_BLE_AND_PROTOCOL.md`
7. `06_KNOWN_ISSUES.md`
8. `07_DUAL_VOLTRA.md`
9. `09_RELEASE_AND_SIGNING.md`
10. `10_OPEN_QUESTIONS.md`
11. `docs/WORK_LOG.md` — last 200 lines

## ⚠️ Deprecated docs — do not read as authoritative

- `01_PROJECT_OVERVIEW.md` — stale, superseded
- `03_ROADMAP.md` — stale, superseded by `03_CURRENT_FEATURE_SPEC.md`
- `06_HEALTHKIT.md` — stale, superseded by `06_KNOWN_ISSUES.md`
- `B52_DIAGNOSIS.md` — build-specific artifact, no longer actionable

## When the user asks for a new feature

1. Repeat the spec back (Karpathy).
2. Ask 1-4 clarifying questions if the spec has holes.
3. Estimate cost class: small / medium / heavy. Mention it.
4. Implement, ship, verify all 5 gates.
5. Append `WORK_LOG.md`. Update `03_CURRENT_FEATURE_SPEC.md` and `04_DECISIONS_AND_CONSTRAINTS.md` if anything decided.
