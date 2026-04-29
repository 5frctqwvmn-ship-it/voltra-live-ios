# 04_DECISIONS_AND_CONSTRAINTS

> Append-only record of design decisions and constraints. New
> entries go at the bottom. Each decision lists the build it
> landed in, the question it answers, the chosen path, and the
> rejected alternatives.

## D1 (b57) — DROP off-state collapses tile entirely

**Q.** When the user taps an armed DROP tile to disarm, do we
keep the nested row visible (with state cleared) or collapse
the row entirely?

**Decision.** Collapse the nested row entirely. The DROP tile
goes back to its un-armed visual state. `manualDropSequence` is
set to `nil`.

**Why.** Symmetry with ECC/CHAIN/INV CHAIN: when those mods are
disarmed, their nested rows disappear. DROP should match.

**Rejected.**
- Keep nested row with greyed values — felt inconsistent and
  led to confusion in V2 user testing.

## D2 (b57) — Logarithmic fade for rep history overlay

**Q.** What fade curve for the historical reps drawn behind the
live force curve?

**Decision.** Logarithmic. `opacity = max(0.10, 1/(1+ln(repsAgo+1)))`,
hard cap at 8 visible reps.

**Why.** Most recent rep stays bold (opacity ~1.0); the next 2-3
reps remain clearly visible (~0.6, 0.5, 0.4); older reps fade
softly without disappearing. Linear fade made rep 2 already
feel washed out; exponential made rep 8 invisible.

**Rejected.**
- Linear `1.0 - repsAgo/8`.
- Exponential `0.5^repsAgo`.

## D3 (b57) — Pulley doubling logic ported from git history

**Q.** Source for the pulley-multiplier doubling logic.

**Decision.** Ported from commits `8a980d6` and `ec71bcc` (b51-era).

**Why.** That logic was correct for the displayed-vs-device
distinction. b56 introduced a regression (multiplied on BLE
write side). b57 restores the b51 split.

**Constraint.** `pendingPlannedWeightLb` is device frame.
Display = device × multiplier. BLE write = device (no
multiplication). See `03_CURRENT_FEATURE_SPEC.md` §4 and
`06_KNOWN_ISSUES.md` for the 2× snap edge case.

## D4 (b57) — Status reveal on tap, not hover/long-press

**Q.** How does the user surface full BLE state from the small
header status dot?

**Decision.** Tap the dot opens a SwiftUI `.popover` with the
full state string ("Connected to VOLTRA-A1B2", "Scanning…",
etc.).

**Why.** iOS has no hover; long-press conflicts with VoiceOver
and feels hidden. Tap-to-popover is discoverable.

**Rejected.**
- Always-on text label (eats horizontal space, defeats the
  point of the V3 cleanup).
- Long-press.

## C1 (carryover, b50+) — Sacred files DO NOT MODIFY

`VoltraProtocol.swift`, `TelemetryExtractor.swift`,
`PacketParser.swift`, `FrameAssembler.swift`. Any change here
requires firmware-side coordination.

## C2 (carryover) — User has no Mac

All signing is browser-only / CI. We do not run xcodebuild,
xcrun, altool, or fastlane on the user's machine.

## C3 (carryover) — 5-gate ship verification

Every TestFlight ship must verify all five:

1. Release workflow returns success.
2. Run log is pulled to `/tmp/release_log_<build>.txt`.
3. altool step duration ≥ 20s.
4. "UPLOAD COMPLETED SUCCESSFULLY" marker appears in the log.
5. Zero ERROR lines in the log.

CI green alone is not enough.

## C4 (carryover) — Append-only WORK_LOG

`docs/WORK_LOG.md` is append-only. Never edit prior entries.
New build entry goes at the bottom.

## C5 (carryover) — `keep features separate bills`

The user pays per build. Keep features small and shippable so
they can correlate cost to feature; never bundle unrelated work
into one build unless the user requests it.

---

## V4 (b58) decision log

### V4-D1 — Dropsets are state-machine ports, not redesigns

**Decided.** Re-use `LoggingStore.startDropSet` / `bumpCascadeTier` /
`cancelDropSet` verbatim from the b22–b25 commits (introduced in
`0d513e4`, hardened in `ec71bcc` / `8a980d6` / `aff322f`). The
LoggingStore code is already mature — full time-driven cascade
with anchor-relative math, 4 s next-fire fuse, 10 s no-movement
watchdog, floor clamp at 5 lb device, combined-mode parity
rounding. The V3 bug was that LiveCaptureViewV2 never called
`startDropSet`; it routed through `manualDropSequence` which is
finalize-driven (queues weight for next set start) and never
actually drops the cable mid-set.

