# 09_NEXT_AGENT_PROMPT

> Read this first. Cold-start prompt for the next agent picking
> up VOLTRA Live iOS. Skim, then read the docs in the order at
> the bottom.

## Where things stand (b57, v0.4.35-build57)

**Last shipped:** v0.4.35-build57 (b57). Tag pushed, altool
verified. See `docs/WORK_LOG.md` for the build entry.

**The big change in b57:** V3 LiveCaptureView. Header redesigned
(no top dial, V3 watermark, marquee, status-dot popover); force
chart got dynamic Y-axis + rep-history overlay; DROP became a
tap-to-toggle; pulley + plates relocated above the chart; the
BLE math bug from b56 is fixed. Full spec in
`03_CURRENT_FEATURE_SPEC.md`.

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

## Karpathy method

Before you start, repeat the user's request back to them so
they can confirm you're getting it correct. They will catch
misunderstandings before you waste a build.

## Current open issues

See `06_KNOWN_ISSUES.md`. Two items at b57 ship:

- **KI-1:** 2× pulley snaps ±1 by 2 lb. Documented.
- **KI-2:** DROP idle auto-fire is intentionally a no-op slot.

## Read order for cold start

1. `00_START_HERE.md`
2. `01_PROJECT_OVERVIEW.md`
3. `02_CURRENT_STATE.md` (snapshot — may be stale; cross-check
   `WORK_LOG.md`)
4. `03_CURRENT_FEATURE_SPEC.md` (V3, b57)
5. `04_DECISIONS_AND_CONSTRAINTS.md`
6. `05_BLE_AND_PROTOCOL.md`
7. `06_KNOWN_ISSUES.md`
8. `09_RELEASE_AND_SIGNING.md`
9. `docs/WORK_LOG.md` — last 1-2 entries
10. `research/intensity_metric.md` (open research stub)

## When the user asks for a new feature

1. Repeat the spec back (Karpathy).
2. Ask 1-4 clarifying questions if the spec has holes.
3. Estimate cost class: small / medium / heavy. Mention it.
4. Implement, ship, verify all 5 gates.
5. Append `WORK_LOG.md` entry. Update
   `03_CURRENT_FEATURE_SPEC.md` and
   `04_DECISIONS_AND_CONSTRAINTS.md` if anything decided.
