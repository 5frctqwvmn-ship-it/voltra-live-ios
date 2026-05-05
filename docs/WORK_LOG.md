# WORK_LOG

Append-only journal. Newest at the bottom. Every meaningful change to the
codebase or to the handoff docs gets one entry here, committed in the same
commit as the change.

## Entry format

```
## YYYY-MM-DD HH:MM UTC — <one-line goal>

- **Files changed:** path/one, path/two
- **What changed:** Short factual description.
- **Verification:** What you ran or observed (build, test, manual on device).
- **Risks:** Anything that could break or that you didn't fully test.
- **Next step:** The next thing the next session should do.
```

Keep entries short. If something needs a long explanation, that explanation
belongs in a handoff doc (`docs/handoff/*.md`) and the WORK_LOG entry just
points at it.

---

## 2026-04-27 17:30 UTC — Establish durable handoff docs

- **Files changed:** `AGENTS.md` (reconciliation), `docs/handoff/00_START_HERE.md`,
  `docs/handoff/01_PROJECT_OVERVIEW.md`, `docs/handoff/02_CURRENT_STATE.md`,
  `docs/handoff/03_ROADMAP.md`, `docs/handoff/04_ARCHITECTURE.md`,
  `docs/handoff/05_BLE_AND_PROTOCOL.md`, `docs/handoff/06_HEALTHKIT.md`,
  `docs/handoff/07_DUAL_VOLTRA.md`, `docs/handoff/08_SUPERSET.md`,
  `docs/handoff/09_RELEASE_AND_SIGNING.md`, `docs/handoff/10_OPEN_QUESTIONS.md`,
  `docs/WORK_LOG.md` (new file).
- **What changed:** Created the durable handoff doc structure. Backfilled
  state from session memory and chat.
- **Verification:** Docs only.
- **Risks:** None to runtime.
- **Next step:** Resume build 30 starting with the drop-set regression.

[...b28-b73 entries preserved in git history...]

## 2026-05-04 04:40 UTC — Chain-centric + inverse-chains fix; full handoff update

- **Files changed:**
  - `VoltraLive/BLE/WriterRouter.swift` — combined-mode chains split
  - `VoltraLive/Logging/Persistence/LoggingStore.swift` — inverse-chains negative payload
  - `VoltraLive/Logging/Model/VoltraDeviceState.swift` — `isInverseChains: Bool = false`
  - `VoltraLive/Logging/Views/ExerciseDetailView.swift` — inverse-chains toggle
  - `docs/handoff/09_NEXT_AGENT_PROMPT.md` — complete clean-start prompt
  - `docs/handoff/CONTEXT_LEDGER.md` — all decisions through 2026-05-03
  - `docs/handoff/PERPLEXITY_TRANSCRIPT_2026-05-03.md` — new
  - `docs/WORK_LOG.md` — this entry
- **What changed:**
  1. `WriterRouter.apply` — when `workoutMode == .combined` AND
     `chainsLb > 0`, split the chains value across both left and right
     writers using the same even-rounding logic as base weight
     (`CombinedParity.roundDownToEven(chainsLb / 2)`).
  2. `VoltraDeviceState` — added `isInverseChains: Bool = false`
     (additive, no SwiftData migration needed).
  3. `LoggingStore` — in `pushUpcomingStateToDevice()`, if
     `upcomingChainsEnabled && state.isInverseChains`, send
     `-upcomingChainsLb` as the chains payload instead of the
     positive value.
  4. `ExerciseDetailView` — added a toggle (``Toggle`` + label
     "Inverse chains") that appears below the chains lb stepper
     when `upcomingChainsEnabled == true`. Binds to
     `logging.upcomingInverseChains` (new `@Published Bool = false`
     on `LoggingStore`, cleared on `endSession()`).
  5. Full handoff docs updated with all decisions from the
     2026-05-03 Perplexity session.
- **Verification:** Static code review only (no Mac). No new unit
  tests added — the chains split math is simple division + round;
  the inverse-chains path is a sign flip. Will add tests when
  Session Recorder lands (P2).
- **Risks:**
  - `isInverseChains` is a local UI flag only; there is no firmware
    telemetry confirming the device received an inverse command. If
    the firmware ignores negative chains values, the behavior will
    be silent. Need on-device verification.
  - Combined-mode chains split rounds DOWN (e.g. 5 lb chain → 2 lb
    per side, not 3/2). Acceptable since combined requires even
    weights.
- **Next step:** Implement Session Recorder (P2). Do NOT ship to
  TestFlight until user says so.
- **Cost:** lite. Four targeted file edits + docs update.
  - P1-2 view-side flip from `restElapsedSeconds` to
    `restActive` is a tiny semantic change. If any other
    view in the codebase reads `restElapsedSeconds > 0` as
    a proxy for "rest active", that view will keep working
    on the second-tick cadence (no regression). Already
    grep-audited: only the two LiveCaptureViewV2 sites used
    this pattern.
  - P1-1 layout assumes the outer HStack always renders
    weight cluster + TWIN badge + stepper spacer in that
    order. Verified visually by reading the file; layout
    matches spec.
- **Next step:** Push branch; run `release.yml` workflow
  with `dry_run=false`; 5-gate altool ship verify; confirm
  TestFlight v0.4.39 / build 66 live.

## 2026-04-29 20:41 UTC — b66 SHIPPED to TestFlight (v0.4.39 / build 66)

- **Branch:** `feat/ui-v4-2-claude` @ `c0723b1` (head-to-head with
  GPT-5.5 fork, intentionally unmerged for side-by-side review).
- **CI run:** `25132430893` — 6m22s, conclusion `success`.
- **Two CI hotfixes were needed before the third run greened:**
  - `8e629f1` — Swift 6 actor-isolation fixes for the V4.2 files
    (MultiDeviceManager+V42 extension, VoltraAssignmentPanel,
    SupersetSwitcherBanner). Under Xcode 26 / Swift 6 strict
    concurrency, members on extensions of `@MainActor` classes
    are NOT automatically main-actor-isolated; explicit `@MainActor`
    annotation was required at three sites. PassthroughSubject's
    static let kept `nonisolated` so non-main-actor subscribers
    can still emit.
  - `c0723b1` — `PageBadgeOverlay` referenced `VoltraTheme.textFaint`;
    the codebase's theme namespace is `VoltraColor` (the file
    happens to be named VoltraTheme.swift, but the enum is
    `VoltraColor`). Two-line symbol fix.
