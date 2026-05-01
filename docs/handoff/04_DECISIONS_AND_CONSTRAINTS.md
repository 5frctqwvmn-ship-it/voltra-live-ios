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

> **⚠️ SUPERSEDED 2026-04-30 by ADR V4-D20.** The decision below was
> reverted in b71. V1's `ForceChartView` (raw-sample phase-colored
> polyline + Catmull-Rom smoothing) is now the canonical force-curve
> renderer for both V1 and V2. The b67-10 sine work landed in
> `ForceChartV2.swift`, which is retained on disk for rollback safety
> but is no longer mounted anywhere. The user's verbatim correction:
> _"the V1 ForceChartView is the one that displays the force curve
> correctly in practice."_ See V4-D20 below for the supersede
> rationale and rejected alternatives. The text below is preserved
> verbatim for historical context only — do not implement against it.

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

## V4-D16 — Demo mode auto-engage contract on LiveCaptureViewV2

**Date.** 2026-04-29 (b68 / B68-01).

**Problem.** B67-01 made `LoggingHomeView` the unconditional
cold-launch surface and demoted `ConnectView` to legacy/deeplink
only. `ConnectView`'s `DemoModeButton(source: .prePair)` at
lines 165–168 became unreachable from the root flow, so a
fresh-install user with no Voltra paired had no way to engage
demo mode and the LIVE force chart sat at zero with weights
loaded — a discoverability regression, not a code defect in
b67's chrome work.

**Decided.** Auto-engage `prePair` demo from
`LiveCaptureViewV2.toggleHardwareLoad()`:

- **Trigger (Q1):** any tap on the WEIGHT NUMBER (b56 hardware
  LOAD path) when `!anyDeviceConnected && !demo.isActive`.
  Idempotent — `DemoController.enter` early-returns when
  already active.
- **Telemetry handler.** `DemoTelemetryBridge.shared.handler`,
  identical to the wiring `LoggingHomeView` uses for
  manual-postPair entry.
- **Auto-handoff (Q2):** `.onChange` observers on
  `ble.connectionState`, `mdm.left.connectionState`,
  `mdm.right.connectionState` call `demo.exit()` when
  `entrySource == .prePair && anyDeviceConnected`. postPair
  demo (manually engaged with a device already paired) is
  intentionally untouched — that's a user-explicit demo
  session that should outlive a connection blip.
- **No banner / toast (Q4).** Existing `DemoModeOverlay` is the
  only signal the user gets; matches the current visual
  language for demo state.
- **Manual postPair button stays (Q3).** `LoggingHomeView`'s
  `DemoModeButton(source: .postPair)` is unchanged so users
  with a paired device can still opt into demo intentionally.

**Why.** Hooks the demo trigger into the user's actual intent
(loading weight) rather than into a navigational surface that
no longer exists. The "weight tap with no device connected"
state is a tight, unambiguous signal that the user is trying to
exercise but has nothing driving the chart — exactly the case
demo mode was designed to cover.

**Rejected.**
- *Auto-engage on view appear* (every time the LIVE screen
  mounts). Engages too early, before user intent is clear; would
  fight `ConnectView` deeplinks and re-fire on every navigation
  back-and-forth.
- *First-LOAD-per-session only.* Functionally equivalent given
  `DemoController.enter`'s `guard !isActive else { return }`
  early-return, and adds a session-tracking flag without
  benefit.
- *Persistent banner / toast on auto-engage.* User picked silent
  per Q4 — `DemoModeOverlay` is the canonical signal.
- *Delete `ConnectView` outright in b68 (Q5).* Deferred to a
  later cycle; out of scope for this single-bug fix.

## V4-D17 — Demo entry source must be connection-aware; `.settingsRestore` is legacy

**Date.** 2026-04-30 (b70).

**Problem.** B68-01 (V4-D16) wired auto-engage demo to the
WEIGHT-tap on the live screens. Two other live entry points
were not updated to the same connection-aware contract:

1. `DebugView.swift`'s existing "Demo Mode" toggle (lines
   86–111) called `enter(source: .settingsRestore, …)`. The
   `.settingsRestore` branch of `DemoController.enter` does
   NOT instantiate `SyntheticTelemetryGenerator` (only
   `.prePair` does). With no Voltra paired, the user toggled
   demo on and saw zero force-chart activity — exactly the
   "Demo simulation broken" bug report against b69.

2. `LoggingHomeView.swift:159–167`'s `DemoModeButton` was
   hardcoded to `.postPair`. With no Voltra paired, this
   produced the same dead-pump symptom by the same mechanism.

The b69 ship mishandled both because the architect's earlier
B68-01 patch only touched the V2 LIVE-screen hook, not the
two *other* live demo entry points.

**Decided.** Every **live** call site that calls
`DemoController.enter(...)` MUST select `source` from the
connection state at call time:

```
let source: DemoEntrySource = anyDeviceConnected ? .postPair : .prePair
demo.enter(source: source, onTelemetry: handler)
```

`anyDeviceConnected` evaluates to:

```
ble.connectionState.isConnected
  || mdm.left.connectionState.isConnected
  || mdm.right.connectionState.isConnected
```

The `.settingsRestore` enum case is **retained** but is now
formally legacy:

- Live UI MUST NOT pass `source: .settingsRestore`.
- It survives as an enum case ONLY so existing
  `DemoTraceLogger` traces (recorded by previous builds) stay
  decodable and replayable. Trace fixtures in `docs/handoff/`
  reference it.
- Lint-gate: `rg "source:\s*\.settingsRestore" VoltraLive`
  must report 0 hits in any file under `VoltraLive/`.
- Cold-launch rehydration uses `.prePair` (see "Rehydration"
  below), NOT `.settingsRestore`, because the rehydrated
  session needs the synthetic pump just like any other
  no-device-connected demo.

**Self-heal contract (DemoController.swift).** `enter(...)`
gains a self-heal branch BEFORE the `guard !isActive` line:

```
if isActive && synthetic == nil && entrySource == .prePair {
    startSynthetic(onTelemetry: onTelemetry, logger: trace)
}
```

Critical: this branch reads `entrySource` (the controller's
own published source-of-truth) NOT the incoming `source`
parameter. The reasoning is that a re-entry call may pass
`.postPair` (because the caller now sees a connection) while
the *original* session was `.prePair` — we must not flip the
pump's intent based on a transient call. The pump's lifecycle
is owned by the original entry; self-heal just rebuilds it if
something nuked the reference.

