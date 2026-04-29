# 02 — Current State

_Last updated: 2026-04-29 (b56 shipped)._

> **Maintenance rule:** this file is overwritten on every ship. The
> append-only history lives in `docs/WORK_LOG.md`. If you're updating
> this file, replace the relevant sections wholesale instead of appending.

## Latest shipped build

**v0.4.34 build 56** — tag `v0.4.34-build56`, label "V2 mods + rest timer + V1 restore".

Previous: v0.4.33 build 55 ("V2 single-Voltra LiveCapture") — first signed-off web-preview port of the V2 LiveCapture; subsumed by b56's mod-row + rest-timer + V1-restore additions.

## What works today

- Single-Voltra capture (V1) — full feature set including drop-set cascade, weight nudges, added-plates, expanded set rows.
- Single-Voltra capture (V2) — opt-in via first-launch picker, falls back to V1 the moment a chain entry exists or both Voltras pair. b56 layout: header → phase strip OR rest-timer bar (HSL sweep, blink) → WEIGHT card with hardware-load tap on big number + nested mod rows (only armed) + 4-up mod tile grid (all selectable) + per-engaged-mod stepper rows (ECC clamps 5–400 lb; CHAIN ↔ INV CHAIN mutually exclusive) → REPS / TOTAL VOLUME tiles → force chart with parent-driven Y-axis (= max(workingLb, eccEffective) × 1.3, animated rescale) → V1RestoreSection (pulley chip + added-plates picker + LOGGED SETS swipeable list + Next-exercise + End-session). DROP is finalize-driven and tap-arms-deeper: each tap deepens the next-step by 5 lb, long-press cancels.
- Dual-Voltra Independent + Combined modes (V1 only).
- Superset chain (V1 only) with b53's per-instance `assignedVoltra` routing source-of-truth, 3-way Left/Right/Both picker, and SWAP-no-auto-LOAD safety.
- HealthKit HR + active calories streaming with PulseDot freshness indicators.
- Session export with sessionVitalsCard (AVG HR / KCAL / TOTAL VOL / DUR) and comparisonCard vs prior session of same dayTypeRaw.
- Markdown export with fixed-width table (no mid-row wrapping).

## Live capture mode handling matrix

| Scenario | Renders |
|---|---|
| 1 Voltra paired, no chain, V1 chosen | V1 |
| 1 Voltra paired, no chain, V2 chosen | **V2** |
| 1 Voltra paired, chain has \u22651 entry | V1 (b54 tightened gate) |
| 2 Voltras paired, Independent | V1 |
| 2 Voltras paired, Combined | V1 |
| 2 Voltras paired, Superset chain | V1 (b53 chain fixes apply here) |

V2 is single-Voltra-no-chain only by design. The `LiveCaptureContainer` view at `VoltraLive/Logging/Views/LiveCaptureContainer.swift` enforces this gate.

## V2 design source

V2 is a port of the b55 sign-off render at `voltra-v2-preview/index.html` (signed off in the b55 session) PLUS the b56 spec dump (3-state rest-timer screenshot + spec text in the b56 user message). The b55-era layout note ("1:1 port of design-system/ui-kit.html") is OBSOLETE — the actual layout-of-truth has been the web preview since b55, and now also the b56 spec.

**Before changing V2, re-read the WORK_LOG b55 + b56 entries and `voltra-v2-preview/index.html`.** Do not rely on prose summaries.

## Known issues / not yet built

1. No Settings toggle to switch back from V2 to V1 after picking V2. First-launch picker is the only entry point. Tracked for a future build.
2. V2 has no chain affordances by design. If a user tries to add a second exercise while on V2, the container falls back to V1; V2 itself does nothing chain-aware.
3. The `swapSupersetSide` no-auto-LOAD behavior changes the user's manual workflow. After a SWAP, they must tap LOAD to arm the new side. Document this in any user-facing release note.
4. b56 V2 DROP is finalize-driven (advances `manualDropIndex` when the next set starts). The legacy V1 timer-cascade `startDropSet` still exists for V1 and is not wired into V2 — V2 only uses `manualDropSequence` head/next pair.

## Key files (quick map)

| Concern | File |
|---|---|
| Live capture V1 | `VoltraLive/Logging/Views/LiveCaptureView.swift` |
| Live capture V2 | `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` |
| V1/V2 routing | `VoltraLive/Logging/Views/LiveCaptureContainer.swift` |
| Per-instance Voltra assignment | `VoltraLive/BLE/Dual/DualMode.swift` (`DeviceSlotAssignment`) |
| Routing logic | `VoltraLive/BLE/WriterRouter.swift` |
| Chain state | `VoltraLive/BLE/Dual/MultiDeviceManager.swift` |
| Session/instance models | `VoltraLive/Logging/Model/LoggingModels.swift` |
| Export sheet | `VoltraLive/Logging/Views/ExportSheet.swift` |
| HealthKit + session snapshot | `VoltraLive/Health/HealthKitStore.swift` |
| Design system spec | `design-system/` on branch `design-studio` |
| Design tokens (Swift) | `VoltraLive/Views/VoltraTheme.swift` |

## Repository facts

- Canonical local path: `/tmp/voltra-live-ios`
- Default branch: `main`
- HEAD at last summarization: TBD post-b56 commit
- Working tree: clean post-b56-ship
- CI runner: `macos-26`, Xcode `26.2`, iPhoneOS `26.2.sdk`
- Bot identity for commits: `git -c user.name="VOLTRA Live Bot" -c user.email="bot@voltralive.app"`

## Recent tags

- `v0.4.34-build56` — V2 mods + rest timer + V1 restore (current)
- `v0.4.33-build55` — V2 single-Voltra LiveCapture (signed-off web-preview port)
- `v0.4.32-build54` — V2 spec match (superseded by b55)
- `v0.4.31-build53` — V2 preview + chain fixes (V2 was broken, superseded)
- `v0.4.30-build52` — Chain logging + summary
- `v0.4.29-build51` — Telemetry + UI fixes
- `v0.4.28-build50` — Chain routing fix
- `v0.4.27-build49` — Unified flow + HK fix

## Apple's version-component rule

`CFBundleShortVersionString` must be **\u2264 3 components** (e.g. `0.4.32`, not `0.4.32.1`). Use `CFBundleVersion` (build number) for finer granularity.

## Three places to bump on every release

1. `VoltraLive/Info.plist` \u2192 `CFBundleShortVersionString` and `CFBundleVersion`
2. `project.yml` settings block (lines ~64-65): `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`
3. `project.yml` `info.properties` block (lines ~92-93): `CFBundleShortVersionString` and `CFBundleVersion`

Plus `VOLTRAFeatureLabel` in both files. All must agree or signing fails.