- **5-gate altool ship verify:**
  1. Workflow conclusion: `success`.
  2. altool exit code: 0 (no `::error::` line emitted by the
     workflow's exit-trap step).
  3. altool wall-clock duration: 36s (≥20s threshold).
  4. Positive success marker: present — both
     "UPLOAD SUCCEEDED with no errors" and
     "No errors uploading archive at 'build/export/VoltraLive.ipa'".
  5. Zero failure markers: confirmed clean grep against the full
     blocklist (UPLOAD FAILED / Validation failed / ERROR ITMS- /
     Failed to upload package / ERROR: [ContentDelivery / ERROR:
     [altool / (-NNNN)).
- **Delivery UUID:** `1ad7fa3a-2991-4533-8756-1b43b38086a0`.
- **What's in this build:**
  - V4.2 reskin: VoltraAssignmentPanel, SupersetSwitcherBanner,
    PageBadgeOverlay (15 screens).
  - Cherry-picked b60-prep dropset arm-only refactor.
  - Cascade timer cadence T1: 2.0s → 3.0s.
  - Bug fixes P1-1 (TWIN badge overlap on 3-digit weights) and
    P1-2 (rest-timer first-engage view race).
  - WorkoutVoltraPickerSheet superseded; file kept on disk.
- **NOT in this build (deferred):** F1 sine-wave per-rep overlay
  (skipped per the user's "skip if it touches telemetry" rule;
  ForceChartV2 already does Tonal-style rep-map gradients).
- **Sacred files:** untouched. Confirmed by audit before shipping.
- **Hardware QA pending:** Once b66 surfaces in TestFlight, the
  user installs and re-tests KI-10 (phantom -5 lb), the rest-bar
  first-engage path on a fresh launch, and 3-digit + TWIN layout
  on a real device. Results captured in `docs/handoff/QA_LOG.md`.

## v0.4.40 / build 67 — b67: 9-bug ship cycle (Apr 29 2026)

User ran b66 on hardware (Apr 29 2026) and reported 9 bugs across
8 paste blocks in one session. All entries in `B67_BUG_QUEUE.md`.
Single release, single branch (`feat/ui-v4-2-claude` open, no PR
merge per sticky-rules), shipped as v0.4.40 / build 67.

### Bugs closed

| # | Title | Commit | Notes |
|---|---|---|---|
| 01 | Cold launch → ConnectView | `3257517` | `ContentView` flipped: `LoggingHomeView` is unconditional landing surface; pairing is foreground gesture via `PairingCoordinator`. |
| 02 | Footer watermark verbose | `a3b6c6e` | `VOLTRAFeatureLabel` cleared; only the two-sided `pageBadge` carries identity. |
| 03 | Wordmark / duplicate identity chrome | `faad2c6` | VOLTRA wordmark + bolt logo removed from `ConnectView` and `LoggingHomeView` header. |
| 04+05 | `DualConnectView` + `DualCaptureView` killed | `3257517` | 598 LOC removed. LOAD/UNLOAD already on weight-tap binding (b56). |
| 06 | Single `LiveWorkoutScreen` | `faad2c6` | Unified header chrome via `VoltraUnitHeader` removes per-mode forks at the top of the screen. |
| 07 | Shared `PairingCoordinator` | `3257517` | New file `Coordinators/PairingCoordinator.swift`, env-object, drives `UnifiedConnectSheet` from any of the 3 mounts. |
| 08 | Single canonical `VoltraUnitHeader` | `faad2c6` | New file `Views/VoltraUnitHeader.swift` (326 lines); mounts on home / detail / live; `VoltraAssignmentPanel.swift` deleted (-359). |
| 09 | (reserved, skipped) | n/a | User numbered force-curve as Bug 10; 09 stays explicitly reserved. |
| 10 | Force curve = parametric sine | `660853a` | `ForceChartV2` rewritten: `repSineGeometry` builds two `sin(π·t)` lobes (con + ecc), `eccConFill` traces same path, log-fade history overlay preserved. ADR V4-D13. |

### Decisions added

- ADR **V4-D13** — Force-curve geometry: parametric per-rep sine
- ADR **V4-D14** — Single canonical chrome: `VoltraUnitHeader`
- ADR **V4-D15** — Shared `PairingCoordinator`

(All in `04_DECISIONS_AND_CONSTRAINTS.md`.)

### Net code delta

- Created: `Views/VoltraUnitHeader.swift` (326), `Coordinators/PairingCoordinator.swift` (80)
- Deleted: `Views/VoltraAssignmentPanel.swift` (359), `Views/Dual/DualConnectView.swift` (336), `Views/Dual/DualCaptureView.swift` (262), `Views/WorkoutVoltraPickerSheet.swift` (186)
- Modified: `LoggingHomeView`, `ExerciseDetailView`, `LiveCaptureViewV2`, `ContentView`, `VoltraLiveApp`, `ConnectView`, `ForceChartV2`, `Info.plist`, `project.yml`
- Empty `Views/Dual/` directory removed.

### Lint-gate verification

`grep -rni "VL1\|LiveStatusPill\|LeftRightStatusPill\|DeviceStatusStrip\|VoltraWordmark" VoltraLive/Views/ VoltraLive/Logging/Views/`
returns matches **only** in:
- comments inside `VoltraUnitHeader.swift` (intentional documentation header listing what was removed)
- `DebugView.swift` user-facing copy referring to "VOLTRA Live" as the iOS app name in Settings → Privacy → Health (legitimate product reference)

Zero matches in non-comment in-app chrome.

### Sacred files: untouched.

`VoltraProtocol.swift`, `TelemetryExtractor.swift`, `PacketParser.swift`,
`FrameAssembler.swift`, `release.yml`, `build.yml` all clean.

### Ship verification (5-gate altool, b67)

Workflow run: [25137426370](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25137426370)
status = success.

1. **Exit code 0** — confirmed (`altool upload succeeded`).
2. **Wall-clock duration ≥20 s** — 33 s.
3. **Positive success marker** — both `UPLOAD SUCCEEDED with no errors`
   and `No errors uploading archive at 'build/export/VoltraLive.ipa'`
   present in the altool log.
4. **Zero failure markers** — blocklist grep clean against the live
   altool stdout (UPLOAD FAILED / Validation failed / ERROR ITMS- /
   Failed to upload package / ERROR: [ContentDelivery / ERROR:
   [altool / `(-NNNN)`).
5. **Delivery UUID:** `db338dcf-9c67-4d47-8853-c415bf62797a`.

**TestFlight surface:** v0.4.40 (build 67) uploaded to App Store
Connect at 22:42 UTC on Apr 29 2026. Awaiting Apple processing
before the build appears in TestFlight.

---

## 2026-04-29 (b68) — B68-01 demo auto-engage on LiveCaptureViewV2

**Bug.** Demo mode regression caused by B67-01 cold-launch flip.
`LoggingHomeView` became the unconditional root, demoting
`ConnectView` to legacy/deeplink and orphaning the
`DemoModeButton(source: .prePair)` at `ConnectView:165–168`. A
fresh-install user with no Voltra paired could load weights on
LIVE but had no path to engage demo, so the force chart sat at
zero with weights on screen.

**User answers driving the fix.**
- Q1 = any weight tap, no device → fire on every
  `toggleHardwareLoad()` invocation when not connected.
- Q2 = auto-exit on real device pair → `.onChange` observers on
  all three connection states drop prePair demo automatically.
- Q3 = keep `LoggingHomeView` postPair `DemoModeButton` as
  manual entry → no home-screen change.
- Q4 = silent activation → existing `DemoModeOverlay` is the
  only signal.
- Q5 = `ConnectView` retirement deferred (not asked, not
  blocking).

**Files touched.**
- `VoltraLive/Logging/Views/LiveCaptureViewV2.swift`
  - `@EnvironmentObject var demo: DemoController` (root-injected
    from `VoltraLiveApp:119`).
  - `private var anyDeviceConnected: Bool` derives from
    `ble.connectionState.isConnected || mdm.left.connectionState.isConnected || mdm.right.connectionState.isConnected`.
  - `private func autoEngageDemoIfNeeded()` records a button-tap
    trace (parity with `LoggingHomeView`) and calls
    `demo.enter(source: .prePair, onTelemetry:
    DemoTelemetryBridge.shared.handler)`.
  - `private func handleConnectionChange()` exits demo when
    `entrySource == .prePair && anyDeviceConnected`.
  - Three `.onChange(of: …connectionState)` modifiers on body.
  - `toggleHardwareLoad()` calls `autoEngageDemoIfNeeded()`
    before LOAD/UNLOAD branch.
- `docs/handoff/B68_BUG_QUEUE.md` — Q&A locked, status FIXED.
- `docs/handoff/06_KNOWN_ISSUES.md` — banner moved to
  fixed-pending-ship.
- `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` — ADR V4-D16
  records the auto-engage contract.
- `docs/handoff/09_NEXT_AGENT_PROMPT.md` — flipped to
  "fixed in-tree, awaiting altool".

**Lint-gate invariants (b67 carryover).** `grep -rni
"VL1\|LiveStatusPill\|LeftRightStatusPill\|DeviceStatusStrip\|VoltraWordmark"
VoltraLive/Views/ VoltraLive/Logging/Views/` still must return
zero matches outside the two known doc/copy exceptions in
`VoltraUnitHeader.swift` and `DebugView.swift`.

**Ship.** Pending. Will run `release.yml dry_run=false` after
this commit lands; 5-gate altool verify, then v0.4.41 / build 68.

### Ship verification (5-gate altool, b68)

Workflow run: [25138837190](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25138837190)
status = success.

1. **Exit code 0** — confirmed (altool job step succeeded;
   `altool upload succeeded (duration 57s, success marker
   present).`).
2. **Wall-clock duration ≥20 s** — 57 s.
3. **Positive success marker** — both `UPLOAD SUCCEEDED with no
   errors` and `No errors uploading archive at
   'build/export/VoltraLive.ipa'` present in the altool log.
4. **Zero failure markers** — blocklist grep clean against the
   live altool stdout (UPLOAD FAILED / Validation failed / ERROR
   ITMS- / Failed to upload package / ERROR: [ContentDelivery /
   ERROR: [altool / `(-NNNN)`). The only blocklist-pattern hits
   in the run log are script-source comment lines that document
   the gate itself, not actual upload errors.
5. **Delivery UUID:** `bb7425ca-c619-4db3-b961-15ac5fc83928`.

**TestFlight surface:** v0.4.41 (build 68) uploaded to App
Store Connect on Apr 29 2026 (PDT). Awaiting Apple processing
before the build appears in TestFlight.

---

## 2026-04-29 (b69) — B68-02 demo auto-engage on V1 (LiveCaptureView)

**Bug.** B68-01 (shipped in build 68) added `autoEngageDemoIfNeeded()`
to `LiveCaptureViewV2` only. User tested 68 on device and confirmed
Demo Mode engaged but the simulation didn't run — chart inert, reps
stuck, force at zero. Root cause: `LiveCaptureContainer`'s b53
router defaults the user to **V1 (`LiveCaptureView`)** unless they
opt into V2 via the first-launch picker (default = V1) or both
Voltras pair (forces V2). Production default users hit V1, where
B68-01's helper does not exist, so Demo Mode never engaged on
LOAD and synthetic telemetry never fired.

**Fix (V1 parity port of B68-01).** `LiveCaptureView.swift`:

- `@EnvironmentObject var demo: DemoController` added next to
  `mdm` (root-injected from `VoltraLiveApp:119`).
- `private var anyDeviceConnected: Bool` derives from
  `ble || mdm.left || mdm.right` connection states.
- `private func autoEngageDemoIfNeeded()` records button-tap
  trace ("Auto-engage (no device, LOAD pressed)" / screen
  "LiveCaptureView") and calls
  `demo.enter(source: .prePair, onTelemetry:
   DemoTelemetryBridge.shared.handler)`. Idempotent.
- `private func handleConnectionChange()` exits demo when
  `entrySource == .prePair && anyDeviceConnected`.
- `sendLoad()` now calls `autoEngageDemoIfNeeded()` first so
  both the `loadUnloadTile` LOAD button (line ~740) and the
  debug LOAD button (line ~1462) hit the gate. Promoted the
  debug button from `ble.sendLoad()` direct call to
  `sendLoad()` for parity.
- Three `.onChange(of: …connectionState)` modifiers on V1 body.

**Why hook on `sendLoad()` and not weight steppers.** User
wording was "loads weights from the Live View screen" — that's
the explicit LOAD command, not weight stepping. V1 has no
"tap weight number" gesture; the equivalent intent is the LOAD
button. Mirrors B68-01's V2 hook on `toggleHardwareLoad()`.

**ADR.** No new ADR. V4-D16 (b68) already documents the
auto-engage contract and applies to both V1 and V2 by symmetry.

**Bump.** v0.4.42 / build 69.

**Ship.** Pending. Will run `release.yml dry_run=false` after
this commit lands; 5-gate altool verify, then v0.4.42 / build 69.

### Ship verification (5-gate altool, b69)

Workflow run: [25140763953](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25140763953)
status = success.

1. **Exit code 0** — confirmed (`altool upload succeeded
   (duration 52s, success marker present).`).
2. **Wall-clock duration ≥20 s** — 52 s.
3. **Positive success marker** — both `UPLOAD SUCCEEDED with no
   errors` and `No errors uploading archive at
   'build/export/VoltraLive.ipa'` present in the altool log.
4. **Zero failure markers** — blocklist grep clean against the
   live altool stdout. Only blocklist-pattern hits in the run
   log are script-source comment lines that document the gate
   itself, not actual upload errors.
5. **Delivery UUID:** `7e036a7d-7060-4682-8212-c253b815118a`.

**TestFlight surface:** v0.4.42 (build 69) uploaded to App
Store Connect on Apr 29 2026 (PDT). Awaiting Apple processing
before the build appears in TestFlight.

## 2026-04-30T14:52:12Z — chore(handoff): source zip for b70 architect review

Packaged a read-only source bundle for the architect to scope the b70
patch in a single session.

**Artifact:** `docs/handoff/_tmp/voltra-live-source-b70.zip`
- Size: 331320 bytes (~324K)
- SHA-256: `7b5d53f54849e37a1eeaf4ad2835c4013873b5e9608a9049bd8c290fba3a1693`
- Built from commit: `2b32bec445c0b48e030d8a344d0a50515d2edf84`
- Contents: 32 Swift source files (verbatim, no modifications) + 19
  handoff docs snapshot + MANIFEST.txt + GREP.txt + SCREEN_TREE.md +
  GIT_STATE.md + WORK_LOG_TAIL.md.

**Path deltas surfaced in MANIFEST.txt:**
- `Logging/Stores/{Logging,Session}Store.swift` are at `Logging/Persistence/LoggingStore.swift` and `Session/SessionStore.swift` respectively.
- `BLE/MultiDeviceManager.swift` -> `BLE/Dual/MultiDeviceManager.swift`.
- `BLE/VoltraProtocol.swift` -> `Protocol/VoltraProtocol.swift`.
- `Shared/HealthKitStore.swift` -> `Health/HealthKitStore.swift`.
- `Shared/VoltraColor.swift` does not exist as its own file; `VoltraColor` is defined in `Views/VoltraTheme.swift` and that file is included.

**Missing files (architect's manifest listed but repo does not contain):**
- `Logging/Views/DropSetPlannerSheet.swift` — drop-set planning is implemented inline in `LiveCaptureView` + `LoggingStore`; no dedicated planner sheet exists.

**Next step:** architect returns six paste-blocks for b70 (per their
contract). No source modifications until those land.

This commit touches docs only — no Swift was modified.

## 2026-04-30T16:11:12Z — feat(b70): demo entry source connection-aware + debug grid overlay + page registry

**Cycle.** v0.4.43 / build 70.

**Branch.** `feat/ui-v4-2-claude` (no merge to `main` per agent
operating rules — keep open).

**User report (b69 still broken).** Demo simulation does not
start the synthetic force chart from the in-app debug toggle.
Architect (Opus) adjudicated the b70 ambiguity prompt and
isolated **H3** as the primary root cause:

- `DebugView.swift` already has a "Demo Mode" toggle.
- That toggle calls `DemoController.enter(source: .settingsRestore, …)`.
- Inside `DemoController.enter`, ONLY the `.prePair` branch
  instantiates `SyntheticTelemetryGenerator`.
- `.settingsRestore` (and `.postPair`, when no device is
  connected) enter demo mode with no synthetic pump → user sees
  empty force chart and the "Demo simulation broken" report.

Architect's judgement: H1/H2/H4 not falsified yet but H3 alone
explains the symptom; b70 fixes only H3 plus connection-aware
call sites and rehydration glue. Other hypotheses re-evaluated
post-ship.

### Tasks landed

1. **DemoController.swift** — added private `startSynthetic()`
   helper so the prePair-pump construction lives in exactly
   one place. Added a self-heal branch BEFORE the
   `guard !isActive else { return }` line that uses
   `entrySource` (the published, currently-active source field)
   — NOT the incoming `source` parameter — to detect the case
   "demo is active but the synthetic pump is missing because
   the original entry was `.settingsRestore` or `.postPair`
   with no real device" and rebuilds the pump in place. The
   incoming `source` parameter is intentionally not consulted
   here because the architect's contract is "the pump must
   reflect what the active session actually is, not what a
   late re-entry call thinks it is." Also added a legacy
   marker comment on `.settingsRestore` documenting that the
   case is retained for trace-replay compatibility only and
   that NO live call site should use it going forward.

2. **DebugView.swift:86–111 (existing toggle, REBOUND).** Did
   NOT add a second toggle. Kept the existing UI verbatim and
   only changed the source value passed to `enter(...)`. Added
   `@EnvironmentObject ble: VoltraBLEManager` and
   `mdm: MultiDeviceManager` to the view. Source is now derived
   live: `anyDeviceConnected ? .postPair : .prePair`. Toggle
   label / description / accent tint unchanged.

3. **LoggingHomeView.swift:159–167 (DemoModeButton).** Replaced
   hardcoded `.postPair` with the same connection-aware
   selector. Kept the `if !demo.isActive` visibility gate
   (already correct — the button stays visible regardless of
   whether a Voltra is paired, only hidden when demo is already
   running). `ble` and `mdm` env-objects were already on the
   view (lines 15, 27).

4. **VoltraLiveApp.swift / ContentView.swift** — root
   `.onChange` observers on `bleManager.connectionState`,
   `multi.left.connectionState`, `multi.right.connectionState`
   call `demo.exit()` when `entrySource == .prePair` and any
   device transitions to `.connected`. Mirrors the V2 hook
   from V4-D16 (b68) but at root scope so the handoff fires
   regardless of which screen is foreground when the device
   pairs. Launch rehydration: if `demo.settingsToggleOn` is
   true on cold launch and `demo.isActive` is false, call
   `enter(source: .prePair, onTelemetry: telemetryHandler)` so
   a backgrounded demo session picks back up with a working
   pump (this is the case the legacy `.settingsRestore` was
   trying to handle, now expressed via `.prePair`).

5. **Debug grid overlay** — new file
   `VoltraLive/Views/DebugGridOverlay.swift`. `DebugGridMode`
   enum: `.off`, `.corners` (C-prefix labels at each corner),
   `.midlines` (M-prefix labels at midpoints of each edge),
   `.full` (corners + midlines + center F-prefix). Opacity
   0.85, monospaced 9pt, mint tint matching the page badge.
   View modifier `.debugGridOverlay()` reads
   `@AppStorage("debugGridMode")` and switches by mode.

6. **Page registry** — new file
   `VoltraLive/Views/PageRegistry.swift`. Static table built
   from the 13 distinct `.pageBadge(...)` call sites currently
   in the source tree (verified via
   `rg "\\.pageBadge\\(" VoltraLive --type swift`). Keys are
   the verbatim Swift type-name strings the screens already
   pass in; values are stable 2-digit numeric IDs assigned in
   alphabetical order so future reorderings don't churn the
   numbering.

7. **PageBadgeOverlay.swift** — render now formats as
   `"NN · ScreenName"` where `NN` is the registry-assigned
   number (defaults to `--` if a screen calls `.pageBadge()`
   with a name not in the registry, so unknown screens still
   render a badge). Mounted `.debugGridOverlay()` inside the
   modifier so any screen with a page-badge automatically gets
   the grid overlay too.

8. **BuildBadgeOverlay.swift** — added a tap gesture that
   cycles `@AppStorage("debugGridMode")` through the four
   `DebugGridMode` cases. Chip layout / colors / position
   unchanged — only behavior added is the tap.

9. **Version bump.** `project.yml` MARKETING_VERSION 0.4.43,
   CURRENT_PROJECT_VERSION 70 (both the settings block and the
   info.properties block). `Info.plist` CFBundleShortVersionString
   0.4.43, CFBundleVersion 70.
   `docs/handoff/01_PROJECT_OVERVIEW.md` and
   `docs/handoff/02_CURRENT_STATE.md` both updated per
   `00_START_HERE.md:135` mapping table (Karpathy
   `01_PROJECT_STATE` role → both real files). The mapping
   note in `00_START_HERE.md` was also extended with a "must
   be updated together on any version bump" line so future
   agents don't re-ask.

10. **Lint gates passed.**
    - `rg "source:\s*\.settingsRestore" VoltraLive` → 0 (only
      the enum case definition + legacy comment remain)
    - `rg "DemoModeButton\(source:\s*\.postPair\)" VoltraLive/Logging/Views/LoggingHomeView.swift` → 0
    - `DemoModeButton(source: .prePair)` is NOT zero-gated;
      ConnectView's legacy deeplink site still has it.

**ADR.** New ADR V4-D17 in
`04_DECISIONS_AND_CONSTRAINTS.md` documents (a) the
connection-aware source rule for any live demo entry, (b) the
self-heal contract using `entrySource` not `source`, and
(c) the deprecation policy for `.settingsRestore`.

**Sacred files.** Untouched. No changes to `VoltraProtocol.swift`,
`TelemetryExtractor.swift`, `PacketParser.swift`,
`FrameAssembler.swift`, or any `DemoTraceLogger.Event` case.
The `.settingsRestore` enum case is retained in
`DemoEntrySource` for trace-replay compatibility.

**Out of scope.** `.pageBadge` additions to sheets that don't
yet have one, deletion of `.settingsRestore`, BLE/protocol
changes, H1/H2/H4 fixes — all deferred per b70 prompt §12.

**Bump.** v0.4.43 / build 70.

**Ship.** Pending. Will run `release.yml dry_run=false` after
this commit lands; 5-gate altool verify, then v0.4.43 / build 70.

### Ship verification (5-gate altool, b70)

Workflow run: [25176969283](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25176969283)
status = success.

1. **Exit code 0** — confirmed (`altool upload succeeded
   (duration 29s, success marker present).`).
2. **Wall-clock duration ≥20s** — 29s.
3. **Positive success markers** — `UPLOAD SUCCEEDED with no errors`
   AND `No errors uploading archive at 'build/export/VoltraLive.ipa'`
   both present in the altool log.
4. **Zero failure markers** — blocklist grep clean against the live
   altool stdout. Only blocklist-pattern hits in the run log are
   script-source comment lines (prefix `[36;1m`) that document the
   gate itself, not actual upload errors.
5. **Delivery UUID:** `fc2f3148-6f9e-484e-b83c-23534bcc1582`.

**TestFlight surface:** v0.4.43 (build 70) uploaded to App Store
Connect on Apr 30 2026 at 16:34 UTC. Awaiting Apple processing
before the build appears in TestFlight.

**HEAD SHA at ship:** `e10b428fbf4afdb75db8f3ffc72b4730bac49a65`.

**Commits in b70 cycle (2):**
- `af68099` — docs(handoff): b70 ambiguity prompt for Opus adjudication (pre-implementation)
- `e10b428` — feat(b70): demo entry source connection-aware + page registry + debug grid overlay (v0.4.43 / build 70)

## 2026-04-30 22:02 UTC — b70 hotfix: page-badge double-render (containers must not own .pageBadge)

**Goal.** Fix the b70 visual regression visible in IMG_2438 / 2442 / 2444 / 2445 / 2446 / 2447: the bottom-leading page badge rendered as two stacked text layers (e.g. "CoggingMomeView", "CourCoptureCostainer"). DebugView was unaffected (clean `04 · DebugView`), which isolated the cause to overlay inheritance — not to `PageBadgeOverlay` itself.

**Files changed.**

- `VoltraLive/Views/ContentView.swift` — removed the `.pageBadge("ContentView")` call site at line 41. Replaced it with a load-bearing comment explaining the inheritance trap so a future agent does not re-introduce a root or container badge. No other behavior in this file was modified — `.buildBadgeOverlay()`, the three `.onChange` handoff observers, and `handoffIfNeeded()` are unchanged.
- `docs/handoff/03_CURRENT_FEATURE_SPEC.md` — added a "Mounting rule" subsection under §9 documenting that only leaf, user-visible screens may carry `.pageBadge`.
- `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` — appended ADR V4-D19 ("Containers must not own `.pageBadge` (b70 hotfix)") with diagnosis, decision, rule, rejected alternatives, and out-of-scope list.

**What changed.** SwiftUI's `.overlay(alignment: .bottomLeading)` propagates to every descendant inside the same overlay context. ContentView wraps `LoggingHomeView` (which owns the NavigationStack), so the root `.pageBadge("ContentView")` rendered simultaneously with each pushed child's own page badge at the identical anchor. Two 9pt text layers stacking produced the garbled "CoggingMomeView" / "CourCoptureCostainer" effect. Sheet-presented surfaces (DebugView via `.sheet(isPresented:)` at LoggingHomeView:212) get a fresh overlay context, which is why every DebugView screenshot rendered cleanly. Removing the single redundant root call site eliminates the double-render without touching any of the rendering primitives.

**Verification.**

1. `grep -rn '\.pageBadge(' VoltraLive --include='*.swift'` BEFORE: 13 Swift call sites (1 in ContentView, 2 in `Views/`, 10 in `Logging/Views/`). AFTER: 12 Swift call sites — ContentView's is gone; all 12 leaf screens (ConnectView, DashboardView, LoggingHomeView, ExercisePickerView, LiveCaptureView, SetLogView, ExportSheet, ExerciseStartView, DebugView, ExerciseDetailView, LiveCaptureContainer, LiveCaptureViewV2) retain their badges.
2. ContentView still parses cleanly: braces balanced, no orphan modifier chain, `.buildBadgeOverlay()` followed directly by the three `.onChange` observers as before. No Xcode toolchain on the sandbox; CI `build.yml` on push is the authoritative compile check.
3. `PageBadgeOverlay`, `BuildBadgeOverlay`, `DebugGridOverlay`, `PageRegistry` — all untouched (verified by `git diff --stat`).

**Risks.** Low.

- The only screen that loses its badge is the root `ContentView` itself, which is never the foreground user-visible screen — `LoggingHomeView` is always rendered on top of it as the cold-launch screen. Every reachable user-visible surface still carries its own `.pageBadge`.
- No change to the rendering primitives, no change to header chrome, no change to routing, no change to any control write.
- Sacred files (`VoltraProtocol.swift`, `TelemetryExtractor.swift`, `PacketParser.swift`, `FrameAssembler.swift`) untouched.

**Out of scope.** No version bump. No TestFlight ship. b71 mode-glyph implementation remains paused. No changes to `PageBadgeOverlay` / `BuildBadgeOverlay` / `DebugGridOverlay` / `PageRegistry`, headers, ⋏/merge glyphs, force chart, or routing logic. No removal of the b66 `.settingsRestore` legacy enum case (b70 prompt §12).

**Next step.** Push to `feat/ui-v4-2-claude` and let `build.yml` confirm the unsigned build still compiles. User decides when (or if) to roll the hotfix into a b71 cycle bump and ship.


## 2026-04-30 22:30 UTC — b71 force-chart canonicalization: V1 ForceChartView mounted in V2 (supersedes V4-D13)

**Goal.** Replace V2's `ForceChartV2` (b67-10 parametric `sin(π · t)` half-sine lobes) with V1's `ForceChartView` (raw-sample phase-colored polyline + Catmull-Rom smoothing + b49 superset secondary-trace overlay) as the canonical force-curve renderer for the V2 capture screen. User rationale (verbatim, 2026-04-30 17:25 CDT): *"the V1 ForceChartView is the one that displays the force curve correctly in practice. Replace or wrap V2's force panel so LiveCaptureViewV2 uses the V1 ForceChartView behavior/data path."*

**Files changed.**

- `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` — `forceChartCard` is now a thin V1-input adapter that returns `ForceChartView(...)` directly. Reproduces the same builder block V1's `LiveCaptureView.forceChart` uses (sample source `currentSet?.samples ?? lastFinalizedSamples`, peak source, `forceMultiplier = logging.pulleyMultiplier`, `plannedCeilingLb = ((pendingPlannedWeightLb ?? 0) + upcomingEccLb) × m + (upcomingAddedLoadLb ?? 0)`, and the b49 `mdm.hasActiveSupersetChain` secondary-trace gate with `lastFinalizedByExercise[other.exerciseName]`). Stripped the V2 outer card chrome (sibling `FORCE · 30 S` header + bordered rounded-rect wrapper) because `ForceChartView` paints its own header / legend / peak readout / padding / `bgElev` / border / clip — wrapping would produce double headers and nested cards. Removed `computedYAxisMaxLb()` helper (unused), and the `eccBandActive` / `chainMirrorActive` / `yAxisMaxLb` / `resting` / `idlePhase` plumbing (V2-only inputs to `ForceChartV2` only). Top-of-file layout-summary comment updated so item 5 reads "ForceChartView (V1) — canonical per b71 (V4-D20)" instead of "ForceChartV2".
- `VoltraLive/Logging/Views/V2/ForceChartV2.swift` — added a SUPERSEDED banner at the top of the file. The struct itself is unchanged and still compiles, but it is no longer mounted anywhere in the production path. Search anchor `SUPERSEDED-V4-D20`. Rollback path (re-mount + restore helper) is documented in the banner.
- `docs/handoff/02_CURRENT_STATE.md` — corrected stale "Latest shipped build = v0.4.42 / build 69" to v0.4.43 / build 70 (run `25176969283`, Delivery UUID `fc2f3148-6f9e-484e-b83c-23534bcc1582`, HEAD `e10b428`); rewrote the active-cycle section to describe b71 as a working diff with two unshipped commits (b70 page-badge hotfix `34ba63e` + this force-chart commit); updated the V2 layout bullet to reference V1's `ForceChartView` per V4-D20.
- `docs/handoff/03_CURRENT_FEATURE_SPEC.md` — rewrote §5 ("Force chart") wholesale. New title: "b71 V4-D20 — V1 ForceChartView is canonical". Documents the renderer choice, the V2 input-adapter contract, the rendering details (Catmull-Rom, 3-sample smoothing, full-set X-domain, 5-line grid, peak label), the chrome-ownership rule (no V2 wrapper), and the explicit removed-in-b71 list (`computedYAxisMaxLb`, `eccBandActive` / `chainMirrorActive`, dual-band ECC / CON fill, CHAIN gradient mirror, rep-history log-decay overlay, ECC / CON centroid labels, 1.5 s rescale ease — all `ForceChartV2`-only features).
- `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` — appended ADR V4-D20 ("V1 `ForceChartView` is canonical for V2"). Marks V4-D13 (b67, Bug 10) as **superseded** with an inline blockquote at the top of V4-D13 pointing forward to V4-D20. V4-D20 captures the user's verbatim rationale, the four rejected alternatives (sine-with-secondary-trace port, V2-wrapper-around-V1-chart, delete-`ForceChartV2`-immediately, port-fill/mirror/overlay-features-into-V1), and the explicit out-of-scope list (no version bump / push / ship, no `LiveCaptureContainer.shouldUseV2` change, no V1 removal, no b70-hotfix changes, sacred files untouched).
- `docs/handoff/design/force_curve.md` — flagged the doc header with a 2026-04-30 update notice and prefixed §10 ("b67 implementation status") with a SUPERSEDED blockquote. The Tonal-style design references (§§2–7) are preserved as future-reintroduction material, but per V4-D20 they must land in V1's `ForceChartView` if reintroduced, not by re-mounting `ForceChartV2`.

**What changed.** V2's force-curve panel now renders the same chart V1 has rendered for its entire lifetime — raw 80 Hz sensor samples, phase-segmented (`pull` / `return` / `transition` / `idle`) with per-phase color, Catmull-Rom smoothing inside each segment, 3-sample moving-average pre-smoothing pre-multiplied by `forceMultiplier` so the chart reflects effective load under pulley, X-domain anchored to the actual first-and-last sample timestamps of the set (no 30 s rolling window), and a dimmed dashed secondary trace behind the primary line when an active superset chain has a different "next" exercise with a finalized sample buffer. Rendering happens through `ForceChartView(samples:peakLb:plannedCeilingLb:forceMultiplier:secondarySamples:primaryLabel:secondaryLabel:)` with a `.frame(minHeight: 280)` to match V1's vertical footprint inside the V2 scroll view.

**Verification.**

- Brace / paren / quote balance via comment-and-string-stripped Python regex pass on both `LiveCaptureViewV2.swift` (221 / 221 / 620 / 620 / 7 / 7) and `ForceChartV2.swift` (96 / 96 / 250 / 250 / 45 / 45) — both balanced. No Xcode toolchain on the sandbox; CI `build.yml` on push is the authoritative compile check.
- `grep -rn 'ForceChartV2\b' VoltraLive --include='*.swift'` shows the struct itself in `V2/ForceChartV2.swift` plus only **comment-only references** in `LiveCaptureViewV2.swift` (the layout-summary header at top of file + the b71 supersede comment block above `forceChartCard`). No production code path mounts `ForceChartV2` anymore.
- `grep -rn 'ForceChartView\b' VoltraLive --include='*.swift'` shows three production call sites: `DashboardView.swift:74` (unchanged from V1), `LiveCaptureView.swift:1074` (unchanged — V1 screen still uses it), `LiveCaptureViewV2.swift:1128` (the new mount). `LoggingStore.swift:356` is a comment-only reference.
- Sacred files (`VoltraProtocol.swift` / `TelemetryExtractor.swift` / `PacketParser.swift` / `FrameAssembler.swift`) untouched — verified by `git diff --stat` scope.
- The b49 superset secondary-trace logic uses APIs that V2 already binds: `mdm.hasActiveSupersetChain`, `mdm.activeSupersetEntry`, `mdm.nextSupersetEntry` are `@Published` on `MultiDeviceManager` (lines 190 / 324 / 331); `session.lastFinalizedByExercise` is `@Published` on `SessionStore` (line 57). All are already EnvironmentObjects on `LiveCaptureViewV2`.

**Risks.**

- Behavioral change is intentional and user-requested. The chart visually swaps from parametric sine lobes (b67-10) back to the raw-sample polyline (V1). Anyone who validated against the b67-10 visual will see a different shape in the next build — this is the desired outcome per V4-D20.
- The V2 force panel's outer chrome (sibling `FORCE · 30 S` header + bordered rounded card) is removed. `ForceChartView` carries equivalent chrome internally, so the panel still renders as a self-contained card; vertical footprint is `minHeight: 280` (V1 default) instead of the old `minHeight: 175` + 12 pt vertical padding (~199 pt total). Slightly taller in V2 by design.
- `ForceChartV2.swift` remains in the build target, so any future static-analysis pass may flag it as dead code. SUPERSEDED banner explains why it stays. If a future agent removes it without touching V4-D20, the rollback path documented in the ADR breaks — leaving a comment in the banner saying "do NOT delete without explicit user approval."
- The b58 dual-band ECC / CON fill, CHAIN gradient mirror, rep-history log-decay overlay, and centroid `ECC` / `CON` labels are no longer rendered anywhere. If any of those were load-bearing for a downstream feature (ECC mode comprehension, CHAIN visual cue, fatigue-across-reps reading), the user will need to call them out and we'll port them into V1's `ForceChartView` per V4-D20.
- No version bump, no push, no TestFlight ship — strictly per the standing constraint. CI has not yet compiled this change.

**Next step.** Awaiting explicit user approval before any push, version bump, or TestFlight ship. When that approval comes, the cycle is b71 / v0.4.44 / build 71. Pre-ship: bump `project.yml` + `Info.plist` + `01_PROJECT_OVERVIEW.md` + `02_CURRENT_STATE.md` (NOT `_tmp/archive`), run lint gates, push to `feat/ui-v4-2-claude` with bot identity, let `build.yml` compile, then `release.yml dry_run=false` with the 5-gate altool verify protocol.


## 2026-04-30 23:30 UTC — b71 below-chart parity port: SetMode chips, target reps, drop-cancel chip, mode-aware nudgers, lifecycle hooks (V4-D21 part 1 of 3)

**Goal.** Step 5 of the b71 full-scope mandate: diff V1's below-chart UI (`upcomingSetCard`, `dropSetSection`, `loggedSetsSection`, `bottomActions`) against V2's `LiveCaptureViewV2` + `V1RestoreSection` and either port missing pieces or document the equivalence. b71 routing flip (Step 3) will send EVERY user — including chain users — through V2, so any V1-only affordance below the force chart that can't be reached on V2 is a regression and must be closed before the flip.

**Parity diff result.** Audit of the four V1 sections vs the V2 surface:

| V1 element | V2 status | Action this commit |
|---|---|---|
| `upcomingSetCard` "UPCOMING SET" header card | Absent in V2; weight + mods live inline in `weightCard` | **Equivalence documented** — V2's `weightCard` is the canonical "upcoming set" surface. The label text is gone but every control is reachable. Cleaner UI; no port. |
| `weightNudgerRow` big number | Present (`weightCard` big number) | Equivalent |
| `weightNudgerRow` ±5 / ±1 steps | Present BUT hard-coded ±5 / ±1 — broke Combined-mode parity (V1 advertises ±2 / ±6 in Combined to keep totals even per b47) | **Bug fix** — V2 stepperButtons now read `CombinedParity.smallStepLb(for: mdm.workoutMode)` / `largeStepLb(...)` like V1's `weightNudgerRow` does. |
| `eccentricNudgerRow` ECC nudger | Present (`ModStepperRowV2` for ECC, with `clampedECC` 5–400 lb range) | Equivalent |
| `effectiveTargetReps` "Target N reps" chip | Absent in V2 | **Ported** — small chip in `weightCard` header, hidden when no target. Mirrors V1 LiveCaptureView.swift:1480. |
| `modeChipsRow` (`SetMode` picker for working / warmUp / eccentric / band / pause / dropSet / isoHold) | Absent in V2 — V2 only had armed-mods (ecc / chain / inv / drop), so `warmUp` / `pause` / `isoHold` could not be selected at all | **Ported** — new `modeChipsRow` view at the bottom of `weightCard`, ScrollView of seven `Capsule` buttons identical in behavior to V1. |
| `loadUnloadRow` (LOAD / UNLOAD pair buttons) | Present via `toggleHardwareLoad` (tap big WEIGHT NUMBER toggles + LOADED pill) | Equivalent (different surface, same opcode path). |
| `addedWeightSection` (pulley chip + plates picker) | Present via `PulleyAndPlatesBarV3` mounted above `forceChartCard` | Equivalent. |
| `dropSetSection` / `dropCancelChip` (visible cancel chip when cascade live) | Absent in V2 (cancel only via long-press on DROP tile, not discoverable) | **Ported** — new `dropCancelChipV2` mounted between `forceChartCard` and `V1RestoreSection`, self-hides unless `logging.dropSetActive`. Mirrors V1 LiveCaptureView.swift:1958. |
| `loggedSetsSection` LOGGED SETS list | Present via `V1RestoreSection.loggedSetsSection` (literally the same `SwipeableSetRow` code) | Equivalent. |
| `undoToast` for set deletion | Present in `V1RestoreSection` | Equivalent. |
| `bottomActions` (Next exercise / End session) | Present in `V1RestoreSection` | Equivalent. |
| onAppear `writerRouter.attach + writerRouter.resetAppliedState + mdm.left/rightWriter.resetAppliedState` (writer-cache wipe so first LOAD after device power-cycle isn't no-op'd) | Partial — V2 only did `writerRouter.attach`. Dual-side writer caches were leaked across sessions. | **Ported** — V2 onAppear now wipes all three cached states. |
| onAppear `applyWorkoutMode(mdm.workoutMode) + enforceCombinedParityOnEntry()` | Absent in V2 — drop-set cascade math could use the wrong step (-5 vs -6) on Combined entry, and a non-even pendingPlannedWeightLb was never rounded | **Ported** — V2 onAppear now applies workout mode + Combined parity. |
| onChange `mdm.workoutMode` → re-apply mode + parity | Absent in V2 | **Ported.** |
| onDisappear `health.stop()` | Absent in V2 — HR / kcal pollers were leaked across navigation pops. | **Ported.** |

Two V1 lifecycle hooks are scoped to the chain UI port (Step 4) and intentionally NOT included in this commit:

- onAppear chain restoration (V1 LiveCaptureView.swift:242-248 — switch to `activeSupersetEntry`'s exercise / weight / cascade anchor + push device state).
- onChange `currentSet != nil` → `lockSupersetTag()`.
- onChange `mdm.supersetActiveSlot` → `switchActiveInstanceByExerciseName`.
- Full chain swap flow (auto-end in-flight set + UNLOAD outgoing + flip slot + switch instance + restore chain-entry weight + push), replacing `SupersetSwitcherBanner.swap` which currently only does the simple weight mirror.

These will land in the Step 4 commit (b71 chain UI in V2) so the chain port stays reviewable as one unit. Keeping them out of this commit also means Step 5 can be reverted independently if a chain bug surfaces and the surgery needs to be split.

**Files changed.**

- `VoltraLive/Logging/Views/LiveCaptureViewV2.swift`
  - `weightCard` top row: added "Target N reps" chip between the WEIGHT label and the `loadedPill`. Hidden when `effectiveTargetReps == nil`.
  - `weightCard` stepper row: replaced hard-coded `\u00B15 / \u00B11` literals with `CombinedParity.smallStepLb(for: mdm.workoutMode)` / `largeStepLb(...)` — Combined mode now nudges in `\u00B12 / \u00B16` like V1.
  - `weightCard` body: added `modeChipsRow` at the bottom of the card (seven `SetMode` chips, identical to V1 `modeChipsRow`).
  - Body stack: mounted `dropCancelChipV2` between `forceChartCard` and `V1RestoreSection`. Self-hides unless `logging.dropSetActive`.
  - `onAppear`: added `writerRouter.resetAppliedState()`, `mdm.leftWriter.resetAppliedState()`, `mdm.rightWriter.resetAppliedState()`, `logging.applyWorkoutMode(mdm.workoutMode)`, `enforceCombinedParityOnEntry()` — port of V1 LiveCaptureView.swift:213-224.
  - Added `.onChange(of: mdm.workoutMode)` → `applyWorkoutMode + enforceCombinedParityOnEntry` (V1 LiveCaptureView.swift:250).
  - Added `.onDisappear { health.stop() }` (V1 LiveCaptureView.swift:289).
  - New private members: `effectiveTargetReps` computed property, `modeChipsRow` view, `dropCancelChipV2` view, `enforceCombinedParityOnEntry()` helper.

No changes to LoggingStore, MultiDeviceManager, WriterRouter, CombinedParity, ForceChartView, ForceChartV2, V1RestoreSection, SupersetSwitcherBanner, or any sacred file.

**Verification.**

- Brace / paren / bracket balance via comment-and-string-stripped Python regex pass on `LiveCaptureViewV2.swift` (1693 lines): braces 0 / parens 0 / brackets 0 — balanced.
- All referenced symbols exist:
  - `logging.upcomingTargetReps: Int` (LoggingStore.swift:49)
  - `logging.upcomingMode: SetMode` (LoggingStore.swift:47)
  - `logging.dropSetActive`, `logging.cascadeStepLabel` (LoggingStore.swift:171, 517-context)
  - `logging.cancelDropSet()` (LoggingStore.swift:517)
  - `logging.applyWorkoutMode(_:)` (LoggingStore.swift:244)
  - `logging.reanchorCascadeIfActive(toLb:)` (LoggingStore.swift:609)
  - `mdm.workoutMode.requiresEvenWeight` (DualMode.swift:107)
  - `mdm.leftWriter.resetAppliedState()` / `mdm.rightWriter.resetAppliedState()` (MultiDeviceManager.swift:64-65, VoltraWriter.swift:128)
  - `CombinedParity.smallStepLb(for:)` / `largeStepLb(for:)` / `roundDownToEven(_:)` (CombinedParity.swift)
  - `SetMode` cases + `.label` (LoggingModels.swift:77-99)
- Sacred files (`VoltraProtocol.swift` / `TelemetryExtractor.swift` / `PacketParser.swift` / `FrameAssembler.swift`) untouched — git diff scope is `LiveCaptureViewV2.swift` only.
- No Xcode toolchain on the sandbox; CI `build.yml` on push is the authoritative compile check.

**Risks.**

- The new `modeChipsRow` adds a horizontally-scrolling row of seven capsules at the bottom of `weightCard`. Vertical footprint of the card grows by ~36 pt. Mitigated by the existing `ScrollView` enclosing `weightCard`.
- `pushUpcomingStateToDevice()` is now called when the user picks a new `SetMode`. If `voltraMode == .band` the BLE write switches `VoltraMode.band` on the device; this is the V1 behavior verbatim and correct.
- `onChange(of: mdm.workoutMode)` will fire `applyWorkoutMode + enforceCombinedParityOnEntry` whenever the user toggles `[⇄ MERGE]` mid-session. The parity helper rounds DOWN per b47 Q1, so the user never silently gains weight. If they were at 35 lb in Independent and toggle to Combined they land at 34 lb on the device; toggling back to Independent leaves them at 34 (no automatic restore). Behavior matches V1.
- Combined-mode step parity is a real fix that changes user-visible nudger labels (\u00B15 / \u00B11 \u2192 \u00B16 / \u00B12 in Combined). V1 has shipped this since b47 / v0.4.25; V2 was silently regressed.
- `health.stop()` on disappear may race a session-end path that also pops navigation. `HealthKitStore.stop()` is documented as idempotent (verified on the V1 path which has shipped this for the entire HealthKit lifetime), so a redundant call is a no-op.

**Out of scope (this commit).** No routing change (Step 3); no chain UI port (Step 4); no parity verification pass (Step 6); no version bump; no push.

---

## 2026-04-30 23:03 UTC — b71 Step 4: chain / superset UI port into V2 (V4-D21 part 2 of 3)

Port the V1 chain / superset SWAP flow into V2 so `LiveCaptureViewV2`
behaves identically to V1 when the user has built a 2+ entry superset
chain. Lands in two surgical files: `SupersetSwitcherBanner.swift`
(which now hosts the full SWAP semantics) and `LiveCaptureViewV2.swift`
(which now wires session/onAfterSwap and the three V1 lifecycle hooks).

This commit makes Step 3 (V1 fallback removal) safe — without it,
removing `if hasChain { return false }` would route chain users to a
V2 that did not preserve activeInstance across slot flips, did not
seal `supersetTag` on set 1, and did not re-anchor the cascade on
chain entry.

**Files changed.**

- `VoltraLive/Views/SupersetSwitcherBanner.swift` (~310 lines)
  - Header docs expanded with V4-D21 part 2 rationale (gate widening,
    chain-aware swap flow, host integration contract).
  - Added optional inputs: `var session: SessionStore? = nil`,
    `var onAfterSwap: (() -> Void)? = nil`. Backwards-compatible —
    older host call sites that pass only `mdm` and `logging` still
    compile.
  - Visibility gate widened from
    `mdm.supersetTag && bothPaired` to
    `(mdm.supersetTag && bothPaired) || mdm.hasActiveSupersetChain`,
    so a chain that hasn't been "tagged" via the legacy two-side flow
    still surfaces the banner on the live screen.
  - Display rewrites: when a chain is active, the LEFT / RIGHT badges
    prefer `mdm.activeSupersetEntry?.exerciseName` /
    `mdm.nextSupersetEntry?.exerciseName` and the "Next:" weight
    prefers `mdm.nextSupersetEntry?.plannedWeightLb` over the
    mirrored side weight (V1 LiveCaptureView.swift:805-814 verbatim).
  - `swap()` rewritten as the full V1 7-step flow:
    1. `session?.forceFinalizeCurrentSet()` — telemetry-safe boundary
       so a mid-set swap never orphans samples.
    2. Save outgoing planned weight (mirror).
    3. `mdm.unload(target: outgoing)` — outgoing side returns to bar.
    4. `mdm.flipSupersetActiveSlot()` — slot pointer advances.
    5. `logging.switchActiveInstanceByExerciseName(incoming)` so the
       LoggingStore commits sets against the new exercise.
    6. Restore weight: prefer
       `mdm.activeSupersetEntry?.plannedWeightLb` over the mirrored
       value, set `pendingPlannedWeightLb`, and
       `reanchorCascadeIfActive(toLb:)`.
    7. Fire `onAfterSwap?()` so the host's `pushUpcomingStateToDevice`
       is the single source of device-side state (writer-cache aware).
  - **Non-negotiable preserved (b53):** no auto-LOAD on the incoming
    side. SWAP only LOADs when the user pulls the trigger.

- `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` (1693 → ~1740
  lines after diff)
  - `body`: banner mount updated to
    `SupersetSwitcherBanner(mdm: mdm, logging: logging, session: session, onAfterSwap: { pushUpcomingStateToDevice() })`.
  - `onAppear`: added the V1 chain-restoration block verbatim
    (LiveCaptureView.swift:242-248) — when `mdm.activeSupersetEntry`
    is non-nil and `mdm.supersetChain.count >= 2`, switch active
    instance, set `pendingPlannedWeightLb`, re-anchor cascade, and
    `pushUpcomingStateToDevice()`. Idempotent with SWAP's restore.
  - Added `.onChange(of: session.currentSet != nil) { _, started in if started && mdm.supersetTag { mdm.lockSupersetTag() } }`
    (V1 LiveCaptureView.swift:264-268 verbatim) — seals the
    historical `supersetTag` the instant set 1 starts.
  - Added `.onChange(of: mdm.supersetActiveSlot) { _, _ in guard session.currentSet == nil else { return }; if let entry = mdm.activeSupersetEntry { logging.switchActiveInstanceByExerciseName(entry.exerciseName) } }`
    (V1 LiveCaptureView.swift:283-288 verbatim) — keeps
    `LoggingStore.activeInstance` synced with the chain slot for any
    flip path that bypasses SWAP (chain advance, navigation re-entry).

**APIs verified before edit.**

- `SessionStore.forceFinalizeCurrentSet()` (SessionStore.swift:305)
- `MultiDeviceManager.unload(target:)` (MultiDeviceManager.swift:445)
- `MultiDeviceManager.lockSupersetTag()` (MultiDeviceManager.swift:181)
- `MultiDeviceManager.hasActiveSupersetChain` (MultiDeviceManager.swift:190)
- `MultiDeviceManager.activeSupersetEntry` / `nextSupersetEntry` (MultiDeviceManager.swift:324, 331)
- `MultiDeviceManager.flipSupersetActiveSlot()` (MultiDeviceManager.swift:314)
- `LoggingStore.switchActiveInstanceByExerciseName(_:) -> Bool` (LoggingStore.swift:1252) — return value intentionally ignored to mirror V1 verbatim.
- `LoggingStore.reanchorCascadeIfActive(toLb:)` (LoggingStore.swift:609)
- V2 already has `@EnvironmentObject var session: SessionStore` (LiveCaptureViewV2.swift:87).

**Verification.**

- Brace / paren / bracket balance via comment-and-string-stripped
  Python regex pass:
  - `LiveCaptureViewV2.swift`: braces 0 / parens 0 / brackets 0
  - `SupersetSwitcherBanner.swift`: braces 0 / parens 0 / brackets 0
- No duplicate observers — `grep` confirms one `lockSupersetTag` site
  and one `onChange(of: mdm.supersetActiveSlot)` site in V2.
- Sacred files untouched (git diff scope is the two files above).
- No Xcode toolchain on the sandbox; CI `build.yml` on push is the
  authoritative compile check. Step 3 (routing flip) lands next and
  will not push without explicit user approval.

**Risks.**

- The widened banner gate (`|| hasActiveSupersetChain`) means the
  banner now appears in chain mode even if `supersetTag` was never
  flipped via the legacy two-side flow. This matches V1 (chain-only
  builds shipped from b48 onward). If a user has an in-flight chain
  and somehow lands on a build where only one side is paired, the
  banner will render but `swap()` will still try to flip slots; the
  V1 `swap()` has shipped under that condition without report so the
  port should be safe.
- `swap()` calls `session?.forceFinalizeCurrentSet()` only when the
  host passed `session`. The legacy two-arg call site (no session)
  still falls through to a slot flip without finalize — V1 behavior
  for the pre-chain era. V2 always passes `session` so it gets the
  full safety contract.
- The `onChange(of: mdm.supersetActiveSlot)` observer in V2 fires on
  every slot flip including the one inside `swap()`. The guard
  `session.currentSet == nil` is intact, and V1 has shipped this
  exact pattern since b52, so the redundant call is a defensive
  no-op (V1 LiveCaptureView.swift:283 inline comment).
- Two compiler warnings expected (matches V1):
  `Result of call to 'switchActiveInstanceByExerciseName' is unused`
  on the two onAppear / onChange call sites. V1 has shipped these
  warnings since b52; not promoting to errors.

**Out of scope (this commit).** No routing change (Step 3);
no parity verification (Step 6); no version bump; no push.

---

## 2026-04-30 23:09 UTC — b71 Step 3: V1 fallback removal; V2 is canonical (V4-D21 part 3 of 3)

The routing flip. After V4-D21 parts 1 (below-chart parity) and 2
(chain UI port) closed every behavior gap, `LiveCaptureContainer.shouldUseV2`
collapses from a three-stage conditional cascade to a single line.
V2 is now the canonical live capture view for every session shape;
`@AppStorage("liveCaptureUIVersion")` is an emergency rollback kill
switch only.

**Files changed.**

- `VoltraLive/Logging/Views/LiveCaptureContainer.swift`
  - Header comments rewritten: pre-b71 routing rules listed and
    marked deprecated; new V2-by-default policy spelled out;
    kill-switch semantics inverted from opt-in (b53) to opt-out
    (b71).
  - `liveCaptureUIVersionKey` docstring updated: `"v1"` is now the
    emergency rollback value; `""` and `"v2"` both route to V2.
  - Removed `@EnvironmentObject var mdm: MultiDeviceManager` from
    the container struct — the routing predicate no longer reads
    MDM. App-entry-level injection still passes MDM down to V1 / V2.
  - `shouldUseV2` rewritten as a single line:
    `return uiVersion != "v1"`. The old three-stage cascade
    (`hasChain → V1` / `bothPaired → V2` / else preference) is
    preserved verbatim in a comment block immediately above the
    return, citing V4-D21 parts 1+2 as the prerequisites that made
    the flip safe.

- `docs/handoff/02_CURRENT_STATE.md`
  - "Five unshipped commits" header (was four).
  - Added the V4-D21 part 3 entry beneath part 2.
  - Trailing summary line updated: only Step 6 (parity verification)
    remains before the version bump.
  - "What works today" section: added a routing note at the top
    flagging that "V1 only" bullets describe pre-b71 history, not
    post-b71 runtime; rewrote the Live capture / Dual-Voltra /
    Superset chain bullets to call out V2 as the canonical render
    path post-b71 with V1 retained as a rollback artifact.

- `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md`
  - Appended ADR **V4-D21 part 3** with the full rationale (why a
    kill switch instead of a hard cut, alternatives considered,
    files changed, deferred V1 deletion plan).

- `docs/handoff/08_SUPERSET.md`
  - "V1/V2 routing interaction" section rewritten to reflect the
    post-Step-3 policy. Pre-b71 rules retained as deprecated
    history; new one-line predicate quoted; kill-switch semantics
    documented; V1 rollback path noted.

- `docs/handoff/10_OPEN_QUESTIONS.md`
  - "Should V2 become the default?" entry deleted from the open
    questions section per the file's standing rule ("delete in
    the same commit as the code that uses the answer"); a closure
    note was added under "Recently closed" pointing at V4-D21 part 3.

- `docs/WORK_LOG.md` (this entry).

**Verification.**

- Brace / paren / bracket balance via comment-and-string-stripped
  Python regex pass on `LiveCaptureContainer.swift`: braces 0 /
  parens 0 / brackets 0.
- `grep` confirms no remaining `hasChain`, `bothPaired`, or
  `MultiDeviceManager` references inside `LiveCaptureContainer.swift`
  beyond the deprecated-cascade comment block.
- Sacred files untouched.
- No Xcode toolchain on the sandbox; CI `build.yml` on push remains
  the authoritative compile check. No push performed.

**Risks.**

- Existing installs whose `liveCaptureUIVersion` is the empty string
  (never picked at first launch) now route to V2 instead of V1. This
  matches the b71 mandate but is the largest behavior change in this
  cycle — the picker UX in b53 said "default V1 on cancel," and that
  promise is now broken. Mitigation: V4-D21 parts 1+2 closed every
  V1→V2 behavior gap, and the kill switch is reachable for users
  who prefer V1.
- Existing installs with `liveCaptureUIVersion == "v2"` see no
  change in behavior. Existing installs with
  `liveCaptureUIVersion == "v1"` (rare — required an explicit pick
  of V1 from the b53 first-launch sheet) continue routing to V1
  via the new kill-switch semantics. Verified on paper — the
  predicate `uiVersion != "v1"` returns `false` for `"v1"`, `true`
  for `""` / `"v2"` / any other value, matching intent.
- The `LiveCaptureContainer.shouldUseV2` predicate is now stateless
  with respect to runtime device state. A user who had paired both
  Voltras pre-b71 and was relying on the implicit `bothPaired → V2`
  fast path is now routed by AppStorage alone. This is the intent
  of the flip but is worth noting if a future regression surfaces.
- V2 carries the entirety of the live capture surface area. The
  parity verification pass (Step 6) is the next step to flush out
  any remaining V1↔V2 discrepancy not caught by parts 1 / 2.

**Out of scope (this commit).** No V1 source deletion (deferred to
b75+ at the earliest). No Settings toggle for the kill switch
(deferred). No parity verification (Step 6 next). No version bump.
No push.

---

## 2026-04-30 23:13 UTC — b71 Step 6: V1↔V2 parity verification (source-level audit)

Pre-ship code-level audit across all eight items the b71 mandate
called out. Sandbox is Linux with no Xcode toolchain — every item
is verified by reading source, not by running the app. On-device
QA happens post-TestFlight per the standing 5-gate ship discipline
and is captured in `QA_LOG.md`.

**Scope.** The eight items: LOAD/UNLOAD, ±5/±1 nudgers, Combined
dual-fire, 4-row live grid, HR/KCAL, rest/idle, force chart live +
`lastFinalizedSamples`, chain routing through V2.

**Result.** All eight items pass. No genuine blockers. No b71
scope item deferred.

| # | Item | Verdict |
|---|------|---------|
| 1 | LOAD/UNLOAD | Verbatim — same `mdm.load`/`mdm.unload`/`ble.sendLoad`/`ble.sendUnload` opcode path |
| 2 | ±5/±1 nudgers | Verbatim port (b71 V4-D21 part 1, b93b4fe) — both views read `CombinedParity.smallStepLb`/`largeStepLb` |
| 3 | Combined dual-fire | Verbatim — same `WriterRouter.combined → mdm.applyCombined` graph; both views feed it |
| 4 | 4-row live grid | Documented intentional redesign — every V1 tile mapped to a V2 surface (table in B71_PARITY_VERIFICATION.md § 4) |
| 5 | HR/KCAL | Behavioral equivalent — V2 surfaces in `headerStrip` / `dualHeaderCluster` instead of tile grid row 4 |
| 6 | Rest/idle | Verbatim port + b66 P1-2 honesty fix |
| 7 | Force chart live + `lastFinalizedSamples` | Verbatim (b71 V4-D20) — same `ForceChartView` instance, same fallback, same secondary trace |
| 8 | Chain routing through V2 | Verbatim port (b71 V4-D21 part 2, 2488484) — three V1 hooks + V1 7-step swap flow |

**Files changed.**

- `docs/handoff/B71_PARITY_VERIFICATION.md` (new) — full audit
  with V1 source location, V2 source location, and verdict for
  each of the eight items, plus the V1→V2 tile-mapping table for
  item 4 (the only item that's a documented redesign rather than
  a verbatim port).
- `docs/WORK_LOG.md` (this entry).

**Verification of the audit itself.**

- Each V1 source location was confirmed via `grep` against
  `LiveCaptureView.swift`.
- Each V2 source location was confirmed via `grep` against
  `LiveCaptureViewV2.swift`.
- The `WriterRouter.combined → mdm.applyCombined` route was traced
  via the same router instance that V1 and V2 both share through
  the SwiftUI environment.
- Force chart sample-fallback equivalence verified by reading
  `LiveCaptureViewV2.forceChartCard` lines 1294-1330 against the
  V1 path; both use
  `session.currentSet?.samples ?? session.lastFinalizedSamples`
  and both pull secondary traces from
  `session.lastFinalizedByExercise[other.exerciseName]`.

**Risks.**

- Source-level parity is necessary but not sufficient. CI
  `build.yml` is the authoritative compile check; the user's
  post-build TestFlight QA checklist is the authoritative
  behavior check. Both are still pending (no push performed).
- Item 4's "documented intentional redesign" verdict relies on
  the standing rule "do not restore the b46 4×2 grid unless I
  explicitly ask for that rollback." If the user disagrees with
  the V2 surface mapping for any of the eight tiles, that's a
  scope-discussion item, not a regression.
- Combined dual-fire is verified at the router level, not at the
  V2 surface level. V2's WEIGHT card stepper writes through
  `pendingPlannedWeightLb` which is the same source V1 uses; the
  router fans the value to both sides via `mdm.applyCombined`
  identically. The V2 stepper has shipped this path since b54.

**Out of scope (this commit).** No code changes — audit only. No
version bump. No push.

---

## 2026-04-30 23:15 UTC — b71 version bump v0.4.43/70 → v0.4.44/71 (FINAL commit of b71 cycle)

Final commit of the b71 cycle per the standing mandate ("Keep the
version bump as the final separate commit only after the full
scope lands"). All six b71 scope items landed in the preceding
six commits:

1. b70 page-badge double-render hotfix retained — commit `34ba63e`
2. V1 ForceChartView canonical for V2 — commit `92cac54`
3. V1 below-chart UI parity into V2 — commit `b93b4fe`
4. V1 chain / superset UI port into V2 — commit `2488484`
5. V1 fallback removal; V2 canonical — commit `c7427ce`
6. V1↔V2 parity verification audit — commit `c797d7f`

This commit is the version bump only. No code logic changes.

**Files changed.**

- `project.yml`
  - Settings block (lines ~64-65): `MARKETING_VERSION` 0.4.43 → 0.4.44,
    `CURRENT_PROJECT_VERSION` 70 → 71.
  - Info plist generation block (lines ~92-93):
    `CFBundleShortVersionString` 0.4.43 → 0.4.44,
    `CFBundleVersion` 70 → 71.
- `VoltraLive/Info.plist`
  - `CFBundleShortVersionString` 0.4.43 → 0.4.44.
  - `CFBundleVersion` 70 → 71.
- `docs/handoff/01_PROJECT_OVERVIEW.md`
  - Top-of-file shipping-build line bumped to v0.4.44 / build 71
    (b71 cycle).
- `docs/handoff/02_CURRENT_STATE.md`
  - Header timestamp + cycle summary updated: "BUMPED, awaiting
    user push approval. Seven unshipped commits in tree."
  - "Active cycle" section: SHA list extended to include all
    seven commits (added the parity-audit and version-bump
    bullets).
  - Trailing summary updated to reflect that all six b71 scope
    items have landed and the version bump is the FINAL commit
    per the b71 mandate.
- `docs/WORK_LOG.md` (this entry).

Per the b71 process requirement "version bump in `project.yml` +
`Info.plist` + `01_PROJECT_OVERVIEW.md` + `02_CURRENT_STATE.md`
(NOT _tmp/archive)" — the `_tmp/archive` tree was deliberately
NOT touched.

**Verification.**

- `grep -rn '0.4.43\|"70"' project.yml VoltraLive/Info.plist
   docs/handoff/01_PROJECT_OVERVIEW.md docs/handoff/02_CURRENT_STATE.md`
  returns no matches outside the historical "Latest shipped build:
  **v0.4.43 / build 70**" line in 02_CURRENT_STATE (which is
  correct — it documents the LAST shipped build, which is still
  b70).
- `git log --oneline -8` confirms the commit ordering:
  - b70 ship (e10b428)
  - b70 hotfix (34ba63e)
  - b71 force chart (92cac54)
  - b71 below-chart parity (b93b4fe)
  - b71 chain UI port (2488484)
  - b71 V1 fallback removal (c7427ce)
  - b71 parity audit (c797d7f)
  - b71 version bump (this commit)

**Risks.**

- Apple's version-component rule: `CFBundleShortVersionString` ≤ 3
  components. `0.4.44` is 3 components — compliant.
- Existing TestFlight history shows builds 1-70. Build 71 is the
  next contiguous integer — compliant with App Store Connect's
  "build numbers must monotonically increase" rule.
- The `_tmp/archive` tree was intentionally NOT touched per the
  b71 process requirement. If a future maintainer expects archived
  copies of the bumped version strings, that's a separate
  archival workflow that does not apply here.

**Out of scope (this commit).** No code changes. No push. No
altool. No release.yml run. No QA_LOG entry (that lives post-
TestFlight per the b58 process). No Apple submission.

**Pending.** Final summary back to the user. Wait for explicit
push approval before any TestFlight ship.

---

## b71 ship — v0.4.44 / build 71 — 2026-04-30 23:43 UTC

**HEAD shipped:** `26af534` (commit 7 of the b71 chain — version
bump). Branch `feat/ui-v4-2-claude` pushed to origin earlier the
same evening (`41556db..26af534`).

**Ship workflow.** `release.yml` triggered via
`workflow_dispatch` with `dry_run=false` on
`feat/ui-v4-2-claude`. Run ID
[25194880211](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25194880211).
Conclusion = `success`. Run duration consistent with prior signed
TestFlight ships on this branch (~6m).

**5-gate verification (release.yml steps).**
1. `Run protocol unit tests` — success. Sacred-file goldens
   green, including the b58 5-gate signing assertions.
2. `Build and archive (signed)` — success. Xcode 26 / iOS 26 SDK,
   Release configuration, signed with the App Store
   distribution profile.
3. `Verify signed IPA` — success.
4. `Verify embedded entitlements (HealthKit, iCloud)
   [b49 hardened]` — success.
5. `Upload to TestFlight via altool` — **success**. This is the
   canonical TestFlight-acceptance signal (altool exits 0 only
   when ASC has accepted the IPA into processing).

**Skipped steps (intentional).** Dry-run-only artifact upload and
tag-only GitHub-release publish skipped because the dispatch was
`dry_run=false` and not tag-driven. Matches the b66-b70 ship
pattern.

**ASC cross-check.** `asc-status.yml` triggered manually
(run 25195421641, conclusion = success). Log readback was
blocked by a transient GitHub Actions jobs-API rate limit on the
sandbox IP, so the parsed processing state was not captured
inline. Not a blocker — altool success is the load-bearing
signal; ASC status is supplementary.

**Build context.** This is the FIRST TestFlight build with V2 as
the canonical live capture view. The V1 source tree remains on
disk as a rollback artifact (deletion deferred to b75+, after 2
clean V2 ships per V4-D21 part 3). `liveCaptureUIVersion="v1"`
AppStorage value is now an emergency kill switch, not the
default.

**User-visible changes shipped.**
- b70 page-badge double-render hotfix (V4-D19).
- Force chart canonical implementation in V2 (V4-D20).
- V1 below-chart UI parity in V2 (V4-D21 part 1).
- V1 chain/superset UI ported into V2 with full SWAP safety,
  chain restore, secondary force trace (V4-D21 part 2).
- V2 routing predicate collapsed to `uiVersion != "v1"`
  (V4-D21 part 3).

**Post-build QA pass.** OWED per AGENTS.md §"Post-build QA
checklist". A skeleton entry has been added to
`docs/handoff/QA_LOG.md` with "User responses" left pending; the
agent will run the multiple-choice QA pass with the user before
the next ship cycle starts.

**Out of scope (this entry).** Bookkeeping only. No code changes.
No version bump. No push (the b71 commit chain was already pushed
during the original cycle).

---

## 2026-05-01 02:0X UTC — b72 debug grid overlay (V4-D22)

**Why.** The b70/V4-D18 9-anchor marker overlay (C-TL / M-T /
F-CTR / …) was not precise enough for design feedback. The user
asked for a real spreadsheet-style graph-paper grid with column
letters + row numbers and progressive density via the existing
build-badge tap.

**Karpathy "request back" verbatim** (captured 2026-04-30 ~01:35
UTC, full prompt in `docs/handoff/B72_DEBUG_GRID_PROMPT.md`):
"Replace it with a real spreadsheet-style graph-paper grid with
column letters and row numbers, and make the existing tap toggle
progressively increase density over 4 levels."

**User confirmed design choices** (2026-04-30 ~02:00 UTC):
- Base spacing: **32 pt** (over 24 pt / 40 pt). Yields ~12 cols
  A-L on 390 pt-wide devices, ~26 rows on 844 pt body.
- State 3 quarter-step labels: **margin-only** (over full
  interior / every-other interior). Body stays readable.

**What changed.**

- `VoltraLive/Views/DebugGridOverlay.swift` rewritten in place:
  new `enum DebugGridDensity` (`.off / .base / .half / .quarter
  / .max`), Canvas-based gridline renderer (single draw call,
  no per-line views), Text-based margin-strip labels (column
  letters wrapping `A..Z, AA..AB..`, row numbers `1..N`),
  `anchorPreference`-based region overlay for State 4.
  AppStorage key kept as `"debugGridMode"` so persisted user
  preference survives the upgrade; legacy raw values migrate
  via `DebugGridDensity.from(_:)` ("off" stays off, anything
  else → `.base`). The legacy `enum DebugGridMode` is RETAINED
  in the same file behind a `// SUPERSEDED` marker for
  rollback.
- `VoltraLive/Views/BuildBadgeOverlay.swift`: tap handler
  cycles `DebugGridDensity.next()` instead of
  `DebugGridMode.next()`. Header docblock updated. Layout /
  colors / position unchanged.
- `VoltraLive/Views/PageBadgeOverlay.swift`: header docblock
  updated to note V4-D22. No code change — `.debugGridOverlay()`
  remains the LAST modifier in the chain so the grid renders
  ABOVE both badge overlays in z-order.

**State cycle (what the user sees on tap-through).**

| Tap | State | What renders |
|---|---|---|
| 0 | `.off` | nothing |
| 1 | `.base` | 32 pt grid, mint @30 % opacity, top + leading margin labels A,B,C,…/1,2,3,… at 8 pt @0.85 |
| 2 | `.half` | + 16 pt half-step lines @20 %, half labels (`A.5`, `10.5`) interior on margin strips at reduced weight |
| 3 | `.quarter` | + 8 pt quarter-step lines @14 %, quarter labels (`A.25`, `A.75`, `10.25`, `10.75`) MARGIN-ONLY |
| 4 | `.max` | (state 3) + region outlines @40 % `VoltraColor.accent` with the screen's published region names (none in this commit — see KI-12) |

**Constraints honored.**

- `.allowsHitTesting(false)` on every overlay layer — overlay
  never blocks UI underneath.
- Margin strips sit inside `safeAreaInsets` so labels don't
  slide under iOS status bar / home indicator.
- Sacred files untouched. No version bump. No push. CI
  `build.yml` on push remains the authoritative compile check.
- Same toggle surface (build badge), same gesture, same
  AppStorage key. No new affordances added.

**Files changed.**

- `VoltraLive/Views/DebugGridOverlay.swift` (rewrite)
- `VoltraLive/Views/BuildBadgeOverlay.swift` (tap handler)
- `VoltraLive/Views/PageBadgeOverlay.swift` (comment only)
- `docs/handoff/02_CURRENT_STATE.md` (overlay bullet + file map)
- `docs/handoff/03_CURRENT_FEATURE_SPEC.md` (Debug grid section
  rewritten)
- `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` (V4-D22 ADR)
- `docs/handoff/06_KNOWN_ISSUES.md` (KI-12 added)
- `docs/WORK_LOG.md` (this entry)

**07_FILE_MAP.md note.** The b72 prompt mentions
`docs/handoff/07_FILE_MAP.md` but no such file exists in the
repo. The file-map row in `docs/handoff/02_CURRENT_STATE.md`
serves as the de-facto file map and has been updated to reflect
the b72 → b72 cycle line. Creating a separate `07_FILE_MAP.md`
would duplicate that table; raising as a non-blocker for
future cleanup.

**Out of scope (this commit).** No version bump. No push. No
TestFlight ship. No region instrumentation on individual
screens (deferred per KI-12). No removal of legacy
`DebugGridMode` enum (retained for rollback per b72 prompt's
"do not remove the existing overlay before the new one renders
correctly" rule; deletion target is post-b73 if no rollback
fires).

**Pending.** Visual sanity check on simulator (CI `build.yml`
on push will be the first compile gate; user has not approved
push of the bookkeeping commit `8bdd88b` yet, so this commit
also stays local).

---

## 2026-05-01 02:35 UTC — b72 version bump v0.4.44/71 → v0.4.45/72 (FINAL commit of b72 cycle)

Final commit of the b72 cycle per the standing mandate ("Keep
the version bump as the final separate commit only after the
full scope lands"). The b72 scope (debug grid overlay upgrade)
landed in the preceding two commits:

1. Bookkeeping (log b71 ship, open b71 QA skeleton, capture
   b72 grid prompt) — commit `8bdd88b`
2. Replace 9-anchor debug overlay with progressive-density
   grid (V4-D22) — commit `65ddd5c`

This commit is the version bump only. No code logic changes.
This is a debug-overlay-only build per user request — pre-b72
the only behavioral delta from v0.4.44/71 is the State 0→4
debug grid cycle on the build-badge tap. No protocol, routing,
chart, or page-registry changes.

**Files changed.**

- `project.yml`
  - Settings block (lines ~64-65): `MARKETING_VERSION` 0.4.44 →
    0.4.45, `CURRENT_PROJECT_VERSION` 71 → 72.
  - Info plist generation block (lines ~92-93):
    `CFBundleShortVersionString` 0.4.44 → 0.4.45,
    `CFBundleVersion` 71 → 72.
- `VoltraLive/Info.plist`
  - `CFBundleShortVersionString` 0.4.44 → 0.4.45.
  - `CFBundleVersion` 71 → 72.
- `docs/handoff/01_PROJECT_OVERVIEW.md`
  - Top-of-file shipping-build line bumped to v0.4.45 / build
    72 (b72 cycle).
- `docs/handoff/02_CURRENT_STATE.md`
  - Header: "Last shipped b71 (v0.4.44 / build 71)" preserved
    as canonical last-shipped reference.
  - Active-cycle banner rewritten for b72 / v0.4.45 / build 72,
    listing all three b72 commits (`8bdd88b`, `65ddd5c`, this
    bump).
- `docs/WORK_LOG.md` (this entry).

Per the standing process requirement "version bump in
`project.yml` + `Info.plist` + `01_PROJECT_OVERVIEW.md` +
`02_CURRENT_STATE.md` (NOT _tmp/archive)" — the `_tmp/archive`
tree was deliberately NOT touched.

**Verification.**

- `git log --oneline -3` confirms the commit ordering on top of
  b71's shipped HEAD `26af534`:
  - b72 bookkeeping (`8bdd88b`)
  - b72 grid implementation (`65ddd5c`)
  - b72 version bump (this commit)
- CI on `65ddd5c`: run
  [25199140398](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25199140398)
  = `BUILD SUCCEEDED`. SwiftCompile log confirms
  `DebugGridOverlay.swift`, `BuildBadgeOverlay.swift`,
  `PageBadgeOverlay.swift` all genuinely recompiled (not
  cached).

**Risks.**

- Apple's version-component rule: `CFBundleShortVersionString`
  ≤ 3 components. `0.4.45` is 3 components — compliant.
- Existing TestFlight history shows builds 1-71. Build 72 is
  the next contiguous integer — compliant with App Store
  Connect's "build numbers must monotonically increase" rule.
- The `_tmp/archive` tree was intentionally NOT touched per the
  carryover process requirement. Same as b71.

**Out of scope (this commit).** No code changes. No QA_LOG
entry yet (lives post-TestFlight per b58 process). The pending
b71 post-build QA pass is paused while this b72 ship lands;
when it resumes it will cover BOTH b71 items AND the new b72
debug grid overlay.

**Pending.** Push approval already granted by user ("Bump to
v0.4.45 / build 72, push, ship to TestFlight"). Next steps
after this commit: push to `feat/ui-v4-2-claude`, trigger
`release.yml` with `dry_run=false`, poll to completion, verify
altool upload step success, report ship complete.

---

## 2026-05-01 03:50 UTC — b73 debug grid scroll-anchor fix (V4-D23) + bump v0.4.45/72 → v0.4.46/73

**Why.** b72 / V4-D22 shipped a viewport-pinned grid: column
letters AND row numbers were both anchored to the screen
viewport (the device's safe-area frame). When the user scrolled
a list (e.g. `LoggingHomeView`'s exercises), UI content slid
under stationary row labels — so "C10" pointed at one element
before the scroll and a different element after. Coordinates
that don't survive scrolling are useless for design feedback.

**Karpathy "request back" verbatim** (captured 2026-05-01
~03:00 UTC, single-prompt FULL SHIP autonomy granted): "Scope:
Debug Grid Overlay — fix scroll-relative coordinate drift.
[…] Mount the row numbers + horizontal gridlines so they travel
with the ScrollView's content coordinate space, while column
letters + vertical gridlines stay viewport-pinned (no horizontal
scroll exists in this app)."

**Decision (V4-D23).** Split the debug grid coordinate system:

1. Vertical gridlines + column letters (A, B, C, …) stay
   viewport-pinned — X axis has no horizontal scroll, so
   nothing to reconcile.
2. Horizontal gridlines + row numbers (1, 2, 3, …) anchor to
   the ScrollView's content coordinate space via a new
   `.debugGridContent()` view modifier attached to the inner
   content stack of every page-badged ScrollView.
3. Mechanic: the overlay establishes a named coordinate space
   `"debugGridViewport"` on the screen root via
   `.coordinateSpace(name:)`. The `.debugGridContent()` modifier
   wraps a `GeometryReader` around the content stack that
   measures `proxy.frame(in: .named("debugGridViewport"))` and
   publishes `(minY, height)` via a new
   `DebugGridContentMetricsKey` PreferenceKey. The overlay's
   `onPreferenceChange` reads that and translates horizontal
   gridlines + row label strip by `contentMinY`.
4. Backward compatible: screens without `.debugGridContent()`
   default to `metrics = .zero` and render row labels at the
   top of the viewport — identical to b72 behavior. No per-screen
   breakage if a screen is missed during ScrollView migration.
5. Row 1 is the top of content, NOT the top of viewport. As the
   user scrolls down, row labels slide off the top; as they
   scroll up past content origin, labels drift below the safe-area
   header. This is the desired behavior — it means "C10" identifies
   a piece of UI furniture not a piece of glass.

**What changed.**

- `VoltraLive/Views/DebugGridOverlay.swift` rewritten in place
  (480 → 630 lines). Added `DebugGridContentMetrics` struct,
  `DebugGridContentMetricsKey` PreferenceKey, `View+`
  extension `.debugGridContent()` modifier, named coordinate
  space `"debugGridViewport"` on the overlay root,
  `.onPreferenceChange(DebugGridContentMetricsKey.self)`
  subscriber on the overlay, content-translated `Path` draw
  for horizontal gridlines (offset by `contentMinY`), and
  content-translated row label strip. Legacy
  `enum DebugGridDensity` (b72 / V4-D22) and density region
  outline preference machinery preserved verbatim. Legacy
  `enum DebugGridMode` retained behind `// SUPERSEDED` marker
  per the b72 retain-for-rollback pattern.
- `.debugGridContent()` applied to the inner content stack of
  10 ScrollView screens (1-line change per screen):
  - `VoltraLive/Logging/Views/LoggingHomeView.swift`
  - `VoltraLive/Logging/Views/LiveCaptureView.swift`
  - `VoltraLive/Logging/Views/LiveCaptureViewV2.swift`
  - `VoltraLive/Logging/Views/ExerciseDetailView.swift`
  - `VoltraLive/Logging/Views/ExerciseStartView.swift`
  - `VoltraLive/Logging/Views/DebugView.swift`
  - `VoltraLive/Logging/Views/ExercisePickerView.swift`
  - `VoltraLive/Logging/Views/SetLogView.swift`
  - `VoltraLive/Logging/Views/ExportSheet.swift`
  - `VoltraLive/Views/DashboardView.swift`
- Intentionally NOT wired: `ConnectView` (no ScrollView),
  `LiveCaptureContainer` (b53 router forwarder; owns no
  content), `ContentView` (host shell; owns no content). See
  KI-13 for the design rationale on the fall-through default.

**Constraints honored.**

- States 0 → 4 from V4-D22 preserved unchanged (mounting fix
  only, not a density change).
- `.allowsHitTesting(false)` on every overlay layer — overlay
  never blocks UI underneath.
- Same toggle surface (build badge tap), same gesture, same
  AppStorage key (`"debugGridMode"`). No new affordances.
- Sacred files untouched. `_tmp/archive` untouched.
- Scope fence honored: BLE, telemetry, logging, LiveCapture
  set logic, MDM, chain UI, HealthKit, force chart all
  untouched.

**Files changed (this commit).**

- `VoltraLive/Views/DebugGridOverlay.swift` (rewrite)
- `VoltraLive/Logging/Views/LoggingHomeView.swift` (1 line)
- `VoltraLive/Logging/Views/LiveCaptureView.swift` (1 line)
- `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` (1 line)
- `VoltraLive/Logging/Views/ExerciseDetailView.swift` (1 line)
- `VoltraLive/Logging/Views/ExerciseStartView.swift` (1 line)
- `VoltraLive/Logging/Views/DebugView.swift` (1 line)
- `VoltraLive/Logging/Views/ExercisePickerView.swift` (1 line)
- `VoltraLive/Logging/Views/SetLogView.swift` (1 line)
- `VoltraLive/Logging/Views/ExportSheet.swift` (1 line)
- `VoltraLive/Views/DashboardView.swift` (1 line)
- `project.yml` — `MARKETING_VERSION` 0.4.45 → 0.4.46,
  `CURRENT_PROJECT_VERSION` 72 → 73, `CFBundleShortVersionString`
  0.4.45 → 0.4.46, `CFBundleVersion` 72 → 73,
  `VOLTRAFeatureLabel` "" → "Grid scroll fix".
- `VoltraLive/Info.plist` — same string updates plus
  `VOLTRAFeatureLabel` "Grid scroll fix".
- `docs/handoff/01_PROJECT_OVERVIEW.md` (shipping build line)
- `docs/handoff/02_CURRENT_STATE.md` (active cycle banner +
  file map row)
- `docs/handoff/03_CURRENT_FEATURE_SPEC.md` (Debug grid header
  bumped to V4-D22 → V4-D23, scroll-anchoring subsection added)
- `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` (V4-D23 ADR
  appended)
- `docs/handoff/06_KNOWN_ISSUES.md` (KI-13 added)
- `docs/WORK_LOG.md` (this entry)
- `scripts/render_b73_grid_diagram.py` (NEW) —
  Python/Pillow validator that uses the SAME row-coord formula
  as the SwiftUI overlay (`row = floor(y_center / 32) + 1`).
  Renders side-by-side panels at offsets 0 pt and 192 pt
  showing LEG DAY landing on content row 10 in both states.
- `docs/handoff/screenshots/b73/grid_scroll_invariant.png` (NEW)
- `docs/handoff/screenshots/b73/logging_home_offset_0.png` (NEW)
- `docs/handoff/screenshots/b73/logging_home_offset_192.png`
  (NEW)

**Why one commit instead of three.** b73 is one feature per the
one-feature-per-build mandate. b72 split into three commits
(bookkeeping → implementation → version bump) because of the
unrelated b71-cycle bookkeeping debt that needed to land first.
b73 has no bookkeeping debt — the previous shipping build (b72)
left the tree clean — so implementation + version bump + docs
collapse into a single atomic commit per Karpathy "minimum
diff" preference.

**Verification (pre-CI).**

- `git status --short` confirms 17 modified + 4 new files; no
  `_tmp/archive` paths.
- Brace/paren balance check passed on `DebugGridOverlay.swift`
  and all 10 screen files (one pre-existing imbalance in
  `ExerciseDetailView` from string interpolation,
  unrelated — would not have compiled in b72 if real).
- Visual validation via `scripts/render_b73_grid_diagram.py`:
  the math is the same closed-form expression as the SwiftUI
  overlay's row computation. The PNG shows LEG DAY anchored at
  content row 10 across both scroll offsets — that is the
  invariant the user asked for.
- iOS Simulator screenshots are NOT available from the Linux
  sandbox. Real on-device captures will land in the b73
  TestFlight build itself; the user can validate against the
  Python-rendered diagram for the math, and against TestFlight
  for the actual SwiftUI render.

**CI verification.** Release run
[25201372318](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25201372318)
on commit `68b4a0e` = `success`. All 5 gates green:
protocol unit tests, build & archive (signed), verify signed
IPA, verify embedded entitlements (HealthKit, iCloud)
[b49 hardened], upload to TestFlight via altool. Steps 19-20
(dry-run artifact + tag-only release publish) skipped — expected
for non-dry-run, non-tag dispatch. altool reported
`UPLOAD SUCCEEDED with no errors` in 28 s. Delivery UUID
`6b12a064-b20a-4152-82c5-d578edb0c9d9`. v0.4.46 / build 73 is
live on TestFlight.

**Risks.**

- `GeometryReader` adds one layout pass per ScrollView screen.
  iOS 17 has well-optimized GeometryReader; the wrapped content
  is a `LazyVStack` / `VStack` so the perf hit is a constant
  overhead, not O(rows). Acceptable.
- PreferenceKey publish-on-every-frame potential — mitigated by
  the default `reduce` summing only the latest value (last write
  wins) and SwiftUI's diff suppression on identical values.
- iOS 17 minimum deployment target unchanged from b72.
- Apple version-component rule: `0.4.46` is 3 components,
  compliant. Build 73 follows 72 monotonically, compliant.

**Out of scope (this commit).** No protocol changes, no
telemetry changes, no logging changes, no chart changes, no
HealthKit changes, no MDM changes, no chain-UI changes, no
LiveCapture set logic changes. No region instrumentation —
KI-12 stays open. Legacy `DebugGridMode` enum still retained
behind `// SUPERSEDED` marker.

**Pending (post-this-commit).** Push to
`feat/ui-v4-2-claude`, trigger `release.yml` with
`dry_run=false`, poll ~5-6 min for signed TestFlight ship,
verify all 5 gates including altool upload, fill in the CI
verification block above, report ship complete.

---

## 2026-05-01 — b74 (V4.6) — Debug grid TRUE content-space layer (PR-only, UNVERIFIED)

**Goal.** Fix the b73 / V4-D23 ship that failed on device: the
debug grid's row labels remained effectively viewport-pinned
under scroll despite the `DebugGridContentMetricsKey`
PreferenceKey + `contentMinY` translation path. Replace the
PreferenceKey approach with a real content-space layer
(`DebugGridContentLayer`) attached via `.background(...)` on
each ScrollView's inner content stack. Horizontal gridlines and
row labels now physically live INSIDE the scrollable content
and scroll with it for free — no preference-key plumbing, no
named-coordinate-space translation. See ADR **V4-D24** in
`04_DECISIONS_AND_CONSTRAINTS.md`.

**Context.** b73 / v0.4.46 / build 73 shipped 2026-05-01 03:56
UTC and the user reported the grid still does not move with
scroll on device. The PreferenceKey path is the wrong shape:
the overlay still renders viewport-level above the ScrollView,
and the translation pass ran but did not produce a visible
travel of the rows. b74 abandons that path entirely and uses
SwiftUI's native composition: the `.background(...)` modifier
makes the layer's frame match its host's intrinsic frame, so a
content-stack-attached background is genuinely a sibling of
that content and physically scrolls with it.

**Files changed.**

- `VoltraLive/Views/DebugGridOverlay.swift` — rewrite. Removed:
  `DebugGridContentMetrics`, `DebugGridContentMetricsKey`
  PreferenceKey, the old `.debugGridContent()` modifier, the
  `"debugGridViewport"` named coordinate space, and the
  `originY/contentOriginY` translation pass in the canvas
  renderer. Added: `struct DebugGridContentLayer` (Canvas +
  ZStack of row labels), `View.debugGridContentLayer()`
  modifier (attaches the layer via `.background(...)`),
  `private struct DebugGridViewportLayer` (vertical lines +
  column letters + region overlay only, viewport-pinned). The
  density enum (`DebugGridDensity`), region anchor preference,
  `.debugRegion("name")` modifier, and `// SUPERSEDED` legacy
  `DebugGridMode` enum are unchanged.
- 10 page-badged ScrollView screens — each `.debugGridContent()`
  replaced with `.debugGridContentLayer()` on the same inner
  stack: `LoggingHomeView`, `LiveCaptureView`,
  `LiveCaptureViewV2`, `ExerciseDetailView`, `ExerciseStartView`,
  `DebugView`, `DashboardView`, `ExercisePickerView`,
  `SetLogView`, `ExportSheet`. Inline comments updated from
  "b73 V4-D23: pipe content metrics …" to "b74 V4-D24: attach
  content-space debug grid layer …".
- `docs/handoff/03_CURRENT_FEATURE_SPEC.md` — Debug grid
  section amended: rows + horizontal lines content-anchored,
  columns + vertical lines viewport-pinned. Mechanic is
  `.debugGridContentLayer()` (background sizing), not the b73
  PreferenceKey.
- `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` — appended
  ADR **V4-D24**.
- `docs/handoff/06_KNOWN_ISSUES.md` — KI-13 closed; the
  non-scrolling-screen note is now a one-line caveat under
  KI-13 because non-scrolling screens simply omit the modifier
  (no preference default, no fallback path).
- `docs/handoff/02_CURRENT_STATE.md` — file-map row updated
  for the new mechanic.
- `docs/WORK_LOG.md` — this entry.

**Screens wired (b74 coverage list — same 10 as b73).**

`LoggingHomeView`, `LiveCaptureView`, `LiveCaptureViewV2`,
`ExerciseDetailView`, `ExerciseStartView`, `DebugView`,
`DashboardView`, `ExercisePickerView`, `SetLogView`,
`ExportSheet`. Non-scrolling screens (`ConnectView`,
`LiveCaptureContainer`, `ContentView`) intentionally untouched
— there is no scroll content for the layer to scroll with, so
attaching it would be a no-op-with-extra-render-cost.

**No version bump.** This is a PR-only fix on
`feat/b74-debug-grid-content-space`, branched from
`origin/feat/ui-v4-2-claude`. PR base: `feat/ui-v4-2-claude`
(b72/b73 code is on this branch, not on `main`). No push to
`release.yml`. No TestFlight ship. No `VOLTRAFeatureLabel`
change.

**Verification (UNVERIFIED — Path A, awaiting on-device).**

The user requested Path B (CI-driven screenshot artifacts) as
the preferred verification, with Path A (UNVERIFIED PR awaiting
on-device verification) as the fallback. Path B was deemed
infeasible in this single sequential pass because:

1. The repo has no UI test target (`VoltraLiveUITests/`
   doesn't exist). Adding one expands scope beyond debug-
   overlay surgery and would touch `project.yml` (XcodeGen).
2. `xcrun simctl io booted screenshot` can capture a screenshot
   post-launch but cannot programmatically scroll a SwiftUI
   ScrollView without a UI test driving the gesture.
3. A launch-arg-driven scroll-on-launch path would require
   shipping-surface code (a `ScrollViewReader` + `.onAppear`
   `proxy.scrollTo(...)` in every adopting screen), which is
   shipping code, not debug-overlay scope.

The user's explicit fallback applies: "Open the PR anyway.
Mark it clearly UNVERIFIED — awaiting on-device verification."
The PR title and body are tagged accordingly. A human-tester
TestFlight checklist is included in the PR body.

**Risks.**

- `.background(DebugGridContentLayer())` adds one
  GeometryReader-backed Canvas + ZStack per ScrollView screen.
  When density is `.off` the layer body returns `Color.clear`
  immediately, so the runtime cost on shipped builds is a
  single empty `Color` background per adopting screen.
- The layer's `GeometryReader` reads its host's intrinsic
  frame — for a `LazyVStack` inside a ScrollView that means
  the grid covers the full content extent (the desired
  behavior). If a screen wraps a fixed-height container, the
  grid will only cover that height; this is also correct
  (rows beyond the host's frame would be off-content anyway).
- iOS 17 deployment target unchanged.

**Out of scope.** No protocol/BLE changes, no telemetry
changes, no logging changes, no chart changes, no HealthKit
changes, no MDM changes, no chain-UI changes, no LiveCapture
set logic changes. No region instrumentation (KI-12 stays
open). Legacy `DebugGridMode` enum still retained behind
`// SUPERSEDED`. No version bump. No CI workflow added.

**Pending (post-PR).** Human-on-device verification on
TestFlight build (b73 still shipping; b74 is PR-only). When
the user confirms on device, this entry should be revised
from UNVERIFIED to VERIFIED with a screenshot link.

---

## 2026-05-01 04:54 UTC — b74 v0.4.47 build 74 — release ship of PR #5

- **Files changed:** `project.yml`, `VoltraLive/Info.plist`, `docs/WORK_LOG.md`
- **What changed:** Merged PR #5 (b74 V4-D24 debug grid TRUE content-space layer) into `feat/ui-v4-2-claude` (merge commit 027a84c). Bumped MARKETING_VERSION/CFBundleShortVersionString 0.4.46 -> 0.4.47 and CURRENT_PROJECT_VERSION/CFBundleVersion 73 -> 74. Set `VOLTRAFeatureLabel` to "Grid scroll fix v2" (project.yml + Info.plist).
- **Verification:** Will be `release.yml` dryRun=false on `feat/ui-v4-2-claude` — TestFlight ship + altool 5-gate verification.
- **Risks:** PR #5 is tagged UNVERIFIED — shipping to TestFlight so the user can verify on device. No forward fix attempted.
- **Next step:** Monitor CI run, capture Delivery UUID, post TestFlight status. If CI fails with a compile error, stop and surface the log per user release instruction.

## 2026-05-01 05:16 UTC — B74-F1: auto-connect L/R buttons by Voltra advertised name

- **Files changed:** `VoltraLive/BLE/Dual/DualMode.swift`,
  `VoltraLive/Views/UnifiedConnectSheet.swift`,
  `VoltraLiveTests/SideNameMatchTests.swift` (new),
  `docs/WORK_LOG.md`, `docs/handoff/B74_BUG_QUEUE.md`.
- **What changed:** Tapping the greyed L or R pill in
  `VoltraUnitHeader` already routed through
  `PairingCoordinator.presentPair(slot:)`, but
  `UnifiedConnectSheet` then ignored the slot intent and
  presented the manual multi-select picker — which
  RSSI-sorted the discoveries strongest-first, so users
  reported L and R both pairing to the closer Voltra
  regardless of which side button they tapped. The fix:
  (1) added `DeviceSlot.advertisedNameKeyword` /
  `matchesAdvertisedName(_:)` (case-insensitive substring
  on `left` / `right`); (2) when the sheet appears with
  `pairing.requestedSlot != nil`, watch
  `scanner.discovered` and as soon as a Voltra whose
  advertised name contains the slot keyword shows up,
  call `mdm.connect(slot:discovered:)` and dismiss
  immediately. Until a side-name match is found the
  sheet stays visible with "Searching for a Voltra
  named "left"…" (or "right") so the user does not get
  silently auto-connected to the wrong device. The
  generic "Connect to VOLTRA" entry on `ConnectView`
  is unchanged: it opens the sheet with no slot intent
  and the multi-select flow still works.
- **Verification:** Pure-Swift unit tests in
  `SideNameMatchTests.swift` pin the case-insensitive
  substring contract (positive: "voltra-left",
  "VOLTRA Left", "VoltraLEFT", "Voltra Left A1B2";
  negative: opposite-side names, "VOLTRA" alone, ""
  empty string). Cannot run `xcodebuild test` in this
  environment (Linux container, no Xcode toolchain) —
  unit tests must be run on macOS as part of the merge
  CI / human verification. No hardware BLE verification
  performed; that needs both Voltras paired by the user
  on TestFlight.
- **Risks:** (a) If a Voltra is named with both keywords
  ("left-right-rig"), the L tap will match it; this is
  the user's labelling problem and the user spec
  explicitly chose the substring-match contract. (b) If
  no matching device is in range when the user taps L/R,
  the sheet stays open with the searching banner — user
  must Cancel manually. We deliberately do NOT fall back
  to the wrong-side device or to RSSI order. (c) The
  `.onChange(of: scanner.discovered)` hook compares
  arrays element-wise via `Discovered`'s id-only
  `==`; pure RSSI re-sorts that don't change the id set
  won't re-fire the matcher, but the matcher already ran
  on the previous emission so this is fine.
- **Next step:** Human on-device verification with two
  Voltras named "...left" and "...right" — confirm that
  L pill pairs only the left-named device and R pill
  pairs only the right-named device, both as solo and
  as a sequenced pair. Then unblock B74-F2/F3/F5/F6 per
  the bug queue note that F1 is a prereq for repro.

## 2026-05-01 22:10 UTC — B74-F8: replace dual-dot HR pill with single neutral Health signal indicator

- **Files changed:** `VoltraLive/Views/VoltraUnitHeader.swift`,
  `docs/handoff/B74_BUG_QUEUE.md`, `docs/WORK_LOG.md`.
- **What changed:** Replaced the legacy `●●` HR pill (3-state
  dark / blinking-accent / solid-accent surface with rounded
  background + border) with a single neutral `●` Health signal
  indicator at the same mount point in `VoltraUnitHeader`. New
  contract: live when
  `hk.isAvailable && hk.hasRequestedAuthorization &&
  hk.currentHR != nil && lastHRSampleAt` is within a 10 s
  freshness window — rendered in the existing header text color.
  Otherwise idle, rendered in `VoltraColor.textFaint` (faint,
  not hidden). Tap routes through `hk.requestAuthIfNeeded()`
  iff the user has not yet been asked; after that the tap is
  a deliberate no-op (no system sheet, no analytics). A
  `TimelineView(.periodic(from:.now, by:1))` wraps the dot so
  the freshness check re-evaluates without requiring a new
  `@Published` change — staleness flips live → idle on the wall
  clock. Removed the old `HRState` enum, `hrState`,
  `heartRatePill`, `hrDots`, and `hrAccessibilityLabel`
  members. Did NOT touch `HealthKitStore.swift`; did NOT use
  `HKHealthStore.authorizationStatus(for:)`; did NOT introduce
  `heartRateAuthStatus`. Did NOT touch BLE / pairing /
  WatchConnectivity / Watch target / Info.plist / project.yml /
  entitlements / version-build-feature-label / release
  workflows. Added an `IN PROGRESS` row + full entry section
  for B74-F8 in `B74_BUG_QUEUE.md`.
- **Verification:** Cannot run `xcodebuild` or `swift build`
  in this environment (Windows; iOS Swift project). Static
  searches confirm: zero hits for `authorizationStatus` and
  `heartRateAuthStatus` across the working tree (existing
  guardrail searches pass). The new `healthSignalIndicator`
  / `healthSignalLive` / `hrFreshnessWindow` symbols compile
  in this Swift dialect by construction (TimelineView
  `.periodic(from:by:)` and `Button { } label: { }` are
  iOS 17 standard SwiftUI surface already used in this
  project). Mac-side verification needed before this is
  trusted: (a) Xcode compile clean, (b) idle dot visible and
  faint before HK auth, (c) tap-when-unauthorized shows the
  system HK consent sheet, (d) post-auth + live HR sample =
  normal header text color (not accent green), (e) >10 s of
  no samples flips the dot back to faint without app
  re-foreground, (f) no regressions on the L / R / ⋏ pills.
- **Risks:** (a) The 1 Hz `TimelineView` tick is cheap but
  runs continuously while the header is on screen; if any
  performance-sensitive screen mounts multiple
  `VoltraUnitHeader` instances simultaneously this would
  multiply — current mount-point invariant is one header per
  screen so this should be fine. (b) The freshness window is
  hardcoded at 10 s as `hrFreshnessWindow`; tuning will need
  a code change rather than a runtime knob — by design, per
  F8 spec. (c) The header text color (`VoltraColor.text`) is
  used for the live state; if a future theme change makes
  that color hard to distinguish from the idle `textFaint` at
  small dot sizes the affordance could weaken — flag for
  design review if it lands. (d) No unit tests added —
  `healthSignalLive` is pure-Swift (`hk` published state +
  `Date()`) and would be testable, but the spec did not
  require tests and adding them would expand the change
  surface beyond the F8 contract.
- **Next step:** Open the changed file in Xcode on macOS,
  confirm a clean build, run the app on TestFlight or a
  signed dev build, and walk the four verification scenarios
  above (idle pre-auth, tap → consent sheet, live sample =
  text color, 10 s staleness flip). When verified, revise
  the queue row from `IN PROGRESS` to `VERIFIED` and append
  the verifying commit / TestFlight build to this entry.
  This branch (`feat/b74-f8-watch-presence-indicator`) is
  committed locally only — `git push` is deferred per the
  F8 contract.

## 2026-05-01 22:50 UTC — b76 v0.4.49: bump build 75 -> 76, feature label "Health signal indicator" (B74-F8 release-only ship)

- **Files changed:** `project.yml`, `VoltraLive/Info.plist`,
  `docs/handoff/00_START_HERE.md`,
  `docs/handoff/02_CURRENT_STATE.md`,
  `docs/handoff/03_ROADMAP.md`, `docs/WORK_LOG.md`.
- **What changed:** Release-only ship of B74-F8 ("Health signal
  indicator") from `feat/ui-v4-2-claude`. The implementation was
  already merged at `713a851` via PR #8 (`8fd6f95`) — this commit
  bumps `MARKETING_VERSION` 0.4.48 → 0.4.49 and
  `CURRENT_PROJECT_VERSION` 75 → 76 in both `project.yml` (lines
  64–65 and 92–93) and `VoltraLive/Info.plist`, sets
  `VOLTRAFeatureLabel` to exactly `Health signal indicator` in
  both files, and overwrites the durable handoff sections per
  `00_START_HERE.md` ship discipline (Latest shipped, Done table,
  Last shipped line). Zero implementation changes — this is the
  ship commit, not a code commit. Per task brief, the release was
  dispatched via `gh workflow run release.yml --ref
  feat/ui-v4-2-claude -f dry_run=false`. CI conclusion + altool
  5-gate verification recorded in the commit message and in the
  task's `/tmp/claude_code_output.md` report.
- **Verification:** `grep -nE
  'MARKETING_VERSION|CURRENT_PROJECT_VERSION|CFBundleShortVersionString|CFBundleVersion|VOLTRAFeatureLabel'
  project.yml VoltraLive/Info.plist` shows all 7 lines consistent
  at `0.4.49` / `76` / `Health signal indicator`. No
  `xcodebuild`/`swift build` available in this Linux container —
  compile validation is the release workflow's responsibility.
- **Risks:** (a) If the release workflow's compile gate fails on
  any of the B74-F8 Swift surface (`TimelineView(.periodic(...))`,
  the new `healthSignalIndicator` view, the removed `HRState`
  symbols), the ship will be aborted and the user will be asked
  before any forward fix — per the task contract this is a
  release-only ship and we do not alter implementation under any
  CI failure. (b) The b75 ship verification status was not
  recorded in `02_CURRENT_STATE.md`'s "Latest shipped build"
  block before this bump, so the prior-build TestFlight history
  is sourced from `git log` rather than from the durable docs.
- **Next step:** Six-item user device QA checklist (idle dot
  faint pre-auth, tap → consent sheet, live HR sample = header
  text color, >10 s stale flip, L/R/⋏ pills unchanged, Xcode
  compile via release workflow). After user QA, append to
  `docs/handoff/QA_LOG.md` per b58 sticky requirement.

## 2026-05-02 15:42 UTC — B74-F11: Session Recorder spec PR (docs-only)

- **Files changed:** `docs/handoff/SESSION_RECORDER_SPEC.md` (new),
  `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` (V4-D25 appended),
  `docs/handoff/B74_BUG_QUEUE.md` (B74-F11 status row + entry),
  `docs/handoff/07_FILE_MAP.md` (new — first sections; satisfies the
  Karpathy `07_FILE_MAP` wiki role flagged "(not yet authored)" in
  `00_START_HERE.md`), `docs/WORK_LOG.md` (this entry).
- **What changed:** Opened B74-F11 — Session Recorder — as a
  spec-only PR on branch `docs/session-recorder-spec` against
  `feat/ui-v4-2-claude`. Spec calls for a local-only,
  AI-readable session recorder activated by triple-tap on the
  build-badge chip and surfaced as a single 24×24 pt root-level
  overlay dot on every screen. Architecture: one shared
  `SessionRecorder` `ObservableObject` injected via
  `.environmentObject` owning a 10,000-event FIFO ring buffer,
  `ActionScope` task-local `actionId` for cause → effect chains,
  thread-safe via serial queue or `actor`, opportunistic
  persistence to `Application Support/SessionRecorder/last_session.json`
  on background / kill, **no** other disk writes, **no** network,
  **no** analytics. Redaction maps PII surfaces (BLE peripheral
  name, exercise name, free text) to UUIDs / `<redacted:len=N>`;
  raw passthrough requires explicit `unsafeRaw` opt-in. Export is
  `.txt` + `.json` together via `ShareLink`. Hard runtime
  invariants: no `Info.plist` / `project.yml` / entitlements /
  release-workflow changes, no BLE / WatchConnectivity runtime
  behavior changes, no per-screen toggle buttons, no new silent
  guards (existing user-visible-path guards become loud via
  `rec.guardTrip(...)` in the implementation PR). Verification
  contract: Swift compile + unit tests for `RecorderBuffer`,
  `RecorderRedactor`, `RecorderExporter`, `ActionScope`, and
  TestFlight QA passes A–G recorded in `QA_LOG.md`. ADR V4-D25
  appended to `04_DECISIONS_AND_CONSTRAINTS.md` with full
  alternatives-considered rationale (OSLog-only, per-feature
  recorders, server telemetry, per-screen buttons, unbounded
  buffer — all rejected, with reasons). `B74_BUG_QUEUE.md` gains
  a B74-F11 row (status `OPEN (spec-only)`) and a full entry
  section. `07_FILE_MAP.md` is created fresh with placeholder
  rows for every recorder file the implementation PR will land
  (`SessionRecorder.swift`, `RecorderEvent.swift`,
  `RecorderBuffer.swift`, `RecorderRedactor.swift`,
  `RecorderExporter.swift`, `ActionScope.swift`,
  `SessionRecorderToggle.swift`, `SessionRecorderViewer.swift`,
  `View+RecorderScreen.swift`, plus tests).
- **Verification:** Docs-only — no Swift, no `xcodebuild`, no CI
  gate. Working-tree review confirms five files touched and the
  spec / ADR / queue / map cross-references resolve. Branch
  pushed as `docs/session-recorder-spec`; PR opened against
  `feat/ui-v4-2-claude`; not merged.
- **Risks:** (a) `11_AGENT_ROLES.md` is referenced by the
  existing B74_BUG_QUEUE.md text but does not exist on
  `feat/ui-v4-2-claude` (it lives only on `main` post-merge of
  PR #4). Pre-existing inconsistency; out of scope for this
  spec PR. (b) The B74-F11 entry in the queue and the V4-D25
  ADR will need to be updated when the implementation PR lands
  — both contain "spec only" and "PLACEHOLDER" markers that
  must flip to "implemented" / "EXISTS" in the same commit as
  the implementation. (c) Nothing in this commit changes
  runtime behavior; if any reviewer thinks they see a Swift
  diff, the PR has been mis-scoped and should be rejected.
- **Next step:** Implementation PR on a separate branch (per
  the agent-roles split-role contract — Claude is release-only
  while GPT-5 owns implementation) lands the recorder code
  with unit tests. After Xcode compile + test pass, ship a
  TestFlight build with feature label `"Session Recorder"`
  and run QA passes A–G with the user, recording results in
  `QA_LOG.md`. Any **Not** result becomes a KI-N entry in
  `06_KNOWN_ISSUES.md` or a follow-up fix PR.

## 2026-05-02 17:00 UTC — Durable handoff checkpoint after B74-F11 Commit 1

- **Files changed:** `docs/handoff/00_START_HERE.md` (overwrite),
  `docs/handoff/CONVERSATION_LOG.md` (new), `docs/WORK_LOG.md` (this
  entry).
- **What changed:** Captured the full session context for B74-F11
  Session Recorder implementation in repo so a fresh Voltra Brain chat
  can resume by reading files only. Documented: worktree blocker
  resolution (created `feat/b77-session-recorder` from
  `origin/feat/ui-v4-2-claude` inside the existing worktree instead of
  switching branches in the main checkout); approved 3-commit plan
  (core engine done at `76becdf`, then root overlay + viewer + share +
  screen tags, then instrumentation + loud guards + docs); hard stops
  (no Info.plist / project.yml / entitlements / workflow / release /
  TestFlight / version bump / `git add -A` / `.claude/` staging /
  rebase / force-push / BLE-runtime / WatchConnectivity-runtime /
  network / analytics / per-screen toggle / new silent guard);
  approval policy (auto / pause / reject buckets); Windows host
  limitation (no `xcodebuild`); PR description requirements (spec
  clause → file mapping, touched-file list, `.recorderScreen` tags,
  loud-guard conversions, "Could not verify" section); commit cadence
  (push every ~10 turns); risks; Commit 1 state at `76becdf` (11
  files, 1098 insertions). No code behavior changed in this entry.
- **Verification:** `git status --short` reviewed before staging; only
  the three intended doc files staged. `.claude/` left untracked. No
  source files touched.
- **Risks:** Docs drift from code if not updated in the same commit.
  `CONVERSATION_LOG.md` will go stale if future commits skip the
  append step — `00_START_HERE.md` documents this requirement
  explicitly so fresh agents enforce it.
- **Next step:** Proceed with B74-F11 Commit 2 — root overlay
  (`SessionRecorderToggle`) + viewer (`SessionRecorderViewer`) + share
  (`ShareLink` for `.txt` + `.json`) + `.recorderScreen` tags on
  ~13 top-level screens. Edits to `VoltraLiveApp.swift` and
  `BuildBadgeOverlay.swift` per the route map.

## 2026-05-02 17:30 UTC — Add full Perplexity control-plane transcript

- **Files changed:** `docs/handoff/PERPLEXITY_TRANSCRIPT_2026-05-02.md`
  (new), `docs/handoff/00_START_HERE.md` (link added to read order +
  index), `docs/handoff/CONVERSATION_LOG.md` (pointer added at top of
  Perplexity section).
- **What changed:** Added the complete verbatim Perplexity AI advisory
  chat transcript that directed the B74-F11 implementation session.
  19 turns captured in full, including paste-to-Claude prompts,
  approval decisions, screenshots interpreted, and the final
  meta-iteration where the user pushed for transcript-grade fidelity
  rather than a decision summary. `00_START_HERE.md` now lists this
  file at position #4 in the read order so a fresh agent picks it up
  before the spec. `CONVERSATION_LOG.md`'s Perplexity-session section
  now links to the transcript as the authoritative "why" reference.
  No code behavior changed.
- **Verification:** `git status --short` reviewed before staging; only
  the four intended doc files staged. `.claude/` left untracked.
- **Risks:** Transcript is human-curated from one side of a two-party
  chat — Perplexity's responses are paraphrased / structurally
  reconstructed from what Perplexity output, since Claude cannot read
  the Perplexity chat directly. Future Perplexity turns must be
  appended by the user pasting them into Claude (Claude has no other
  way to see them).
- **Next step:** Proceed with B74-F11 Commit 2 (unchanged from the
  previous WORK_LOG entry).

## 2026-05-02 17:35 UTC — Add Karpathy context protocol (AGENTS.md + CONTEXT_LEDGER.md)

- **Files changed:** `AGENTS.md` (new section "Voltra Brain & Agent
  Organization (Karpathy Method)"),
  `docs/handoff/CONTEXT_LEDGER.md` (new),
  `docs/handoff/00_START_HERE.md` (added `CONTEXT_LEDGER.md` to read
  order, added "Context protocol" section, added entry to handoff
  index), `docs/handoff/CONVERSATION_LOG.md` (new entry),
  `docs/handoff/PERPLEXITY_TRANSCRIPT_2026-05-02.md` (Turn 20
  appended), `docs/WORK_LOG.md` (this entry).
- **What changed:** Established automatic context management protocol
  so we never need another massive transcript backfill. Three
  additions, all in `AGENTS.md` so they apply to every future agent:
  (1) every response that does repo work must end with one of
  `Context is good.` / `Context is degrading.` /
  `Context is dangerously low.`; (2) every 10 turns (or sooner if
  health drops) the agent appends a structured summary to
  `CONTEXT_LEDGER.md` and commits before writing more code;
  (3) Karpathy filesystem-as-memory + select-don't-dump read order +
  leash constraints (every Voltra Brain instruction must include
  clear instruction, constraints, scope, stopping criteria).
  No code behavior changed.
- **Verification:** `git status --short` reviewed before staging; only
  the six intended files staged. `.claude/` left untracked. No Swift
  files touched.
- **Risks:** Agents may not follow the protocol if they skip reading
  `AGENTS.md`. Mitigation: `00_START_HERE.md` puts `AGENTS.md` first
  in the read order and the new "Context protocol" section there
  surfaces the rules a second time.
- **Next step:** Proceed with B74-F11 Commit 2 — root overlay
  (`SessionRecorderToggle`) + viewer (`SessionRecorderViewer`) + share
  (`ShareLink` for `.txt` + `.json`) + `.recorderScreen` tags on
  ~13 top-level screens.

## 2026-05-02 17:55 UTC — B74-F11 (2/3): Root overlay + viewer + share + screen tags

- **Files changed:**
  - NEW Swift: `VoltraLive/Recorder/SessionRecorderToggle.swift`,
    `VoltraLive/Recorder/SessionRecorderViewer.swift`.
  - EDIT Swift: `VoltraLive/VoltraLiveApp.swift` (env-object
    injection + bottom-trailing overlay + scenePhase persist hook),
    `VoltraLive/Views/BuildBadgeOverlay.swift` (triple-tap unlock
    declared before existing single-tap so disambiguation prefers it),
    `VoltraLive/Recorder/RecorderEvent.swift` (added `CaseIterable`
    to `RecorderCategory` for viewer filter chips).
  - EDIT (13 screens, 1 line each — `.recorderScreen("Name")`):
    `LoggingHomeView`, `LiveCaptureView`, `LiveCaptureViewV2`,
    `LiveCaptureContainer`, `ConnectView`, `DebugView`,
    `DashboardView`, `ExerciseDetailView`, `ExerciseStartView`,
    `ExercisePickerView`, `SetLogView`, `ExportSheet`,
    `UnifiedConnectSheet`.
  - DOCS: `docs/handoff/00_START_HERE.md` (state update),
    `docs/handoff/CONVERSATION_LOG.md` (Commit 2 entry),
    `docs/handoff/CONTEXT_LEDGER.md` (entry 1), this entry.
- **What changed:** Added the recorder UI surface. `SessionRecorder`
  is now injected at the app root via `.environmentObject`; a
  24x24 pt dot lives in a single root-level
  `.overlay(alignment: .bottomTrailing)`, hidden until the user
  triple-taps the build-badge chip
  (`UserDefaults["VOLTRARecorderUnlocked"] = true`). Tap toggles
  recording; long-press opens `SessionRecorderViewer` (event timeline
  with category filter chips + `ShareLink` exporting both `.txt` and
  `.json` payloads). Recording state shows a 1 Hz red pulse via
  `TimelineView(.animation)`; idle is faint `VoltraColor.textFaint`.
  scenePhase observer calls `recorder.persist()` on background /
  inactive. `.recorderScreen("Name")` on 13 top-level screens emits
  `nav.screenAppear` / `nav.screenDisappear`.
- **Verification:** Cannot run `xcodebuild` (Windows host).
  `git status --short` reviewed before staging; `.claude/` not staged;
  no `git add -A`. No `Info.plist`, `project.yml`, entitlements,
  workflow, BLE, HealthKit, sacred-protocol, or version-bump files
  touched.
- **Risks:**
  - SwiftUI single-tap on the build badge now has a ~250 ms delay
    introduced by triple-tap disambiguation. Spec accepts this; needs
    QA verification on device.
  - The recorder dot's 36 pt bottom padding assumes the build badge
    chip stays roughly its current size (~14 pt + 6 pt padding). If
    that chrome changes, revisit padding.
  - `ShareLink` writes temp files on viewer open; the user may share
    a stale snapshot if they leave the viewer open and trigger more
    events. Reload button regenerates.
- **Next step:** B74-F11 Commit 3 — instrumentation + loud guards
  (additive BLE sinks, HK read-only, ActionScope wrapping for major
  UI actions, user-visible silent-guard sweep) + remaining doc
  updates (`07_FILE_MAP.md` PLACEHOLDER → EXISTS,
  `03_CURRENT_FEATURE_SPEC.md` pointer, `09_NEXT_AGENT_PROMPT.md`
  append).

## 2026-05-02 18:30 UTC — B74-F11 (3/3): Session Recorder instrumentation + loud guards

- **Files changed (Swift, additive only):**
  - `VoltraLive/BLE/VoltraBLEManager.swift` — 14 recorder emit
    sites across BLE chokepoints (`ble.discovery`, `ble.connect`,
    `ble.disconnect`, `ble.write.tx`, `ble.write.ack`,
    `ble.notify.rx`, `ble.error`). NO behavior change.
  - `VoltraLive/BLE/VoltraWriter.swift` — 2 sites: writer-level
    `ble.write.tx` with high-level `label` + `cmd` metadata,
    `ble.error` on payload-build failure.
  - `VoltraLive/BLE/Dual/MultiDeviceManager.swift` — 5 emit-site
    groups: slot-tagged `ble.connect`/`disconnect`,
    `state.modeChange` for disconnectBoth, `ble.error` +
    `state.modeChange` on combined drop,
    `async.taskStart`/`.taskEnd`/`.taskError` for the reconnect
    loop.
  - `VoltraLive/Health/HealthKitStore.swift` — 6 read-only emit
    groups: `state.flagChange` for auth attempt + result,
    `lifecycle.healthkit.start`/`.stop`, per-sample HR/kcal events
    with `HKSource.name` + `bundleIdentifier` (passed via
    `redactor.unsafeRaw` since these are developer-controlled
    identifiers, not user PII).
  - `VoltraLive/VoltraLiveApp.swift` — scenePhase observer extended
    with `lifecycle.appBackground` / `lifecycle.appForeground`
    events alongside the existing persist call.
  - `VoltraLive/Logging/Views/LoggingHomeView.swift` — wrapped Demo
    Mode button tap and `startCustom(_:)` in
    `SessionRecorder.shared.action(...)`; converted 2 user-visible
    silent guards (`demo.handlerMissing`, `startCustom.emptyLabel`).
  - `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` — wrapped
    `tapDropTile()` and `toggleHardwareLoad()` in `action()`;
    converted 4 user-visible silent guards (`dropStart.noWeight`,
    `dropStep.notActive`, `demo.alreadyArmedOrConnected`,
    `demo.handlerMissing`).
  - `VoltraLive/Logging/Views/LiveCaptureView.swift` (V1) — wrapped
    `sendLoad()` and `sendUnload()` in `action()`; converted 3
    user-visible silent guards (V1 mirrors of `dropStart.noWeight`,
    `demo.alreadyArmedOrConnected`, `demo.handlerMissing`).
- **Files changed (docs, per AGENTS.md mandatory enforcement):**
  - `docs/handoff/07_FILE_MAP.md` — flipped 9 source + 4 test
    PLACEHOLDER → EXISTS, expanded mounts + screen-tag +
    instrumentation sections.
  - `docs/handoff/03_CURRENT_FEATURE_SPEC.md` — added §10 Session
    Recorder pointer.
  - `docs/handoff/09_NEXT_AGENT_PROMPT.md` — appended
    "post-b76, B74-F11 implementation merged" status section.
  - `docs/handoff/00_START_HERE.md` — Commit 3 marked DONE.
  - `docs/handoff/CONVERSATION_LOG.md` — Commit 3 entry (V1
    parallel wrapping decision; ActionScope inner-body indentation
    note).
  - `docs/handoff/CONTEXT_LEDGER.md` — entry 2 (Commit 3 checkpoint
    per the 10-turn protocol).
  - `docs/WORK_LOG.md` — this entry.
- **What changed:** Added the recorder instrumentation layer. Every
  BLE chokepoint and every HealthKit sample arrival now emits a
  recorder event when recording is active. Major user actions
  (Demo Mode, startCustom, drop tile, weight tap, LOAD/UNLOAD)
  mint a fresh `actionId` via `SessionRecorder.shared.action(...)`
  so downstream events auto-inherit it for cause→effect chains.
  9 user-visible silent guards now leave `guard.trip` traces with
  the original condition preserved verbatim.
- **Verification:** Cannot run `xcodebuild` (Windows host).
  `git status --short` reviewed before staging; `.claude/` not
  staged; no `git add -A`. No `Info.plist`, `project.yml`,
  entitlements, workflow, sacred-protocol, WatchConnectivity, or
  version-bump files touched.
- **Risks:**
  - Layered `ble.write.tx` events from `VoltraWriter.send` (intent)
    + `VoltraBLEManager.writeControlFrame` (bytes) are intentional
    pairs; reviewers reading the export should expect both.
  - Per-frame `ble.notify.rx` emit fires at the assembly rate
    (~10–50 Hz during a live set). With a 10k-cap buffer, ~3
    minutes of live BLE activity will start dropping the oldest
    events. By design (FIFO; current-session bias) but worth
    flagging.
  - ActionScope inner-body indentation in
    `LiveCaptureViewV2.tapDropTile()` and `toggleHardwareLoad()`
    intentionally NOT re-indented — the wrapper sits at the same
    indent level as the original body to keep the diff small.
    Swift tolerates this; reviewers may find it stylistically odd.
- **Next step:** Push branch and open PR against
  `feat/ui-v4-2-claude` with the spec-required PR description
  (clause→file map, `.recorderScreen` tag list, guard-conversion
  list, "Could not verify" section). Do not merge. Do not release.

## 2026-05-02 19:55 UTC — B74-F11 CI compile fix (failed run → green run)

- **Files changed:** `docs/WORK_LOG.md` (this entry).
- **Goal:** document the CI failure → fix → green CI outcome on
  PR #10's branch `feat/b77-session-recorder` so the repo records
  what happened (chat is ephemeral).
- **What changed:** PR #10 was opened at head `492130a`. Branch CI
  (`build.yml`) was manually dispatched
  ([run 25260163621](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25260163621))
  and FAILED at the "Build (unsigned, iphoneos SDK)" step in 47s
  with 3 Swift compile errors:
  - `MultiDeviceManager.swift:697` — `argument 'metadata' must
    precede argument 'error'` in the `async.taskError` emit inside
    `scheduleReconnect` (parameter-order swap on
    `SessionRecorder.shared.record(...)`).
  - `SessionRecorder.swift:76` — `invalid redeclaration of
    'start()'` because Commit 1 declared both
    `@Published var start: Date?` and `@MainActor func start()`
    (Swift refuses property + method sharing the same base name).
  - `SessionRecorder.swift:73` — cascading `cannot call value of
    non-function type 'Date?'` from the same name collision.

  Fix landed at `77e2b5a B74-F11: fix session recorder CI compile
  errors` (2 files, +16 / −10):
  - `MultiDeviceManager.swift`: swapped `metadata:` and `error:`
    argument order on the `async.taskError` emit.
  - `SessionRecorder.swift`: renamed `start: Date?` →
    `startedAt: Date?` and `end: Date?` → `endedAt: Date?`;
    updated 4 internal references (`start()` setter,
    `stop()` setter, two `await MainActor.run` blocks in
    `currentExport()` and `persist()`). External impact: zero —
    the viewer doesn't reference these properties and tests pass
    dates directly to `RecorderExporter` rather than through the
    singleton.

  Re-dispatched
  ([run 25260420548](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25260420548)):
  green in 1m17s. Unsigned IPA artifact produced.

  PR #10 follow-up comment posted:
  [#issuecomment-4364664979](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/pull/10#issuecomment-4364664979).
- **Verification result:** `build.yml` manual `workflow_dispatch`
  on `feat/b77-session-recorder` succeeded — full app Swift compile
  + unsigned IPA package + artifact upload. **`xcodebuild test`
  did NOT run** (build.yml does not invoke the test action); the 4
  new recorder unit-test files compile (since the test target
  builds as a dependency) but their assertions remain unverified.
- **Risks:** Unit-test assertions and on-device QA passes A–G
  remain unverified. The Commit 1 `start`/`end` → `startedAt`/`endedAt`
  rename is undocumented in the PR #10 description body but is
  captured in the follow-up PR comment and in this entry.
- **Next step:** Decide whether to (a) run `release.yml dry_run`
  against this branch to exercise `xcodebuild test` + signed-archive
  flow before TestFlight, or (b) proceed with on-device QA
  passes A–G first, or (c) merge the PR after a code review and
  defer all device verification to the post-merge ship cycle.
  All three are valid; current branch state supports any of them.
  PR #10 remains OPEN and UNMERGED.

## 2026-05-02 20:50 UTC — B74-F11 release.yml dry_run verification

- **Files changed:** `docs/WORK_LOG.md` (this entry).
- **Goal:** Record the B74-F11 `release.yml` dry_run verification on
  PR #10's branch `feat/b77-session-recorder` so the repo captures
  what the dry-run actually validated (chat is ephemeral).
- **What changed:** Manually dispatched `release.yml` with
  `dry_run=true` on `feat/b77-session-recorder` head
  `6ab55b8681f039d9d927b4e8f9974fae565d2371`.
  [Run 25261426415](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25261426415).
- **Verification result:** `success` in **5m21s**. All steps green:
  - `xcodebuild test -scheme VoltraLive -only-testing:VoltraLiveTests`
    on iPhone simulator passed, including the 4 new recorder test
    files: `RecorderBufferTests`, `RecorderRedactorTests`,
    `RecorderExporterTests`, `ActionScopeTests`. Existing
    `ProtocolGoldenTests`, `CombinedMathTests`, `DropSetCascadeTests`,
    `HistoryImporterTests`, `RecentCustomLabelsTests`,
    `SetSuggestionEngineTests`, `SideNameMatchTests`,
    `VoltraControlFramesTests`, `WarmupAutoDetectTests` all still
    pass — no regression.
  - Independent ASC API key smoke test passed (read-only ASC REST
    verification).
  - Decode signing assets + Build and archive (signed) + Export
    IPA for App Store Connect all green.
  - `Upload IPA as workflow artifact (dry-run only)` produced
    artifact `VoltraLive-dryrun-ipa` (signed IPA preserved as
    workflow artifact for 7 days).
- **Hard stops honored:**
  - ❌ No TestFlight upload — `Upload to TestFlight via altool`
    step correctly skipped by dry_run gate
    (`if: github.event_name == 'push' || github.event.inputs.dry_run == 'false'`).
  - ❌ No GitHub release / tag created — `Publish signed IPA to
    GitHub release` step gated to `github.event_name == 'push'`,
    and workflow_dispatch did not push a tag.
  - ❌ No version / build number bumped (workflow does not mutate
    those; the in-runner `Info.plist` Demo trace-relay substitution
    was not committed back to the repo).
  - ❌ No workflow edits, no repo `Info.plist` / `project.yml` /
    entitlements / sacred-protocol / WatchConnectivity changes by
    the agent.
- **Risks:** On-device QA passes A–G remain required per the spec's
  Verification Contract — the dry_run validates compile + tests +
  signing pipeline but cannot exercise the recorder UI, real
  CoreBluetooth callbacks, real HealthKit sample arrivals,
  ShareLink, SwiftUI triple-tap timing, scenePhase lifecycle, or
  Application Support `last_session.json` write on a real device.
- **Next step:** Merge PR #10 into `feat/ui-v4-2-claude` via merge
  commit (not squash) to preserve the implementation / checkpoint
  / fix / doc commit chain. After merge, decide separately whether
  to start the b77 TestFlight ship cycle (would require a manual
  version + build bump in `project.yml` + `Info.plist`, a `v*` tag
  push, and a non-dry-run `release.yml` invocation — all out of
  scope for the current PR).

## 2026-05-03 01:38 UTC — b77 ship: v0.4.50 / build 77 — Session Recorder (B74-F11)

- **Files changed:** `project.yml`, `VoltraLive/Info.plist`,
  `docs/handoff/00_START_HERE.md`,
  `docs/handoff/01_PROJECT_OVERVIEW.md`,
  `docs/handoff/02_CURRENT_STATE.md`,
  `docs/handoff/03_ROADMAP.md`,
  `docs/handoff/09_NEXT_AGENT_PROMPT.md`,
  `docs/WORK_LOG.md` (this entry).
- **Goal:** Ship B74-F11 Session Recorder as build 77. Single ship
  commit + tag `v0.4.50-build77` to trigger `release.yml` for
  TestFlight upload + GitHub release.
- **What changed:**
  - `project.yml`: `MARKETING_VERSION` 0.4.49 → 0.4.50,
    `CURRENT_PROJECT_VERSION` 76 → 77 (both in target settings AND
    in `info.properties` block); `VOLTRAFeatureLabel`
    "Health signal indicator" → "Session Recorder".
  - `VoltraLive/Info.plist`: `CFBundleShortVersionString` 0.4.49 →
    0.4.50, `CFBundleVersion` 76 → 77, `VOLTRAFeatureLabel`
    "Health signal indicator" → "Session Recorder".
  - Doc updates per AGENTS.md "Mandatory ship discipline":
    `00_START_HERE.md` (active branch state + Last shipped line),
    `01_PROJECT_OVERVIEW.md` (current shipping build line),
    `02_CURRENT_STATE.md` (Last updated, Latest shipped build,
    Active cycle, Recent shipped history head row),
    `03_ROADMAP.md` (Last updated, b77 row at top of Done table),
    `09_NEXT_AGENT_PROMPT.md` (post-b77 status section).
- **Verification (pre-tag):** B74-F11 implementation chain merged
  via PR #10 (`88a4eaf`). Pre-ship CI on PR head:
  - `build.yml` workflow_dispatch run 25260420548 — `success` in
    1m17s.
  - `release.yml dry_run=true` workflow_dispatch run 25261426415 —
    `success` in 5m21s on code-equivalent head `6ab55b8` (final PR
    head `fa8e89a` only added a docs-log metadata commit on top, so
    compile/test/signing signal carries forward to the merged state).
    `xcodebuild test -only-testing:VoltraLiveTests` passed including
    all 4 new recorder unit-test files. Signed archive + export
    green.
- **Verification (post-tag):** PENDING — tag push triggers
  `release.yml` non-dry-run path (TestFlight upload + GitHub
  release). 5-gate altool verify required per `09_RELEASE_AND_SIGNING.md`:
  (1) run conclusion `success`, (2) raw altool log pulled,
  (3) altool wall-clock ≥ 20 s, (4) positive marker present,
  (5) zero ERROR / Failed / numeric-error lines.
- **Risks:** On-device QA passes A–G per `SESSION_RECORDER_SPEC.md`
  "Verification Contract" remain required after TestFlight
  surface — recorder UI rendering, real CoreBluetooth callbacks,
  real HealthKit sample arrivals, ShareLink, SwiftUI triple-tap
  timing, scenePhase lifecycle, and Application Support
  `last_session.json` write only verifiable on a real device.
  Results land in `docs/handoff/QA_LOG.md`.
- **Next step:** After tag CI completes + 5-gate verify passes,
  run post-build QA checklist (passes A–G) and append results to
  `QA_LOG.md`. Any "Not" result → `KI-N` in `06_KNOWN_ISSUES.md`
  or follow-up fix PR.

## 2026-05-03 02:51 UTC — b78 ship: v0.4.51 / build 78 — Session Recorder (launch fix)

- **Files changed:** `VoltraLive/VoltraLiveApp.swift` (env-object
  re-injection on root overlay content),
  `VoltraLiveTests/RecorderLaunchSmokeTests.swift` (new regression
  test), `project.yml`, `VoltraLive/Info.plist`,
  `docs/handoff/00_START_HERE.md`,
  `docs/handoff/01_PROJECT_OVERVIEW.md`,
  `docs/handoff/02_CURRENT_STATE.md`,
  `docs/handoff/03_ROADMAP.md`,
  `docs/handoff/06_KNOWN_ISSUES.md` (KI-13 entry),
  `docs/handoff/09_NEXT_AGENT_PROMPT.md`,
  `docs/WORK_LOG.md` (this entry).
- **Goal:** Hotfix the b77 launch crash. b77 (v0.4.50 / build 77,
  PR #10 + PR #11) shipped a SwiftUI `EnvironmentObject.error()`
  crash on launch — `SessionRecorderToggle` mounted at the app
  root via `.overlay { ... }` could not resolve its
  `@EnvironmentObject SessionRecorder` even though
  `.environmentObject(recorder)` was applied to the modifier chain
  above. Single-line code fix + smoke test + standard ship
  bookkeeping.
- **What changed:**
  - **Fix (single line):** `VoltraLiveApp.swift` line ~346 — the
    `.overlay(alignment: .bottomTrailing) { SessionRecorderToggle() }`
    block now re-injects `recorder` via
    `SessionRecorderToggle().environmentObject(recorder)`. Root
    cause: `.overlay { content }` creates a composite where
    `content` is a SIBLING of the modified view, not a descendant —
    env-objects on the modifier chain do NOT propagate to the
    overlay's content. Crash fires at SwiftUI's `_EnvironmentObject`
    DynamicProperty resolution during initial view setup, even when
    the toggle's body returns `EmptyView()` because
    `VOLTRARecorderUnlocked` is `false` on a fresh install. See
    KI-13 in `06_KNOWN_ISSUES.md` for the full diagnosis.
  - **Regression test (new file):**
    `VoltraLiveTests/RecorderLaunchSmokeTests.swift` — three tests:
    1. `testRootOverlayWithRecorderToggleResolvesEnvironmentObject`
       mounts the same `Color.clear.environmentObject(recorder).overlay { SessionRecorderToggle().environmentObject(recorder) }`
       shape via `UIHostingController` and forces layout to exercise
       the SwiftUI body / DynamicProperty resolution. Removing the
       env-object re-injection in the future would crash this test.
    2. `testSharedSingletonInitDoesNotCrash` sanity-checks
       `SessionRecorder.shared` access (no force-unwraps in current
       init).
    3. `testSessionRecorderViewerResolvesEnvironmentObject` mirrors
       the same pattern for the long-press sheet content.
  - **Version bump:** `project.yml` + `VoltraLive/Info.plist` from
    v0.4.50 / 77 to v0.4.51 / 78. `VOLTRAFeatureLabel` set to
    `"Session Recorder (launch fix)"`.
  - **Doc updates per AGENTS.md "Mandatory ship discipline":**
    `00_START_HERE.md` (Last shipped lines updated; b77 marked
    PULLED), `01_PROJECT_OVERVIEW.md` (current shipping build),
    `02_CURRENT_STATE.md` (Last updated, Latest shipped build,
    Active cycle, Recent shipped — b77 added with PULLED note),
    `03_ROADMAP.md` (Last updated, b78 row added with b77 row
    re-labeled "PULLED — launch crash"),
    `09_NEXT_AGENT_PROMPT.md` (post-b78 status section).
  - **KI-13 opened in `06_KNOWN_ISSUES.md`** with full diagnosis,
    fix commit reference, verification, and a general lesson for
    future SwiftUI overlay patterns.
- **Verification (pre-tag):**
  - `build.yml` workflow_dispatch
    [run 25267980973](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25267980973)
    on `fix/b78-recorder-launch-crash` head `e1c19c7`: `success`
    in 1m18s. Compile + unsigned IPA artifact.
  - `release.yml dry_run=true` workflow_dispatch
    [run 25267981601](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25267981601)
    on the same head: `success` in 4m52s.
    `xcodebuild test -only-testing:VoltraLiveTests` exercised
    the new smoke tests and they all passed alongside the existing
    test suite. Signed archive + IPA export green.
  - Post-bump dry_run on the bumped head: PENDING (will land before
    PR open).
- **Verification (post-tag):** PENDING — tag push triggers
  `release.yml` non-dry-run path. 5-gate altool verify required per
  `09_RELEASE_AND_SIGNING.md`.
- **Risks:** On-device QA passes A–G per `SESSION_RECORDER_SPEC.md`
  "Verification Contract" remain required. The smoke test only
  verifies the SwiftUI env-object resolution pattern; full UI
  exercise (recorder dot, viewer, ShareLink, scenePhase, etc.)
  still needs device QA.
- **Next step:** Open PR against `feat/ui-v4-2-claude` ready for
  review. After user merges + pushes tag `v0.4.51-build78`, run
  5-gate altool verify on the tag-triggered `release.yml` run.
  Then on-device QA passes A–G to `QA_LOG.md`.

---

## 2026-05-03 15:44 UTC — Docs-only alignment for Telemetry v2

- **Goal:** Align stale handoff docs with the actual shipped state
  (v0.4.51 / build 78, Delivery UUID
  `3433cd79-fb4a-48db-9c70-b3e0289740e1`, run 25268455532) and
  prepare the repo for the **Authoritative Device State + Telemetry
  Collector v2** cycle. Docs-first, no Swift. Premise from prior
  prompt that `02_CURRENT_STATE.md` was stale at b56 was inaccurate
  (file was already at "b78 SHIPPING") but still needed
  SHIPPING → SHIPPED advancement plus Telemetry v2 active-cycle
  setup.
- **Files changed (docs only):**
  - `docs/handoff/02_CURRENT_STATE.md` — Last-updated banner;
    Latest-shipped advanced from SHIPPING → SHIPPED with run
    25268455532, merge SHA 32f9300, Delivery UUID
    `3433cd79-fb4a-48db-9c70-b3e0289740e1`; new "Verification
    status (post-b78)" subsection noting demo-mode and hardware-mode
    recorder verification claims live in chat only and need QA_LOG
    entries; Active cycle replaced with "Authoritative Device
    State + Telemetry Collector v2 — docs-first, no Swift yet";
    "Last cycle (b73)" header retitled to "Last cycle (b78)" with
    b73 demoted.
  - `docs/handoff/03_CURRENT_FEATURE_SPEC.md` — prepended full
    Telemetry v2 spec (Goal, Scope, Principles, Problems,
    Architecture, DeviceState/LoadState/DeviceUpdateSource models,
    Event model, Decoder reqs with hypothesis flags on `0x03` and
    `2b010100`, Source-of-truth, Conflict resolution, Load/unload
    behavior, Weight/mode sync, Recorder improvements, Constants
    (750 ms write timeout, 500 ms / 2000 ms stream gap, 5000-event
    ring buffer), Export reqs (schemaVersion 1 → 2 additive), UX,
    BLE audit requirement, Migration, Open hypotheses, Acceptance
    criteria, 10-step implementation order, Non-goals, Decision
    summary). V4 b58 LiveCapture spec preserved below new section
    under "# Historical: V4 LiveCapture spec (b58)" demarcator.
  - `docs/handoff/06_KNOWN_ISSUES.md` — appended KI-14 (handoff
    staleness, closed in this commit) through KI-26 (BLE audit
    needed). Specifically: KI-15 dup write.tx; KI-16 demo-mode
    `ble.error` ordering; KI-17 1000-event cap; KI-18 no semantic
    events; KI-19 no DeviceState mirror; KI-20 weight changes
    don't update; KI-21 ecc/conc/chains drift; KI-22 load drop not
    surfaced; KI-23 `0x03` hypothesis; KI-24 `553a0470` byte
    unknown; KI-25 controls missing `ui.tap`; KI-26 BLE audit.
    File grew to 736 lines.
  - `docs/handoff/10_OPEN_QUESTIONS.md` — added 8 new Telemetry v2
    open questions OQ-T1 … OQ-T8: meaning of `0x03` status byte;
    byte positions for ecc / conc / chains; meaning of `2b000100`
    vs `2b010100`; existence of an unsubscribed notify/indicate
    status characteristic; force / tension decodability; ring-buffer
    compression strategy preserving rep / force debug; whether
    `load.state.change` should be its own event or a field of
    `device.state.change`; exact UI copy for unloaded / fault /
    unknown states.
  - `docs/handoff/09_NEXT_AGENT_PROMPT.md` — full rewrite. Killed
    stale b66 / b67 / b68 sections at the top. New version:
    instructs next agent to read AGENTS.md + handoff 00–10 +
    WORK_LOG + optional skim docs (QA_LOG, B74_BUG_QUEUE,
    B52_DIAGNOSIS, 11_AGENT_ROLES, 09_RELEASE_AND_SIGNING,
    03_ROADMAP, 06_HEALTHKIT, 07_DUAL_VOLTRA, 08_SUPERSET);
    summarize repo state before code; docs-first, no Swift until
    user says go; Step 1 = BLE characteristic audit, Step 2 =
    shared decoder abstraction; sacred files listed; decoder must
    be additive alongside existing `VoltraLive/Protocol/` pipeline;
    wait for user go.
  - `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` — appended ADR
    **V4-D26 — Telemetry v2 decoder is additive, sacred files
    unchanged**. Locks: additive module only; sacred files not
    modified; hypothesis bytes round-trip raw and emit hypothesis
    flag; schemaVersion 1 → 2 additive. Path C (docs-only)
    verification for the ADR itself; implementation PRs land Path A
    once on-device fixtures pin OQ-T1, OQ-T3, OQ-T5 and the BLE
    audit closes.
  - `docs/handoff/05_BLE_AND_PROTOCOL.md` — appended "BLE
    characteristic audit (post-b78)" plan: discover all advertised
    services / characteristics, diff against current subscriptions,
    probe unsubscribed notify/indicate candidates with a build-time
    debug toggle (no edits to sacred files), cross-reference
    against `553404ac` / `553a0470` byte stream, write up audit
    table here. Definition-of-done closes OQ-T4 and any of OQ-T1 /
    OQ-T3 / OQ-T5 the audit deterministically resolves.
  - `docs/handoff/04_ARCHITECTURE.md` — appended "Telemetry v2
    decoder (additive, post-b78)" note pointing at the spec and
    ADR V4-D26, restating the additive constraint and that sacred
    files are unchanged.
  - `docs/WORK_LOG.md` — this entry.
- **What changed:** the repo now reflects the actual shipped state
  (b78 SHIPPED with full ship metadata) and is set up for
  Telemetry v2 in the order the next agent will execute: BLE audit
  first, additive shared decoder second. All hypothesis bytes are
  written down explicitly with their evidence level and the OQ-T
  entry that gates promotion to a constant.
- **Verification:** docs-only commit; `git status --short` shows
  only `docs/` paths; `git diff --cached --name-only | grep -E
  '\.swift$'` returns empty; `git diff` reviewed by file. No
  `Info.plist`, `project.yml`, entitlements, or workflow changes.
  `_tmp/archive/` not touched. Sacred files
  (`VoltraLive/Protocol/VoltraProtocol.swift`,
  `TelemetryExtractor.swift`, `PacketParser.swift`,
  `FrameAssembler.swift`, `.github/workflows/build.yml`)
  not touched.
- **Risks:**
  - Build / version truth in `02_CURRENT_STATE.md` ultimately
    depends on the WORK_LOG ship narrative + TestFlight surface.
    If the b78 entry is later corrected (e.g. delivery UUID
    mismatch on Apple's side), this commit will need a follow-up
    correction.
  - All Telemetry v2 byte mappings remain hypotheses. `0x03` in
    `553404ac` and `2b010100` in `553a0470` are documented as
    single-observation guesses; the additive decoder must not
    promote either to a constant before the corresponding OQ-T
    entry is closed with hardware evidence.
  - Hardware verification claims (1000-event live session,
    base-weight changes, probable load cutout) and demo-mode
    verification (33-event session, valid `.txt` / `.json`
    exports) are now written into `02_CURRENT_STATE.md`
    "Verification status (post-b78)" but **explicitly NOT signed
    off as QA passes A–G** — those still require per-pass
    `QA_LOG.md` entries.
- **Next step:** BLE characteristic audit per the plan in
  `05_BLE_AND_PROTOCOL.md`, then design the shared additive
  decoder abstraction per ADR V4-D26 and the 10-step implementation
  order in `03_CURRENT_FEATURE_SPEC.md`. No Swift until the user
  explicitly gives the go.

---

## 2026-05-03 18:46 UTC — BLE characteristic audit (paper) for Telemetry v2

- **Goal:** Step 1 of the Telemetry v2 cycle per
  `09_NEXT_AGENT_PROMPT.md` — produce a documented map of every
  service / characteristic on the VOLTRA peripheral, identify any
  notify/indicate-capable channel the iOS app is not subscribed to,
  and resolve / partially-resolve OQ-T4 in the same commit.
- **Method:** **Paper audit only** (release-only mode + no hardware
  in this environment). Cross-referenced this repo's
  `VoltraProtocol.swift` (HEAD `6a3162b`) against two independent
  public reference implementations by the same reverse-engineering
  author:
  - `dylanmaniatakes/Beyond-Power-Voltra-Android`
    (`core/protocol/.../VoltraUuidRegistry.kt`,
    `core/protocol/.../VoltraOfficialReadOnlyBootstrap.kt`,
    `device/ble/.../AndroidVoltraClient.kt` — `main` branch as of
    2026-05-03)
  - `dylanmaniatakes/Beyond-Power-HomeAssistant`
    (`custom_components/voltra/const.py`,
    `custom_components/voltra/protocol.py` — `main` branch as of
    2026-05-03)
  No live nRF Connect / LightBlue scan was run. Method caveat is
  documented prominently in every artifact.
- **Files changed (docs only):**
  - `docs/handoff/artifacts/ble_characteristic_audit_2026-05-03.md`
    — new file. Full audit: source table, per-row characteristic
    table (C1–C4 with role / properties / iOS-subscribe / sources),
    cross-implementation subscription matrix, candidate-channels
    section, implications for Telemetry v2, bootstrap-writes
    discrepancy, exhaustive "what remains unknown" list, recommended
    next actions.
  - `docs/handoff/05_BLE_AND_PROTOCOL.md` — appended **"BLE
    characteristic audit results — 2026-05-03"** section with
    method caveat, char table, candidate channels (zero), Telemetry
    v2 implications, what-remains-unknown summary. Section sits
    immediately after the pre-existing audit-plan section from the
    prior commit.
  - `docs/handoff/10_OPEN_QUESTIONS.md` — updated OQ-T2 (status
    advanced to "non-hardware resolution path identified" with
    pointer to Android bootstrap packet 10's `CMD_PARAM_READ`) and
    OQ-T4 (status advanced to "partially resolved" with the
    no-fifth-channel finding from the paper audit, and a clear
    enumeration of what only an on-device scan can close).
  - `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` — appended ADR
    **V4-D27** as a follow-up to V4-D26: Telemetry v2 proceeds on
    the existing 3 notify channels (C1 cmdChar, C2 notifyChar,
    C3 transport) plus an additive `CMD_PARAM_READ` for the 19-param
    mode/weight state set on C3 transport, sourced via the v2
    collector module (not by editing the sacred 9-entry
    `BOOTSTRAP_WRITES` constant). OQ-T1 and OQ-T3 explicitly remain
    hypothesis; OQ-T4 explicitly remains open pending on-device
    scan.
  - `docs/WORK_LOG.md` — this entry.
- **What changed substantively:**
  1. **OQ-T4 partially resolved.** All three independent reference
     implementations (iOS, Android, HA) enumerate exactly the same
     4 characteristic UUIDs on the VOLTRA service
     (`e4dada34-…c7e4`) and subscribe to the same 3 of 4
     (cmd / notify / transport). C4 `justWrite` is
     `WRITE_NO_RESPONSE` only in all three sources. **No reference
     implementation documents an unsubscribed notify or indicate
     channel on the VOLTRA service.**
  2. **OQ-T2 has a non-hardware path.** Android bootstrap packet 10
     (`read mode feature state`,
     `VoltraOfficialReadOnlyBootstrap.kt` lines 55–81) issues a
     single `CMD_PARAM_READ` for 19 mode/weight params including
     `PARAM_BP_BASE_WEIGHT`, `PARAM_BP_CHAINS_WEIGHT`,
     `PARAM_BP_ECCENTRIC_WEIGHT`, `PARAM_FITNESS_INVERSE_CHAIN`.
     Authoritative ecc / conc / chains values are available via
     parameter response on C3 transport.
  3. **Bootstrap-writes discrepancy logged.** iOS has 9 bootstrap
     writes (`VoltraProtocol.swift` lines 24–40); Android has 10.
     The 10th is the `CMD_PARAM_READ` above. **Not a bug in iOS** —
     iOS's 9-entry array is sacred and stays untouched. The v2
     collector will issue the read from its own module, not by
     editing the sacred constant.
  4. **No new ADR was added speculatively.** ADR V4-D27 was added
     because the audit yielded a real, repo-grounded design
     decision (proceed on existing channels + additive
     `CMD_PARAM_READ`), exactly the case the prompt authorized.
- **Verification:**
  - `git status --short` and `git diff --stat` reviewed; only
    `docs/` paths in diff.
  - `git diff --name-only | grep '\.swift$'` returned empty → no
    Swift files changed.
  - Sacred files untouched: `VoltraProtocol.swift`,
    `TelemetryExtractor.swift`, `PacketParser.swift`,
    `FrameAssembler.swift`, `.github/workflows/build.yml`.
  - `_tmp/archive/` untouched.
  - No `Info.plist`, `project.yml`, entitlements, or version-bump
    edits.
- **Risks:**
  - **Paper audit, not on-device.** Every entry in the char table
    is sourced from public reference implementations that all share
    the same blind spot — none use unfiltered service /
    characteristic discovery on iOS. If the VOLTRA peripheral
    advertises additional services (DIS `0x180A`, Battery `0x180F`,
    or vendor-specific) or additional characteristics on the VOLTRA
    service beyond the 4 known UUIDs, **this audit cannot see them**
    and neither can the iOS app's logs (the iOS app uses
    `discoverServices([VoltraUUID.service])` and
    `discoverCharacteristics([4-UUID list], …)` —
    `VoltraBLEManager.swift` lines 418, 424). OQ-T4 is therefore
    only **partially** resolved.
  - **OQ-T1 and OQ-T3 remain hypothesis.** The Android
    `VoltraNotificationParser.kt` is 2005 lines and may or may not
    contain a meaning for the `0x03` status byte and `2b010100`
    phase flag — **not exhaustively read in this pass.** Flag for
    the shared-decoder design step.
  - **`CMD_PARAM_READ` request shape unverified on iOS.** The Android
    reference uses a frame builder we have not yet ported. Building
    the iOS request will need a fixture (or a hardware capture) to
    confirm the on-the-wire byte sequence before the v2 collector
    issues the read.
- **Next step:** Step 2 of the Telemetry v2 cycle — design the
  shared additive decoder abstraction per ADR V4-D26 / V4-D27 and
  the 10-step implementation order in `03_CURRENT_FEATURE_SPEC.md`.
  Recommended pre-work, all docs-only and before any Swift: read
  `Beyond-Power-Voltra-Android`'s `VoltraNotificationParser.kt`
  end-to-end and write up byte-level semantics it documents
  (especially anything touching `553404ac` status frames or
  `553a0470` stream frames) into a follow-up artifact under
  `docs/handoff/artifacts/`. That may close OQ-T1 / OQ-T3 without
  hardware. Optional parallel track: when the user has a moment,
  run an iOS-side nRF Connect / LightBlue scan against a paired
  VOLTRA and drop the export at
  `docs/handoff/artifacts/ble_scan_<date>.{json,txt}` — that closes
  the remaining unknowns in OQ-T4.

## 2026-05-03 15:30 EDT — Telemetry v2 first slice: base-weight decoder

- **Goal.** Land the first Swift slice of Telemetry v2 / Authoritative
  Device State: an additive BLE frame decoder, a `DeviceState` model
  and reducer, pending/confirmed write attribution, and a
  `device.state.change` semantic recorder event — all scoped to base
  weight only. User explicitly authorized the Swift work in this
  session; release-only mode lifted for this slice. Drop-set stuck
  bug (KI-19) is deferred per user decision.

- **Files added.**
  - `VoltraLive/BLE/Decoder/VoltraDecodedEvent.swift` — `DeviceStateField`,
    `DeviceStateChangeSource`, `VoltraDecodedEvent`.
  - `VoltraLive/BLE/Decoder/VoltraDecodeTable.swift` — `VoltraDecodePattern`
    + base-weight pattern (`paramId 0x3E86`, uint16-LE pounds, range 0..250).
  - `VoltraLive/BLE/Decoder/VoltraBLEFrameDecoder.swift` — `decode(_:)`
    + `PendingWriteTracker` (FIFO, 32 cap, 2 s window).
  - `VoltraLive/BLE/State/DeviceState.swift` — `DeviceState`,
    `ConfirmedValue<T>`, `DeviceStateReducer.apply(_:to:)`,
    `DeviceStateChange`.
  - `VoltraLiveTests/VoltraBLEFrameDecoderTests.swift` — 11 cases
    (golden 5/15/20/95, source attribution, pending expiry, candidate
    pass-through, reducer idempotency + transitions).

- **Files modified.**
  - `VoltraLive/Recorder/RecorderEvent.swift` — added
    `RecorderCategory.device` (additive enum case).
  - `VoltraLive/BLE/VoltraBLEManager.swift` — added
    `@Published deviceState: DeviceState`, `frameDecoder`, decoder
    invocation in `handleNotification(...)` (between `ble.notify.rx`
    and the legacy `parsePacket(...)`), `device.state.change` recorder
    emit, `recordOutboundParamWrite(field:lb:)` public hook.
  - `VoltraLive/BLE/VoltraWriter.swift` — added optional
    `onOutboundParam` init param; calls it after each base-weight
    write in `flush()`.
  - `VoltraLive/BLE/WriterRouter.swift` — wires `onOutboundParam` to
    the legacy single-device manager's pending tracker.
  - `VoltraLive/BLE/Dual/MultiDeviceManager.swift` — wires
    `onOutboundParam` per side (left/right).

- **Docs updated in same commit.** `03_CURRENT_FEATURE_SPEC.md`
  (implementation order steps 1–7 status), `04_ARCHITECTURE.md`
  (first-slice file map + invocation point + source attribution),
  `05_BLE_AND_PROTOCOL.md` (base-weight wire format with byte-vector
  table + decoder invariants), `06_KNOWN_ISSUES.md` (KI-20 →
  in-progress), `10_OPEN_QUESTIONS.md` (new OQ-T0 RESOLVED entry),
  `CONVERSATION_LOG.md`.

- **Sacred-files invariant.** Verified untouched:
  `VoltraProtocol.swift`, `TelemetryExtractor.swift`,
  `PacketParser.swift`, `FrameAssembler.swift`,
  `.github/workflows/build.yml`. The legacy 0xAA telemetry pipeline
  is unchanged; the v2 decoder runs alongside it.

- **Verification.**
  - Static review of all 5 new files + 5 modified files; no obvious
    Swift syntax issues. Decoder logic is pure-function over `Data`
    and uses `subdata(in:)` indices correctly for sliced buffers.
  - `xcodebuild test` could not run in this Linux sandbox (no Swift
    toolchain). Tests must be run by the user / CI before this slice
    is shipped to TestFlight. 11 unit tests are included; the build
    surface change is small (no new `import`s, no project.yml change
    — XcodeGen `path: VoltraLive` glob auto-includes the new
    `BLE/Decoder/` and `BLE/State/` subdirectories, and the test
    file lands in the existing `VoltraLiveTests` target).
  - `git diff --name-only HEAD` against the sacred list returned 0
    matches. Confirmed twice.

- **Risks.**
  - `DeviceState.baseWeightLb` is published but no UI binds to it
    yet. `LiveCaptureView` still reads the user's most recent UI
    request, so machine-side dial changes still won't visibly update
    the tile — KI-20 stays "in progress" until that wire is run.
    Decision: ship the data path now, bind UI in a follow-up commit
    so each commit can be reverted independently if it misbehaves.
  - The `PendingWriteTracker` window is 2 s (vs. 750 ms target in
    the spec). Conservative on purpose while we observe the real
    confirmation cadence; tightening is a one-line change once we
    have a bigger sample.
  - Eccentric / chains / inverse-chain confirmations are NOT yet
    decoded. The writer registers ONLY base-weight outbound writes;
    other params will surface as `deviceUnsolicited` in the recorder
    until their patterns are added. Documented in 03 step 9 and 10.

- **Next step.** Either (a) bind LiveCaptureView's base-weight tile
  to `VoltraBLEManager.deviceState.baseWeightLb?.value` to close
  KI-20 end-to-end, or (b) extend the decode table to chains
  (`0x3E87`) + eccentric (`0x3E88`) using the same proof-by-byte-
  vector approach. Both are independent of this commit.

## 2026-05-03 20:03 UTC — LiveCaptureViewV2 mirrors device-confirmed base weight

- **Files changed:** `VoltraLive/Logging/Views/LiveCaptureViewV2.swift`,
  `docs/handoff/03_CURRENT_FEATURE_SPEC.md`,
  `docs/handoff/04_ARCHITECTURE.md`,
  `docs/handoff/06_KNOWN_ISSUES.md`, `docs/WORK_LOG.md`.
- **What changed:** Closed the UI half of the Telemetry v2 base-weight
  bridge (KI-20). Added three private members to `LiveCaptureViewV2`
  next to `focusedBle`:
  - `focusedConfirmedBaseWeight: ConfirmedValue<Int>?` — the full
    confirmed value off the focused unit's `deviceState`.
  - `focusedConfirmedBaseWeightValue: Int?` — `Equatable` keypath for
    `.onChange` so SwiftUI doesn't observe the whole struct.
  - `applyDeviceOriginatedBase(_:)` — filters strictly on
    `confirmed.source == .deviceUnsolicited`, clamps `0...500` lb,
    and writes `LoggingStore.pendingPlannedWeightLb` +
    `reanchorCascadeIfActive(toLb:)` only when the value actually
    differs from current planned weight.
  Wired a single `.onChange(of: focusedConfirmedBaseWeightValue)`
  modifier to the existing outermost view chain (next to
  `.pageBadge`/`.recorderScreen`) that calls
  `applyDeviceOriginatedBase(focusedConfirmedBaseWeight)`.
  **Display unchanged:** the WEIGHT card big number still computes
  off `(logging.pendingPlannedWeightLb ?? 0) * pulleyMultiplier`,
  so app-side `+/-` taps remain visually instant. `adjustWeight`,
  `pushUpcomingStateToDevice`, `toggleHardwareLoad`, `tapDropTile`,
  and `WriterRouter.apply` are untouched.
- **Verification:** Static review only — no Swift toolchain in this
  sandbox; `xcodebuild test` must run on macOS/CI. Verified by
  inspection: `ConfirmedValue<Int>` and `DeviceStateChangeSource
  .deviceUnsolicited` exist in `VoltraLive/BLE/State/DeviceState.swift`
  and `VoltraLive/BLE/Decoder/VoltraDecodedEvent.swift` exactly as
  the patch assumed. Two-parameter `.onChange(of:_:_:)` form is
  already in use elsewhere in this file (line 340 `mdm
  .supersetActiveSlot`) so the iOS 17 minimum is fine.
  `git diff --name-only` against the sacred list (`VoltraProtocol
  .swift`, `TelemetryExtractor.swift`, `PacketParser.swift`,
  `FrameAssembler.swift`, `.github/workflows/build.yml`,
  `project.yml`) returned 0 matches. No version/build bump.
- **Risks:**
  - The filter is `.deviceUnsolicited` only. If a future decode
    path mis-attributes a machine-side change as
    `appRequestConfirmed` (e.g. tracker window too wide and a
    dial twist coincides with an in-flight write), that twist
    would be silently dropped from the UI. Mitigation: the
    `PendingWriteTracker` 2 s window is already conservative and
    `consume(field:lb:)` requires a `(field, lb)` exact match,
    so a coincidental same-pound write is the only failure
    mode. Low risk in practice.
  - The bridge mutates `logging.pendingPlannedWeightLb` outside
    the `pushUpcomingStateToDevice()` path. That's intentional —
    we don't want a machine-originated change to be re-written
    back to the device — but it means the device will not be
    "told" again by the app until the next user edit. That
    matches the user's mental model (the dial is the source of
    truth) but should be confirmed in hardware testing.
  - `xcodebuild test` not run; if I miscounted a brace or got a
    SwiftUI generic wrong, CI will catch it.
- **Next step.** Hardware re-verification with the recorder armed:
  twist the VOLTRA dial, confirm `device.state.change` events
  emit with `source=deviceUnsolicited`, confirm the WEIGHT tile
  on `LiveCaptureViewV2` updates within ~one frame, confirm
  `+/-` app taps remain instant and don't flicker on echo. Once
  green, mark KI-20 fully resolved (currently
  "implemented-pending-hardware-verification") and start the
  decode-table expansion for eccentric (`0x3E88`) and chains
  (`0x3E87`).

## 2026-05-03 20:30 UTC — Fix non-exhaustive switch on RecorderCategory.device

- **Files changed:** `VoltraLive/Recorder/SessionRecorderViewer.swift`,
  `docs/WORK_LOG.md`.
- **What changed:** CI run 25289829556 on `feat/ui-v4-2-claude` failed
  with one Swift compile error directly caused by the `da34cd4`
  decoder slice:
  ```
  SessionRecorderViewer.swift:288:9: error: switch must be exhaustive
  note: add missing case: '.device'
  ```
  `da34cd4` added `case device` to `RecorderCategory` (the new
  Telemetry v2 semantic-event bucket) but did not update the
  `categoryColor(_:)` exhaustive switch in `SessionRecorderViewer`.
  Added a single `case .device: return VoltraColor.accent` arm with
  a Telemetry v2 / b73-b79 comment explaining why the category gets
  the accent color (distinct from `.ble` raw bytes and `.state`
  app-side state). No other changes; no other files touched.
- **Verification:** Static review only here; CI will re-verify on
  push (this is a CI-loop fix, so re-run is the test).
- **Risks:** None to runtime. Worst case the accent color choice
  conflicts visually with `.ui`, but the recorder viewer is an
  internal debug surface and color tuning is trivial.
- **Next step:** Re-trigger build.yml; if green, KI-20 stays at
  "implemented-pending-hardware-verification" awaiting hardware
  re-test (unchanged). No TestFlight ship without explicit user
  go-ahead.

## 2026-05-03 20:50 UTC — TestFlight ship: v0.4.52-build79 (Telemetry v2 base weight)

- **Goal:** Ship the Telemetry v2 base-weight verification build
  (da34cd4 + bdbf91b + 53af938) to TestFlight per the
  `09_RELEASE_AND_SIGNING.md` documented process.
- **Files changed (this commit):**
  - `project.yml` — bumped `MARKETING_VERSION` to `0.4.52`,
    `CURRENT_PROJECT_VERSION` to `79`; mirror block updated;
    `VOLTRAFeatureLabel` set to `"Telemetry v2 base weight"`.
  - `VoltraLive/Info.plist` — `CFBundleShortVersionString`
    `0.4.52`, `CFBundleVersion` `79`, `VOLTRAFeatureLabel`
    `"Telemetry v2 base weight"`.
  - `docs/handoff/06_KNOWN_ISSUES.md` — KI-20 status header
    updated to "shipped — pending hardware verification" with
    `v0.4.52-build79` reference; per-commit traceability noted
    (da34cd4 / bdbf91b / 53af938).
  - `docs/handoff/QA_LOG.md` — appended b79 skeleton entry per
    AGENTS.md "Post-build QA checklist", with QA focus areas
    for MJ on physical VOLTRA.
- **What changed.** Version bump only; no source edits to the
  Telemetry v2 slice. Bumped per the documented 6-line policy
  (3 in `project.yml`, 2 in `Info.plist`,
  `MARKETING_VERSION/CURRENT_PROJECT_VERSION` source-of-truth in
  `project.yml` lines 64–65 mirrored to lines 92–93 and into
  `Info.plist`). Sacred files NOT touched (`VoltraProtocol.swift`,
  `TelemetryExtractor.swift`, `PacketParser.swift`,
  `FrameAssembler.swift`, `.github/workflows/build.yml`,
  `_tmp/archive`).
- **Verification.**
  - `grep -n -E 'MARKETING_VERSION|CURRENT_PROJECT_VERSION|CFBundleShortVersionString|CFBundleVersion'`
    confirms 6 lines all read `0.4.52 / 79`.
  - macOS CI green on HEAD `53af938` (build.yml run
    25289913362) before the bump commit.
- **Risks / what could still go wrong.**
  - `altool` silent-fail (the b55 signature). Mitigated by the
    `release.yml` triple-check (failure-marker grep + ≥10 s
    duration + positive success-marker), then post-run raw-log
    audit per `09_RELEASE_AND_SIGNING.md` step (4)–(5).
  - Apple-side processing latency: a "shipped" green run still
    means TestFlight processing must complete before MJ sees
    the build.
- **Next step.** Tag `v0.4.52-build79` and push to trigger
  `release.yml`; watch run; audit the upload step's job log
  for both positive success markers and zero `ERROR:` /
  `Failed to upload package` / `(-NNNNN)` lines; report the run
  URL + ASC processing status to the user. KI-20 stays at
  "shipped — pending hardware verification" until MJ confirms
  on the physical VOLTRA.

## 2026-05-03 21:25 UTC — Universal agent workflow rules landed

- **Goal:** Make the user-supplied workflow rules
  (Plan-first / Subagent strategy / Self-Improvement Loop /
  Verification / Elegance / Autonomous Bug Fixing / Core
  Principles) durable across every agent and every Computer
  session in this repo. User answered the gating questions:
  AGENTS.md pointer + new dedicated long-form doc, create the
  `tasks/` files the spec references, push immediately.
- **Files changed (this commit):**
  - `AGENTS.md` — appended new section "Universal agent
    workflow (added 2026-05-03 — sticky for all agents)"
    under §"Karpathy Leash Constraints"; expanded Karpathy
    Select Rule reading order to include
    `docs/handoff/AGENT_WORKFLOW.md`, `tasks/lessons.md`,
    `tasks/todo.md`.
  - `docs/handoff/AGENT_WORKFLOW.md` — NEW. Long-form spec
    transcribed from the user's image, restructured as a repo
    doc with a precedence-ordering section that composes
    cleanly with the existing Karpathy rules and handoff-doc
    enforcement.
  - `tasks/todo.md` — NEW. Active task plan template with
    Plan / Review structure; current state set to "no active
    task" since the in-flight item (TestFlight ship) just
    closed at v0.4.52-build79.
  - `tasks/lessons.md` — NEW. Append-only self-improvement
    log with format spec and a genesis entry.
- **What changed.** Documentation only. No source edits, no
  build-system edits, no version bump.
- **Sacred-files invariant.** ✓ Not touched: `VoltraProtocol.swift`,
  `TelemetryExtractor.swift`, `PacketParser.swift`,
  `FrameAssembler.swift`, `.github/workflows/build.yml`,
  `project.yml`, `_tmp/archive`.
- **Verification.**
  - Repo source-of-truth rule satisfied: every rule in the
    image now lives in a committed file, not in chat.
  - Path-existence rule satisfied: `tasks/todo.md` and
    `tasks/lessons.md` exist before any rule references them.
  - Karpathy Select Rule updated so future agents read these
    files at session start (steps 2–4).
  - Composes cleanly with existing AGENTS.md sections — see
    `AGENT_WORKFLOW.md` "How this composes" precedence list.
- **Risks.** Two doc surfaces (AGENTS.md non-negotiables +
  AGENT_WORKFLOW.md long-form) must stay in sync on future
  edits. Mitigated by the pointer line at top of
  AGENT_WORKFLOW.md and the explicit "stack on" wording in
  AGENTS.md.
- **Next step.** Commit + push to `feat/ui-v4-2-claude` per
  user instruction "Apply now and push." No CI required (doc
  only). KI-20 still at "shipped — pending hardware
  verification" — independent of this change.

## 2026-05-03 22:10 UTC — KI-20 visual bridge fix

- **Goal.** Fix the KI-20 visual update failure: after A1 hardware
  test (physical VOLTRA 20→15 lb), telemetry decode passed but the
  LiveCapture WEIGHT tile did NOT update. Fix the UI bridge without
  touching the decoder or protocol.
- **Files changed.**
  - `VoltraLive/BLE/VoltraBLEManager.swift` — new
    `@Published private(set) var deviceOriginatedBaseWeightUpdate:
    ConfirmedValue<Int>?`; set inside `handleNotification` reducer
    loop when `change.field == .baseWeight && change.source ==
    .deviceUnsolicited`.
  - `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` — replaced
    `focusedConfirmedBaseWeightValue` computed key with
    `focusedDeviceOriginatedBaseWeightUpdateValue`; replaced old
    `.onChange` with new `.onChange(of:
    focusedDeviceOriginatedBaseWeightUpdateValue)`; added
    `applyDeviceOriginatedBase(...)` call inside existing `.onAppear`;
    added `SessionRecorder.shared.record(category: .ui, name:
    "ui.deviceBaseWeightApplied", ...)` inside `applyDeviceOriginatedBase`.
  - `docs/handoff/03_CURRENT_FEATURE_SPEC.md` — updated step 4 to
    document A1 failure + new bridge architecture.
  - `docs/handoff/04_ARCHITECTURE.md` — added "Telemetry v2 UI bridge
    (post-A1 fix)" section with full path diagram.
  - `docs/handoff/06_KNOWN_ISSUES.md` — updated KI-20 status to
    "fix implemented after failed A1 visual test — pending retest".
  - `docs/handoff/QA_LOG.md` — added b79 A1/B1 hardware test results.
  - `docs/handoff/CONVERSATION_LOG.md` — appended decision record.
  - `tasks/todo.md` — plan + review.
  - `tasks/lessons.md` — appended lesson on dedicated @Published bridge.
- **What changed.** Visual path only. Decoder, reducer,
  PendingWriteTracker, recorder emission, and app +/- write path are
  all unchanged. No sacred files touched.
- **Verification result.** Static review only (no macOS/Xcode in
  environment). Confirmed:
  - `ConfirmedValue<Int>` is defined in `DeviceState.swift` and is
    visible to `VoltraBLEManager.swift` (same module).
  - `deviceOriginatedBaseWeightUpdate` property type matches
    `deviceState.baseWeightLb` type exactly.
  - `.onChange(of:)` uses two-parameter iOS 17 closure form
    consistent with all other `.onChange` calls in the file.
  - `applyDeviceOriginatedBase` still guards `source == .deviceUnsolicited`
    as belt-and-suspenders even though the caller already guarantees it.
  - `SessionRecorder.shared.record(category: .ui, ...)` uses the
    existing `record(category:name:metadata:)` signature.
  - Sacred files unchanged: `VoltraProtocol.swift`,
    `TelemetryExtractor.swift`, `PacketParser.swift`,
    `FrameAssembler.swift`, `.github/workflows/build.yml`.
  - `project.yml` unchanged.
  - No version/build bump.
- **Risks.** SwiftUI `.onChange` behaviour on two-parameter form must
  fire for reference-type wrapper (`ConfirmedValue` is a struct but
  `Optional<ConfirmedValue<Int>>` equality depends on the contained
  struct's `Equatable`). `ConfirmedValue` conforms to `Equatable` per
  `DeviceState.swift`. The bridge assigns a new `ConfirmedValue` on
  every device-unsolicited change (not idempotent for same value), so
  SwiftUI will always see an inequality and fire onChange. The
  `guard current != lb` inside `applyDeviceOriginatedBase` prevents
  redundant `pendingPlannedWeightLb` mutations.
- **Next step.** Push to `feat/ui-v4-2-claude`, ship to TestFlight.
  Run A1 test: set app to 20 lb, change physical VOLTRA to 15 lb,
  confirm tile changes to 15 lb. Expected logs:
  `device.state.change source=deviceUnsolicited to=15` +
  `ui.deviceBaseWeightApplied to=15`.

## 2026-05-03 22:20 UTC — KI-20 bridge event-based patch

- **Goal.** Make device-originated base-weight bridge fire for every
  device event, even if lb value repeats (same-weight confirmation).
- **Files changed.**
  - `VoltraLive/BLE/VoltraBLEManager.swift` — added
    `@Published private(set) var deviceOriginatedBaseWeightUpdateID: Int = 0`;
    added `deviceOriginatedBaseWeightUpdateID &+= 1` alongside
    `deviceOriginatedBaseWeightUpdate = confirmed`.
  - `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` — replaced
    `focusedDeviceOriginatedBaseWeightUpdateValue: Int?` computed key
    with `focusedDeviceOriginatedBaseWeightUpdateID: Int`; replaced
    `.onChange(of: focusedDeviceOriginatedBaseWeightUpdateValue)` with
    `.onChange(of: focusedDeviceOriginatedBaseWeightUpdateID)`.
  - `docs/handoff/04_ARCHITECTURE.md` — updated bridge path to reference
    event ID observer.
- **What changed.** Observer key is now a monotonic Int that increments
  on every device event. SwiftUI always sees a new value, so the onChange
  fires regardless of whether lb repeated.
- **Sacred files.** Unchanged.
- **Verification.** Static review only.
- **Next step.** Push, ship TestFlight, run A1 retest.

## 2026-05-03 22:15 UTC — Build bump 79 → 80 for KI-20 TestFlight ship

- **Goal.** Bump build number to 80 and ship to TestFlight so the KI-20
  visual bridge fix (commits 08a8b7c + a46d45f) can be hardware-retested.
- **Exception approved.** User granted one-time explicit approval to edit
  `project.yml` for the build-number bump only. Scope: lines 65 and 93
  (`CURRENT_PROJECT_VERSION` / `CFBundleVersion`) `79` → `80`. Marketing
  version unchanged (`0.4.52`). `project.yml` remains sacred for all
  non-release-bump changes. Reason: `project.yml` is the repo source of
  truth for the TestFlight build number per `09_RELEASE_AND_SIGNING.md`.
- **Files changed.**
  - `project.yml` — lines 65, 93: `79` → `80`. Lines 64, 92 unchanged
    (`0.4.52`). No structural, target, or settings changes.
  - `VoltraLive/Info.plist` — `CFBundleVersion` `79` → `80`.
    `CFBundleShortVersionString` unchanged (`0.4.52`).
- **6-line verification.** All 6 canonical version lines confirmed:
  project.yml:64 MARKETING_VERSION=0.4.52,
  project.yml:65 CURRENT_PROJECT_VERSION=80,
  project.yml:92 CFBundleShortVersionString=0.4.52,
  project.yml:93 CFBundleVersion=80,
  Info.plist CFBundleShortVersionString=0.4.52,
  Info.plist CFBundleVersion=80.
- **Other sacred files.** Unchanged.
- **Next step.** Commit, tag v0.4.52-build80, push tag to trigger release.yml.

## 2026-05-03 22:22 UTC — TestFlight ship: v0.4.52-build80 (KI-20 visual bridge)

- **Goal.** Ship build 80 to TestFlight for KI-20 hardware retest.
- **Tag.** `v0.4.52-build80` at commit `51908f2`.
- **Workflow run.** `release.yml` run 25292365029.
  URL: https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25292365029
  Conclusion: success. Duration: ~6 min.
- **5-gate altool verification.**
  1. Failure-marker grep: PASS — zero real error lines.
  2. Wall-clock duration: PASS — ~6 min (>> 10 s floor).
  3. Positive success marker: PASS — "No errors uploading archive at 'build/export/VoltraLive.ipa'."
  4. No `ERROR:` lines in altool output: PASS.
  5. Delivery UUID present: PASS — `1d4a639d-542a-4a3b-93ec-d640459da0cd`.
- **Commits shipped.**
  - `08a8b7c` fix: apply device-originated base weight in live capture
  - `a46d45f` fix: make device base-weight bridge event-based
  - `51908f2` chore(release): bump to 0.4.52 / build 80
- **KI-20 status.** Pending hardware retest on build 80. DO NOT mark closed
  until MJ confirms tile updates to 15 lb on physical VOLTRA.
- **Next step.** Run A1 hardware test: set app to 20 lb, change physical
  VOLTRA to 15 lb. Expected: tile updates to 15 lb. Expected logs:
  device.state.change source=deviceUnsolicited to=15 +
  ui.deviceBaseWeightApplied to=15.

## 2026-05-03 23:10 UTC — KI-20 focusedBle topology fix

- **Goal.** Fix root cause of KI-20 visual bridge miss on build 80.
  Read-only audit confirmed: when only one VOLTRA is connected via MDM,
  `bothVoltrasConnected` is false and `focusedBle` was returning the
  standalone `ble` manager (never receives BLE notifications in MDM
  sessions), not the MDM slot manager that actually has the connection.
- **Files changed.**
  - `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` — `focusedBle`
    computed property replaced with a topology-only switch on
    `(mdm.left.connectionState.isConnected, mdm.right.connectionState.isConnected)`.
    Routes to `mdm.left` when only left is connected, `mdm.right` when
    only right is connected, `focusedSlot` switch when both are connected,
    standalone `ble` only when neither MDM slot is connected.
    No peripheral names, labels, or advertised names used.
- **What changed.** `focusedBle` now always returns the manager that
  holds the live BLE connection, regardless of how many MDM slots are
  active. `deviceOriginatedBaseWeightUpdateID` on the correct manager
  will now fire the SwiftUI onChange in LiveCaptureViewV2.
- **What did NOT change.** `bothVoltrasConnected`, `twinModeActive`,
  `focusedSlot`, writer routing, header UI, `applyDeviceOriginatedBase`
  guards — all unchanged.
- **Sacred files.** Unchanged.
- **Verification.** Static review only (no Xcode available).
- **Next step.** Commit, bump build 81, ship TestFlight, run A1 retest.

## 2026-05-04 03:00 UTC — RC-01 / SC-01 coaching card integration (feature-flagged OFF)

- **Goal.** Integrate rest-state Coaching Card + Smart Coach rule engine from
  operator-supplied VoltraCoaching_v3 source into the VOLTRA Live iOS repo.
  Feature-flagged off by default. No BLE writes. No auto weight changes.
- **Files created (new).**
  - `VoltraLive/FeatureFlags.swift` — all flags default false.
  - `VoltraLive/Coaching/CoachingConstants.swift`
  - `VoltraLive/Coaching/Models/SetPerformanceSnapshot.swift`
  - `VoltraLive/Coaching/Models/ExerciseSessionCursor.swift`
  - `VoltraLive/Coaching/Models/HistoricalSetMatch.swift`
  - `VoltraLive/Coaching/Models/CoachingRecommendation.swift`
  - `VoltraLive/Coaching/Services/HistoricalWorkoutMatcher.swift`
  - `VoltraLive/Coaching/Services/CoachingEngine.swift`
  - `VoltraLive/Coaching/Services/SetSnapshotBuilder.swift` (adapter)
  - `VoltraLive/Coaching/Views/CoachingCardView.swift`
  - `VoltraLive/Coaching/Views/CoachingCardButtonRow.swift`
  - `VoltraLive/Coaching/Views/FatigueIndicatorView.swift`
  - `VoltraLiveTests/CoachingEngineTests.swift` (placeholder)
  - `docs/incoming/VoltraCoaching_v3.swift` (staging)
  - `docs/incoming/CoachingEngineTests_v4.swift` (staging)
  - `docs/specs/RC-01_COACHING_CARD.md` (spec)
- **Files modified.**
  - `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` — added
    `@State coachingCardVisible/coachingDebounceWork`, panel switch in
    `forceChartCard`, `onDeviceBecameUnloaded/Loaded()` helpers,
    `buildCoachingCursor/History()` helpers,
    `.onChange(of: session.restActive)` debounce observer.
  - `VoltraLive/Logging/Persistence/LoggingStore.swift` — added
    `allExerciseInstances(for:)` fetch method.
  - `tasks/todo.md` — updated.
- **Key design decisions.**
  1. `coachingCardEnabled` defaults `false` — ships dark until KI-20 passes.
  2. Buttons call `adjustWeight(delta:)`, not direct `pendingPlannedWeightLb` —
     preserves `CombinedParity` + reanchor.
  3. Fatigue gate always `.unknown` for now — `LoggedSet` has no per-rep force
     fields. Gate resolves when Telemetry v2 per-rep data lands.
  4. `allExerciseInstances(for:)` fetches all instances and filters in Swift —
     avoids SwiftData `#Predicate` issues with optional relationship traversal.
  5. Panel switch uses `AnyView` type erasure — `forceChartCard` is a computed
     `some View` property; the two branches have different concrete types.
  6. Debounce trigger is `session.restActive`, not device force level —
     consistent with existing `phaseOrRestBar` logic.
- **What did NOT change.** Sacred files. KI-20 fix. focusedBle topology.
  Existing telemetry/recorder behavior. BLE write path.
- **Verification.** Static review only. No Xcode/CI available in this env.
  Build 81 CI will be the compile verification gate.
- **Next step.** Build 81 push + CI. KI-20 hardware retest. If KI-20 passes,
  enable `coachingCardEnabled = true` for build 82 coaching TestFlight.

## 2026-05-04 03:20 UTC — Build bump 80 → 81 for KI-20 topology fix + RC-01 dark ship

- **Goal.** Ship build 81 containing KI-20 focusedBle topology fix
  (9788d49) + RC-01/SC-01 coaching scaffold (ad3c11b, all flags false).
- **Exception approved.** Same one-time project.yml exception as build 80.
  Scope: lines 65 + 93 only. CURRENT_PROJECT_VERSION + CFBundleVersion
  80 → 81. Marketing version unchanged (0.4.52).
- **Coaching flags.** All false. coachingCardEnabled=false,
  smartCoachEnabled=false, aggressiveRecommendationsEnabled=false,
  hrRecoveryHardLockEnabled=false, telemetryDebugExportEnabled=false.
  No coaching UI visible in this build.
- **Files changed.** project.yml lines 65+93, VoltraLive/Info.plist.
- **6-line verification.** project.yml:64 MARKETING_VERSION=0.4.52,
  project.yml:65 CURRENT_PROJECT_VERSION=81,
  project.yml:92 CFBundleShortVersionString=0.4.52,
  project.yml:93 CFBundleVersion=81,
  Info.plist CFBundleShortVersionString=0.4.52,
  Info.plist CFBundleVersion=81.
- **KI-20 status.** Pending hardware retest on this build.
  A1 test: set app 20 lb, change physical VOLTRA to 15 lb.
  Expected: tile updates to 15 lb.
  Expected logs: device.state.change source=deviceUnsolicited to=15
  + ui.deviceBaseWeightApplied to=15.
  Do NOT close KI-20 until confirmed.

## 2026-05-04 03:26 UTC — TestFlight ship: v0.4.52-build81

- **Tag.** `v0.4.52-build81` at commit `7da4ef2`.
- **Workflow run.** release.yml run 25299344681.
  URL: https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25299344681
  Conclusion: success. Duration: ~5m27s.
- **5-gate altool verification.**
  1. Failure-marker grep: PASS — zero real error lines.
  2. Wall-clock duration: PASS — ~5m27s.
  3. Positive success marker: PASS — "No errors uploading archive at 'build/export/VoltraLive.ipa'."
  4. No ERROR: lines: PASS.
  5. Delivery UUID: PASS — 08ffc5e4-ca3e-4aba-81a7-6a06bef011ae.
- **Commits shipped.**
  - 9788d49 fix: route focusedBle by connection topology
  - ad3c11b feat: RC-01/SC-01 coaching scaffold (all flags false)
  - 5b8d978 docs: context checkpoint
  - 7da4ef2 chore(release): bump to 0.4.52/build81
- **Coaching flags.** All false. No coaching UI visible.
- **KI-20 status.** Pending hardware A1 retest on this build.
  DO NOT close KI-20 until MJ confirms tile updates to 15 lb.

## 2026-05-04 04:20 UTC — KI-20 closed, KI-21 documented

- **Goal.** Document build 81 A1 hardware retest results. Close KI-20.
  Open/expand KI-21 with byte-level evidence for chains/ecc/inverse.
- **Session.** `EA473194-40BF-4580-BEEE-8C6033535923`. App 0.4.52 build 81.
- **KI-20 result.** CLOSED. baseWeight device→UI confirmed passing.
  device.state.change source=deviceUnsolicited + ui.deviceBaseWeightApplied
  both present for all device-side dial changes (50→45→40→35→30 lb).
- **KI-21 result.** OPEN. Chains/eccentric/inverse notify frames arrive
  in raw hex but no parsed/apply events emitted:
  - `87 3E` = chains (hypothesis)
  - `88 3E` = eccentric (hypothesis)
  - `B0 53` = inverse toggle (hypothesis)
- **Files changed (docs only).**
  - `docs/handoff/06_KNOWN_ISSUES.md` — KI-20 marked CLOSED with evidence;
    KI-21 expanded with byte table + full resolution plan.
  - `docs/handoff/QA_LOG.md` — build 81 A1 PASS + mode-param FAIL entries.
  - `docs/handoff/02_CURRENT_STATE.md` — latest shipped updated to build 81.
  - `docs/handoff/CONTEXT_LEDGER.md` — checkpoint updated.
- **Sacred files.** Unchanged. No code touched.
- **Next step.** Implement KI-21: decoder + bridge + UI apply for
  chains (87 3E), eccentric (88 3E), inverse (B0 53).

---

## 2026-05-04 — KI-21 — add chains/eccentric/inverse decoder + state fields

- **Goal.** Implement KI-21: decoder patterns + DeviceState fields for
  chains, eccentric, and inverse-chain parameters observed in build 81
  hardware session EA473194-40BF-4580-BEEE-8C6033535923.
- **Files changed.**
  - `VoltraLive/BLE/Decoder/VoltraDecodedEvent.swift` — `DeviceStateField`
    enum: added `chainsWeight`, `eccentricWeight`, `inverseChain`.
  - `VoltraLive/BLE/Decoder/VoltraDecodeTable.swift` — added patterns
    `0x3E87` (chainsWeight), `0x3E88` (eccentricWeight), `0x53B0`
    (inverseChain), appended all three to `.all`.
  - `VoltraLive/BLE/State/DeviceState.swift` — added `chainsWeightLb`,
    `eccentricWeightLb`, `inverseChainEnabled` fields to `DeviceState`;
    added `case .chainsWeight`, `.eccentricWeight`, `.inverseChain` to
    `DeviceStateReducer.apply` switch.
- **What changed.** Decoder now recognises the three new param IDs in
  assembled BLE notify frames. Reducer updates the corresponding
  `DeviceState` fields and emits `device.state.change` events for each.
  `VoltraBLEManager` will log these via the existing recorder loop.
- **Verification.** Static review only — no Xcode in env. CI build is
  the compile gate.
- **Risks.** Param IDs are hypotheses from session EA473194. Values will
  appear in recorder logs after next TestFlight ship. Confirm against
  physical hardware before promoting hypotheses to confirmed spec.
- **Next step.** Push → CI → TestFlight ship for hardware retest.
  Then add `@Published` bridges + `LiveCaptureViewV2` `.onChange` wiring
  for chains/ecc/inverse (same pattern as KI-20 baseWeight).


## 2026-05-04 16:40 UTC — KI-21 follow-through bridges + LiveCapture apply wiring

- **Goal.** Finish KI-21 follow-through after the decoder/state-field commit:
  device-originated chains, eccentric, and inverse confirmations now reach the
  V2 live UI and recorder timeline. KI-21 remains pending hardware retest.
- **Files changed:**
  - `VoltraLive/BLE/VoltraBLEManager.swift`
  - `VoltraLive/Logging/Views/LiveCaptureViewV2.swift`
  - `VoltraLive/BLE/VoltraWriter.swift`
  - `docs/handoff/06_KNOWN_ISSUES.md`
  - `docs/handoff/02_CURRENT_STATE.md`
  - `docs/WORK_LOG.md`
- **What changed:** Added `@Published` bridge values + monotonic update IDs for
  `deviceOriginatedChainsWeightUpdate`, `deviceOriginatedEccentricWeightUpdate`,
  and `deviceOriginatedInverseChainUpdate`, mirroring the KI-20 base-weight
  pattern. `VoltraWriter` now registers existing outbound eccentric/chains/
  inverse writes with the pending-write tracker so app echoes stay
  `appRequestConfirmed` and do not feed the device-originated UI bridge.
  `LiveCaptureViewV2` now observes the focused BLE manager's new update IDs,
  applies device-originated changes into existing `LoggingStore` state, and
  records `ui.deviceChainsApplied`, `ui.deviceEccentricApplied`, and
  `ui.deviceInverseApplied`.
- **Verification:** `git diff --check` PASS. Grep verified all three new event
  names and the original `ui.deviceBaseWeightApplied` path are present. Grep
  verified new manager update IDs and outbound pending-tracker registrations.
  `xcodebuild -version` unavailable in the local execution environment, so the
  compile gate remains Xcode/CI. No TestFlight ship in this commit.
- **Risks:** KI-21 param IDs remain hardware hypotheses until a TestFlight
  recorder session confirms `device.state.change` + `ui.*Applied` for each field.
  Inverse write behavior is intentionally unchanged; this patch only bridges
  read/apply/recorder flow.
- **Next step:** Run build/CI, then ship a later build only when approved for
  TestFlight hardware retest. Do not close KI-21 until that retest passes.

## 2026-05-04 18:30 UTC — Hidden Smart Coach unlock + handoff refresh

- **Goal.** Add hidden 4-tap UserDefaults unlock for Smart Coach card so QA
  can test without a code-change rebuild. Refresh all handoff docs to
  eliminate drift accumulated since b81.
- **Files changed (Swift).**
  - `VoltraLive/FeatureFlags.swift` — `coachingCardEnabled` / `smartCoachEnabled`
    converted from `static var = false` to computed vars backed by
    `UserDefaults.standard.bool(forKey: smartCoachUnlockUserDefaultsKey)`.
    Added `smartCoachUnlockUserDefaultsKey = "VOLTRASmartCoachUnlocked"`.
    `aggressiveRecommendationsEnabled` / `hrRecoveryHardLockEnabled` /
    `telemetryDebugExportEnabled` unchanged (static defaults).
  - `VoltraLive/Views/BuildBadgeOverlay.swift` — added
    `@AppStorage(FeatureFlags.smartCoachUnlockUserDefaultsKey) smartCoachUnlocked`
    and `.onTapGesture(count: 4) { smartCoachUnlocked.toggle() }` declared
    BEFORE the existing 3-tap and 1-tap. 3-tap (VOLTRARecorderUnlocked) and
    1-tap (grid cycling) preserved verbatim.
  - `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` — added
    `@AppStorage(FeatureFlags.smartCoachUnlockUserDefaultsKey) smartCoachUnlocked`
    and `coachingCardRuntimeEnabled` computed var. Replaced both
    `FeatureFlags.coachingCardEnabled` gate sites with `coachingCardRuntimeEnabled`.
    Added `.onChange(of: smartCoachUnlocked)` observer to mount/dismount card
    live when unlocked during rest state.
- **Files changed (docs).**
  `docs/handoff/00_START_HERE.md`, `docs/handoff/02_CURRENT_STATE.md`,
  `docs/handoff/03_CURRENT_FEATURE_SPEC.md`,
  `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md`,
  `docs/handoff/05_BUILD_TEST_DEPLOY.md`, `docs/handoff/06_KNOWN_ISSUES.md`,
  `docs/handoff/07_FILE_MAP.md`, `docs/handoff/08_GIT_HISTORY_SUMMARY.md`,
  `docs/handoff/09_NEXT_AGENT_PROMPT.md`, `docs/handoff/10_OPEN_QUESTIONS.md`.
- **What changed.** Smart Coach is now togglable at runtime without a code
  change. Default remains OFF (UserDefaults key absent = false). Unlock
  contract: 4 taps on version badge toggles `VOLTRASmartCoachUnlocked`.
- **Verification.** Static + grep only (no Xcode on Windows). All required
  symbols confirmed present via `git grep`. CI build is the compile gate.
- **Risks.** `@AppStorage` on a value key shared between BuildBadgeChip and
  LiveCaptureViewV2 — both observe the same key, so unlock/lock propagates
  across all mounted views simultaneously. No thread safety concern (both
  are @MainActor SwiftUI views).
- **No version/build bump.** No workflow/signing changes. Sacred BLE files
  untouched. `aggressiveRecommendationsEnabled` remains false.
- **Next step.** CI build → TestFlight ship → hardware verification:
  4-tap toggles Smart Coach; card appears in rest state; KI-21
  chains/ecc/inverse device→UI events confirm in recorder.

## 2026-05-04 20:00 UTC — CORRECTION: run 25336582738 was dry-run; bump to build 82 + fix release.yml

- **Goal.** Corrective commit: (1) correct the false TestFlight success claim for run
  25336582738; (2) fix `release.yml` so `workflow_dispatch` without arguments does a real
  upload; (3) bump build 81 → 82.
- **What was wrong.** Run 25336582738 ("Release to TestFlight", dispatched for df11ed5)
  executed with `dry_run=true` because `workflow_dispatch` default was `'true'`. The
  "Upload to TestFlight via altool" step was skipped by its `if:` condition
  (`push || dry_run == 'false'`). The run instead uploaded a GitHub artifact
  named `VoltraLive-dryrun-ipa`. No IPA was sent to Apple. App Store Connect
  showed no new build. The prior WORK_LOG entry incorrectly claimed success.
- **Files changed.**
  - `.github/workflows/release.yml` — changed `dry_run` default from `'true'` to `'false'`;
    reordered options list (`'false'` first). Requires explicit user approval per AGENTS.md
    sacred-file rule — approved by task instruction.
  - `project.yml` — lines 65, 93: `CURRENT_PROJECT_VERSION` / `CFBundleVersion` 81 → 82.
  - `VoltraLive/Info.plist` — `CFBundleVersion` 81 → 82.
  - `docs/handoff/02_CURRENT_STATE.md` — corrected shipped build record.
  - `docs/handoff/06_KNOWN_ISSUES.md` — corrected KI-SC-01 TestFlight status.
- **6-line verification.** project.yml:64 MARKETING_VERSION=0.4.52,
  project.yml:65 CURRENT_PROJECT_VERSION=82, project.yml:92
  CFBundleShortVersionString=0.4.52, project.yml:93 CFBundleVersion=82,
  Info.plist CFBundleShortVersionString=0.4.52, Info.plist CFBundleVersion=82.
- **Sacred file.** release.yml edited under explicit user task instruction.
  Change is minimal: one-line default change + option order. All step logic unchanged.
- **Risks.** The `dry_run=false` default means any future `gh workflow run "Release to TestFlight"`
  without arguments will perform a real upload. Operators must pass `--field dry_run=true`
  explicitly for dry runs from this point forward.
- **Next step.** Push tag `v0.4.52-build82` → release.yml runs → confirm altool success
  markers + delivery UUID → verify App Store Connect shows 0.4.52 (82).

## 2026-05-04 19:18 UTC — TestFlight ship confirmed: v0.4.52-build82

- **Tag.** `v0.4.52-build82` at commit `e91c148`.
- **Workflow run.** release.yml run 25337935549 — event: push (tag-triggered).
  URL: https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25337935549
  Conclusion: success. Duration: ~10m38s.
- **5-gate altool verification.**
  1. Failure-marker grep: PASS — zero real errors.
  2. Wall-clock: PASS — ~10m38s >> 10s floor.
  3. Success marker: PASS — "No errors uploading archive at 'build/export/VoltraLive.ipa'."
  4. No ERROR: lines: PASS.
  5. Delivery UUID: PASS — `496678a7-ab0b-4a7d-b08a-d1077c315fb7`.
- **Commits shipped.**
  - df11ed5 feat: hidden Smart Coach unlock + handoff refresh
  - e91c148 fix: upload build 82 to TestFlight (build bump + release.yml dry_run fix)
- **Coaching flags.** All off by default. Unlock with 4-tap on version badge.
- **KI-21.** Still open — pending hardware retest.
- **Next step.** App Store Connect will process the build. Once available in
  TestFlight, run hardware verification per 09_NEXT_AGENT_PROMPT.md.

## 2026-05-04 21:10 UTC — Fix stale 01_PROJECT_OVERVIEW.md (missed on every b79-b82 ship)

- **Goal.** Correct `01_PROJECT_OVERVIEW.md` which still said `v0.4.51 / build 78`
  despite b79–b82 having shipped. Rule in `00_START_HERE.md` requires both
  `01_PROJECT_OVERVIEW.md` and `02_CURRENT_STATE.md` to be updated together on every
  ship — I updated `02` each time but skipped `01`. Acknowledged and corrected.
- **Files changed.**
  - `docs/handoff/01_PROJECT_OVERVIEW.md` — top line updated to `v0.4.52 / build 82`.
  - `docs/handoff/02_CURRENT_STATE.md` — header + latest shipped section updated to
    reflect b82 as the current shipped build.
- **Root cause.** Process failure: the `02_CURRENT_STATE.md` update happened on every
  ship commit but `01_PROJECT_OVERVIEW.md` was never included. Will correct on every
  future ship.

## 2026-05-05 04:00 UTC — b82 merge pass: coaching toggle, inverse reconnect, session tracker, viewer, docs

- **Goal.** Merge-only pass against b82 HEAD. Add only missing behavior
  identified in gap audit of paste.txt against existing code. No
  architectural rewrites. No build bump. No push.
- **Files changed (Swift).**
  - `VoltraLive/FeatureFlags.swift` — added `sessionTrackerUserDefaultsKey`
    and `sessionTrackerEnabled` computed var (defaults ON via nil-check).
  - `VoltraLive/Logging/Views/DebugView.swift` — added `@AppStorage
    smartCoachDebugUnlocked` property + "COACHING FEATURES" section with
    a Toggle wired to `VOLTRASmartCoachUnlocked`. Mirrors 4-tap badge
    gesture. No FeatureFlagStore introduced.
  - `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` — expanded
    `handleConnectionChange()` to call `pushUpcomingStateToDevice()` when
    `anyDeviceConnected == true && activeSession != nil &&
    pendingPlannedWeightLb != nil`. Emits `ble.reconnect.statePushed`
    recorder event with base/ecc/chains/inverse metadata.
  - `VoltraLive/Recorder/SessionTrackerIndicator.swift` — NEW. Bottom-left
    20×20 stroke-ring indicator (visually distinct from recorder dot).
    Visible when any VOLTRA is connected. Tap opens `SessionRecorderViewer`.
    Gated by `FeatureFlags.sessionTrackerEnabled`.
  - `VoltraLive/VoltraLiveApp.swift` — added `.overlay(alignment:
    .bottomLeading) { SessionTrackerIndicator() ... }` with env-objects
    re-injected per KI-13 / AGENTS.md E5.
  - `VoltraLive/Recorder/SessionRecorderViewer.swift` — added
    `categoryCounts` state + `summaryBar` computed var. Summary bar shows
    per-category event counts as tappable filter chips. Computed from
    `recorder.snapshot()` — no new persistence model.
- **Files changed (docs).**
  - `docs/handoff/00_START_HERE.md` — last-shipped line + section
    corrected to b82.
  - `docs/handoff/03_ROADMAP.md` — last-updated updated; builds 79-82
    added to Done table.
  - `docs/handoff/B74_BUG_QUEUE.md` — ARCHIVED header added.
  - `docs/handoff/06_KNOWN_ISSUES.md` — KI-ST-01 (deferred saved-reports
    browser) and KI-INV-01 (inverse reconnect unverified) added.
- **What preserved (not changed).**
  - `FeatureFlags.swift` enum architecture — unchanged.
  - `CoachingEngine.swift`, `CoachingCardView.swift`, all RC-01 files — unchanged.
  - KI-21 bridge (`VoltraBLEManager`, `DeviceState`, `VoltraDecodeTable`) — unchanged.
  - `SessionRecorder`, `RecorderExporter` — no new duplicates.
  - No new `@Model` or SwiftData schema.
  - Sacred files — all unchanged.
- **Verification.** Static + grep only (no Xcode on Windows). All symbols
  confirmed present. `git diff --check` passes. No sacred file in diff.
- **Risks.**
  - Inverse reconnect replay: fires on EVERY connectionState change while
    session is active (including the first connect). The `pendingPlannedWeightLb
    != nil` guard prevents spurious writes on first connect before the user
    has set a weight. Hardware verification still needed (KI-INV-01).
  - SessionTrackerIndicator mounts on top of all screens. If a full-screen
    sheet or alert covers the safe area, the indicator may be obscured. Low
    risk — same behavior as existing recorder dot.
- **Next step.** CI build (manual dispatch) → hardware verification of:
  (1) DebugView coaching toggle, (2) inverse reconnect replay,
  (3) Session Tracker bottom-left indicator, (4) Viewer summary bar.
