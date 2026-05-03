# 06_KNOWN_ISSUES

> Live list of bugs, edge cases, and quirks. Fixed items move to
> `docs/WORK_LOG.md` and are deleted from here. Unfixed items
> stay until shipped.

## KI-13 (b78) — B74-F11 Session Recorder launch crash (FIXED in b78)

**Surfaced:** b77 ship to TestFlight, 2026-05-03. App crashed
immediately on launch with `EXC_BREAKPOINT / SIGTRAP` on the main
thread; stack trace top:
`_assertionFailure → SwiftUI.EnvironmentObject.error() → ViewBodyAccessor.updateBody`.

**Root cause:** `.overlay { content }` does NOT propagate env-objects
from the modifier chain to the overlay's content. The overlay
creates a composite where `content` is a SIBLING of the modified
view, not a descendant — so `.environmentObject(X)` calls on the
chain only reach the modified view's descendants, not the overlay
content.

In `VoltraLiveApp.swift` (b77 head `60df3f3`), `SessionRecorderToggle`
was mounted via:

```swift
ContentView()
    .environmentObject(recorder)   // line 127
    ... other modifiers ...
    .overlay(alignment: .bottomTrailing) {
        SessionRecorderToggle()    // line 347 — DOES NOT inherit recorder
    }
```

`SessionRecorderToggle` has `@EnvironmentObject private var recorder: SessionRecorder`.
SwiftUI's `_EnvironmentObject` `DynamicProperty` resolution runs
during initial view setup — even when the toggle's body returns
`EmptyView()` because `VOLTRARecorderUnlocked` is `false` on a fresh
install, the property-wrapper resolution still fires and crashes
when the env-object cannot be found.

**Fix commit:** `e1c19c7` on `fix/b78-recorder-launch-crash` →
merged into `feat/ui-v4-2-claude` via PR #12.

```swift
.overlay(alignment: .bottomTrailing) {
    SessionRecorderToggle()
        .environmentObject(recorder)   // ← THE FIX
}
```

**Verification:**
- `build.yml` workflow_dispatch run 25267980973 on the fix branch
  HEAD `e1c19c7`: `success` in 1m18s.
- `release.yml dry_run=true` workflow_dispatch run 25267981601 on
  the same head: `success` in 4m52s. `xcodebuild test` exercised
  the new `VoltraLiveTests/RecorderLaunchSmokeTests.swift` (3
  tests: `testRootOverlayWithRecorderToggleResolvesEnvironmentObject`,
  `testSharedSingletonInitDoesNotCrash`,
  `testSessionRecorderViewerResolvesEnvironmentObject`) and they
  all passed. Removing the env-object re-injection in the future
  would crash `testRootOverlayWithRecorderToggleResolvesEnvironmentObject`
  and fail CI.
- Final on-device verification deferred to b78 TestFlight surface +
  QA passes A–G per `SESSION_RECORDER_SPEC.md`.

**General lesson for future SwiftUI overlay patterns:** any view
mounted via `.overlay { ... }` (or `.background { ... }`) at the
app root that reads `@EnvironmentObject` MUST receive a direct
`.environmentObject(...)` re-injection inside the overlay closure.
The same applies to any view passed to a custom modifier that
takes a `@ViewBuilder` content closure.

---

## b68 Bug Batch — in flight

Cycle opened Apr 29 2026 (PDT) immediately after b67 TestFlight
ship verify. Active branch: `feat/ui-v4-2-claude`. See
`B68_BUG_QUEUE.md` for per-bug detail + Q&A and
`04_DECISIONS_AND_CONSTRAINTS.md` ADR V4-D16 for the B68-01
auto-engage contract.

- **B68-01** — SHIPPED v0.4.41 / build 68 (`408db2e`) — demo
  mode auto-engages on `LiveCaptureViewV2.toggleHardwareLoad()`
  when no Voltra is connected, and auto-exits via `.onChange`
  observers when any device pairs mid-session (prePair source
  only). 5-gate altool verify: PASS. Delivery UUID
  `bb7425ca-c619-4db3-b961-15ac5fc83928`.
