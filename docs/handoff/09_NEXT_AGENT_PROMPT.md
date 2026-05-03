# 09_NEXT_AGENT_PROMPT

> Read this first. Cold-start prompt for the next agent picking
> up VOLTRA Live iOS. Skim, then read the docs in the order at
> the bottom.

## Where things stand (b68 fixed in-tree, awaiting altool ship)

**ACTIVE CYCLE:** b68 / v0.4.41 / build 68 — the single
user-reported bug **B68-01** (demo mode auto-engage regression
caused by B67-01's cold-launch flip) is **fixed and committed**
on `feat/ui-v4-2-claude`. The branch is awaiting
`release.yml dry_run=false` + 5-gate altool verify + TestFlight
surface. Read **`B68_BUG_QUEUE.md`** for the Q&A + close-out
detail, **`docs/WORK_LOG.md`** for the v0.4.41 ship narrative,
and **`04_DECISIONS_AND_CONSTRAINTS.md`** ADR V4-D16 for the
auto-engage contract.

b68 wins (closed):
1. **B68-01** — `LiveCaptureViewV2.toggleHardwareLoad()`
   auto-engages prePair demo when no Voltra is connected, and
   `.onChange` observers on the three connection states
   auto-exit demo when any device pairs mid-session.

### Next-agent action: ship b68

1. Run `gh workflow run release.yml --repo 5frctqwvmn-ship-it/voltra-live-ios --ref feat/ui-v4-2-claude -f dry_run=false`
2. 5-gate altool verify (UPLOAD SUCCEEDED / ≥20s / exit 0 / no
   blocklist markers / Delivery UUID captured).
3. Record ship verification in `docs/WORK_LOG.md`, commit with
   bot identity, push.

## Previous cycle (b67) — SHIPPED to TestFlight

**ACTIVE CYCLE:** b67 / v0.4.40 / build 67 — all 9 user-reported
bugs (Apr 29 2026 batch) are **fixed and committed** on
`feat/ui-v4-2-claude`. The branch is awaiting `release.yml dry_run=false`
+ 5-gate altool verify + TestFlight surface. Read
**`B67_BUG_QUEUE.md`** for the per-bug evidence + close-out commit
IDs, **`docs/WORK_LOG.md`** for the v0.4.40 ship narrative, and
**`04_DECISIONS_AND_CONSTRAINTS.md`** ADRs V4-D13 / V4-D14 / V4-D15
for design rationale.

b67 wins (all closed):
1. **B67-01** — `LoggingHomeView` is unconditional cold-launch surface (no Voltra-pair wall)
2. **B67-02** — footer watermark cleared
3. **B67-03** — wordmark + duplicate identity chrome removed
4. **B67-04+05** — `DualConnectView` + `DualCaptureView` deleted; `UnifiedConnectSheet` is canonical pair flow
5. **B67-06** — single `VoltraUnitHeader` mounts on home / exercise detail / live
6. **B67-07** — `PairingCoordinator.swift` env-object owns all pair gestures
7. **B67-08** — `VoltraAssignmentPanel.swift` deleted; identity chrome lives in `VoltraUnitHeader.swift` only
8. **B67-09** — reserved/skipped (user numbered force-curve as Bug 10)
9. **B67-10** — force-curve = parametric `sin(π·t)` lobes per rep with log-faded history overlay

Lint-gate grep invariants pass post-fix:
```
grep -rni "VL1\|LiveStatusPill\|LeftRightStatusPill\|DeviceStatusStrip\|VoltraWordmark" VoltraLive/Views/ VoltraLive/Logging/Views/
```
zero matches outside of (a) the documentation header inside
`VoltraUnitHeader.swift` listing what was killed and (b) `DebugView`
user copy referring to the iOS app name in Settings → Privacy →
Health.

### Next-agent action: ship b67

1. Run `gh workflow run release.yml --repo 5frctqwvmn-ship-it/voltra-live-ios --ref feat/ui-v4-2-claude -f dry_run=false`
2. 5-gate altool verify (see `09_RELEASE_AND_SIGNING.md`)
3. Confirm TestFlight surface for v0.4.40 / build 67
4. Append `WORK_LOG.md` ship-verification subsection with delivery UUID + duration.

## Where things stand (b66, v0.4.39-build66)

**Last shipped:** v0.4.39-build66 (b66) on branch
`feat/ui-v4-2-claude` — head-to-head with the GPT-5.5 fork
(`voltra-live-ios-gpt-5-5`, do NOT contact). PR is intentionally
unmerged for side-by-side review.

**The big change in b66 (V4.2 reskin):**

1. **VoltraAssignmentPanel.** New top-of-screen panel
   `VL1 ⌚ │ L R ⋏ •• │ SS` with a single mint breathing ring on
   the active pill. Mounted on LoggingHomeView (global scope),
   ExerciseDetailView (per-exercise override), and
   LiveCaptureViewV2 (read-only when a live set is in progress
   per `isLiveSetInProgress` — force > 3 lb).
2. **SupersetSwitcherBanner.** V1 supersetBanner verbatim port
   (commit `e22aaa6`) + breathing-ring delta on the ACTIVE side.
   Mounted on LiveCaptureViewV2 only.
3. **PageBadgeOverlay.** `.pageBadge("<TypeName>")` modifier
   visible bottom-leading on every top-level screen — 9 pt mono,
   faint mint, always shown. Applied to all 15 view structs.
4. **WorkoutVoltraPickerSheet superseded.** File kept on disk
   with a header banner; no live call sites.
5. **Cascade timer cadence T1.** `cascadeArmIdleSec` and
   `cascadeIntervalSec` bumped 2.0 s → 3.0 s in `LoggingStore`.
6. **Bug fixes P1-1 + P1-2 (this build).** TWIN badge overlap
   on 3-digit weights fixed by promoting the badge out of the
   inner weight HStack; rest-timer first-engage view race fixed
   by switching the mount predicate to `session.restActive` and
   publishing `restElapsedSeconds` synchronously inside
   `finalizeSet()` and `tapRestTile()`.

Full V4.2 spec in `03_CURRENT_FEATURE_SPEC.md`. Decisions in
`04_DECISIONS_AND_CONSTRAINTS.md` (entries V4-D1 … V4-D9 +
V4.2 entries). Dual-VOLTRA details in `07_DUAL_VOLTRA.md`.

## Where things stood at b58 (kept for context)

**Last shipped before b66:** v0.4.36-build58 (b58). Tag pushed,
altool verified.


**The big change in b58 (V4):** four spec items in one ship.

1. **Dropset state machine port.** `tapDropTile()` and
   `adjustDropStep()` in `LiveCaptureViewV2.swift` no longer
   manage their own array — they call `LoggingStore`'s existing
   cascade API (`startDropSet(startingLb:pushWeight:)`,
   `bumpCascadeTier()`, `cancelDropSet()`). Nested DROP row
   reads `dropChainPlannedLb` + `previewNextCascade(from:count:)`.
   `dropArmed` is now `logging.dropSetActive`. No more split
   sources of truth.
2. **Tonal-style force curve.** `ForceChartV2.swift` adds an
   ECC/CON dual-band gradient fill **under** the polyline, with
   inline "ECC" / "CON" labels at the phase centroid (when
   `repsAgo == 0`). CHAIN mode mirrors the gradient
   (`.topTrailing → .bottomLeading`). New init params:
   `eccBandActive`, `chainMirrorActive`.
3. **Weight cell single-line fix.** `.lineLimit(1)`,
   `.minimumScaleFactor(0.6)`, fade mask, `.layoutPriority(1)`.
   No more wrap-overlap with the WEIGHT label. TWIN badge sits
   inline next to the number when `twinModeActive`.
4. **Dual-VOLTRA Independent + Twin Mode.** When
   `bothVoltrasConnected`, header swaps to a L/MERGE/R cluster
   (or fused TWIN pill in combined mode). `focusedSlot`
   `@State` drives which side gets writes via
   `focusOverrideAssignment`. Pulley chip greys out (lock icon,
   not hidden) in Twin Mode via `PulleyAndPlatesBarV3`.

Full V4 spec in `03_CURRENT_FEATURE_SPEC.md`. Decisions in
`04_DECISIONS_AND_CONSTRAINTS.md` (entries V4-D1 … V4-D9). Dual-
VOLTRA details in `07_DUAL_VOLTRA.md`.

## Hard rules (do not violate)

1. **Sacred files DO NOT MODIFY:** `VoltraProtocol.swift`,
   `TelemetryExtractor.swift`, `PacketParser.swift`,
   `FrameAssembler.swift`.
2. **5-gate ship verification.** CI green is not enough. Pull
   the run log, confirm altool ≥20s, "UPLOAD COMPLETED
   SUCCESSFULLY" marker, zero ERROR lines.
3. **`gh` CLI for GitHub.** Never use a browser for this repo.
   Bot identity:
   `git -c user.name="VOLTRA Live Bot" -c user.email="bot@voltralive.app"`
4. **`docs/WORK_LOG.md` is append-only.**
5. **No micro-drops.** DROP must always be a multiple of 5 lb.
6. **CHAIN and INV CHAIN are mutually exclusive** at the UI
   layer. Don't try to allow both.
7. **User has no Mac.** All signing is CI-only.
8. **Preserve previous builds.** All 110 commits and 57+ build
   tags are in git history. Dig with `git log --all` and
   `git tag` before asking the user "where is the old code".
9. **Pulley in Twin Mode: grey, don't hide** (V4-D5).
10. **One TestFlight build per V-spec.** Don't split a numbered
    V-release across multiple builds unless the user says so.

## Karpathy method

Before you start, repeat the user's request back to them so
they can confirm you're getting it correct. They will catch
misunderstandings before you waste a build.

## Current open issues (post-b66)

See `06_KNOWN_ISSUES.md`. At b66 ship:

- **KI-1:** 2× pulley snaps ±1 by 2 lb. Cosmetic.
- **KI-3:** V2 dial cleanup (residual references in tests).
- **KI-4:** CI watermark blocking artifact.
- **KI-5:** Dropset ordering verified — leave as-is unless user
  reports regression.
- **KI-6:** Missing `weight-overlap-v3.jpeg` reference (S3 was
  unreachable when user dropped the screenshot link). Recreate
  from local photo if user reposts.
- **KI-10:** Phantom -5 lb weight drop — likely closed by the
  b60-prep arm-only refactor (cherry-picked into b66 as
  `0465b34`); awaiting hardware re-test.
- **KI-11:** Force-curve full spec not yet implemented (P1).

Closed in b66: KI-F10 (cascade timer cadence T1), KI-F11
(3-digit weight + TWIN badge overlap, P1-1), KI-F12 (rest-timer
first-engage view race, P1-2).
Closed in b60-prep (cherry-picked into b66): KI-F7, KI-F8, KI-F9.
Closed in b58: KI-F3, KI-F4.

## Read order for cold start

1. `00_START_HERE.md`
2. `01_PROJECT_OVERVIEW.md`
3. `02_CURRENT_STATE.md` (snapshot — may be stale; cross-check
   `WORK_LOG.md`)
4. `03_CURRENT_FEATURE_SPEC.md` (V4, b58)
5. `04_DECISIONS_AND_CONSTRAINTS.md`
6. `05_BLE_AND_PROTOCOL.md`
7. `06_KNOWN_ISSUES.md`
8. `07_DUAL_VOLTRA.md` (b58 Independent + Twin Mode)
9. `09_RELEASE_AND_SIGNING.md`
10. `docs/WORK_LOG.md` — last 1-2 entries (b57, b58)
11. `research/intensity_metric.md` (open research stub)

## When the user asks for a new feature

1. Repeat the spec back (Karpathy).
2. Ask 1-4 clarifying questions if the spec has holes.
3. Estimate cost class: small / medium / heavy. Mention it.
4. Implement, ship, verify all 5 gates.
5. Append `WORK_LOG.md` entry. Update
   `03_CURRENT_FEATURE_SPEC.md` and
   `04_DECISIONS_AND_CONSTRAINTS.md` if anything decided.

## Where things stand (post-b78, B74-F11 launch-crash hotfix shipped)

**Branch:** `feat/ui-v4-2-claude` (integration). No feature
in flight beyond post-ship QA.

**Last shipped: v0.4.51 / build 78 — "Session Recorder (launch fix)" —
B74-F11 hotfix.** Re-injects `SessionRecorder` env-object directly
on `SessionRecorderToggle()` inside the root `.overlay` closure in
`VoltraLiveApp.swift`. Fixes the b77 launch crash where SwiftUI
raised `EnvironmentObject.error()` because the overlay's content
did not inherit env-objects from the modifier chain. Adds
`VoltraLiveTests/RecorderLaunchSmokeTests.swift` regression test.
PR #12 merged. Tag `v0.4.51-build78` triggered `release.yml` on the
b78 ship commit. KI-13 in `06_KNOWN_ISSUES.md`.

**Prior shipped (PULLED): v0.4.50 / build 77 — "Session Recorder" —
B74-F11.** PR #10 merged via `88a4eaf`. Tag `v0.4.50-build77`.
Pulled from TestFlight due to launch crash on first body
evaluation. Implementation chain remains on `feat/ui-v4-2-claude`
for context.

**Pre-ship verification (PR #10 head, dry_run on `feat/b77-session-recorder`):**
- `build.yml` workflow_dispatch run 25260420548: `success` in
  1m17s. Compile + unsigned IPA artifact.
- `release.yml dry_run=true` workflow_dispatch run 25261426415:
  `success` in 5m21s on code-equivalent head `6ab55b8` (the final
  PR head `fa8e89a` only added a docs-log metadata commit on top
  of `6ab55b8`, so the dry-run signal carries forward).
  `xcodebuild test -only-testing:VoltraLiveTests` passed including
  the 4 new recorder unit-test files (`RecorderBufferTests`,
  `RecorderRedactorTests`, `RecorderExporterTests`,
  `ActionScopeTests`). Signed archive + IPA export green.

**Next-agent action: post-ship QA.** After tag CI completes
successfully and the 5-gate altool verify passes, run the post-build
QA checklist (passes A–G per `SESSION_RECORDER_SPEC.md`
"Verification Contract"): Ubiquity, Lifecycle, Semantic log,
ActionId correlation, Loud guards, Share, HealthKit truthfulness.
Results land in `docs/handoff/QA_LOG.md` (one section per build).
Any "Not working as intended" result becomes a `KI-N` entry in
`docs/handoff/06_KNOWN_ISSUES.md` or a follow-up fix PR per the
spec's Definition of Done.
