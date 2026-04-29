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

### V4.2-D1 (b66) — Top-of-screen VoltraAssignmentPanel mirror rule

**Q.** When the user changes the L/R/MERGE/TWIN selection from
inside an exercise context (LiveCaptureViewV2 or
ExerciseDetailView), should that change scope globally
(MultiDeviceManager.workoutMode) or only to the current
exercise?

**Decided.** Per-exercise override (mirror rule 1A). Selections
made inside an exercise context write into
`MultiDeviceManager.exerciseAssignmentOverride[exerciseName]`
(side-store via static dict keyed by ObjectIdentifier — Swift
extensions cannot add stored properties). Selections made on
LoggingHomeView write to the global `workoutMode`. The panel
reads from the override first, falls back to the global.

**Why.** A user supersetting Bench + Row may want TWIN on Bench
(both Voltras pulling on one bar) and L-only on Row (alternating
arms). Forcing one global selection forces a re-tap every time
they switch. Override scoping is invisible when the user only
ever uses one assignment.

**Rejected.**
- Always-global. Fails the superset use case.
- Per-set scope. Too granular; the user never asked for this and
  the bookkeeping (which set "owns" an override) explodes.

### V4.2-D2 (b66) — VoltraAssignmentPanel lock during live set

**Q.** Should the panel allow assignment changes while a set is
in progress?

**Decided.** No (lock rule 2A). The panel renders read-only
when `isLiveSetInProgress == true`, defined as
`ble.telemetry.forceLb > 3.0` (mirrors private
`LoggingStore.cascadeIdleForceFloorLb`). Pills become
non-interactive and a faint lock affordance appears in the
header. The panel re-enables the moment force drops below
3 lb (between sets).

**Why.** Switching L→R mid-rep would flip which Voltra is
receiving writes mid-set and shift the cable load instantly.
Hardware safety risk. Locking by force-floor is honest to the
"is the user actually pulling the cable right now" question
without coupling to set state machinery.

**Rejected.**
- Lock by `currentSet != nil`. Locks the panel during the
  4-second idle grace window, when the user is between sets
  and might reasonably want to switch.
- Lock by `dropSetActive`. Doesn't cover the normal case (a
  non-dropset set in progress).

### V4.2-D3 (b66, P1-1) — TWIN badge promoted out of inner weight HStack

**Q.** When the WEIGHT card shows a 3-digit weight (≥100 lb)
plus the TWIN badge, the badge overlapped the `lb` suffix.
Where should the badge live in the layout?

**Decided.** Outer HStack as a fixed-size sibling between the
weight cluster and the stepper spacer. The weight Text wraps in
a leading-aligned flexible frame so it owns its slot; the `lb`
suffix gets `.layoutPriority(2)` + `.fixedSize()` so 3-digit
values can never push the badge into overlap.

**Why.** The b58 fix (V4-D9) added `.minimumScaleFactor(0.6)`
+ trailing-mask gradient on the weight number, which solved
the stepper overlap but didn't account for the TWIN badge that
b58 placed inside the same inner HStack. Promoting the badge
to a sibling decouples it from the auto-shrink behavior.

**Rejected.**
- Shrink the badge with `.minimumScaleFactor`. Badge reads as
  small text and looks broken at fractional scales.
- Hide the badge above 99 lb. User explicitly asked to keep
  it visible; assignment context is more important than a
  perfectly-tight layout.

### V4.2-D4 (b66, P1-2) — Rest-timer mount predicate keys on restActive

**Q.** The view-side mount predicate for the rest bar was
`Int(session.restElapsedSeconds.rounded()) > 0`, but
`restElapsedSeconds` is updated only by the 0.25 s ticker.
On the very first set finalize after launch, the bar silently
failed to mount. Where should the synchronization point live?

**Decided.** Two-sided fix:
1. `SessionStore.finalizeSet()` now publishes
   `restElapsedSeconds` synchronously (computed against
   `Date()` so the −2 s backdate is honored).
2. `LiveCaptureViewV2.phaseOrRestBar` predicate keys on
   `session.restActive` (set synchronously inside both
   `finalizeSet()` and `tapRestTile()`) instead of rounded
   elapsed seconds.

**Why.** The fix could have been done on either side alone, but
both serve different needs: (1) ensures the displayed elapsed
value is correct on the first frame; (2) ensures mount/unmount
honor intent rather than a sampled-clock proxy. Distinct from
KI-F1 (b57), which fixed the engagement-detection side in
`SessionStore.handleLiveSample`.

**Rejected.**
- Fire the rest bar on a 0.001 s nudge to elapsed seconds.
  Brittle: `Int(0.001.rounded()) == 0` so the predicate still
  fails. Switching the predicate is the honest fix.
- Move the publisher to a 0.0 s tick. Doesn't solve the race;
  the publisher's first run is still on the next run-loop turn.

### V4-D13 (b67, Bug 10) — Force-curve geometry: parametric per-rep sine

**Q.** The b58–b66 force-curve traced raw sensor samples as a
phase-segmented polyline. User feedback: reps look blocky/spiky
and "bleed into one continuous trace." How should rep shapes be
rendered on `LiveWorkoutScreen` (`LiveCaptureViewV2` →
`ForceChartV2`)?