- **B68-02** — SHIPPED v0.4.42 / build 69 (`b0f67ac`) — V1
  (`LiveCaptureView`, the production default per
  `LiveCaptureContainer`'s b53 router) now auto-engages prePair
  demo on `sendLoad()` when no Voltra is connected, with
  `.onChange` observers for real-device handoff. B68-01 was
  V2-only and missed the default user path. 5-gate altool
  verify: PASS. Delivery UUID `7e036a7d-7060-4682-8212-c253b815118a`.

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

### KI-12 (b72) — Debug grid State 4 region overlay coverage is partial

**Status.** Open. Acceptable trade-off; tracked here so the
follow-up is not lost.

**What.** The b72 / V4-D22 progressive-density grid's State 4
(`.max`) renders translucent outlines around named UI regions
that the screen publishes via `.debugRegion("name")`. As of the
b72 commit, NO screens have been instrumented yet. State 4 still
works — it just shows the quarter-step grid with no region
outlines. Tap-through 0 → 1 → 2 → 3 is fully populated on every
page-badged screen.

**Why partial.** The user's b72 prompt explicitly required
"replace the existing overlay with the new one in a single
commit only after you have visually validated the new renderer
compiles and lays out sanely" — so the renderer + state machine
ship first, screen instrumentation lands incrementally. Every
region added is per-screen surgical work that can land in
isolation without touching the overlay infrastructure.

**Planned region names** (per the user's b72 prompt — these are
the identifiers the agent will use when the user references them
by name):

- `headerPillRow` — the b67 unit-status pill row at the top of
  Workout / Live / Detail screens.
- `tileGrid` — the V2 4-up live tile grid on
  `LiveCaptureViewV2`.
- `forceChartCard` — the force chart container.
- `upcomingSetCard` — the V1RestoreSection upcoming-set
  panel.
- `dropSetSection` — the drop-set chip + bar section.
- `loggedSetsSection` — the logged-sets list.
- `bottomActions` — the bottom action bar (LOAD/UNLOAD,
  ADD/EDIT, FINISH).
- `pageBadge` / `buildBadge` — the chrome layer overlays
  themselves (lowest priority).

**Resolution plan.** Add `.debugRegion("name")` calls
incrementally as the user identifies regions they want labeled.
Each addition is a 1-line change, doesn't require an ADR, and
ships in whatever feature build is open at the time. KI-12
closes when the 7 high-priority regions above are all
instrumented on `LiveCaptureViewV2` and `LoggingHomeView`.

### KI-13 (b73 → b74) — Scroll-anchored row labels (CLOSED in b74)

**Status.** Closed in b74 / V4-D24.

**Original problem (b72/b73).** b72's grid was viewport-anchored
on both axes; "C10" pointed to a physical pixel rather than a UI
element, so the row coordinate of an element changed with scroll.
b73 / V4-D23 attempted to fix this with a `DebugGridContentMetricsKey`
PreferenceKey + `contentMinY` translation in the viewport-level
overlay, but on device the grid still rendered viewport-pinned —
the translation pass either never updated, never produced a
visible offset, or was clipped by the overlay frame.

**b74 / V4-D24 fix.** The grid is split into two physical
layers. The viewport-pinned half (vertical lines + column
letters + region overlay) lives in `.debugGridOverlay()` on the
screen body. The content-space half (horizontal lines + row
labels) is implemented as `DebugGridContentLayer` and attached
via `.background(DebugGridContentLayer())` (modifier
`.debugGridContentLayer()`) to the inner content container of
each ScrollView. SwiftUI's background sizing makes the layer's
frame inherit the host's intrinsic frame, so the layer covers
the full scrollable content and physically scrolls with it —
no PreferenceKey, no named coordinate space, no translation.

**Screens wired in b74** (10): `LoggingHomeView`,
`LiveCaptureView`, `LiveCaptureViewV2`, `ExerciseDetailView`,
`ExerciseStartView`, `DebugView`, `DashboardView`,
`ExercisePickerView`, `SetLogView`, `ExportSheet`.

**Screens intentionally NOT wired** (3): `ConnectView` (no
ScrollView), `LiveCaptureContainer` (b53 router forwarder, owns
no content), `ContentView` (host shell, owns no content). On
those screens row labels do not render at all — there is no
ScrollView for the layer to attach to. The viewport-pinned
column letters + vertical gridlines are still drawn so the X
axis remains useful.

**When to revisit.** If a future cycle adds a ScrollView to
`ConnectView` or any other currently-unwired screen, that
screen must add `.debugGridContentLayer()` to its inner content
stack in the same commit. Otherwise no action.

**Verification status.** b74 PR opened on
`feat/b74-debug-grid-content-space` is UNVERIFIED — awaiting
on-device verification on TestFlight (b73 still shipping). When
the user confirms the grid moves with scroll on device, this
entry should be revised to "Closed — VERIFIED on device on
build N."

---

## Telemetry v2 (active-cycle) known issues (KI-14 … KI-26)

> Opened 2026-05-03 in the docs-only alignment commit before the
> Authoritative Device State + Telemetry Collector v2 work begins.
> Each entry below is a problem that the v2 spec
> (`03_CURRENT_FEATURE_SPEC.md`, "Authoritative Device State +
> Telemetry Collector v2") explicitly addresses. They are tracked
> here so progress can be measured commit-by-commit.

### KI-14 (post-b78) — Handoff/current-state docs were stale

**Status.** Closed at the docs-only alignment commit on
2026-05-03.

**What.** A previous handoff prompt referenced
`docs/handoff/02_CURRENT_STATE.md` as stale at v0.4.34 / build 56
while the current tested build was actually v0.4.51 / build 78.
On inspection the file had already been advanced to "b78
SHIPPING" (the b78 ship commit's same-commit doc update) but had
NOT been advanced to "b78 SHIPPED" with the run + Delivery UUID
artifacts after the tag-triggered release succeeded.

**Resolution.** The docs-only alignment commit:
- Advanced `02_CURRENT_STATE.md` from "SHIPPING" to "SHIPPED"
  with run 25268455532, merge SHA `32f9300`, and Delivery UUID
  `3433cd79-fb4a-48db-9c70-b3e0289740e1`.
- Wrote down the demo-mode and hardware-mode recorder
  verification observations that previously lived only in chat
  (33-event demo session export; 1000-event live VOLTRA
  session with real BLE write/ack/notify chain, base-weight
  changes, probable load cutout) — explicitly NOT signing them
  off as QA passes A–G until they are written per-pass to
  `QA_LOG.md`.
- Set the Active cycle to "Authoritative Device State +
  Telemetry Collector v2" (docs-first).

**General lesson.** Whenever the post-tag CI run completes and
5-gate altool verify passes, the verification artifacts (run
ID, altool wall-clock, Delivery UUID, success markers) MUST be
written to `02_CURRENT_STATE.md` and `WORK_LOG.md` in a
follow-up commit on the working branch. Letting the ship facts
sit only in chat is what created this drift.

### KI-15 (post-b78, open) — Duplicate `ble.write.tx` events

**Status.** Open. Targeted by Telemetry v2 implementation step 8.

**What.** The b78 recorder emits duplicate `ble.write.tx`
events for the same payload. Observed during the 1000-event
hardware session. Inflates event count, makes the actionId
chain harder to read, and contributes to the buffer-fill rate
described in KI-17.

**Resolution plan.** De-dupe within a small window; collapse
to a single event with a `coalescedCount` field. Spec is in
`03_CURRENT_FEATURE_SPEC.md` "Telemetry recorder improvements".

### KI-16 (post-b78, open) — Demo-mode not-connected guard logs as `ble.error`

**Status.** Open. Targeted by Telemetry v2.

**What.** When demo mode is enabled and a BLE write is
attempted with no Voltra connected, the guard fires a
`ble.error` event AHEAD of the corresponding write event.
Reading the recorder timeline left-to-right makes it look
like the error caused the write, when in reality the guard
prevented the write from happening. Misleading.

**Resolution plan.** Rename the event to `ble.write.skipped`
with payload `{reason: "not_connected"}`, and emit it AFTER
the `write.request` event so the chain is visually correct:
`ui.tap → write.request → write.skipped`.

### KI-17 (post-b78, open) — 1000-event cap fills too quickly in real live capture

**Status.** Open. Targeted by Telemetry v2 buffer-policy
change.

**What.** The 1000-event in-memory buffer (b78) fills within
a single representative live VOLTRA session (1000-event
hardware capture observed in chat). High-frequency stream
frames dominate. Useful incident context gets evicted before
the user has a chance to look at the export.

**Resolution plan.** Switch to a 5000-event ring buffer AND
compress repeated identical high-frequency stream frames in
the human-readable `.txt` export (preserve full fidelity in
JSON). See `03_CURRENT_FEATURE_SPEC.md` "Constants" and
"Telemetry recorder improvements".

### KI-18 (post-b78, open) — Session Recorder lacks semantic device-state events

**Status.** Open. Targeted by Telemetry v2.

**What.** Today the recorder captures `ble.write.tx`,
`ble.write.ack`, `ble.notify.rx`, `ui.tap` and lifecycle/nav
events. It does NOT emit a "the device's base weight changed
from X to Y" event, or "load state transitioned from loaded
to unloaded". The user has to read raw hex to figure out what
the machine actually did.

**Resolution plan.** Add `device.state.change`,
`load.state.change` (or its field-of equivalent — see
KI-22 / open question), `incident.loadDropped`,
`write.confirmation.timeout`, `write.request.overridden`,
`ble.stream.gap`. Spec in `03_CURRENT_FEATURE_SPEC.md`.

### KI-19 (post-b78, open) — App lacks authoritative DeviceState mirror

**Status.** Open. Targeted by Telemetry v2.

**What.** The app maintains in-memory state in
`WriterState`, `MultiDeviceManager`, `LoggingStore`, etc., but
none of those is a **decoded mirror of what the machine
reports**. They reflect what the app last wrote, plus
heuristics. There is no single place the UI can read to ask
"what is the live VOLTRA's base weight, ecc, conc, chains,
mode, load state right now, and how confident are we?"

**Resolution plan.** Introduce `DeviceState` per the spec:
each machine-facing field carries
`confirmed | pending | stale | unknown` status. UI binds to
`DeviceState`. Migration is one field at a time, base weight
first.

### KI-20 (post-b78, in progress) — Machine-side weight changes do not reliably update app

**Status.** In progress. Decoder + reducer landed in the
first Telemetry v2 slice; UI binding to `DeviceState` for
base-weight is the remaining piece before this can be marked
resolved.

**What.** User adjusts the dial on the VOLTRA itself. App
display does not update without manual refresh. Observed in
the hardware verification session.

**Progress (this commit).**
- `VoltraBLEFrameDecoder` recognizes the `86 3E XX YY` token
  in any assembled notify frame and decodes the trailing two
  bytes as `uint16-LE` pounds.
- Hypothesis pinned via byte-vector parity with the writer
  side: the captured iPad frames in
  `VoltraControlFramesTests` show `setBaseWeightPayload(5)`
  produces `0100863E0500`, `setBaseWeightPayload(10)`
  produces `0100863E0A00`, etc. The device echoes the same
  param-id + uint16-LE value layout when confirming, so the
  observed `863e5f / 863e14 / 863e0f` from the hardware
  session decode correctly to 95 / 20 / 15 lb.
- `PendingWriteTracker` (2 s window) attributes confirmations
  to `appRequestConfirmed` vs. `deviceUnsolicited`; the
  writer registers outbound base-weight writes via the new
  `onOutboundParam` callback wired in both `WriterRouter`
  (single-device) and `MultiDeviceManager` (per-side).
- `device.state.change` semantic events now flow through
  `SessionRecorder` under the new `.device` category.

**Remaining for resolution.**
- Bind LiveCaptureView's base-weight tile to
  `VoltraBLEManager.deviceState.baseWeightLb` so the dial
  update visibly reaches the user.
- Hardware re-verification with the recorder armed to
  confirm the `device.state.change` event stream matches
  observed dial movements end-to-end.
- Eccentric / chains / mode confirmations remain deferred
  (KI-21).

### KI-21 (post-b78, open) — Eccentric/concentric/chains can drift between hardware and app

**Status.** Open. Targeted by Telemetry v2 (deferred until
BLE characteristic audit + decoder validation).

**What.** When the user changes ecc / conc / chains values on
the machine itself, the app's in-memory model can drift. Byte
positions for these fields in device-state frames are
**unknown**. The decoder cannot fix this until those positions
are validated on hardware.

**Resolution plan.** Until validated, the UI greys those
fields and the recorder emits
`device.state.change(field=..., status=unknown)` so we can see
the frame arrived but couldn't decode it. Promotion to
`confirmed` waits on hardware validation.

### KI-22 (post-b78, open) — Load drop / unload / cutout not surfaced to app state

**Status.** Open. Targeted by Telemetry v2 LoadState +
stream-gap detection.

**What.** During the 1000-event hardware session a probable
load cutout was observed (status byte transition described in
KI-23). The app continued behaving as if the cable were still
loaded. Rep counting and weight-stable assumptions were
wrong for that window.

**Resolution plan.** Implement `LoadState` with the six
states (`idle / armed / loaded / unloaded / fault / unknown`),
the 500 ms soft + 2000 ms hard stream-gap thresholds, the
`loaded → unloaded` set-interrupt + banner behavior, and the
no-auto-resume on `unloaded → loaded`. Spec in
`03_CURRENT_FEATURE_SPEC.md`.

### KI-23 (post-b78, open) — `0x03` status byte is only a hypothesis

**Status.** Open. Hypothesis-tracking entry.

**What.** In a `553404ac` status frame observed during the
hardware session, a byte transitioned `0x02 → 0x03` around
the load-cutout event. **Hypothesis:** `0x03` means
"load dropped / cutout". Single-session observation. Not
enough to promote to a named constant.

**Resolution plan.** Multi-session corroboration on hardware,
fixture-pin in `VoltraLiveTests/ProtocolGoldenTests.swift` (or
a new sibling test file for the additive decoder), THEN
promote to a named constant. Until then the decoder treats
`0x03` as a candidate and the UI/recorder must not assume the
meaning. See open question OQ-T2 in `10_OPEN_QUESTIONS.md`.

### KI-24 (post-b78, open) — `553a0470` phase / tension byte unknown

**Status.** Open. Hypothesis-tracking entry.

**What.** In `553a0470` stream frames, a byte near
`2b000100` vs `2b010100` may represent phase / tension state.
Hypothesis only.

**Resolution plan.** Same gate as KI-23: hardware
corroboration → fixture pin → named constant. See open
question OQ-T3 in `10_OPEN_QUESTIONS.md`.

### KI-25 (post-b78, open) — Weight/ecc/conc/chains controls missing `ui.tap` / `actionId` instrumentation

**Status.** Open. Targeted by Telemetry v2 recorder
correlation work.

**What.** Today's recorder cannot draw a complete chain from
"user tapped weight +5" to "device confirmed weight=85"
because the source `ui.tap` event is missing on those
controls. The chain is broken at the user's finger.

**Resolution plan.** Add `recorder.uiTap(...)` calls inside
an `ActionScope.run { ... }` on every weight / ecc / conc /
chains stepper and on the LOAD/UNLOAD button. The
`actionId` then propagates through the writer + decoder by
the existing task-local mechanism.

### KI-26 (post-b78, open) — Need BLE characteristic audit

**Status.** Open. Step 1 of Telemetry v2 implementation.

**What.** Before the decoder finalizes byte-position
assumptions, every BLE service/characteristic exposed by the
VOLTRA must be enumerated against nRF Connect or LightBlue.
There may be a notify-capable characteristic the iOS app does
not currently subscribe to that carries device-state
updates we are missing today.

**Resolution plan.** User runs nRF Connect or LightBlue
against a paired Voltra and pastes results into
`05_BLE_AND_PROTOCOL.md` "BLE characteristic audit
(post-b78)". Decoder work cannot finalize before this is
done.
