# 09_NEXT_AGENT_PROMPT

> Read this first. Cold-start prompt for the next agent picking
> up VOLTRA Live iOS. Skim, then read the docs in the order at
> the bottom.

## Where things stand (b58, v0.4.36-build58)

**Last shipped:** v0.4.36-build58 (b58). Tag pushed, altool
verified. See `docs/WORK_LOG.md` for the build entry.

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

## Current open issues (post-b58)

See `06_KNOWN_ISSUES.md`. At b58 ship:

- **KI-1:** 2× pulley snaps ±1 by 2 lb. Cosmetic.
- **KI-3:** V2 dial cleanup (residual references in tests).
- **KI-4:** CI watermark blocking artifact.
- **KI-5:** Dropset ordering verified — leave as-is unless user
  reports regression.
- **KI-6:** Missing `weight-overlap-v3.jpeg` reference (S3 was
  unreachable when user dropped the screenshot link). Recreate
  from local photo if user reposts.

Closed in b58: KI-F3 (dropset cascade source-of-truth),
KI-F4 (weight cell wrap-overlap).

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
