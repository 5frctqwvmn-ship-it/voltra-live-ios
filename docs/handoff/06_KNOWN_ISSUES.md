# 06_KNOWN_ISSUES

> Live list of bugs, edge cases, and quirks. Fixed items move to
> `docs/WORK_LOG.md` and are deleted from here. Unfixed items
> stay until shipped.

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

### KI-7 (b58 → b59 QA) — Dropset cascade timer is 4 s, user wants 2 s

**Surfaced:** b58 post-build QA wave 1.
**File(s):** `VoltraLive/Logging/Persistence/LoggingStore.swift` —
search for the cascade fire interval (`nextDropFiresAt`,
`dropFinalizeAt`).
**What:** Currently each cascade tier fires ≈ 4 s after the lift
enters idle. User wants the interval set to **2 s**.
**Severity:** P1 — dropset feels sluggish; reduces the "snap" the
feature is supposed to convey.
**Owner:** Next session.

### KI-8 (b58 → b59 QA) — Idle bar should morph into dropset progress bar, then rest timer

**Surfaced:** b58 post-build QA wave 1.
**File(s):** `VoltraLive/Logging/Views/LiveCaptureViewV2.swift`
(idle/rest bar component) + `LoggingStore` (state machine driving
the cascade).
**What:** While DROP is armed, the existing idle bar should morph
into a **dropset progress bar** showing the 2 s countdown to the
next cascade tier. Once cascade reaches floor, that same bar
morphs into the **rest timer**. Right now the idle bar stays
generic and the dropset progress isn't surfaced visually.
Must be a single bar across all three states (idle / dropset
progress / rest), not three separate components.
**Severity:** P1 — dropsets work mechanically but the user can't
*see* the cascade timing.
**Owner:** Next session. Pairs with KI-7 (the new bar must reflect
the correct 2 s interval).

### KI-9 (b58 → b59 QA) — DROP tap pre-lowers weight; should arm-only

**Surfaced:** b58 post-build QA wave 1.
**File(s):** `VoltraLive/Logging/Views/LiveCaptureViewV2.swift`
`tapDropTile()` + `LoggingStore.startDropSet(...)`.
**What:** Tapping DROP currently calls into the cascade and the
weight drops immediately. User wants tap-to-arm only: weight
should stay at the working number until the lift goes idle AND
the (KI-7) 2 s timer elapses, then the cascade fires the next
tier. This matches how dropsets actually work in a gym — you
finish the rep, *then* the weight drops.
**Severity:** P0 — changes the felt behavior of the feature; users
will think the DROP tile is a regular weight stepper.
**Owner:** Next session. Refactors `startDropSet` into
`armDropSet` (no-op weight) + a separate `fireNextCascade` driven
by the idle-detector + KI-8 progress bar.

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
**Owner:** Next session. Add a temporary debug log on every
resistance-write call site, ship as a debug build, capture a
real session, then patch.

### KI-11 (b58 → b59 QA) — Force-curve full spec not yet implemented

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
