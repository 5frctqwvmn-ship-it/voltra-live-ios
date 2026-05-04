# 08 — Git History Summary

_Last updated: 2026-05-04. Covers 1ecd16b → HEAD (pre-Smart Coach unlock commit)._

## Commits since last transcript archive (1ecd16b)

| SHA | Description |
|---|---|
| `7c02c59` | **fix: bridge KI-21 device params into live UI** — adds `@Published` bridges (`deviceOriginatedChainsWeightUpdate`, `deviceOriginatedEccentricWeightUpdate`, `deviceOriginatedInverseChainUpdate` + monotonic IDs) to `VoltraBLEManager`; `VoltraWriter` registers outbound writes with pending-write tracker for chains/ecc/inverse; `LiveCaptureViewV2` observes and applies device-originated changes, emits `ui.deviceChainsApplied`, `ui.deviceEccentricApplied`, `ui.deviceInverseApplied`. KI-21 remain open pending hardware retest. |
| `1ecd16b` | docs: archive full 2026-05-04 Perplexity transcript |
| `54416c0` | docs: archive 2026-05-04 Perplexity thread + context index |
| `ba8d3ef` | docs: restore full WORK_LOG after truncation |
| `27e9eec` | docs: restore full WORK_LOG after truncation |
| `e4a79fe` | docs: restore full WORK_LOG after placeholder corruption |
| `5824c61` | docs: restore AGENTS.md |
| `5046c5f` | docs: restore 09_RELEASE_AND_SIGNING.md |
| `0848d46` | docs: restore AGENTS.md + 09_RELEASE_AND_SIGNING + WORK_LOG |
| `6d5c23a` | docs: add safe-sync policy for agents |
| `fe0355c` | **fix: implement KI-21 mode parameter decoders** — `DeviceStateField` + 3 cases; `VoltraDecodeTable` + `0x3E87`/`0x3E88`/`0x53B0` patterns; `DeviceState` + 3 fields + reducer cases |
| `8f51437` | docs: full context ledger + next-agent prompt |
| `278865e` | docs: track mode parameter sync gap after b81 (KI-21 opened) |
| `bae9e7a` | docs: record b81 TestFlight ship |
| `7da4ef2` | **chore: bump 0.4.52/build81** — ships KI-20 topology fix + RC-01 dark |
| `5b8d978` | docs: context checkpoint post-RC-01 |
| `ad3c11b` | **feat: RC-01 coaching card + SC-01 smart coach engine** — 16 new files; all flags default false |
| `9788d49` | **fix: focusedBle topology** — routing by `connectionState.isConnected`, not `bothVoltrasConnected`; KI-20 root cause fix |
| `04d09ae` | docs: record b80 ship |
| `51908f2` | chore: bump 0.4.52/build80 |
| `a46d45f` | fix: device base-weight bridge event-based (monotonic ID) |
| `08a8b7c` | fix: apply device-originated base weight in live capture |
| `507c7f2` | docs: universal agent workflow rules |
| `aa5a77c` | chore: bump 0.4.52/build79 |
| `53af938` | fix: missing .device case in SessionRecorderViewer |
| `bdbf91b` | feat: mirror device-confirmed base weight into live capture |
| `da34cd4` | feat: base-weight device state decoder |
| `2636b49` | docs: BLE characteristic audit |
| `6a3162b` | docs: align handoff for telemetry v2 |
| `32f9300` | Merge PR #12: B74-F11 launch crash fix; bump to v0.4.51/build78 |

## Open KIs at HEAD

| ID | Status |
|---|---|
| KI-20 | CLOSED (b81 A1 retest passed) |
| KI-21 | OPEN — follow-through at `7c02c59`; pending hardware retest |
| KI-SC-01 | OPEN — Smart Coach unlock at next commit; pending hardware retest |
