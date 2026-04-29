# 02 — Current State

_Last updated: 2026-04-28 (b54 shipped)._

> **Maintenance rule:** this file is overwritten on every ship. The
> append-only history lives in `docs/WORK_LOG.md`. If you're updating
> this file, replace the relevant sections wholesale instead of appending.

## Latest shipped build

**v0.4.32 build 54** — tag `v0.4.32-build54`, run `25082811585`, label "V2 spec match".

Previous: v0.4.31 build 53 ("V2 preview + chain fixes") — shipped but contained a V2 LiveCaptureView that did NOT match the design-studio spec. b54 hotfixed it. b53 should be considered superseded.

## What works today

- Single-Voltra capture (V1) — full feature set including drop-set cascade, weight nudges, added-plates, expanded set rows.
- Single-Voltra capture (V2 preview) — opt-in via first-launch picker, falls back to V1 the moment a chain entry exists or both Voltras pair.
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

V2 is a 1:1 port of `design-system/ui-kit.html` from the `design-studio` branch (HEAD `74d0d3b9`). Layout: header strip \u2192 primary 2x2 grid (REPS / PHASE / FORCE / REST) with phase-tinted wash on PHASE tile \u2192 HR/KCAL secondary pair with 1Hz pulse-dot \u2192 CompareStripView (LAST REPS / BEST FORCE / TARGET) \u2192 force chart card \u2192 plan + 50px LOG SET CTA.

**Before changing V2, re-read `design-system/ui-kit.html` on the design-studio branch.** Do not rely on prose summaries.

## Known issues / not yet built

1. No Settings toggle to switch back from V2 to V1 after picking V2. First-launch picker is the only entry point. Tracked for a future build.
2. V2 has no chain affordances by design. If a user tries to add a second exercise while on V2, the container falls back to V1; V2 itself does nothing chain-aware.
3. b53 (broken V2) is still in TestFlight. Testers may hit it if they install before b54 propagates. Consider expiring the b53 build in App Store Connect.
4. The `swapSupersetSide` no-auto-LOAD behavior changes the user's manual workflow. After a SWAP, they must tap LOAD to arm the new side. Document this in any user-facing release note.

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
- HEAD at last summarization: `eae659f` (b54)
- Working tree: clean post-b54-ship
- CI runner: `macos-26`, Xcode `26.2`, iPhoneOS `26.2.sdk`
- Bot identity for commits: `git -c user.name="VOLTRA Live Bot" -c user.email="bot@voltralive.app"`

## Recent tags

- `v0.4.32-build54` — V2 spec match (current)
- `v0.4.31-build53` — V2 preview + chain fixes (V2 was broken, superseded by b54)
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
