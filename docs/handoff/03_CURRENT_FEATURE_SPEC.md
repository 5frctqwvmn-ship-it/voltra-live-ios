# 03_CURRENT_FEATURE_SPEC

> **Scope.** This doc captures the V4 LiveCaptureView feature spec as
> it stands at the **b58** ship. It is the authoritative description
> of what the screen *does* — not how it's wired internally (that's
> `04_ARCHITECTURE.md`) and not what's planned next (that's
> `03_ROADMAP.md` — note: the 03_ROADMAP file predates this spec doc;
> the two are intentionally separate).
>
> **V4 (b58) summary.** Four user-visible changes on top of V3 (b57):
>
> 1. **Dropsets are time-driven again.** First DROP tap fires an
>    immediate −5 lb drop and starts the b22-era cascade state
>    machine in `LoggingStore`. The b56 finalize-driven
>    `manualDropSequence` path is deprecated.
> 2. **Force chart goes Tonal-style.** Dual-band ECC / CON gradient
>    fill under the curve; CHAIN mirrors the gradient; the most
>    recent rep is annotated with inline ECC / CON kerned captions.
> 3. **Weight cell auto-fits.** Single-line, 60% min font scale,
>    soft right-edge fade so 3-digit + TWIN never overlaps the
>    steppers.
> 4. **Dual-Voltra surfaced in V3 layout.** When both Voltras are
>    paired, the header swaps to `[● L bpm] [⇄ MERGE] [● R bpm]
>    kcal`. Independent mode binds the screen's mod controls to the
>    focused side; Twin (combined) mode mirrors writes to both,
>    fuses the side pills into `[● L+R bpm]`, adds a `TWIN` badge
>    next to the weight number, and **greys (does not hide)** the
>    pulley toggle.

## V4 Live Capture screen — top-to-bottom

### §1. Header strip

- **Leading:** ← End button.
- **Inline:** small "V3" build watermark (kept for visual
  continuity; CI-injected build tag is a still-open known issue).
- **Center:** exercise-name marquee. 5s pause → scroll left → 1s
  pause at end → reset → loop. If name fits, no scroll.
- **Trailing — single Voltra (unchanged from b57):** telemetry
  cluster `[● 118 bpm · 42 kcal]`. The leading dot is the BLE
  connection status (green = connected, amber = scanning/
  connecting, grey = idle, red = disconnected). Tapping the dot
  opens a popover with full BLE state text.
- **Trailing — dual Voltra (NEW in b58):** when MDM reports
  both `.left` and `.right` connected the cluster swaps to a
  unit-selector strip. See §8.
- **No top dial.** The V2 dial is removed entirely.

### §1a. Phase strip OR Dropset Progress Bar OR Rest Timer Bar

> **b60 change vs b58:** the phase strip slot now morphs across
> **three** states (was two). Priority order on conflict: rest >
> dropset > phase.

- **Active set, no DROP arm/engage:** compact phase strip with
  PUSH/PULL/IDLE color band.
- **DROP armed or active (b60, KI-8):** unified
  `dropProgressBar`. Labels: `DROP · ARM` (armed, lift active,
  no countdown yet) → `DROP · IN` (armed, lift idle, 2 s
  countdown to first drop) → `DROP · NEXT` (active cascade,
  2 s tier-to-tier countdown) → `DROP · BOTTOM` (cascade hit
  the 5 lb floor, full bar, no further drops). Sweep tied to
  `nextDropFiresAt` / `dropArmedFiresAt`; reuses the ambient
  2 Hz blink republish.
- **Post-finalize rest:** `RestTimerBarV2` HSL sweep green →
  amber → red over the rest preset, blinks 1 Hz once over
  preset.

### §2. WEIGHT card (the big number)

- Big number shows **effective** weight (device frame ×
  pulleyMultiplier).
- Tap the number to toggle hardware LOAD / UNLOAD.
- Pill in upper-right shows LOADED / UNLOADED.
- **Stepper grid:** −5 / −1 / +1 / +5 (lb). Same shape as all four
  nested mod rows.

### §3. Mod tile row + nested mod rows

Four tiles: ECC, CHAIN, INV CHAIN, DROP. Tapping any tile
arms/disarms the mod. Nested rows expand below the tile row, one
row per armed mod.

**Increment grid (all four):** `−5 / −1 / +1 / +5`. ECC range
5–400, CHAIN/INV CHAIN range 0–300.

**DROP tile (b60 V4 §2 — arm-only, port of b22 / aff322f, KI-9 refactor):**