**Rejected.** A re-implementation in the view layer. Would
duplicate the 200+ lines of state-machine code and re-introduce
bugs we already fixed in b22–b25.

### V4-D2 — Tonal + Beyond Power as canonical reference apps

**Decided.** When the spec is ambiguous, behave like Tonal for
force-curve visuals and like Beyond Power for the L / R + Twin
mental model. Specifically: dual-band ECC / CON fill (Tonal),
side-pill + MERGE button (Beyond Power).

### V4-D3 — Force curve uses dual-band gradient, not stacked bars

**Decided.** Fill UNDER the rep polyline with a gradient,
phase-segmented. Eccentric gets a stronger fill (top-α ≈ 0.55),
concentric gets a thinner band (top-α ≈ 0.22). Idle segments
don't fill. This reads as a Tonal-style "rep map" without
introducing a second chart type or losing the existing rep-
history overlay.

**Rejected.** Stacked bars (loses the rep-shape signal that the
phase-segmented polyline already gives us).

### V4-D4 — CHAIN mirrors the gradient; INV CHAIN does not

**Decided.** Engage CHAIN → flip the gradient direction
(`.topTrailing → .bottomLeading`) so the heaviest visual weight
sits at top of ROM. INV CHAIN keeps the standard direction
because the thru-ROM offset is already encoded in the polyline
shape (the curve dips at mid-ROM); doubling the visual
communication would over-emphasize a single mod.

### V4-D5 — DROP step clamps to multiples of 5 lb (no micro-drops)

**Decided.** ±1 in the DROP stepper is a hard no-op (greyed via
`dropMode: true`). ±5 cycles the cascade tier (1 → 2 → 3 → 1,
mapping to 5 / 10 / 15 lb step). Justifies the unique tile
treatment and matches the user's stated mental model that
"a drop is meaningful only at 5 lb granularity."

**Rejected.** Free-form micro-drops. Would re-introduce the b56
`manualDropSequence` path and bury the cascade behavior.

### V4-D6 — Pulley is GREYED in Twin Mode, never hidden

**Decided.** When `mdm.workoutMode == .combined` and both Voltras
are connected, the pulley chip stays visible but `disabled =
true`. A small `lock.fill` SF symbol appears inline so the
disabled state is unambiguous. Tap is a hard no-op.

**Rejected.** Hiding the chip. Hiding hides current state — the
user can still SEE that pulley = 1× / 2× even though they can't
edit it. Discoverability beats minimalism here.

### V4-D7 — Twin Mode mirrors writes via `mdm.applyCombined`

**Decided.** In Twin (combined) mode the screen passes
`assignment: nil` to `WriterRouter.apply`, which routes through
the existing `.combined` branch and calls `mdm.applyCombined(state)`
— preserving CombinedParity's odd-total rounding (e.g. 101 →
51 / 50, never 50.5 / 50.5). No new write path; we re-use the
existing dual-Voltra plumbing.

### V4-D8 — Independent + dual-connected = focus-bound writes

**Decided.** When both Voltras are connected and `workoutMode ==
.independent`, the screen overrides the per-instance assignment
with `DeviceSlotAssignment(slot: focusedSlot)` so the user's
mod edits land on exactly the side they're looking at. Tapping
the OTHER side dot just changes focus — no write fires until the
next mod edit. This is intentional: switching focus shouldn't
itself send a state change to the silent side.

### V4-D9 — Weight cell auto-fits via fade mask, not ellipsis

**Decided.** `.minimumScaleFactor(0.6)` + `.lineLimit(1)` plus a
linear-gradient mask (full opacity 0–92%, fade to 0 at the
trailing edge) so a value like `4xx TWIN` softens off-screen
instead of dead-stopping on `…`. Steppers get a hard-min
4-pt spacer so they never abut the number.

**Rejected.** Two-line wrap (kills vertical rhythm of the WEIGHT
card). Unbounded shrink (3-digit + TWIN at scaleFactor 0.4 is
unreadable in a glance).

### V4-D10 (b60-prep, KI-9) — DROP tap is arm-only; engine engages on lift-idle

**Q.** When the user taps the DROP tile, should the cable
weight drop immediately or wait until they finish the rep?

**Decided.** Wait. Tap captures the anchor + writer bridge and
sets `dropSetArmed = true`. The cable holds the working weight
until `noteTelemetryActivity` observes 2 s of sub-floor force
(`forceLb ≤ 3 lb`) since the LAST above-floor sample, then
`engageArmedDropSet` re-delegates to `startDropSet` and the
cascade engages. The `armDropSet` / `engageArmedDropSet` split
keeps the existing snapshot / parity / floor logic in one
place (still `startDropSet`) while changing the public surface
the V2 view talks to.

