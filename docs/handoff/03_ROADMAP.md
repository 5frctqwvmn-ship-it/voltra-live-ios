# 03 — Roadmap

_Last updated: 2026-05-03 (b77 release dispatched — B74-F11 Session Recorder)._

> **Maintenance rule:** overwritten on every ship. Items that ship move to "Done" with the build number; items that emerge get added to "Next up". History lives in `docs/WORK_LOG.md`.

## Done (recent shipped milestones)

| Build | Tag | Label | Highlights |
|---|---|---|---|
| 77 | v0.4.50-build77 | Session Recorder | B74-F11: local-only AI-readable debug recorder. Hidden 24×24 dot under root overlay (triple-tap build-badge chip to unlock). 10,000-event FIFO actor buffer; `.txt` + `.json` export via `ShareLink` (schemaVersion=1). `SessionRecorder.shared` singleton with `ActionScope` `@TaskLocal UUID` for cause→effect chains. Persists to `Application Support/SessionRecorder/last_session.json` on background. Additive instrumentation: 14 emits in `VoltraBLEManager`, 2 in `VoltraWriter`, 5 emit groups in `MultiDeviceManager`, 6 read-only emit groups in `HealthKitStore`. 9 user-visible silent guards converted to loud `guardTrip`. `.recorderScreen` tags on 13 top-level screens. PR #10 merged via `88a4eaf`. |
| 76 | v0.4.49-build76 | Health signal indicator | B74-F8: replaced legacy dual-dot HR pill in `VoltraUnitHeader` with a single neutral Health signal indicator. Idle = faint but visible pre-HK auth; tap-while-unauthorized → HK consent sheet; live = header text color when HR sample within 10 s freshness window; >10 s stale flips back to faint without app re-foreground. L / R / ⋏ pills unchanged. Release-only ship — implementation already merged at `713a851`. |
| 75 | v0.4.48-build75 | L/R auto-connect | B74-F1: L/R buttons auto-connect to Voltras whose advertised names contain "left"/"right" (case-insensitive). |
| 74 | v0.4.47-build74 | Grid scroll fix v2 | b74 V4-D24 debug grid TRUE content-space layer (PR-only / unverified) + b74 grid scroll-anchor fix. |
| 73 | v0.4.46-build73 | Grid scroll fix | Debug grid scroll-anchor fix (V4-D23). |
| 54 | v0.4.32-build54 | V2 spec match | V2 LiveCaptureView rewritten as 1:1 port of design-system/ui-kit.html. V2 gate tightened to fall back on any chain entry. |
| 53 | v0.4.31-build53 | V2 preview + chain fixes | Per-instance `assignedVoltra` routing, 3-way Left/Right/Both picker, "Superset · {head} · HR · {day}" header, no SWAP auto-LOAD, session vitals + comparison cards, EXERCISES count fix, markdown export fixed-width. V2 itself was wrong, hotfixed in b54. |
| 52 | v0.4.30-build52 | Chain logging + summary | Chain logging foundations, multi-card export, totals + vitals lines. |
| 51 | v0.4.29-build51 | Telemetry + UI fixes | Telemetry wiring + assorted UI fixes. |
| 50 | v0.4.28-build50 | Chain routing fix | First chain routing pass (superseded by b53's per-instance approach). |
| 49 | v0.4.27-build49 | Unified flow + HK fix | Unified add-exercise flow + HealthKit query fix. |

For anything pre-b49, read `docs/WORK_LOG.md`.

## Next up (no build number assigned yet)

Order is rough priority, not commitment.

1. **Settings toggle for V1/V2.** Currently the first-launch picker is the only way to choose. Add a Settings row (or long-press on the V2 pill) to switch back. Cost: lite.
2. **V2 polish based on actual user testing.** b54 ships the spec-match. Next round depends on what the user reports after using V2 for real sessions \u2014 likely candidates: tile sizing on smaller iPhones, CompareStrip when no prior data exists, force chart empty state.
3. **Expire b53 in App Store Connect.** b53 is a known-bad TestFlight build. Pulling it prevents testers installing the wrong version. Ask the user before doing this; needs ASC access.
4. **Document SWAP no-auto-LOAD in user-facing release note.** The b53 behavior change means the user must manually tap LOAD after SWAP. Mention this somewhere visible.
5. **Verify session HR rollups are landing.** b53 added async HK snapshot in `endSession`. Confirm `avgHRSession` / `kcalSession` actually populate post-session by checking a real export.

## Parking lot

- **CloudKit sync re-enablement.** See `09_RELEASE_AND_SIGNING.md`. Wait until the fresh store has been stable across more releases.
- **Old-store import.** Build 29 abandoned the legacy SwiftData store. If the user wants old logs back, add a one-shot importer. Confirm with user first.
- **Apple Watch companion (v1.2).** Strategy: separate Xcode project, not a Watch target in the same project.
- **`altool` \u2192 `notarytool` migration.** Apple deprecating altool; migrate before removal.
- **Drop-set support in V2.** Currently V2 has no cascade UI. Either keep V2 single-Voltra-no-cascade or add it later.
- **Dual-Voltra in V2.** Currently V2 always falls back to V1 when both Voltras pair. If V2 becomes the default, this needs answering.

## Ordering rationale

V2 is now in user-test mode. Until the user reports back on real sessions, do not pile more V2 features in \u2014 wait for signal. Chain bugs were the higher-priority fix (they affected V1, the production path) and are landed in b53. Parking-lot items are large, isolated, and should wait until V2 is either promoted or rolled back.