> **b60 change vs b58:** tap is now arm-only. The cable holds
> the working weight until the lift goes idle for 2 s, then the
> first cascade drop fires automatically. See
> [entities/dropset_state_machine.md](entities/dropset_state_machine.md)
> for the full state diagram.

- **First tap (inactive):** arms the cascade via
  `LoggingStore.armDropSet(startingLb:pushWeight:)`. Captures
  the anchor + writer bridge but DOES NOT touch the cable.
  `dropSetArmed = true`; the unified progress bar shows
  `DROP · ARM`.
- **Lift goes idle (force ≤ 3 lb for ≥ 2 s):** engine engages
  the cascade. `engageArmedDropSet` re-delegates to
  `startDropSet` which fires drop #2 at the current tier and
  starts the recurring 2 s `cascadeTimer` + 10 s no-movement
  watchdog. `dropSetArmed` clears, `dropSetActive` flips on.
  ECC / CHAIN / INV CHAIN flags from the parent set are
  inherited automatically.
- **Tap while armed (not yet engaged):** `cancelArmedDropSet`
  clears arm state with a 1.5 s cooldown. The cable was never
  moved so no device write is needed.
- **Tap while active:** `bumpCascadeTier` rolls 1 → 2 → 3 → 1
  (5 / 10 / 15 lb step). Fires an immediate drop at the new tier
  AND resets the 4-second next-fire fuse.