**Decided.** Each rep is rendered as **two half-sine lobes**:
- Concentric (`pull`)  : `sin(π · t)` over `[0, splitT]`,
                          peaking at the rep's measured concentric
                          peak force.
- Eccentric (`return`) : `sin(π · t)` over `[splitT, 1]`,
                          peaking at the rep's measured eccentric
                          peak force.

`splitT` is the normalized timestamp of the first `.return` sample
in the rep (so a slow lower vs fast lift still renders correctly).
Both fill (`eccConFill`) and stroke (`repPolyline`) use the SAME
parametric path so they cannot drift. Older reps in the set are
overlaid at log-decay opacity (newest 100% → oldest 15%, cap 8)
exactly as `docs/handoff/design/force_curve.md` §3f requires.

**Why.** The polyline-of-samples approach was honest to telemetry
but visually ambiguous — 80 Hz sample noise dominated the rep
envelope shape, and the user reads the chart for *envelope*, not
microvariance. A parametric shape lets the rep peak and the
ECC-vs-CON asymmetry telegraph at a glance, matching Tonal
parity (`force_curve.md` §3a–§3f). Phase boundary is still
hardware-derived (not a fixed 50/50 guess) so a slow eccentric
genuinely takes more chart-width.

**Rejected.**
- Sample-mean polyline. Smooths the raw-sample noise but
  inherits the bleeding-rep boundary problem and still has
  asymmetric peak-misalignment artifacts.
- Single full-period `sin(2π · t)` per rep. Pretty but maps
  con→peak→ecc→trough; the ecc trough goes BELOW baseline
  which is geometrically wrong for force-vs-time (force is
  non-negative).
- `|sin(π · t)|` of a single half-period. Collapses to a
  single hump, loses the ECC vs CON visual asymmetry that's
  the whole point.

### V4-D14 (b67, Bug 03/06/08) — Single canonical chrome: VoltraUnitHeader

**Q.** Three screens (`WorkoutSelectionScreen` /
`LoggingHomeView`, `ExerciseDetailScreen` /
`ExerciseDetailView`, `LiveWorkoutScreen` / `LiveCaptureViewV2`)
each rendered their own VOLTRA wordmark + L/R status pill +
HR pill + LIVE/IDLE/WAIT chip. Diverged copy, diverged colors,
duplicated state. What replaces them?

**Decided.** One file: `VoltraLive/Views/VoltraUnitHeader.swift`.
Owns L/R/⋏/●● mode pills + 3-state HR pill (dark/blink/solid).
Mounted at all 3 screens with the same call signature; per-screen
behavior controlled by two props:
- `exerciseName: String?` — `nil` means "writes
  `mdm.workoutMode` (default for the day)"; non-nil means
  "writes `mdm.exerciseAssignmentOverride[name]` (per-exercise
  override)". Mirror rule 1A.
- `isReadOnly: Bool` — locks every pill mid-set. Mirror rule 2A.

**Removed entirely:** VOLTRA wordmark text + bolt icon,
"Live" word, telemetryPulsePill (LIVE/IDLE/WAIT chip),
connectionPill (Left ● Right ●), and the `VoltraAssignmentPanel`
file's duplicate `VL1 ⌚ │ … │ SS` strip.

**Why.** The user's evidence (Bugs 03/06/08) showed the same
identity chrome rendered 2–3 times on a single screen — wordmark
in nav, wordmark in panel, dot status in two places. Single
canonical surface is the only fix that scales as we add more
screens later (Settings, History, Onboarding).

**Rejected.**
- Keep the wordmark, just dedupe the pills. User explicitly
  said the wordmark is also redundant — they know what app
  they're in.
- Make the header per-screen with shared sub-views. Doesn't
  prevent future divergence.

### V4-D15 (b67, Bug 07) — Shared PairingCoordinator

**Q.** Pairing was triggered from three places (greyed-pill
tap on home, exercise detail, live screen) and presented from
local `@State showingPairSheet: Bool` on each — with each
screen subscribing independently to
`MultiDeviceManager.scanRequestedSubject`. How should the
gesture be unified?

**Decided.** New file:
`VoltraLive/Coordinators/PairingCoordinator.swift`.
- Owned by `VoltraLiveApp` as `@StateObject`.
- Injected as `@EnvironmentObject` so any screen can call
  `pairing.presentPair(slot:)`.
- `VoltraUnitHeader.onPairRequest` closure is the canonical
  surface from any of the 3 mounts.
- Sheet binding lives at `LoggingHomeView` root so a single
  `UnifiedConnectSheet` presentation backs all three triggers.
- Bridges legacy `MultiDeviceManager.scanRequestedSubject` so
  deep-links / debug menu / hot-reload still surface the sheet
  without per-view subscriptions.

**Why.** Bug 07's hard dependency: once `DualConnectView` is
deleted (Bug 04+05), the only working pairing path today is
gone. Coordinator centralizes both the "what sheet do we show"
and the "how do we show it" decisions, so deletion of legacy
chrome doesn't strand the user mid-flow.

**Rejected.**
- Keep `DualConnectView` alive, just wrap call sites. Doesn't
  remove the duplicate pair UX or the duplicate scanner state.
- Per-screen `@State showingPairSheet`. Status quo; defeats
  the dedupe.
