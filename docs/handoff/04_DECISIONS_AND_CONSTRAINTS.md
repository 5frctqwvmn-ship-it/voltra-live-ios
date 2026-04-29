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