**Why.** Pre-b60 the DROP tile was effectively a "drop weight
NOW" button — tapping it mid-rep yanked the cable on the user.
Mirroring the gym mental model ("finish the rep, then the
weight drops") restores the dropset metaphor and removes the
incentive to tap DROP only after the lift is already idle. Side
benefit: the only path that engages the cascade now requires
explicit arm + 2 s sub-floor gate, which closes the most
plausible cause of KI-10 (phantom −5 lb mid-rep drop).

**Rejected.**
- Keep tap-fires-immediately + add a "delay arm" toggle. Two
  failure modes for one feature; user must remember to arm
  the toggle.
- Tap = arm + IMMEDIATELY drop on the FIRST sub-floor sample
  (no 2 s gate). Machine jitter and rest periods between reps
  would fire spuriously. The 2 s gate matches `cascadeIntervalSec`
  so arm-to-fire and tier-to-tier feel like the same beat.

### V4-D11 (b60-prep, KI-8) — Single bar across idle / dropset / rest

**Q.** Should the dropset progress timing get its own bar
component, or share the existing rest-timer bar?

**Decided.** Share. `LiveCaptureViewV2.phaseOrRestBar` is now
the single sub-header bar slot, with a 3-state morph (priority:
rest > dropset > phase). The dropset state renders a new
private `dropProgressBar` view that mirrors the rest bar's
geometry (4 pt capsule, kerned 9 pt label + monospaced
countdown) but uses `VoltraColor.accent` instead of the HSL
sweep. The new view drives off `nextDropFiresAt` (active) or
`dropArmedFiresAt` (armed); the ambient 2 Hz `blinkOn`
republish provides the redraw cadence.

**Why.** Bar contention is impossible because the three states
are mutually exclusive (you can only be in rest after a
finalize, only in dropset after arming, only in phase
otherwise). Sharing the slot keeps the screen's vertical
rhythm constant — pre-b60 the dropset state had no visual
surface and the user had to infer timing from weight changes
alone.

**Rejected.**
- Standalone `DropProgressBarV2.swift` file. Adds a file just
  to render a Capsule + GeometryReader; the b60 dropProgressBar
  computed-var approach inlines into the V2 view without
  cross-file plumbing.
- HSL sweep matching the rest bar. The rest bar's color carries
  semantic meaning (green = early, red = late); the dropset
  bar doesn't have an analogous "late" state, so a flat accent
  fill is more honest about what the bar communicates.

### V4-D12 (b60-prep, KI-11) — Force-curve full spec compromises

**Q.** Three §-level compromises were made when porting the full
`force_curve.md` spec into `ForceChartV2.swift`. Document them
so the next session doesn't re-litigate.

**Decided.**
1. **§3b 200 ms phase blend = stroke-side dot, not fill-side
   alpha-tween.** Filled-polygon alpha blends across two
   gradients don't survive opacity multiplication well in SwiftUI
   (the under-fill from the next phase shows through and the
   color stops shift). A 5 px dot in the closing segment's color
   at 35% alpha gives the eye a soft handoff with one Path call
   per boundary, no z-order surgery, no custom blend mode.
2. **§3d gradient is 3-stop (0.0 / 0.55 / 1.0), not a true
   ROM-position function.** A faithful ROM-position encoding
   would require per-sample ROM phase metadata that today's
   `ForceSample` doesn't carry. The 3-stop band reads as "heavy
   middle" rather than "uniform ramp" and combined with the
   existing CHAIN endpoint flip is enough to communicate ECC =
   hot low, CHAIN = hot high without a data-model change.
3. **§3g INV CHAIN drives the legend only, not the fill
   direction.** Same reason as §3d above. Until `ForceSample`
   gets ROM-phase metadata, INV CHAIN can't render a faithful
   gradient direction. Surfacing the mode in the legend is the
   honest middle ground — the user knows the mode is on without
   the chart lying about how the load distributes.

**Why.** All three compromises trade visual fidelity for
implementation cost without breaking the user's mental model.
The legend chip + per-rep peak labels + 80% reference line carry
most of the Tonal-parity weight; the fill-side gradient nuance
is a polish layer that can be revisited when `ForceSample` is
ever rev'd.

**Rejected.**
- Adding `romPhase: ROMPhase` to `ForceSample` for this pass.
  Touching the telemetry data model for a rendering polish is a
  bigger surface than the V4 spec asked for and risks a sacred-
  protocol-adjacent regression. Defer to a dedicated RFC.
- Shipping §3b as a custom `BlendMode` overlay. Adds two
  z-layers per rep × per phase boundary; the savings on visual
  smoothness don't pay for the per-frame cost on long sets.
