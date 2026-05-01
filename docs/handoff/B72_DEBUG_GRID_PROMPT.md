# B72 — Debug Grid Overlay upgrade (prompt on disk)

**Status:** IMPLEMENTED in b72. Both design confirmations
received (32 pt base spacing, margin-only quarter labels). Code
in `VoltraLive/Views/DebugGridOverlay.swift` (rewrite),
`BuildBadgeOverlay.swift` (tap handler), `PageBadgeOverlay.swift`
(comment only). ADR V4-D22 logged. Held local pending user push
approval. See `docs/WORK_LOG.md` for the full entry and SHA.

**Scope discipline.** Debug overlay only. No other feature work.
No version bump. No push. No TestFlight ship. No touching
LiveCaptureView, ForceChartView, ForceChartV2, MultiDeviceManager,
chain UI, V1 deprecation, or any non-debug surface.

---

## User request (verbatim)

> Scope: Debug Grid Overlay upgrade. No other feature work. Do
> not touch ship state. Do not version bump. Do not push.
>
> Context:
> The current debug overlay is not a grid. It is a 9-point anchor
> marker set (C-TL, M-T, C-TR, M-L, F-CTR, M-R, C-BL, M-B, etc.)
> placed at hardcoded positions. That is not what I want. Replace
> it with a real spreadsheet-style graph-paper grid with column
> letters and row numbers, and make the existing tap toggle
> progressively increase density over 4 levels.
>
> Desired behavior:
>
> Single toggle target, same tap affordance as today. Cycles
> through 5 states:
>
> State 0 — OFF
> - No overlay at all.
>
> State 1 — BASE GRID (first tap)
> - Full-screen graph-paper grid overlaid on top of the UI.
> - Vertical gridlines every N points.
> - Horizontal gridlines every N points.
> - Choose N so State 1 feels like "graph paper," not dense.
>   Pick a sensible default (e.g., 32pt spacing on iPhone width).
>   Document the chosen value in the ADR + known issues.
> - Column letters across the very top: A, B, C, D, ... wrapping
>   to AA, AB, ... after Z.
> - Row numbers down the far left: 1, 2, 3, ...
> - Labels should sit in a thin margin strip, not overlap screen
>   content edges excessively.
> - Gridlines render at ~30% opacity. Labels slightly higher
>   opacity for legibility.
> - Numbers/letters in a small monospaced font.
>
> State 2 — HALF STEP (second tap)
> - Same grid as State 1 but with one extra gridline halfway
>   between each base gridline, in both axes.
> - Half-step gridlines are visually subordinate to base
>   gridlines (thinner, lower opacity, or dashed).
> - Column/row labels for half-steps use decimal form: between A
>   and B you get A.5. Between 10 and 11 you get 10.5. Keep base
>   labels (A, B, 10, 11) at full weight; decimal labels at
>   reduced weight.
>
> State 3 — QUARTER STEP (third tap)
> - Add quarter-step gridlines between each half-step line.
>   Labels: A.25, A.5, A.75, B, etc. Row equivalent: 10.25, 10.5,
>   10.75, 11, etc.
> - Quarter-step lines are even more subordinate than half-step
>   lines.
> - If full labeling becomes visually cluttered at this density,
>   label every other quarter line OR label only on the margin
>   strip (not inside the screen body). Make a call, document it.
>
> State 4 — MAX GRANULARITY (fourth tap)
> - All of State 3, plus a semantic overlay layer:
>   - Translucent outlines around each major UI region on the
>     current screen (for example: header area, unit-header pill
>     row, tile grid, upcoming-set card, drop-set section,
>     logged-sets list, bottom actions, page badge, build badge).
>   - Each region labeled with its name. Place labels near the
>     top-leading corner of the region OR centered in the region
>     if it fits cleanly. Pick one and be consistent.
>   - Region outlines at ~40% opacity so they read as intrusive
>     but not blocking.
>   - Region names should match the actual Swift view/section
>     identifier used in code (for example: `tileGrid`,
>     `forceChartCard`, `upcomingSetCard`, `dropSetSection`,
>     `loggedSetsSection`, `bottomActions`, `headerPillRow`).
>     When a section has no obvious name, use the nearest
>     enclosing view.
>
> Goal: I should be able to tell you "put the dial in quadrant
> C10, header section" and you know exactly where that is.
>
> Interaction rules:
> - Tap cycles 0 → 1 → 2 → 3 → 4 → 0. No separate buttons per
>   level.
> - Session-persistent, developer/remote only. Same visibility
>   rule as today's overlay.
> - Overlay must not block touch input to the UI underneath it.
>   Use `.allowsHitTesting(false)` on all overlay layers.
> - Overlay must render above everything else, including
>   `BuildBadgeOverlay` and `PageBadgeOverlay`. Margin labels
>   must remain legible over those badges.
> - Must work on every screen that currently shows the page
>   badge. Not just LoggingHomeView.
>
> Rendering requirements:
> - Pure SwiftUI `Canvas` or `Shape` for gridlines — do not spawn
>   a view per line.
> - Labels rendered via `Text` overlay layer, or directly in the
>   Canvas. Whichever performs better.
> - Must not cause noticeable frame drops during normal use.
> - Must respect safe areas: letters/numbers on the margin strip
>   should not sit under the iOS status bar or home indicator.
>
> Files likely to touch:
> - The existing debug overlay component (look for whatever
>   currently draws C-TL / M-T / etc. markers — likely
>   `DebugView.swift` or a `DebugOverlay*.swift` under
>   `VoltraLive/Views/`).
> - `PageBadgeOverlay.swift` or wherever the overlay is mounted
>   globally.
> - New file `VoltraLive/Views/Debug/DebugGridOverlay.swift` if a
>   new component is cleaner than modifying the existing one.
> - Possibly a small enum `DebugGridDensity` with cases `.off,
>   .base, .half, .quarter, .max`.
>
> Docs to update in the SAME commit (Karpathy rule):
> - `docs/WORK_LOG.md`
> - `docs/handoff/03_CURRENT_FEATURE_SPEC.md`
> - `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` — new ADR
> - `docs/handoff/06_KNOWN_ISSUES.md`
> - `docs/handoff/02_CURRENT_STATE.md` (only if behavior is
>   on-by-default in debug builds, otherwise leave alone)
> - `docs/handoff/07_FILE_MAP.md` — register any new file.
>
> Do NOT:
> - Do not ship or version bump.
> - Do not touch LiveCaptureView, ForceChartView, ForceChartV2,
>   MultiDeviceManager, chain UI, V1 deprecation, or any
>   non-debug feature. Debug overlay only.
> - Do not remove the existing overlay before the new one renders
>   correctly. Replace in a single commit only after you have
>   visually validated the new renderer compiles and lays out
>   sanely.
> - Do not change the tap affordance location. Same toggle, same
>   surface, just new behavior.
>
> Before coding:
> 1. Read AGENTS.md and docs/handoff/*.
> 2. Locate the current overlay source of truth (the thing that
>    draws C-TL / M-T / etc. markers). Summarize what it does
>    today and where it is mounted, and confirm you found it
>    before writing code.
> 3. Confirm back to me the chosen base gridline spacing in
>    points and the label strategy for State 3 (full labeling vs.
>    margin-only).
>
> Then implement. Commit as one or two commits:
> - Commit 1: new DebugGridOverlay + wiring, with legacy anchor
>   overlay left in place but unmounted (behind a `// SUPERSEDED`
>   marker for rollback).
> - Commit 2 (optional): doc updates if they didn't fit in
>   Commit 1.
>
> After commits land, post SHAs and a one-paragraph summary of
> what I will see when I tap through states 0 → 4. No push, no
> ship.

---

## Source of truth located (pre-coding step 2)

**Current overlay implementation:**
`VoltraLive/Views/DebugGridOverlay.swift` — draws the 9 anchor
markers (C-TL, C-TR, C-BL, C-BR, M-T, M-R, M-B, M-L, F-CTR) at
hardcoded `.position(x:y:)` coordinates inside a
`GeometryReader`. Modes: `.off`, `.corners`, `.midlines`,
`.full`. Persisted via `@AppStorage("debugGridMode")`. Style:
9pt monospaced, `VoltraColor.textFaint`, opacity 0.85.

**Mount point:** `VoltraLive/Views/PageBadgeOverlay.swift`
applies `.debugGridOverlay()` inside the `.pageBadge(_:)`
modifier, so any of the 13 page-registered screens
(`PageRegistry.swift`) participates automatically.

**Toggle gesture:** `VoltraLive/Views/BuildBadgeOverlay.swift`
chip's `.onTapGesture` cycles `DebugGridMode.next()`. This is
the only UI surface that toggles the grid.

This is exactly what the user described as "not a grid."
Replacement is the work.

## Pending design decisions (asked of user 2026-04-30 ~01:37 UTC)

The user explicitly required these be confirmed before coding
begins. Both questions are sitting in the chat thread; the
agent must wait for explicit answers before writing code.

### Q1 — State 1 base gridline spacing

iPhone portrait widths cluster at 390pt / 393pt / 430pt, so the
column count differs by spacing choice:

| Option | Spacing | Cols on 390pt | Rows on 844pt | Read |
|---|---|---|---|---|
| A | **32pt** | ~12 (A–L) | ~26 | Recommended. Reads as classic graph paper. Spec hints at this value. |
| B | 40pt | ~10 | ~21 | Coarser. Bigger cells; easier to point at columns. |
| C | 24pt | ~16 | ~35 | Denser. State 1 already busy; State 2/3 risk visual overload. |

Agent recommendation: **A (32pt)**.

### Q2 — State 3 quarter-step label strategy

| Option | Behavior | Trade-off |
|---|---|---|
| A | **Margin-only labels** | Quarter labels appear ONLY in the top/left margin strips. Body stays clean; mirrors how a real spreadsheet labels rulers. Recommended. |
| B | Full interior labeling | Every quarter-line gets a label inside the body. Maximum density, very busy. |
| C | Every-other interior | Half-step labels everywhere; quarter-step interior labels only at A.25 / A.75 (skip .5 since it duplicates State 2). Compromise. |

Agent recommendation: **A (margin-only)**.

## Implementation outline (post-confirmation)

1. **New enum** `DebugGridDensity` in
   `VoltraLive/Views/Debug/DebugGridOverlay.swift`:
   `.off, .base, .half, .quarter, .max`. `.next()` cycles
   forward. Replaces `DebugGridMode` (legacy enum kept behind
   `// SUPERSEDED` marker for rollback per user's "do not remove
   the existing overlay before the new one renders correctly"
   rule).
2. **AppStorage key** stays `"debugGridMode"` so existing
   persisted user preference doesn't get orphaned. Migration:
   read legacy values (`off/corners/midlines/full`) and map to
   nearest new value (`off → off`, anything else → `base` —
   user will discover the new behavior on next tap).
3. **Renderer:** SwiftUI `Canvas` for gridlines (single draw
   call, no per-line views). `Text` overlay layer for column
   letters, row numbers, and decimal labels.
4. **Margin strip:** thin top + leading strips (~16pt each),
   inset to respect status bar / home indicator via
   `.safeAreaInset` or geometry math from `proxy.safeAreaInsets`.
5. **State 4 region overlay:** new pluggable mechanism. Each
   page passes a `[DebugRegion]` array via a preference key or
   environment value. When `density == .max`, render translucent
   outlines + labels. **Critical:** do not invent regions for
   screens we haven't instrumented. Start with LoggingHomeView,
   LiveCaptureViewV2, and one or two others; document which
   screens are instrumented in `06_KNOWN_ISSUES.md`.
6. **Hit testing:** `.allowsHitTesting(false)` on every overlay
   layer.
7. **Z-order:** mount the grid overlay AFTER both badge
   overlays in the modifier chain so it renders above.
8. **Tap cycle:** `BuildBadgeOverlay.swift` chip's `onTapGesture`
   updates to use `DebugGridDensity.next()`. No other change to
   the chip layout / position / accessibility.

## Files likely modified

- **NEW** `VoltraLive/Views/Debug/DebugGridOverlay.swift`
  (or `VoltraLive/Views/DebugGridOverlay.swift` rewritten in
  place).
- `VoltraLive/Views/BuildBadgeOverlay.swift` — `onTapGesture`
  cycles new enum.
- `VoltraLive/Views/PageBadgeOverlay.swift` — modifier mount
  order verified, may not need code change.
- (Possibly) per-screen instrumentation for State 4 region
  overlay, in 1-2 high-traffic screens only.

## Docs to update in the same commit

Per user's explicit instruction (Karpathy rule):

- `docs/WORK_LOG.md`
- `docs/handoff/03_CURRENT_FEATURE_SPEC.md` — replace the
  "four-state grid" section with the new 5-state behavior,
  density values, and region naming convention.
- `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` — new ADR
  (next free ID; current top is V4-D21 so this becomes
  **V4-D22**) explaining the 9-anchor → progressive-grid
  replacement.
- `docs/handoff/06_KNOWN_ISSUES.md` — note the visual trade-off
  at State 3/4 (whichever decision was made), and the
  partial-instrumentation status for State 4 regions.
- `docs/handoff/07_FILE_MAP.md` — register the new file.
- `docs/handoff/02_CURRENT_STATE.md` — only if the overlay is
  on-by-default in debug builds, which it is NOT (default
  remains `.off` per user's "session-persistent, developer
  /remote only" requirement).

## Out of scope for this work

- Version bump (no `0.4.45/72` until user explicitly approves).
- Push to origin.
- TestFlight ship.
- Removing the legacy 9-anchor enum/code (kept behind
  `// SUPERSEDED` for one cycle).
- Changing the tap gesture location.
- Touching any non-debug screen behavior.

## Resume instructions for a new agent

If you are picking this up cold:

1. Confirm Q1 + Q2 above are answered in the chat thread (or
   re-ask the user if not).
2. Read AGENTS.md and the current state of the files in
   "Source of truth located" above.
3. Implement per "Implementation outline."
4. Commit with bot identity:
   `git -c user.name="VOLTRA Live Bot"
        -c user.email="bot@voltralive.app" commit -m "..."`
5. Do NOT push. Do NOT version bump. Report SHAs back to user.