- **Telemetry-driven:** `forceLb > 3 lb` calls
  `noteTelemetryActivity` which resets BOTH the 4-second fuse
  (so the cable doesn't auto-drop mid-rep) and the 10-second
  no-movement watchdog. 10 seconds of idle finalizes the chain;
  SessionStore line 146 already checks the dropset boundary
  callback BEFORE finalizing to a normal set, so the rest-timer
  hand-off is correct.
- **Long-press (0.5 s):** `cancelDropSet` — restores the anchor
  weight on the device and starts the 1.5 s arm-cooldown so the
  same touch-up doesn't re-arm.
- **Step buttons:** ±1 are greyed (no micro-drops). ±5 cycles
  the tier forward (+5) or backward (−5) by calling
  `bumpCascadeTier` once or twice.
- **Nested DROP row:** shows `head → next` where `head` is the
  last anchored device-frame weight (effective = ×pulley) and
  `next` is the LoggingStore preview at the current tier.
  Floor = 5 lb device (`cascadeAtFloor` flips on; subsequent
  drops are no-ops).
- **DEPRECATED:** the b56 `manualDropSequence` finalize-driven
  path. `dropArmed` now reads `logging.dropSetActive`, NOT the
  manual sequence. The legacy property is left declared so a
  future build can revive it without diff churn.

**Mutual exclusion:** CHAIN and INV CHAIN cannot be armed at the
same time — arming one disarms the other.

### §4. Pulley + Added-plates bar (above the force chart)

Two compact dial controls, sitting directly above the force
chart (same width as the chart):

- **Pulley:** 1× / 2× toggle. Default **1×**. Multiplies the
  effective force the user feels relative to the device cable
  load. UI side multiplies *display*; BLE side does NOT multiply
  (the device sees the device-frame value).
- **Added plates:** integer 0…N, default **1 lb**, increments
  of 1 lb.

**Pulley math (CRITICAL — verified b57):**

- `LoggingStore.pendingPlannedWeightLb` = device frame.
- WEIGHT card big number, force chart Y axis, log storage all
  use `× pulleyMultiplier`.
- BLE write (`pushUpcomingStateToDevice`) does **not** multiply.
- Under 2× pulley, displayed ±1 lb may snap by 2 lb — this is
  documented in `06_KNOWN_ISSUES.md`.

### §5. Force chart (b71 V4-D20 — V1 ForceChartView is canonical)

**Renderer.** `VoltraLive/Views/ForceChartView.swift` (the V1
chart). Mounted by **both** `LiveCaptureView` (V1 screen) and
`LiveCaptureViewV2.forceChartCard` (V2 screen). The b58/b67-10
`ForceChartV2` (parametric `sin(π · t)` half-sine lobes) is
retained on disk for rollback safety but is **no longer mounted
anywhere** — see the SUPERSEDED banner at the top of
`VoltraLive/Logging/Views/V2/ForceChartV2.swift`.

The user's verbatim rationale (2026-04-30): _"the V1
ForceChartView is the one that displays the force curve correctly
in practice. Replace or wrap V2's force panel so LiveCaptureViewV2
uses the V1 ForceChartView behavior/data path."_ This decision
supersedes the b67-10 polyline-vs-sine reasoning captured in ADR
V4-D13. See ADR **V4-D20** in `04_DECISIONS_AND_CONSTRAINTS.md`.

**Inputs.** V2's `forceChartCard` is a thin V1-input adapter that
reproduces the same builder block V1 uses:

- `samples = session.currentSet?.samples ?? session.lastFinalizedSamples`
  — keeps the chart filled through the rest window instead of
  blanking on finalize.
- `peakLb = session.currentSet?.peakLb ?? session.lastFinalizedPeakLb`.
- `forceMultiplier = logging.pulleyMultiplier` — displayed values
  are EFFECTIVE (what the user feels), matching `LoggedSet`
  storage.
- `plannedCeilingLb = ((pendingPlannedWeightLb ?? 0) + upcomingEccLb) × m + (upcomingAddedLoadLb ?? 0)`
  — anchors the y-axis to planned + 15% headroom (or observed
  peak + 15%, whichever is greater); 12-lb floor inside-session.
- Superset secondary trace: when `mdm.hasActiveSupersetChain` is
  true and the active and next chain entries name different
  exercises, the chart pulls the OTHER exercise's most-recent
  finalized force trace from `SessionStore.lastFinalizedByExercise`
  and renders it as a dimmed dashed line behind the primary
  phase-colored trace, with both exercise labels surfaced in the
  legend.

**Rendering.** Phase-colored line segments (pull / return /
transition / idle), Catmull-Rom interpolation, 3-sample moving-
average smoothing pre-multiplied by `forceMultiplier`, X-domain
spans the whole set (no 30-second rolling window). Five horizontal
grid lines (0 / 25 / 50 / 75 / 100 % of ymax) labeled in lb. Peak
label `peak XX.X lb` rendered in the chart header alongside the
legend.

**Chrome ownership.** `ForceChartView` paints its own header,
legend, peak readout, padding, `bgElev` background, border, and
rounded-corner clip. The V2 call site does NOT wrap it in V2-only
card chrome — stacking would produce double headers / double
borders / nested cards. The previous b58 V2 wrapper (`FORCE · 30 S`
sibling header + outer rounded-rect card) was removed in b71.

**Removed in b71 (along with the V2 mount):**

- `LiveCaptureViewV2.computedYAxisMaxLb()` helper — no longer
  needed; V1's chart computes its own y-axis from
  `plannedCeilingLb` + observed peak.
- The V2-only `eccBandActive` / `chainMirrorActive` plumbing into
  the chart — dual-band ECC / CON fill, CHAIN mirrored gradient,
  and inline `ECC` / `CON` centroid labels were features of the
  superseded `ForceChartV2`. They are NOT present in V1's
  `ForceChartView` and are intentionally NOT carried forward; the
  user has accepted V1's rendering as the correct user-facing
  shape.
- The b57/b58 rep-history overlay (8-rep log-decay fade) and the
  1.5 s y-axis rescale ease — same reason. Both lived only in
  `ForceChartV2`.

If any of those features are reintroduced later, the future ADR
must add them to V1's `ForceChartView` (so V1 and V2 stay in
sync), not by re-mounting `ForceChartV2`.

### §6. Rest timer (b57 V3 §6)

First-engage miss is fixed (b57). Idle detector now accepts
`cs.peakLb > 10` alongside `cs.reps > 0` — the very first rep
of the session no longer slips through the arm-check.

### §7. V1 restore section

Bottom of scroll view: logged sets list + bottom-actions row
(End Set, etc.). Pulley + plates were lifted out of this
section in b57 (now lives above the chart per §4).

### §8. Dual-Voltra header + Twin Mode (NEW in b58)

**When the cluster appears.** Only when MDM reports both
`mdm.left.connectionState.isConnected` AND
`mdm.right.connectionState.isConnected`. Single-Voltra sessions
stay on the b57 cluster.

**Independent mode (default after both pair).**

- Layout: `[● L bpm] [⇄ MERGE] [● R bpm] [● kcal]`.
- Each side dot is a tap-target. Tapping focuses that side —
  the screen's mod controls (weight / ECC / CHAIN / INV CHAIN /
  DROP) bind to the focused unit only.
- Focused side: dot tints accent, pill border highlights.
- Routing: `WriterRouter.apply(state, mdm:, assignment:)` is
  called with `DeviceSlotAssignment(slot: focusedSlot)` so writes
  land on exactly one side.

**Twin Mode (combined).**

