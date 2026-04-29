# 06_KNOWN_ISSUES

> Live list of bugs, edge cases, and quirks. Fixed items move to
> `docs/WORK_LOG.md` and are deleted from here. Unfixed items
> stay until shipped.

## b68 Bug Batch — FIXED in-tree, awaiting altool ship

Cycle opened Apr 29 2026 (PDT) immediately after b67 TestFlight
ship verify. Cycle target: v0.4.41 / build 68 on
`feat/ui-v4-2-claude`. See `B68_BUG_QUEUE.md` for per-bug
detail + Q&A and `04_DECISIONS_AND_CONSTRAINTS.md` ADR V4-D16
for the auto-engage contract.

- **B68-01** — FIXED in-tree — demo mode auto-engages on
  `LiveCaptureViewV2.toggleHardwareLoad()` when no Voltra is
  connected, and auto-exits via `.onChange` observers when any
  device pairs mid-session (prePair source only).

## b67 Bug Batch — SHIPPED in v0.4.40 / build 67

All 9 entries in `B67_BUG_QUEUE.md` are CLOSED in b67. See
`docs/WORK_LOG.md` for the full ship entry. Summary:

- **B67-01** — closed by `3257517` (cold-launch → `LoggingHomeView` always)
- **B67-02** — closed by `a3b6c6e` (footer watermark cleared)
- **B67-03** — closed by `faad2c6` (wordmark + duplicate identity chrome removed)
- **B67-04+05** — closed by `3257517` (`DualConnectView` + `DualCaptureView` deleted; `UnifiedConnectSheet` is canonical)
- **B67-06** — closed by `faad2c6` (single `VoltraUnitHeader` mounted on all 3 screens)
- **B67-07** — closed by `3257517` (`PairingCoordinator.swift` env-object; one sheet binding at home root)
- **B67-08** — closed by `faad2c6` (single canonical unit header; `VoltraAssignmentPanel` deleted)
- **B67-09** — (skipped / reserved per user; not a real bug)
- **B67-10** — closed by `660853a` (parametric per-rep `sin(π·t)` lobes in `ForceChartV2`; ADR V4-D13)

ADRs added in b67: V4-D13 (force-curve geometry), V4-D14 (single
canonical chrome), V4-D15 (PairingCoordinator). See
`04_DECISIONS_AND_CONSTRAINTS.md`.

## Open

### KI-1 (b57) — 2× pulley snap on ±1 displayed

**Symptom.** Under 2× pulley, tapping the displayed ±1 lb
button on the WEIGHT card or any nested mod row may move the
displayed value by 2 lb instead of 1 lb.

**Why.** The displayed value is `device × 2`. Adjusting by 1
lb at the display layer would require a 0.5-lb step on the
device — but the device only accepts integer pounds. We snap
to the nearest device int, which means the user-visible result
moves by 2 lb (one device increment).

**Workaround.** None at the firmware level. Documented for the
user via release notes.

**Possible future fix.** Add a "fine adjust" mode that
round-robins the snap direction (alternates floor/ceil) so the
user can land on any displayed value over two taps. Not in
scope for b58.

### KI-3 (b58) — V2 dial is removed but legacy types remain

**Symptom.** None at runtime. The V2 dial control type
(removed from the toolbar in b57) is still declared in the
codebase. Searching for "Dial" in the project surfaces it.

**Why.** Deleting the type would touch unrelated views that
still reference the helper utilities defined alongside it.
Marked TODO; cleanup is non-urgent.

**When to revisit.** Next time the V2 layout files get a
substantive refactor.

### KI-4 (b58) — CI build watermark is hard-coded "V3"

**Symptom.** The header watermark always reads "V3" even on
builds shipped from b58 onward.

**Why.** The CI step that injects the build tag into the SwiftUI
view at archive time was deferred from b57. The label is a
literal string in `LiveCaptureViewV2.headerStrip`.

**When to revisit.** Add a build-time `#if DEBUG`-aware
extraction of the bundle short version + build number into the
watermark. Low priority — V3 vs V4 is invisible to end users
and the version surfaces in the Settings → About sheet
already.