**Rehydration (VoltraLiveApp.swift).** On cold launch, if
`demo.settingsToggleOn == true` and `demo.isActive == false`,
call `demo.enter(source: .prePair, onTelemetry: telemetryHandler)`.
This is the case the legacy `.settingsRestore` *intent* was
meant to cover ("user backgrounded the app while in demo;
restore demo on relaunch"). Expressing it via `.prePair`
guarantees the pump exists.

**Auto-handoff observers (ContentView root).** Mirror V4-D16
at root scope — `.onChange` on
`bleManager.connectionState`, `mdm.left.connectionState`,
`mdm.right.connectionState`. Call `demo.exit()` when
`demo.entrySource == .prePair && anyDeviceConnected`. Root
scope ensures the handoff fires regardless of foreground
view, including when the user is in DebugView when the
Voltra connects.

**Why.** Single rule covering all live demo-entry surfaces
collapses the two-bugs-from-the-same-root-cause shape we just
hit (`.settingsRestore` in DebugView, hardcoded `.postPair`
in LoggingHomeView). The self-heal branch on `entrySource`
makes the controller resilient to future caller mistakes
without changing the controller's public contract — callers
that follow the connection-aware rule never trip self-heal;
callers that don't get rescued without the user noticing.

**Rejected.**

- *Delete `.settingsRestore` outright.* Architect explicitly
  said no — would break trace-replay for existing fixtures.
- *Make `.settingsRestore` start synthetic telemetry.* Same
  mechanical effect as `.prePair`, but conflates two distinct
  concepts (entry surface vs. data source) and would make
  the trace-replay parity fixtures meaningless.
- *Use the incoming `source` parameter in self-heal.* Lets a
  late `.postPair` re-entry call kill an active prePair pump.
  Wrong direction.
- *Move auto-handoff observers per-screen.* Misses the
  DebugView case, which was the actual b69 regression
  surface.

## V4-D18 — Page registry + debug grid overlay

**Date.** 2026-04-30 (b70).

**Problem.** The b66 `pageBadge(...)` modifier shows the Swift
type name of the screen at bottom-leading so the user can
reference screens unambiguously in feedback. That's the right
floor of fidelity for the b66 ask, but b70 surfaced a new ask:

1. Pair each screen with a **stable numeric ID** the user can
   reference even faster than typing a type name.
2. Provide a **debug grid overlay** the user can flip on from
   any screen to give precise positional feedback (e.g. "the
   misalignment is between M-T and M-R, closer to C-TR").

**Decided.** Two new files + two edits:

- **NEW `VoltraLive/Views/PageRegistry.swift`.** Static
  `[String: Int]` table mapping every distinct
  `.pageBadge("...")` argument currently in the source tree
  to a 2-digit numeric ID. Built by running
  `rg "\.pageBadge\(" VoltraLive --type swift` and assigning
  IDs in alphabetical order. Future screens added to the
  table get the next available ID — no renumbering.

- **NEW `VoltraLive/Views/DebugGridOverlay.swift`.**
  `DebugGridMode` enum: `.off`, `.corners` (4 C-prefixed
  labels: C-TL / C-TR / C-BL / C-BR), `.midlines` (4
  M-prefixed labels at edge midpoints: M-T / M-R / M-B /
  M-L), `.full` (corners + midlines + an F-CTR center
  label). Monospaced 9pt, mint tint, opacity 0.85.
  ViewModifier `.debugGridOverlay()` reads
  `@AppStorage("debugGridMode")` and renders the matching
  set.

- **Edit `PageBadgeOverlay.swift`.** Render format becomes
  `"NN · ScreenName"`. Lookup falls back to `--` for unknown
  names so the badge still renders. The modifier also calls
  `.debugGridOverlay()` so every screen with a page badge
  automatically gets the grid overlay applied (the grid is
  invisible when `debugGridMode == .off`, which is the
  default).

- **Edit `BuildBadgeOverlay.swift`.** Add a tap gesture that
  cycles `@AppStorage("debugGridMode")` through the four
  `DebugGridMode` cases (off → corners → midlines → full →
  off). Visual chip layout unchanged.

**Why.** Numeric IDs collapse 30-char screen-name verbatim
quoting into a 2-digit reference. Grid overlay collapses
"between the third tile and the fourth tile near the bottom"
into "M-B near C-BL." Both reduce friction in the
user-to-agent feedback loop without adding chrome to the
default visual design (grid stays at `.off` until tapped).
Cycling via the build badge keeps the gesture in a place the
user already looks for and avoids adding a new affordance.

**Rejected.**

- *Number screens in source-order or definition-order.*
  Sensitive to file moves and definition reorder; alphabetical
  is robust and obvious.
- *Hardcode an enum of screens.* Forces a Swift edit on every
  new screen; the dictionary lookup is cheaper to maintain.
- *Put grid-toggle on a separate dev-menu button.* Adds
  chrome and a discoverability problem; tapping the build
  badge is already an "I'm looking at chrome" gesture.

## V4-D19 — Containers must not own `.pageBadge` (b70 hotfix)

**Date.** 2026-04-30 (b70 hotfix, post-ship visual regression
pass on IMG_2438–IMG_2447).

**Problem.** The b70 ship mounted `.pageBadge("ContentView")` on
the root container in `VoltraLive/Views/ContentView.swift:41`.
`PageBadgeOverlay` is implemented as `.overlay(alignment:
.bottomLeading)`, which propagates to every descendant in the
same overlay context. ContentView wraps `LoggingHomeView` (which
owns the app's `NavigationStack`), so the ContentView badge
rendered simultaneously with each pushed child's own badge at the
same anchor. The two text layers stacked at 9pt and read as
garbled "CoggingMomeView" / "CourCoptureCostainer" double-render
in IMG_2438, IMG_2442, IMG_2444, IMG_2445, IMG_2446, IMG_2447.

DebugView was unaffected because LoggingHomeView presents it via
`.sheet(isPresented:)`, which creates a fresh overlay context.
That differential is what isolated the diagnosis to inheritance,
not to PageBadgeOverlay itself.

**Decided.** Removed the single `.pageBadge("ContentView")` call
site. Every navigated child already mounts its own `.pageBadge`,
so no screen lost identification. Replaced the call with a
load-bearing comment explaining the inheritance trap so future
agents don't re-introduce a root or container badge.

**Rule going forward.** Only **leaf, user-visible screens** may
carry `.pageBadge`. Containers (root views, route hosts that wrap
other screens, NavigationStack hosts) must not. Sheets and
`.fullScreenCover` surfaces are leaves — they get fresh overlay
contexts and may carry their own badge.

**Rejected.**

- *PreferenceKey-based suppression in `PageBadgeOverlay` so an
  inner badge wins over an outer one.* More invasive than
  needed; the redundant root call site is the actual defect, and
  removing one line is the smallest correct fix. Keeping
  `PageBadgeOverlay` simple preserves the b70 dual-overlay
  contract.
- *Move the badge to a singleton root-only renderer driven by a
  Preference.* Would require touching every screen and the
  registry. Out of scope for a regression hotfix.

**Sacred files.** Untouched.

**Out of scope.** No changes to `PageBadgeOverlay`,
`BuildBadgeOverlay`, `DebugGridOverlay`, `PageRegistry`, header
pills, the `⋏`/merge glyph (b71), force chart, or any routing
logic. No b71 mode-glyph work. No version bump.

## V4-D20 — V1 `ForceChartView` is canonical for V2 (supersedes V4-D13)

**Date.** 2026-04-30 (b71 cycle, working diff on `feat/ui-v4-2-claude`).

**Status.** Active. **Supersedes ADR V4-D13** (b67, Bug 10 —
parametric per-rep sine lobes). V4-D13's decision text is preserved
verbatim above for historical context but its implementation is no
longer mounted.

**Q.** Which force-chart renderer is canonical for the V2 capture
screen (`LiveCaptureViewV2.forceChartCard`)?

- (A) `ForceChartV2` — the b58 dual-band Tonal-style fill upgraded by
  b67-10 to draw each rep as two parametric `sin(π · t)` half-sine
  lobes computed from the rep's measured per-phase peak force.
- (B) `ForceChartView` — V1's raw-sample phase-colored polyline
  with Catmull-Rom interpolation, 3-sample moving-average smoothing,
  pulley-multiplier-aware effective load, and the b49 superset
  secondary-trace overlay.

**Decided.** **(B).** V1's `ForceChartView` is now mounted directly
from `LiveCaptureViewV2.forceChartCard`. The V2 method is a thin
adapter that reproduces the same input-builder block V1's
`LiveCaptureView.forceChart` uses (sample source, peak source,
pulley multiplier, planned ceiling computed in effective space, and
the `mdm.hasActiveSupersetChain` secondary-trace gate). V2's outer
card chrome (`FORCE · 30 S` sibling header + bordered rounded-rect
wrapper) is removed because `ForceChartView` paints its own header,
legend, peak readout, padding, background, border, and clip.

The V2-only helper `computedYAxisMaxLb()` is removed in the same
commit because V1's chart computes its own y-axis from
`plannedCeilingLb` + observed peak. The V2-only `eccBandActive` /
`chainMirrorActive` plumbing is removed because dual-band ECC / CON
fill, CHAIN gradient mirror, and centroid `ECC` / `CON` labels are
features of the superseded `ForceChartV2` and intentionally are NOT
carried forward.

`ForceChartV2.swift` is retained on disk with a SUPERSEDED banner at
the top of the file. Rollback path: re-mount `ForceChartV2(...)` in
`LiveCaptureViewV2.forceChartCard` and restore `computedYAxisMaxLb()`
from git history at the b71 commit. Deletion requires explicit user
approval.

**Why.** The user's verbatim correction at 2026-04-30 17:25 CDT,
responding to a request to keep V2's sine logic and port the V1
below-chart UI separately:

> _"Correction: I do want the V1 force chart view/logic in V2. The V1
> ForceChartView is the one that displays the force curve correctly
> in practice. Replace or wrap V2's force panel so LiveCaptureViewV2
> uses the V1 ForceChartView behavior/data path. Do not reinterpret
> this as 'preserve ForceChartV2 sine logic.' The accepted user-
> facing behavior is the V1 force chart. If this conflicts with the
> old B67 Bug 10 docs, treat the docs as stale/wrong and update them
> in the same commit."_

The b67-10 reasoning (sample noise dominates the rep envelope, so a
parametric shape would read more cleanly) was a plausible inference
but not what the user actually wanted in practice. The polyline
rendering is what the user has been reading as "the force curve"
for the entire V1 lifetime; replacing it with sine lobes in V2 broke
that continuity, and the parametric abstraction lost information the
user was implicitly using (noise-as-effort-signal, fatigue-as-shape-
decay across raw samples within a rep, not just across reps).

This ADR follows the AGENTS.md directive that user-validated
user-facing behavior outranks design-doc reasoning when the two
conflict.

**Rejected.**

- _Keep `ForceChartV2` for V2 and port only V1's secondary-trace
  overlay (the `secondarySamples` / `primaryLabel` / `secondaryLabel`
  fields) into the sine renderer._ The user explicitly rejected this
  framing: "Do not reinterpret this as 'preserve ForceChartV2 sine
  logic.'" Rejected.
- _Wrap `ForceChartView` inside V2's existing outer card chrome (so
  V2 keeps its `FORCE · 30 S` sibling header + bordered card)._ Would
  produce two headers, two borders, and a nested card-in-card layout.
  Rejected per user instruction: "do not keep V2's outer FORCE header
  row if ForceChartView already renders its own header/chrome… The
  goal is not 'V2 card wrapped around V1 chart'; the goal is 'V1
  ForceChartView behavior mounted in V2.'"
- _Delete `ForceChartV2.swift` in the same commit as the supersede._
  Higher-blast-radius. The user approved the surgical path: leave the
  file on disk with a SUPERSEDED banner so a rollback is one re-mount
  away. Rejected for now; revisit only on explicit user approval.
- _Reintroduce the b58 dual-band ECC / CON fill, CHAIN gradient
  mirror, rep-history overlay, or centroid labels by porting them
  into V1's `ForceChartView`._ Out of scope for this commit. If any
  of those features are reintroduced later, the future ADR must add
  them to V1's `ForceChartView` (so V1 and V2 stay in sync) rather
  than re-mounting `ForceChartV2`.

**Sacred files.** Untouched. This ADR concerns rendering only; the
telemetry stream feeding the chart is unchanged.

**Out of scope.** No version bump. No push. No TestFlight ship.
No changes to `LiveCaptureContainer.shouldUseV2` (V2-only routing
is still gated behind `if hasChain { return false }` and
`bothPaired`). No removal of V1 `LiveCaptureView`. No changes to
any sacred protocol file. No changes to b70 hotfix or its ADR
V4-D19. The `force_curve.md` design doc is updated in the same
commit to reflect the supersede; the rep-stacking / dual-band /
gradient-mirror sections in that doc remain as design references
for any future re-introduction (now scoped to V1's renderer).


## V4-D21 — V2 must reach below-chart parity with V1 before chain routing flip (b71)

**Cycle.** b71 / v0.4.44 / build 71 (in-flight, not shipped).

**User direction (verbatim).** _"Stop paring scope down. b71 is NOT
'whatever is already committed.' b71 is the target build scope. Do
not version bump, push, run release.yml, or TestFlight ship until
every item below is implemented, documented, committed, and
summarized back to me."_ Items 3 and 4 of that scope require V2 to
absorb the entire chain UI and become the unconditional default — but
that is only safe if V2 already matches V1's below-chart surface area
for every user, including chain users.

**Decision.** Port the V1 below-chart affordances that V2 was missing
into `LiveCaptureViewV2` directly, not by widening
`V1RestoreSection`'s contract. Specifically:

- **`SetMode` chips picker** at the bottom of `weightCard` (working /
  warmUp / eccentric / band / pause / dropSet / isoHold). V2
  previously had no surface for any of these mode tags, so
  warmUp / pause / isoHold sets could not be tagged at all.
- **`Target N reps` chip** in the `weightCard` header. Hidden when
  `logging.upcomingTargetReps == 0`.
- **Visible drop-cascade cancel chip** (`dropCancelChipV2`) mounted
  between the force chart and `V1RestoreSection`. Self-hides unless
  `logging.dropSetActive`. V2's prior cancel surface was a long-press
  on the DROP tile; the user reported it as undiscoverable.
- **Mode-aware ±step nudgers**. V2 previously hard-coded ±5 / ±1 in
  `weightCard.stepperButton` calls; V1's `weightNudgerRow` reads
  `CombinedParity.smallStepLb(for:) / largeStepLb(for:)` so Combined
  mode shows ±2 / ±6. V2 now reads the same helpers.
- **onAppear lifecycle parity**: `writerRouter.resetAppliedState()`,
  `mdm.leftWriter.resetAppliedState()`, `mdm.rightWriter.resetAppliedState()`,
  `logging.applyWorkoutMode(mdm.workoutMode)`,
  `enforceCombinedParityOnEntry()`. V2 only had `writerRouter.attach`
  before; the dual-side writer caches and the workout-mode handoff
  to `LoggingStore`'s cascade math were leaked.
- **onChange / onDisappear parity**: `onChange(of: mdm.workoutMode)`
  re-applies workout mode + Combined parity (so the user toggling
  `[⇄ MERGE]` mid-session lands on an even pendingPlannedWeightLb);
  `onDisappear { health.stop() }` so HR / kcal pollers stop on
  navigation pop.

**Equivalences not ported.** V1's `upcomingSetCard` outer chrome
(label "UPCOMING SET", bordered card) is intentionally NOT replicated.
V2's `weightCard` is the canonical "upcoming set" surface and already
hosts every nudger / mod tile / stepper / LOAD-toggle the user
needs — adding a second card would duplicate the visual hierarchy.
V1's separate `loadUnloadRow` (LOAD / UNLOAD pair buttons) is also
NOT replicated as a separate row; V2 already binds those opcodes to
the big-WEIGHT-NUMBER tap (`toggleHardwareLoad`) plus the LOADED/
UNLOADED pill, both of which fire `ble.sendLoad()` / `ble.sendUnload()`
through the same path V1 does.

**Sequencing.** This commit is part 1 of three closely-coupled
b71 V4-D21 commits, intentionally split for review reversibility:

1. **Below-chart parity** (this commit) — non-chain ports listed
   above. Reversible without affecting chain UI.
2. **Chain UI port** (next commit) — port the V1 `supersetBanner`
   chain-aware behavior into V2: full chain swap flow (auto-end
   in-flight set + UNLOAD outgoing + flip slot + switch
   `activeInstance` + restore chain-entry weight + push device
   state), onAppear chain restoration, onChange `currentSet != nil`
   → `lockSupersetTag()`, onChange `mdm.supersetActiveSlot` →
   `switchActiveInstanceByExerciseName`. May replace the
   `SupersetSwitcherBanner.swap` simple-mirror path with the V1
   verbatim flow (or layer the chain-aware behavior on top).
3. **Routing flip** (commit after) — remove
   `if hasChain { return false }` (and any other V1-fallback branch)
   from `LiveCaptureContainer.shouldUseV2`. Document
   `@AppStorage("liveCaptureUIVersion")` as an emergency-only kill
   switch, NOT the default route. Update `08_SUPERSET.md`,
   `02_CURRENT_STATE.md`, `04_DECISIONS_AND_CONSTRAINTS.md` (this
   ADR), and `10_OPEN_QUESTIONS.md` (resolve the "Should V2 become
   the default?" question).

A Step 6 parity verification pass follows the routing flip; the
final commit is the version bump (`project.yml` + `Info.plist` +
`01_PROJECT_OVERVIEW.md` + `02_CURRENT_STATE.md`) only after every
item above is implemented and the user has been given a final
summary.

**Alternatives considered.**

1. **Widen `V1RestoreSection` to host the new affordances.** Rejected.
   `V1RestoreSection` is specifically the "below the force curve"
   sub-tree (LOGGED SETS + Next-exercise + End-session). The new
   chips, target-reps, and mode picker belong with the WEIGHT card
   (above the force curve), and the drop-cancel chip belongs
   directly under the chart. Mounting them inside `V1RestoreSection`
   would force odd parent-child plumbing (`logging.dropSetActive`,
   `logging.upcomingMode`, `logging.upcomingTargetReps`,
   `mdm.workoutMode` to compute step sizes) for no UI win.
2. **Change V1 hard-coded ±5 / ±1 to V2 hard-coded ±5 / ±1.**
   Rejected. V1's `CombinedParity`-aware nudger is the correct
   behavior — Combined mode totals must stay even per b47 / V4-D9.
   V2 was silently regressed.
3. **Defer below-chart parity to b72.** Rejected per the b71 scope
   mandate ("Do not use 'this is large' as a reason to move items
   to b72/b73/b74"). Step 3's routing flip in the same cycle would
   route chain users into a V2 that lacked any way to tag a warm-up
   set, see their target reps, or visibly cancel a drop cascade —
   that is a regression we cannot ship.
4. **Build a new V2-native upcomingSetCard equivalent.** Rejected.
   The ports above are surgical adds inside `weightCard`; building
   a new card would mean another wave of layout review for no
   user-visible benefit.

**Out of scope (this ADR).** No routing change — `LiveCaptureContainer`
is untouched. No chain UI port — V2 still gates on
`SupersetSwitcherBanner`'s `supersetTag && bothPaired` predicate;
chain semantics are unchanged. No version bump, no push, no ship.
No sacred-file changes.

## V4-D21 part 2 — Port V1 chain / superset UI into V2 (b71 Step 4)

**Context.** Part 1 of V4-D21 ported all *non-chain* below-chart UI
into V2 so a single-instance user routed through V2 sees every
affordance V1 offers. Part 2 closes the *chain-shaped* gap: when the
user has built a 2+ entry superset chain, V2 must behave identically
to V1 (banner display, SWAP semantics, lifecycle hooks) before Step 3
flips the router to deprecate the V1 fallback. Without part 2 the
Step 3 flip would route chain users into a V2 that:

- Did not surface the active / next exercise names from
  `mdm.activeSupersetEntry` / `nextSupersetEntry`.
- Did not force-finalize a mid-set SWAP (telemetry-orphaned set).
- Did not seal `supersetTag` on set 1 (historical record mutable
  after lifting started).
- Did not re-anchor the cascade on chain entry (drop-set cascade
  computed from the wrong base weight).
- Did not keep `LoggingStore.activeInstance` synced when
  `mdm.supersetActiveSlot` flipped from any path other than SWAP
  (sets committed against the wrong exercise).

V1 has shipped these behaviors since b48–b53. This ADR documents the
V1-verbatim port into V2.

**Decision.** Promote `SupersetSwitcherBanner` to host the full V1
SWAP semantics, parametrize it with optional `session: SessionStore?`
and `onAfterSwap: (() -> Void)?` so the host owns device-side state,
and wire the three V1 lifecycle hooks into `LiveCaptureViewV2`.
Specifics:

1. **Banner gate widening.**
   `SupersetSwitcherBanner` visibility predicate moves from
   `mdm.supersetTag && bothPaired` to
   `(mdm.supersetTag && bothPaired) || mdm.hasActiveSupersetChain`.
   This matches V1 where `supersetBanner` (LiveCaptureView.swift:763
   inline gate) renders the chain-aware variant whenever a chain is
   active, regardless of pair state. `mdm.hasActiveSupersetChain` is
   `chain.count >= 2` (MultiDeviceManager.swift:190).

2. **Banner content prefers chain entries.**
   When a chain is active, the LEFT / RIGHT badge labels prefer
   `mdm.activeSupersetEntry?.exerciseName` /
   `mdm.nextSupersetEntry?.exerciseName`, and the "Next:" weight
   prefers `mdm.nextSupersetEntry?.plannedWeightLb` over the mirrored
   side weight. Verbatim port of V1 LiveCaptureView.swift:805-814.

3. **`SupersetSwitcherBanner.swap()` rewritten as the V1 7-step flow.**
   In order:
   1. `session?.forceFinalizeCurrentSet()` — telemetry-safe boundary.
   2. Save outgoing planned weight (mirror).
   3. `mdm.unload(target: outgoing)` — outgoing side returns to bar.
   4. `mdm.flipSupersetActiveSlot()`.
   5. `logging.switchActiveInstanceByExerciseName(incoming)` —
      LoggingStore commits sets against the new exercise.
   6. Restore weight: prefer
      `mdm.activeSupersetEntry?.plannedWeightLb` over the mirrored
      value, set `pendingPlannedWeightLb`, then
      `reanchorCascadeIfActive(toLb:)`.
   7. Fire `onAfterSwap?()` — host's `pushUpcomingStateToDevice` is
      the single source of device-side state (writer-cache aware).

   **B53 safety preserved verbatim.** No auto-LOAD on the incoming
   side. SWAP only LOADs when the user pulls the trigger. The
   incoming side stays unloaded so the user is never surprised by an
   unexpected hardware engagement.

4. **Three V1 lifecycle hooks wired into V2.**
   Verbatim ports of V1 LiveCaptureView.swift:242-248, 264-268,
   283-288:
   - `onAppear`: when `mdm.activeSupersetEntry` is non-nil and
     `mdm.supersetChain.count >= 2`, switch active instance, set
     `pendingPlannedWeightLb`, re-anchor cascade,
     `pushUpcomingStateToDevice`. Idempotent with SWAP's restore.
   - `onChange(of: session.currentSet != nil)`: when `started`
     becomes true and `mdm.supersetTag` is set,
     `mdm.lockSupersetTag()`. Seals the historical record on set 1.
   - `onChange(of: mdm.supersetActiveSlot)`: guard
     `session.currentSet == nil`, then if
     `mdm.activeSupersetEntry` is non-nil call
     `switchActiveInstanceByExerciseName`. Catches any slot-flip
     path that bypasses SWAP (chain advance, navigation re-entry).

5. **Host call site.**
   V2 mounts the banner as
   `SupersetSwitcherBanner(mdm: mdm, logging: logging, session: session, onAfterSwap: { pushUpcomingStateToDevice() })`.
   Legacy two-arg call sites (no chain context) still compile.

**Why ports are verbatim, not refactored.** V1 has shipped these
exact paths since b48–b53 without report. The b71 mandate is parity
not redesign. Any cleanup (e.g. moving the slot observer into a
dedicated `SupersetCoordinator`) is deferred to a future ADR. The
goal here is "V2 chain UX is observably indistinguishable from V1
chain UX," not "V2 chain UX is structurally improved."

**Alternatives considered.**

1. **Keep the simple `SupersetSwitcherBanner.swap()` and add the
   chain restore in V2 only.** Rejected. The V1 `swap()` is the
   authoritative chain-advance path; if V2 wraps it with extra logic
   the two implementations diverge and a future maintainer must
   reverse-engineer which is canonical. The banner is now the single
   source of SWAP behavior, host-owned state stays in V2.
2. **Inline the swap flow inside V2 directly.** Rejected. The
   banner is the natural home for SWAP UI + behavior; inlining
   would mean two implementations of the same flow (V1 banner,
   V2 inline) and a third cleanup commit later.
3. **Skip chain restore on V2 onAppear and rely on SWAP-only
   restoration.** Rejected. V1's onAppear restore catches the
   "user navigated back to live screen with chain already built"
   case which SWAP cannot — SWAP only fires on the user's tap
   inside the banner.
4. **Defer to b72 because it's surgically large.** Rejected per the
   b71 scope mandate ("Do not use 'this is large' as a reason to
   move items to b72/b73/b74"). Without part 2 the Step 3 routing
   flip is unsafe.

**Sequencing.** Part 2 commits between part 1 (b93b4fe, below-chart
parity) and part 3 (Step 3 routing flip). After part 2 lands, part 3
removes `if hasChain { return false }` from
`LiveCaptureContainer.shouldUseV2`, redocuments the
`@AppStorage("liveCaptureUIVersion")` switch as emergency-only, and
updates 08_SUPERSET / 10_OPEN_QUESTIONS / 02_CURRENT_STATE.

**Out of scope (this ADR).** No routing change (Step 3); no parity
verification (Step 6); no version bump; no push; no sacred-file
changes. No new types, no new MultiDeviceManager APIs, no new
LoggingStore APIs. Two compiler warnings expected on the
`switchActiveInstanceByExerciseName` call sites (return value
unused) — V1 has shipped these warnings since b52, not promoting to
errors.

## V4-D21 part 3 — V2 is the canonical live capture view; V1 fallback removed (b71 Step 3)

**Context.** V4-D21 parts 1 and 2 closed every behavior gap that
made V2 unsafe as the default route:

- Part 1 (b93b4fe) — below-chart parity (`SetMode` chips picker,
  `Target N reps` chip, mode-aware ±step nudgers, drop-cancel chip,
  full onAppear / onChange / onDisappear lifecycle).
- Part 2 (commit 2488484, this session) — chain UI port: full V1
  SWAP semantics inside `SupersetSwitcherBanner`, three V1
  lifecycle hooks wired into V2.

The next step is the routing flip. Pre-b71, `LiveCaptureContainer.shouldUseV2`
short-circuited to V1 on chain or paired-second-Voltra; that path
is now the wrong behavior because V2 handles every shape V1 does.

**Decision.** Remove every V1-fallback branch from
`LiveCaptureContainer.shouldUseV2`. The new predicate is one line:

```swift
return uiVersion != "v1"
```

Where `uiVersion` is `@AppStorage("liveCaptureUIVersion")`. The kill
switch semantics are inverted from b53:

- Pre-b71: `uiVersion == "v2"` was an opt-in toggle; everything else
  defaulted to V1.
- Post-b71: `uiVersion == "v1"` is an opt-out (emergency rollback);
  everything else (including the empty default and explicit `"v2"`)
  routes to V2.

Source-code cleanup:

- The pre-b71 conditional cascade
  `if hasChain { return false } / if bothPaired { return true } / return uiVersion == "v2"`
  is removed (kept verbatim in a comment block as the historical
  reference for the next maintainer reading the simplified predicate).
- `LiveCaptureContainer` no longer reads `MultiDeviceManager` since
  routing is now AppStorage-only. The `@EnvironmentObject` declaration
  was removed; the container is still surrounded by app-entry-level
  injection of MDM, so V1 / V2 still receive it.
- Header comments + storage-key docstring rewritten to spell out
  the kill-switch semantics.

**Why a kill switch instead of a hard cut.** Two reasons:

1. We just doubled the V2 surface area (below-chart UI + chain UI +
   lifecycle hooks). Despite verbatim ports, a regression is
   plausible. A single-install kill switch lets the user (or a
   future Settings toggle) revert without forcing a build hotfix.
2. V1 has shipped continuously since b29 and is battle-tested on
   real hardware; deleting it would discard ~2k lines of working
   code with no rollback path. The rule (per `00_START_HERE.md`)
   is "do not delete code paths until you have a rollback story."
   The kill switch IS the rollback story.

V1 deletion is intentionally deferred to a future build (b75+ at
the earliest, 2 clean V2 ships beyond b71) when the kill switch
has demonstrably not been needed. Until then, V1 lives on disk as
a verbatim rollback artifact reachable via
`@AppStorage("liveCaptureUIVersion") = "v1"`.

**Resolves open question.** The "Should V2 become the default?"
question in `10_OPEN_QUESTIONS.md` is now closed (option a, with
the kill-switch caveat). The entry was moved to "Recently closed"
in the same commit as this ADR.

**Alternatives considered.**

1. **Keep `if bothPaired { return true }` as a forcing rule.**
   Rejected. V2 now handles single-Voltra, dual-Voltra, and chain
   identically; there is no behavioral reason to force-route on
   pair state. Forcing would also override the kill switch in the
   one scenario (dual-Voltra) where a regression is most likely
   to surface.
2. **Force-route on chain (`if hasChain { return true }`).**
   Rejected. Same reason. The kill switch must work in every shape
   or it is not actually a kill switch.
3. **Delete the kill switch and hard-route to V2.** Rejected. See
   "Why a kill switch instead of a hard cut" above.
4. **Add a Settings toggle in this commit.** Deferred. The toggle
   is a user-visible UX surface and warrants its own design pass.
   For b71 the kill switch is reachable via debug builds /
   `defaults write` / a future `xcrun simctl` reset; that is enough
   to recover from a field regression.

**Files changed (this commit).**

- `VoltraLive/Logging/Views/LiveCaptureContainer.swift`
- `docs/handoff/02_CURRENT_STATE.md`
- `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` (this ADR)
- `docs/handoff/08_SUPERSET.md` (routing section rewritten)
- `docs/handoff/10_OPEN_QUESTIONS.md` ("Should V2 become the
  default?" moved to Recently closed)
- `docs/WORK_LOG.md`

No sacred-file changes. No version bump. No push. CI `build.yml`
on push remains the authoritative compile check.

**Out of scope (this ADR).** No V1 deletion (deferred). No Settings
toggle for the kill switch (deferred). No parity verification (Step
6 next). No version bump.

## V4-D22 — Replace 9-anchor debug overlay with progressive-density grid (b72)

**Decision.** The b70/V4-D18 debug overlay (9 hardcoded anchor
markers — `C-TL`, `C-TR`, `C-BL`, `C-BR`, `M-T`, `M-R`, `M-B`,
`M-L`, `F-CTR`) is replaced with a 5-state progressive-density
spreadsheet-style grid. Same toggle surface (build-badge tap),
same AppStorage key (`"debugGridMode"`), new behavior. The legacy
`DebugGridMode` enum is retained behind a `// SUPERSEDED` marker
in `DebugGridOverlay.swift` so rollback is a one-line change in
`BuildBadgeOverlay.swift`'s tap handler.

**User ask (verbatim, 2026-04-30 ~01:35 UTC).** "The current
debug overlay is not a grid. It is a 9-point anchor marker set
placed at hardcoded positions. That is not what I want. Replace
it with a real spreadsheet-style graph-paper grid with column
letters and row numbers, and make the existing tap toggle
progressively increase density over 4 levels." Full prompt
captured verbatim in `docs/handoff/B72_DEBUG_GRID_PROMPT.md`.

**Why.** Anchor markers gave the user 9 reference points across
an entire screen — coarse enough that "between M-R and C-BR,
about a third of the way down" was still ambiguous. A real grid
with column letters + row numbers lets the user say "C10, header
section" and the agent knows exactly where that is. The semantic
region overlay at `.max` density closes the loop by labeling the
same regions the agent already names in code (`tileGrid`,
`forceChartCard`, `upcomingSetCard`, etc.).

**Density cycle (5 states).**

| State | Name | Spacing | Lines | Labels |
|---|---|---|---|---|
| 0 | `.off` | — | none | none |
| 1 | `.base` | 32 pt | 0.6 pt @30 % opacity | `A,B,…,Z,AA,AB,…` top + `1,2,3,…` leading, 8 pt @0.85 |
| 2 | `.half` | + 16 pt | 0.4 pt @20 % | + `A.5`, `10.5` margin labels @0.55, 7 pt |
| 3 | `.quarter` | + 8 pt | 0.3 pt @14 % | + `A.25`, `A.75`, `10.25`, `10.75` **margin-only**, 6 pt @0.45 |
| 4 | `.max` | (same as state 3) | (same) | + region outlines: 1 pt @40 % `VoltraColor.accent` rectangles labeled with `Self.regionName` |

Tap cycles forward: `0 → 1 → 2 → 3 → 4 → 0`. Same build-badge tap
gesture as b70; no new affordances added.

**Key parameter choices (locked).**

- **Base spacing 32 pt.** On a 390 pt-wide device this yields
  ~12 columns A–L and ~26 rows on an 844 pt body. The user
  picked 32 pt over 24 pt (too dense at quarter, 6 pt-spacing
  collapses below SF Mono 9 pt legibility threshold) and 40 pt
  (too coarse for tile-grid pixel-level feedback).
- **State 3 quarter labels are margin-only.** Interior quarter
  labels at 8 pt cell spacing on the dark `VoltraColor.bg`
  background would fight the UI underneath and defeat the
  purpose of the overlay. Margin-only mirrors how a real
  spreadsheet labels its rulers and keeps the body readable.
- **Margin strip 14 pt** (top + leading). Sized to clear iOS
  status-bar glyphs and home-indicator while keeping labels
  tight to the edge. Strips sit inside the safe area so labels
  never disappear under chrome.

**Implementation.**

- New file: nothing. Existing `VoltraLive/Views/DebugGridOverlay.swift`
  rewritten in place. The legacy `enum DebugGridMode` is retained
  at the bottom of the file behind a `// SUPERSEDED` marker so
  rollback is a one-line change in
  `BuildBadgeOverlay.swift`'s tap handler (cycle the legacy enum
  instead of `DebugGridDensity`).
- Renderer: SwiftUI `Canvas` for gridlines (single draw call,
  no per-line views) + `ZStack`/`Text` overlay layers for the
  margin labels and (at `.max`) the region overlay. Cap on label
  count: ~12 cols × ~26 rows base, ~4 × at quarter density when
  margin-only labels stay confined to the strips.
- Region overlay (`.max`): screens publish named regions via a
  new `.debugRegion("name")` modifier, implemented with
  `anchorPreference` so it does not change layout and does not
  intercept hits. Region rectangles resolved at the overlay
  level via `proxy[anchor]`. Screens that have not been
  instrumented render the grid only at `.max` with no regions
  (graceful degradation; tracked as KI-12).
- Migration: `DebugGridDensity.from(_:)` reads the persisted
  `"debugGridMode"` AppStorage key. Legacy `"off"` stays off,
  legacy `"corners"`/`"midlines"`/`"full"` map to `.base` so a
  user with persisted state discovers the new behavior on next
  tap without losing their on/off preference.

**Hit testing + z-order.**

- `.allowsHitTesting(false)` on every overlay layer — overlay
  never blocks touches to the UI underneath.
- The grid is the LAST modifier in `PageBadgeOverlay`'s chain,
  so it renders ABOVE the page badge AND the bottom-trailing
  build badge in z-order. Margin labels remain legible over both
  badges.

**Files changed (this commit).**

- `VoltraLive/Views/DebugGridOverlay.swift` (full rewrite +
  legacy enum kept under `// SUPERSEDED`).
- `VoltraLive/Views/BuildBadgeOverlay.swift` (tap cycles new
  enum; comment updated).
- `VoltraLive/Views/PageBadgeOverlay.swift` (header comment
  updated; no behavior change).
- `docs/handoff/02_CURRENT_STATE.md` (file-map row + bullet
  refreshed).
- `docs/handoff/03_CURRENT_FEATURE_SPEC.md` (Debug grid section
  rewritten).
- `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` (this ADR).
- `docs/handoff/06_KNOWN_ISSUES.md` (KI-12 added: partial
  region instrumentation).
- `docs/WORK_LOG.md` (entry appended).

No sacred-file changes. No version bump. No push. CI `build.yml`
on push remains the authoritative compile check; this commit is
held local until the user explicitly approves push.

**Out of scope (this ADR).** No version bump. No push. No
TestFlight ship. No additional region instrumentation in this
commit — partial coverage is acceptable for the first ship of
the new overlay; the user can tap through 0 → 1 → 2 → 3 fully
on every page-badged screen, and `.max` regions appear only on
screens that opt in. KI-12 tracks the follow-up.

---

## V4-D23 — Debug grid coordinate system: column letters viewport-pinned, row numbers content-pinned (b73)

**Date.** 2026-05-01.

**Status.** Active.

**Cycle.** v0.4.46 / build 73.

**Context.** The b72 (V4-D22) progressive-density debug grid was
mounted at the screen-body level via `PageBadgeOverlay`'s
`.debugGridOverlay()` modifier. That modifier puts the entire
overlay above ANY ScrollView on the screen, so vertical position
on the overlay (a row label) maps to a fixed PHYSICAL pixel —
not to a fixed UI element. Two screenshots of `LoggingHomeView`
shipped on b72 (IMG_2450 unscrolled, IMG_2451 scrolled) show
"LEG DAY" at row 5 in the first and row 11 in the second. That
means a coordinate like "C10" referred to whatever the user
happened to be looking at, not to a stable element of the
design. The whole point of having a coordinate system is to
make a phrase like "tighten the spacing around C10" land
unambiguously on the same UI element regardless of scroll
position. b72's grid did not deliver that.

The fix has to split the coordinate system because the X axis
and the Y axis behave differently in this app: there is NO
horizontal scroll anywhere, so column coordinates are already
stable when pinned to the viewport; the Y axis is where the
scroll happens, and only that axis needs to follow the content.

**Decision.**

1. **Vertical gridlines + column letters stay viewport-pinned.**
   They render in the screen's coordinate space, full width,
   full height. Letters `A, B, C, …` start at the leading edge
   and wrap `Z, AA, AB, …` per the b72 spec.

2. **Horizontal gridlines + row numbers anchor to the
   ScrollView's content coordinate space.** Row 1 is the top of
   the SCROLLABLE CONTENT, not the top of the screen. Row labels
   travel with the content as the user scrolls. The grid extends
   to cover the full content height, so row N is meaningful even
   when N is currently off-screen.

3. **Mechanic.** A new public modifier `.debugGridContent()` is
   attached to the inner content stack inside each page-badged
   ScrollView. It backs the receiver with a `GeometryReader`
   that measures itself in the `"debugGridViewport"` named
   coordinate space (established by `.debugGridOverlay()` on the
   same screen) and publishes the `(minY, height)` of the
   content via a new `DebugGridContentMetricsKey`. The overlay
   reads that preference and translates horizontal lines + row
   labels by `contentMinY`. The translation is the entire
   correction: `minY = 0` at rest, `minY < 0` after the user
   scrolls down by `|minY|` points.

4. **Backward compatibility.** Screens without a ScrollView
   (e.g. `ConnectView`) do not call `.debugGridContent()`. The
   metrics default is `.zero`, so the overlay's row labels land
   at viewport-y = 0 + i * 32 — exactly the b72 behavior. There
   is no per-screen breakage from screens that don't opt in.

5. **Scope of adoption (this commit).** Every existing
   page-badged screen with a ScrollView gets `.debugGridContent()`
   on its inner content stack: `LoggingHomeView`,
   `LiveCaptureView`, `LiveCaptureViewV2`, `ExerciseDetailView`,
   `ExerciseStartView`, `DebugView`, `DashboardView`,
   `ExercisePickerView`, `SetLogView`, `ExportSheet`. Future
   page-badged ScrollView screens must add the modifier;
   omission is detectable visually because rows visibly fail to
   travel with scroll.

**Why not these alternatives.**

- *Move the entire overlay inside each ScrollView.* That would
  put column letters inside the scrollable content too, so they
  would scroll off the top — wrong behavior. The whole point of
  this fix is that the X axis and Y axis are different.

- *Use an `onScrollGeometryChange` / `ScrollPosition` API
  (iOS 17+).* iOS 17 is the deployment target, so this is
  technically available, but it adds an extra type per screen
  (a `ScrollPosition` ObservedObject) and forces every adopting
  screen to wire a `.scrollPosition($var)` binding. The
  `GeometryReader + PreferenceKey` pattern is one line per
  screen, has no extra state, and is the standard SwiftUI
  pattern for content-frame measurement. Reach for the iOS 17
  API only if the preference-key approach proves laggy in
  practice.

- *Use a content `coordinateSpace(name:)` from inside the
  ScrollView.* Equivalent in spirit but harder to wire because
  the OVERLAY, which lives at the screen-body level, would have
  to look INTO the ScrollView's named space. The chosen
  direction (overlay establishes the viewport name; content
  measures itself against it) flows the dependency in the same
  direction layout already does and avoids cross-tree lookups.

- *Reset row 1 to "current viewport top" by reading the visible
  scroll offset on every frame and recomputing.* This is what
  b72 effectively did and it's exactly the bug we're fixing. A
  coordinate system whose origin moves with the camera is not a
  coordinate system.

**Files changed (this commit).**

- `VoltraLive/Views/DebugGridOverlay.swift` — split renderer.
  New `enum DebugGridContentMetrics`, `DebugGridContentMetricsKey`
  PreferenceKey, public `.debugGridContent()` modifier. Canvas
  draws vertical lines in viewport space and horizontal lines
  shifted by `contentMinY`; row label `position(y:)` shifted by
  the same amount. Density enum, region preference key, and
  `// SUPERSEDED` legacy `DebugGridMode` kept verbatim from
  b72.

- 10 page-badge screens with ScrollView: `LoggingHomeView`,
  `LiveCaptureView`, `LiveCaptureViewV2`, `ExerciseDetailView`,
  `ExerciseStartView`, `DebugView`, `DashboardView`,
  `ExercisePickerView`, `SetLogView`, `ExportSheet` — each gains
  one `.debugGridContent()` call on its inner content stack.

- `project.yml`, `VoltraLive/Info.plist` — version bump
  v0.4.45/72 → v0.4.46/73; `VOLTRAFeatureLabel` = "Grid scroll
  fix".

- `docs/handoff/01_PROJECT_OVERVIEW.md`,
  `docs/handoff/02_CURRENT_STATE.md`,
  `docs/handoff/03_CURRENT_FEATURE_SPEC.md` (this ADR + spec
  amendment), `docs/handoff/06_KNOWN_ISSUES.md` (KI-13 added),
  `docs/WORK_LOG.md`.

- `docs/handoff/screenshots/b73/grid_scroll_invariant.png` —
  visual validator (mathematical render, not on-device capture
  — see WORK_LOG for the explicit caveat).

- `scripts/render_b73_grid_diagram.py` — generator for the
  validator diagram.

**Verification.** The visual validator renders LEG DAY (a UI
element at content y=270, height=80) using the same formula as
the SwiftUI overlay (`row = floor((y_center) / 32) + 1 = 10`).
At scroll offset 0 LEG DAY appears next to row label 10; at
scroll offset 192 LEG DAY again appears next to row label 10
(because the row labels translated by -192 along with the
content). Side-by-side comparison saved at
`docs/handoff/screenshots/b73/grid_scroll_invariant.png`.

CI `build.yml` is the authoritative compile check; this commit
ships only after a green CI run on `feat/ui-v4-2-claude`.

**Out of scope.** No protocol/BLE changes. No new
`debugRegion(...)` instrumentation (KI-12 from b72 remains
open). No removal of the b72 SUPERSEDED legacy `DebugGridMode`
enum (delete target slips to post-b74 to keep two clean ships
of distance).