- `mdm.workoutMode = .combined`. The MERGE button reads
  pressed (accent fill).
- The two side pills fuse into a single `[● L+R bpm]` pill.
- A `TWIN` badge appears inline next to the WEIGHT card big
  number.
- The Pulley toggle is **greyed (NOT removed)** — a lock icon
  appears on the chip and the tap handler is a hard no-op.
- Routing: `assignment` is nil so WriterRouter falls through
  to its `.combined` branch and broadcasts via
  `mdm.applyCombined(state)` (which respects CombinedParity
  rounding for odd totals).
- Cascade writes (drop-set step pushWeight callback) also use
  the focus-aware override, so a drop in Twin mode mirrors to
  both sides.

**MERGE button.**

- Tap toggles `mdm.workoutMode` between `.independent` and
  `.combined`. Renders pressed (accent background, bg-color
  text) only when `twinModeActive`.

## What the screen does **not** have

- ❌ Top dial (removed in V3).
- ❌ Micro-drops (DROP must always be a multiple of 5 lb).
- ❌ Simultaneous CHAIN + INV CHAIN.
- ❌ Hidden pulley in Twin Mode (greyed, never hidden).
- ❌ Per-set L/R weight independence in Twin Mode (mirror only —
  for asymmetric loading the user must switch to Independent).
- ❌ The b56 `manualDropSequence` finalize-driven dropset path
  (deprecated; legacy state field retained for future revival).

## §9. Debug surfaces (NEW in b70)

### Page badge

Every screen with `.pageBadge("ScreenName")` renders
`"NN · ScreenName"` at bottom-leading, where `NN` is the 2-digit
ID assigned to that screen by `VoltraLive/Views/PageRegistry.swift`.
Color: `VoltraColor.textFaint`. Font: 9pt monospaced. Always
visible — no debug-build gate (per b66 user ask, retained in b70).
Unknown screen names render `-- · ScreenName` so the badge still
serves its identification purpose; that's the signal to add the
name to the registry.

**Mounting rule (b70 hotfix, V4-D19): containers must not own a
`.pageBadge`.** `PageBadgeOverlay` is implemented as a SwiftUI
`.overlay(alignment: .bottomLeading)`, which **propagates** to
every descendant in the same overlay context (NavigationStack
pushes, plain child views). If a parent container that wraps
other screens mounts a `.pageBadge`, both the parent's and the
child's badges render at the same anchor and visibly overlap as
garbled stacked text. Only **leaf, user-visible screens** may
carry `.pageBadge`. Sheet- and fullScreenCover-presented surfaces
are fine because they get a fresh overlay context. The shipped
b70 binary mounted `.pageBadge("ContentView")` on the root
container; it was removed in the b70 hotfix — see V4-D19 in
`04_DECISIONS_AND_CONSTRAINTS.md`.

### Debug grid overlay

A four-state grid shipped behind `@AppStorage("debugGridMode")`:

- `.off` (default) — invisible; no overlay rendered.
- `.corners` — four labels at the corners of the safe area:
  `C-TL`, `C-TR`, `C-BL`, `C-BR`.
- `.midlines` — four labels at edge midpoints: `M-T`, `M-R`,
  `M-B`, `M-L`.
- `.full` — corners + midlines + a center label `F-CTR`.

All labels: 9pt monospaced, mint tint, opacity 0.85. Mounted
automatically by the page-badge modifier so any screen with a
page badge participates.

### Toggle gesture

Tapping the bottom-trailing build badge cycles the mode:
`.off` → `.corners` → `.midlines` → `.full` → `.off`. State is
persisted in `@AppStorage("debugGridMode")`. No other UI surface
exposes the toggle.

### Demo Mode toggle (DebugView)

Existing toggle behavior is unchanged from b66 (still labeled
"Demo Mode is active / off", still in the `DEMO MODE` section
of `DebugView`). What changed in b70 is the entry source: the
toggle now derives `.prePair` vs `.postPair` from
`anyDeviceConnected` at tap time so flipping it on with no
Voltra paired starts the synthetic telemetry pump (which was
the user-reported b69 bug). See `04_DECISIONS_AND_CONSTRAINTS.md`
ADR V4-D17 for the connection-aware contract.

### Demo Mode button (LoggingHomeView)

Same connection-aware rule as the Debug toggle. Button stays
visible regardless of pairing — only hidden when demo is
already active. Per V4-D17, no live call site uses
`source: .settingsRestore`; that case is retained in
`DemoEntrySource` for trace-replay compatibility only.