### KI-5 (b58) — V4 dropset idle-branch ordering — verified

**Symptom.** Concern that `SessionStore.idle` finalizes a normal
set BEFORE checking the dropset boundary callback, causing the
cascade to never get a "next drop step" notification.

**Why not a bug.** Audited at `SessionStore.swift` line 146 —
`if dropSetMode, let cb = onDropBoundary { cb() }` runs FIRST,
then the normal-set finalizer. Ordering is correct in b58.
Logged here as a sanity-check anchor; no action required unless
SessionStore is refactored.

**Action.** Future SessionStore refactors must preserve this
ordering. Add a regression test before any meaningful change.

### KI-6 (b58) — `weight-overlap-v3.jpeg` screenshot not committed

**Symptom.** The V4 spec referenced a screenshot at
`docs/handoff/screenshots/weight-overlap-v3.jpeg` showing the
3-digit weight overlap regression. The source file lived on the
user's S3 attachment and could not be fetched into the
sandboxed CI environment.

**Why.** The b58 build agent runs in an isolated container; only
the GitHub repo is mounted. The S3 attachment URL was not
re-uploaded into the repo before the b58 build kicked off.

**When to revisit.** Next live session — drop the JPEG into
`docs/handoff/screenshots/` and add a single-line reference in
this file. Until then, the ASCII description in
`03_CURRENT_FEATURE_SPEC.md` §P1 is the canonical reference.

### KI-10 (b58 → b59 QA) — Phantom -5 lb weight drop during reps

