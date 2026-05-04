# 02 — Current State

_Last updated: 2026-05-04 (b82 shipped)._

> **Maintenance rule:** this file is overwritten on every ship. The
> append-only history lives in `docs/WORK_LOG.md`. If you're updating
> this file, replace the relevant sections wholesale instead of appending.

## Latest shipped build

**v0.4.52 build 82** — tag `v0.4.52-build82`, uploaded to TestFlight 2026-05-04.
Delivery UUID: `496678a7-ab0b-4a7d-b08a-d1077c315fb7`.
Altool: No errors. Upload confirmed.

Previous: v0.4.51 build 78 (Session Recorder telemetry v2, BLE telemetry working against VOLTRA hardware).

> **Note:** Builds 56–81 shipped between the last doc update and this patch.
> Full history in `docs/WORK_LOG.md` and `git log --tags`.

## Active bugs targeting build 83

- **BUG-A — Inverse Chains always writes `inverse=false`:** The app sends `inverse=false` in the weight-mode config sequence even when the user has selected Inverse Chains mode. This means the device runs normal Chains, not Inverse Chains. Root cause: `inverse` flag is likely UI-only and not carried into the canonical device config / BLE write path. Fix: ensure `isInverseChains` / `chainsType` is part of the canonical device config model and that every weight-mode apply/replay/reconnect path sends `inverse=true` when Inverse Chains is selected.

- **BUG-B — Manual VOLTRA weight changes do not update app UI:** When the user adjusts weight directly on the physical VOLTRA (unsolicited BLE notify frames), the app UI does not reflect the change. The app only updates from app-request confirmation events (`appRequestConfirmed`). Fix: decode unsolicited device-originated parameter notifications for baseWeight (0x86), chainsWeight (0x87), eccentricWeight (0x88), and inverse/mode flag, and promote them into live UI state.

## What works today (as of b82)

- Single-Voltra capture (V1 and V2) — full feature set.
- Dual-Voltra Independent + Combined modes.
- Superset chain with per-instance `assignedVoltra` routing.
- HealthKit HR + active calories streaming with PulseDot freshness indicators.
- Session export with sessionVitalsCard and comparisonCard.
- Markdown export with fixed-width table.
- Session Recorder telemetry collector (BLE event logging, JSON export).
- Workout logging: 4 day-type home tiles, history-sorted exercise picker, live capture with 4s-idle heuristic, auto-popping log sheet, iCloud-backed SwiftData.

## Live capture mode handling matrix

| Scenario | Renders |
|---|---|
| 1 Voltra paired, no chain, V1 chosen | V1 |
| 1 Voltra paired, no chain, V2 chosen | **V2** |
| 1 Voltra paired, chain has ≥1 entry | V1 |
| 2 Voltras paired, Independent | V1 |
| 2 Voltras paired, Combined | V1 |
| 2 Voltras paired, Superset chain | V1 |

## Repository facts

- Default branch: `main`
- Active feature branch: `feat/ui-v4-2-claude`
- CI runner: `macos-26`, Xcode `26.2`
- Bot identity: `git -c user.name="VOLTRA Live Bot" -c user.email="bot@voltralive.app"`
- Bundle ID: `com.voltralive.app`
- Apple Team ID: `588XUZGNNS` (name only — key values are in GitHub secrets)

## Recent tags (last 5)

- `v0.4.52-build82` — current TestFlight build
- `v0.4.51-build78` — Session Recorder telemetry v2
- `v0.4.36-build58` — V4 LiveCapture (tonal force curve, dual-VOLTRA Independent + Twin)
- `v0.4.35-build57` — V4 spec prep
- `v0.4.34-build56` — V2 mods + rest timer + V1 restore

Full tag list: `git tag --sort=-creatordate | head -20`

## Apple version rules

`CFBundleShortVersionString` must be ≤ 3 components (e.g. `0.4.52`, not `0.4.52.1`). Use `CFBundleVersion` (build number) for finer granularity.

## Three places to bump on every release

1. `VoltraLive/Info.plist` → `CFBundleShortVersionString` and `CFBundleVersion`
2. `project.yml` settings block: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`
3. `project.yml` `info.properties` block: `CFBundleShortVersionString` and `CFBundleVersion`

All must agree or signing fails.