**Surfaced:** b58 post-build QA wave 1.
**File(s):** Unknown. Likely `LoggingStore.noteTelemetryActivity`
or a writer-router callback.
**What:** During a normal exercise (DROP not engaged), the
resistance was observed dropping by 5 lb spontaneously. No user
input, not a manual stepper press. Possibly tied to KI-5
(idle-branch ordering) firing a cascade tier when the lift
briefly went idle between reps; possibly an unrelated writer
race. Needs telemetry repro.
**Severity:** P0 — breaks every set where the user is paused
between reps.
**Status (b60-prep):** The b60 KI-9 arm-only refactor is the
most likely fix. Pre-b60 the only public path into the cascade
was `startDropSet`, which fired drop #2 immediately on tap. If
the user had the V2 manualDropSequence path armed
simultaneously (b56-era `tapDropTile` did NOT route through
the time-cascade — it sat on `manualDropSequence` and waited
for SessionStore's idle finalize), the very first idle between
reps could finalize the set as a "drop" and step the weight
down by 5 lb. Post-b60, `armDropSet` does NOT touch
`manualDropSequence` and does NOT call `beginDropChain`, so the
SessionStore drop boundary path can never engage without
explicit user arm + 2 s sub-floor gate. Re-test on hardware
after b60 ships before closing this entry.
**Owner:** User QA on b60 hardware install. If repro persists,
add debug logging on every resistance-write call site and ship
a debug-only follow-up build.

### KI-11 (b58 → b67, FIXED) — Force-curve full spec

Closed by b67 commit `660853a` (Bug 10 — parametric per-rep sine
lobes + log-fade history overlay). Concrete §3f and §3a/3b/3d
bits land; §3e (80% reference line, peak dots) and §3g (compact
legend) remain optional follow-ups for a later cycle. See ADR
V4-D13 in `04_DECISIONS_AND_CONSTRAINTS.md`.

### KI-11-LEGACY (b58 → b59 QA, superseded) — original spec note

**Surfaced:** b58 post-build QA wave 1; user delivered the full
design in `docs/handoff/design/force_curve.md`.
**File(s):** `VoltraLive/Logging/Views/V2/ForceChartV2.swift`.
**What:** b58 ForceChartV2 only landed §3b dual-band fill + §3c
basic inline labels + §3d corner-mirror gradient. Still missing:
- §3b: 200 ms blended phase transition (current is hard-cut).
- §3c: label fade timing (3 s OR rep 2, whichever first;
  re-surface on mid-set mode change). Today only suppresses for
  `repsAgo > 0`.
- §3d: vertical gradient *within* the fill encoding ROM-position
  (b58 only flips the outer corner direction).
- §3e: dotted 80%-of-peak reference line, per-rep peak dots +
  labels, optional target line hook.
- §3f: rep stacking with logarithmic opacity decay, cap ·8.
- §3g: compact mode-aware legend in top-left.
- §6: low-weight Y floor `max(peak × 1.2, 15 lb)`; mid-set
  mode-change rule (historical reps keep prior rendering).
**Severity:** P1 — the chart works, but doesn't yet match the
design target.
**Owner:** Next session. Tracked as a single epic; do not split
the §3e/§3f/§3g rendering passes across builds unless explicitly
asked. `force_curve.md` is the source of truth.

## Recently fixed (move to WORK_LOG before deleting)

### KI-F12 (b66, fixed) — Rest-timer first-engage view race (P1-2)

**Was.** Distinct from KI-F1 (which fixed the *engagement-detection*
side in `SessionStore.handleLiveSample`). On the very first set
finalize after launch, the **rest bar would silently fail to mount**
on the LiveCaptureViewV2. Root cause: the view-side mount predicate
keyed on `Int(session.restElapsedSeconds.rounded()) > 0`, but
`restElapsedSeconds` is only updated by the 0.25 s ticker — when
`finalizeSet()` set `restStartedAt` synchronously, the elapsed value
stayed at 0 until the next tick fired. SwiftUI re-rendered with the
stale 0 and the bar never appeared on the first set.

**Fix.**
- `SessionStore.finalizeSet()`: publish `restElapsedSeconds`
  immediately after setting `restStartedAt` (computed against
  `Date()` so the -2 s backdate is honored).
- `SessionStore.tapRestTile()`: assign `restElapsedSeconds = 0`
  to re-fire observers on a fresh tap.
- `LiveCaptureViewV2.phaseOrRestBar`: predicate now keys on
  `session.restActive` (set synchronously) instead of rounded
  seconds.
- `LiveCaptureViewV2.forceChartCard`: `resting` flag aligned to
  `restActive` for the same race.

### KI-F11 (b66, fixed) — 3-digit weight + TWIN badge overlap (P1-1)

**Was.** Under TWIN mode at 3-digit weights (≥100 lb), the TWIN
pill overlapped the weight number's `lb` suffix. The badge was
nested inside the inner weight HStack, where it competed with
`.minimumScaleFactor` and the trailing-mask gradient.

**Fix.** Promoted TWIN badge OUT of the inner weight HStack to a
fixed-size sibling between the weight cluster and the stepper
spacer in the outer HStack. Wrapped weight Text in a leading-aligned
flexible frame so it owns its slot; gave the `lb` suffix
`.layoutPriority(2) + .fixedSize()` so 3-digit weights never push
the badge into overlap. (V4-D9 from b58 fixed the stepper-overlap
side; this fix extends it to the TWIN badge.)

### KI-F10 (b66, fixed) — Cascade timer cadence (T1)

**Was.** `cascadeArmIdleSec` and `cascadeIntervalSec` were both
2.0 s. User feedback: too fast, can't keep up with the cable
stepping mid-cascade.

**Fix.** Both bumped to 3.0 s in `LoggingStore.swift`. Constants
table in `docs/handoff/entities/dropset_state_machine.md` updated
to match.

### KI-F7 (b60-prep, fixed) — Cascade interval was already 2 s

**Was.** b58 QA reported the dropset cascade fire interval as 4 s
and asked for 2 s. **Was already 2 s in code** since b45
(`cascadeIntervalSec: Double = 2.0` at LoggingStore.swift:113);
the KI doc was stale. The user-perceived sluggishness in b58 may
have been the b58 4 s arm-to-first-fire (which DID exist per the
b58 architecture) bleeding into the perception of the inter-tier
cadence.

**Fix.** None needed in the cascade path itself. Documented the
inter-tier interval = 2 s explicitly in
`docs/handoff/entities/dropset_state_machine.md`. The arm-to-
first-fire interval (KI-9 fallout) is also set to 2 s as
`cascadeArmIdleSec`.

### KI-F8 (b60-prep, fixed) — Unified bar across idle / dropset / rest

**Was.** b58 had three separate bar concepts: phase strip
(active set), RestTimerBarV2 (post-finalize). Dropset progress
had no visual surface — the user could see weight changes but
not the timing of the next change.

**Fix.** `LiveCaptureViewV2.phaseOrRestBar` now branches across
**rest > dropset > phase** in priority order. New
`dropProgressBar` private view renders one of four labels
(`DROP · ARM` / `· IN` / `· NEXT` / `· BOTTOM`) with a 2 s sweep
tied to `nextDropFiresAt` or `dropArmedFiresAt`. Reuses the
ambient `blinkOn` 2 Hz republish so no new timer source is
needed. See
`docs/handoff/entities/dropset_state_machine.md` for the state
diagram.

### KI-F9 (b60-prep, fixed) — DROP tap pre-lowered weight; now arm-only

**Was.** b58 `tapDropTile()` called `LoggingStore.startDropSet`
which fired drop #2 immediately. User mental-model violation —
tapping DROP mid-rep yanked the cable.

**Fix.** Split the engine into `armDropSet` (captures anchor +
writer; sets `dropSetArmed = true`; cable untouched) and
`engageArmedDropSet` (private; called from
`noteTelemetryActivity` once 2 s of sub-floor force have passed
since the LAST above-floor sample). Tap-to-arm is now the only
public entry from the V2 view; the cascade engages on the first
qualifying lift-idle boundary. State diagram, transitions, timer
constants, and hardware test plan in
`docs/handoff/entities/dropset_state_machine.md`. See V4-D10 in
`04_DECISIONS_AND_CONSTRAINTS.md`.

### KI-F3 (b58, fixed) — DROP tile never actually dropped the cable

**Was.** First tap on DROP set `manualDropSequence` to a
two-step array but never called `LoggingStore.startDropSet`. The
cable held its weight; the drop only "fired" on rest-timer
finalize. From b22 onward the time-driven cascade had been the
intended behavior; b56 had unintentionally regressed it.

**Fix.** `tapDropTile()` now calls `startDropSet(startingLb:
pushWeight:)`. `adjustDropStep(±5)` calls `bumpCascadeTier`.
`dropArmed` reads `logging.dropSetActive`. Long-press calls
`cancelDropSet`. See V4-D1 in `04_DECISIONS_AND_CONSTRAINTS.md`.

### KI-F4 (b58, fixed) — 3-digit weight overlapped steppers

**Was.** Setting weight ≥ 120 lb under TWIN mode pushed the
weight number into the −5 stepper because the WEIGHT card was a
single fixed-size HStack with no scale-factor.

**Fix.** Big number gets `.minimumScaleFactor(0.6)`,
`.lineLimit(1)`, and a trailing-edge linear-gradient mask so
overflow softens instead of clipping. `Spacer(minLength: 4)`
guarantees the steppers can never abut the number. See V4-D9.

### KI-F1 (b57, fixed) — Rest timer first-engage miss

The very first rep of the very first set of a session would
sometimes not arm the rest-timer idle detector, leaving the
user without a timer when they tapped End Set. Fixed in
`SessionStore.swift` line ~132 by accepting `cs.peakLb > 10`
alongside `cs.reps > 0` as engagement evidence.

### KI-F2 (b57, fixed) — BLE write multiplied by pulleyMultiplier

`pushUpcomingStateToDevice` was multiplying the planned base /
ECC / CHAIN values by `pulleyMultiplier` before writing to
BLE. The device received doubled values under 2× pulley. Fixed
by removing the `* m` from baseLb / eccLb / chainsLb in the
push function. Display side still multiplies (correct).
