# B67 Bug Queue — Collected, NOT Yet Fixed

**Status:** OPEN — collecting bugs. Per user rule: "I have more bugs to report. Let's wait until the very end. until I say done to start trying to fix them because some other suggestions might override some of these decisions."

**Branch:** `feat/ui-v4-2-claude` (continuing post-b66 ship)
**Last shipped:** v0.4.39 / build 66 @ commit `085ba4a` (TestFlight, 5-gate altool ✅)
**Next build target:** b67

**Workflow (HARD RULE):** Commit & push this file after every batch of Q&A so context survives sandbox resets. Include all open questions inside this file so they don't get lost.

---

## Cross-Cutting Flags (apply across multiple bugs)

These interlock and should be resolved together when user says **done**:

1. **Bug 01 ↔ Bug 03 collapse.** Bug 03 introduces `L`/`R`/`⋏`/`●●` pills in the header that auto-pair on tap. This makes Bug 01's "auto-scan on launch" + "Demo Mode fallback" questions **moot** — there's no waiting state to fall back from. Cold launch lands directly on `WorkoutSelectionScreen`; the pill-tap is the auto-pair affordance. Bug 01 reduces to a pure route flip.

2. **Bug 03 ↔ existing `VoltraAssignmentPanel`.** The V4.2 panel already ships `L / R / ⋏ / SS` pills inside it (visible in IMG_2415). Bug 03 wants the same component family in the header — which would duplicate. User's paste block says "do not duplicate" for `SS`. Working assumption: **on `WorkoutSelectionScreen` the header pill row replaces the panel's pill row entirely** (panel keeps reference dot row + `SS` only). Need confirmation in batch review.

3. **Bug 03 deliberately reverts the breathing-ring active indicator** (V4.2 delta shipped in b66 with explicit user sign-off). New rule: dark fill = inactive, **static mint fill = active**. No ring, no pulse, no breathing.

4. **Bugs 04 + 05 are the same underlying problem** — a dead-end pairing subflow (`DualConnectView` → `DualCaptureView`) that should not exist. Pairing must move entirely to silent-scan-on-pill-tap on `WorkoutSelectionScreen`. See full Bug 04+05 entry below.

5. **Pairing model fundamentally changes from "select-then-connect" to "tap = connect".** IMG_2413 evidence: `right` device at −58 dBm is selected (✓) but Left/Right rows still read "Idle" — the current flow requires a *separate* `Auto-Pair Both` / `Connect Right` button tap *after* selecting the row. The new spec eliminates that two-step: row tap **is** the pair action. This is a real behavior change, not just rewording.

6. **`LOAD` / `UNLOAD` buttons relocate.** Currently they live on `DualCaptureView` as a screen-level pair of buttons. New spec: load state is bound to the **weight-number tap on `LiveWorkoutScreen`** (per existing V3 behavior). Need to verify V3 actually still has this binding intact and document it explicitly.

7. **Bug 06 cross-cut:** All live workouts (single, merged, superset) route through ONE live screen — mode is a prop, not a separate view. `DualCaptureView` deletion is already covered in Bug 04+05; Bug 06 adds the single-screen rule + extracts `VoltraUnitHeader` as a shared component used on `WorkoutSelectionScreen` AND `LiveWorkoutScreen`.

8. **⚠ BROKEN — sine-wave FORCE trace status (resolved by Bug 10).** Earlier read of the b66 V3 live target image claimed the sine-wave force curve was already rendering correctly. **That reading was wrong.** Bug 10 (filed) confirms `LiveWorkoutScreen` is rendering raw-sample polyline with phase coloring, not parametric per-rep sine waves. Git history search shows the live force chart has *never* been parametric sine since at least v0.4.5 — only Demo Mode (`fef3d6d`) uses `sin(progress * .pi)` and that's data synthesis, not render. F1 telemetry-rule skip from b66 is **NOT** validated and is subsumed by Bug 10. The b66 page-badge / chrome / VL1 strip readings from `targets/06-live-workout-screen-target.jpeg` remain valid — only the FORCE-card waveform claim was wrong. See Bug 10 Q10.1 for the implementation blocker (where does the 'earlier working' geometry actually live?).

9. **Footer Bug 02 confirmed on multiple screens.** The verbose b58-era watermark `v0.4.39 (66) · b66: V4.2 ASSIGN TO VOLTRA panel + superset switcher (HARDWARE-QA-PENDING)` plus `ContentView` page-badge bleed-through appears on `WorkoutSelectionScreen` (Bug 02), `LiveWorkoutScreen` (Bug 06 target), AND `ExerciseDetailScreen` (Bug 07 image). Single fix to `buildBadgeOverlay` removal + `pageBadge` two-sided footer covers all screens.

10. **Bug 07 reveals THREE screens currently embed the cluttered `VL1 ⌘ | L R | SS` header**, not two:
    - `WorkoutSelectionScreen` (Bug 03)
    - `LiveWorkoutScreen` (Bug 06)
    - `ExerciseDetailScreen` — the pre-workout exercise history/detail view (Bug 07 image, e.g., `Back Extension` with progress chart + LAST SESSION + MODE/MODIFIERS)
    The shared `VoltraUnitHeader` extraction must cover all three mount points. None of the prior bugs called out `ExerciseDetailScreen`.

11. **Bug 07 is a hard dependency for Bug 04+05 ship.** Once `DualConnectView` is deleted (Bug 04+05), the only working pairing path today is gone. If Bug 07's silent-scan-from-anywhere fix doesn't ship in the same release, **mid-flow pairing is completely broken**. Bug 04+05 and Bug 07 must land in the same b67 build.

12. **Critical disambiguation:** The screen in the Bug 07 image (`Back Extension`) is **`ExerciseDetailScreen` (pre-workout history/detail)**, NOT `LiveWorkoutScreen` (active session). They both embed the unit header but are different views. The fix is the same (shared `PairingCoordinator` binding) but the doc must distinguish them — they likely have different state ownership and different sheet presentation contexts.

---

## Bug 01 — Cold launch lands on ConnectView instead of WorkoutSelectionScreen

**Evidence:**
- Wrong: `docs/handoff/screenshots/bugs/01-wrong-launch-screen.jpeg` (IMG_2419 — full page WorkoutSelectionScreen reached only because Demo Mode is on; `ContentView` page-badge confirms route gate)
- Correct: `docs/handoff/screenshots/targets/01-correct-launch-screen.jpeg` (IMG_2418 — what cold launch should show)

**Root cause (already analyzed):**
- `VoltraLive/Views/ContentView.swift` is a route gate.
- `shouldShowHome` returns true if any of: `ble.connectionState.isConnected`, `demo.isActive`, `mdm.left.connectionState.isConnected`, `mdm.right.connectionState.isConnected`.
- IMG_2418 reached only because Demo Mode is on (header reads "DEMO MODE — nothing is recorded · build 66").
- Spec wants launch direct into `LoggingHomeView`. Pairing happens via header pills (per Bug 03), not via a separate Connect screen.

**Decision after Bug 03 collapse:**
- Pure route flip: `ContentView` should always show `LoggingHomeView` on cold launch.
- No auto-scan on launch (pill-tap handles it per Bug 03).
- No fallback timer (no waiting state to fall back from).
- ConnectView likely deletable entirely once Bug 04 confirms there are no manual Connect entry points to preserve.

**Open questions for batch:**
- Q1.1: Confirm pure route flip — `ContentView` always renders `LoggingHomeView`?
- Q1.2: Is `DualConnectView` (the sheet that pops from `MultiDeviceManager.scanRequestedSubject`) still needed as the "scanning…" UI when user taps `L` or `R` pill? Or does auto-pair happen silently with toast feedback?

---

## Bug 02 — Footer watermark cluttered

**Evidence:**
- Wrong: `docs/handoff/screenshots/bugs/02-footer-clutter.jpeg` (IMG_2419 — bottom of page reads `v0.4.39 (66) · b66: V4.2 ASSIGN TO VOLTRA panel + superset switcher (HARDWARE-QA-PENDING)` plus `ContentView` page-badge bleeding through)

**Spec:**
- Left side: page name (e.g., `WorkoutSelectionScreen` or `LoggingHomeView`)
- Right side: version only (e.g., `v0.4.39 (66)`)
- Nothing else. Kill the verbose b58-era build-description string.

**Implementation plan (queued, not done):**
- Delete `buildBadgeOverlay()` watermark (legacy, leaks the build description string).
- Modify the existing b66 `.pageBadge("...")` ViewModifier to render two-sided footer: page name left, version-only right.
- Same opacity / mint-faint color as current page-badge.

**Files likely to touch:**
- `VoltraLive/Views/PageBadgeOverlay.swift`
- Wherever `buildBadgeOverlay()` is defined (search needed)

**Open questions for batch:**
- Q2.1: Should footer also disappear in `DEMO MODE` so we don't clutter that already-busy state? Or always visible?

---

## Bug 03 — WorkoutSelectionScreen header is cluttered; consolidate to single minimal pill row

**Evidence:**
- Target: `docs/handoff/screenshots/targets/03-header-row-target.jpeg` (IMG_2423 — tight crop of four pills `L | R | ⋏ | ●●`, dark inactive / mint active)
- Wrong (header detail): `docs/handoff/screenshots/bugs/03-header-clutter.jpeg` (IMG_2415 — current cluttered header `VOLTRA / Live / ● LIVE / Left ● Right ● / gear` + duplicate `L R ⋏ ●● SS` panel row below)
- Wrong (full page): `docs/handoff/screenshots/bugs/03-header-clutter-fullpage.jpeg` (IMG_2419 — full WorkoutSelectionScreen with cluttered header)

**Note on screenshot IDs:** The user's paste-block citation IDs were swapped (same kind of swap as Bug 01's paste). Files saved based on what they actually depict, not the IDs in the message. Prose was correct.

### Spec — what to BUILD

Single horizontal row of **4 pills** (likely; `SS` exclusion pending confirmation), at the top of `WorkoutSelectionScreen`, above "Pick a day to start logging." Same size / radius / visual language as the existing `VoltraAssignmentPanel` pills.

| # | Pill | Glyph | States | Behavior |
|---|------|-------|--------|----------|
| 1 | `L` | letter L | dark = unpaired/inactive · **static mint fill = paired+active** · no ring/pulse | Tap → auto-pair nearest in-range Voltra to Left slot. Tap again → activate. Tap when already active → deactivate. |
| 2 | `R` | letter R | (same as L) | (same as L, Right slot) |
| 3 | `⋏` | fork/join glyph | (same fill rules) | Tap with both L+R paired → enable MERGE. Mutually exclusive with SS. |
| 4 | `●●` | watch / heart glyph (icon-only, no text) | dark/outlined = HK disconnected · **blinking mint = connecting** · solid mint = streaming HR | Replaces old `LIVE` pill. Tap → opens HealthKit/HR source settings. |
| 5? | `SS` | "SS" text | (same fill rules) | **Only if confirmed in batch.** Tap with both L+R paired → enable superset; mutually exclusive with MERGE. Currently TARGET image shows 4 pills, not 5. |

### Spec — what to DELETE

- ❌ `VOLTRA` wordmark (also fixes the wrap-to-two-lines bug visible in IMG_2415: "VOLT / RA")
- ❌ `Live` subtitle
- ❌ `● LIVE` standalone pill (functionality moves to `●●` HR pill)
- ❌ `Left ● Right ●` standalone status pill (functionality moves to `L`/`R` pill fills)
- ❌ Settings gear icon (relocate — see Q3.3)
- ❌ Duplicate `L R ⋏ ●● SS` reference row inside `VoltraAssignmentPanel` on this screen (panel keeps reference dot row + `SS` only, per cross-cutting flag #2)
- ❌ Breathing-ring animation on active pills (cross-cutting flag #3 — deliberate revert of V4.2 delta)

### `●●` HR pill — full state spec

- **Icon:** small watch / HR glyph. Use existing repo icon if available; otherwise add `assets/icons/hr.svg`. Likely candidates: `heart.fill` SF Symbol, or `applewatch` SF Symbol.
- **Three states (drive from `HRSourceConnectionState` enum):**
  - `disconnected` → dark/outlined fill, dim glyph
  - `connecting` → blinking mint fill (1Hz fade in/out)
  - `connected` → solid mint fill, dark glyph (inverted)
- **No text inside pill.**
- **Tap → opens HealthKit source picker / permissions sheet.**

### Files likely to touch

- `VoltraLive/Views/WorkoutSelectionScreen.swift` (or wherever the cluttered header lives — needs grep on launch — possibly part of `LoggingHomeView`)
- `VoltraLive/Views/VoltraAssignmentPanel.swift` — drop duplicate pill row when shown on this screen
- `VoltraLive/Views/PageBadgeOverlay.swift` — N/A here, but coordinated with Bug 02
- HK service: search for `HealthKitService` / `HRManager` / `HKHealthStore` usage; expose `enum HRSourceConnectionState { case disconnected, connecting, connected }`
- Components to delete: any `LiveStatusPill`, `LeftRightStatusPill` views

### Doc updates (Karpathy rule, same commit as code)

- `docs/handoff/06_KNOWN_ISSUES.md` — add B67-01, B67-02, B67-03 entries
- `docs/handoff/entities/voltra_assignment_panel.md` — clarify panel drops its pill row on `WorkoutSelectionScreen`
- `docs/handoff/entities/hr_indicator.md` — **NEW** — three-state HR pill spec
- `docs/handoff/design/tokens.md` — add `icon.hr` if new asset needed
- `docs/handoff/07_FILE_MAP.md` — register new HR component, remove deleted (`LiveStatusPill`, `LeftRightStatusPill`)
- `docs/WORK_LOG.md` — append b67 entry on commit

### Open questions for batch (re-ask user when queue closes)

- **Q3.1 (header chrome):** What's allowed above "Pick a day to start logging"?
  - (a) **Just the 4 pills** (recommended, matches IMG_2423 literally) — no VOLTRA mark, no Live label, no logo, no gear; system status bar (time/battery) stays as iOS provides
  - (b) 4 pills + tiny ⚡ glyph in top-left corner
  - (c) 4 pills + DEMO MODE banner only when demo is on
- **Q3.2 (SS pill):** Does SS belong in the header row?
  - (a) **No** (recommended — IMG_2423 shows 4 pills, matches "do not duplicate" note)
  - (b) Yes — make it 5 pills, accept duplication with panel
- **Q3.3 (gear icon relocation):** Where does Settings go?
  - (a) Tap `●●` HR pill → HealthKit settings only; other settings reachable from elsewhere in app
  - (b) Long-press anywhere on header row → settings sheet
  - (c) Add settings entry to "Open live dashboard" footer bar (small overflow on right)
  - (d) Keep gear, just smaller / corner

---

## Bug 04 + Bug 05 — Delete `DualConnectView` and `DualCaptureView`; pairing happens only via the top-of-home pill row

**One-sentence summary:** There is an entire dead-end pairing subflow (`DualConnectView` → `DualCaptureView`) with manual `Auto-Pair Both` / `Connect Left` / `Connect Right` / `Independent` / `Combined` / `LOAD` / `UNLOAD` buttons that should not exist. Delete it. Pairing happens silently and automatically from the top-of-home pill row on `WorkoutSelectionScreen`.

### Evidence

| File | Page-badge | What it shows |
|------|------------|---------------|
| `bugs/04-dual-connect-idle.jpeg` (IMG_2421) | `DualConnectView` | "Pair 2 Voltras" header, Left/Right both Idle, `Auto-Pair Both` mint button, `Connect Left` / `Connect Right` numbered buttons, Discovered list with `right · −66 dBm`, scanning |
| `bugs/04-dual-connect-selected.jpeg` (IMG_2413) | `DualConnectView` | Same screen, `right · −58 dBm` row checked (✓), "Selected: right" sub-line, Left/Right **still Idle** — proves selection alone does not pair |
| `bugs/04-dual-connect-connected.jpeg` (IMG_2414) | `DualConnectView` | Connected state — Left + Right both mint-dot Connected with red `Disconnect` links, `Open Dual Capture` mint CTA at bottom |
| `bugs/04-dual-capture-view.jpeg` (IMG_2422) | `DualCaptureView` | `Independent` / `Combined` toggle, Left/Right Force/Reps/Phase status cards, `LOAD` / `UNLOAD` mint buttons |

**Note on screenshot ID swap:** The user's paste-block citation IDs `[1][2][3][4]` were reshuffled (third occurrence of this pattern after Bugs 01 and 03). Files saved by what they actually depict, not by ID.

### What's wrong (combined)

- `DualConnectView` exists at all (every aspect of it is wrong)
- `DualCaptureView` exists at all
- `Auto-Pair Both` button — wrong: tap should be implicit in pill tap
- `Connect Left` / `Connect Right` numbered buttons — wrong: "Connect" is never a user verb
- `Independent` / `Combined` toggle on `DualCaptureView` — wrong: superset/merge mode lives on `⋏` and `SS` pills only
- `LOAD` / `UNLOAD` standalone buttons — wrong: load state binds to weight-number tap on `LiveWorkoutScreen`
- `Open Dual Capture` CTA — wrong: there is no "capture mode" navigation
- `Back` button to a parent that contains this view — wrong: there is no parent route to this view because this view shouldn't exist
- Two-step "select row → tap Connect button" pairing model — wrong: tap = connect

### What's right (required flow)

There is **one and only one** pairing path. It lives on `WorkoutSelectionScreen`:

1. User taps the **`L` pill** (or `R` pill) in the top control row from Bug 03.
2. App **silently scans** Bluetooth for in-range Voltras (~4s window).
3. **Exactly one candidate** → auto-pair to that slot. Pill transitions to paired-active (static mint fill, inverted glyph). No dialog.
4. **Multiple candidates** → bottom sheet `PairVoltraSheet` slides up with a list of `DiscoveredDeviceRow`s (device name + signal strength + Wi-Fi bars, salvaged from `DualConnectView`'s discovered-list visual). Tap row → pair → sheet dismisses → pill paired-active. No `Connect` button on sheet — tap is the connect.
5. **Zero candidates** after scan → inline toast: *"No Voltra found. Make sure it's powered on and nearby."* Pill returns to unpaired. No navigation.

Swipe-down on the bottom sheet cancels.

### Files / components to DELETE

- `DualConnectView.swift`
- `DualCaptureView.swift`
- All `NavigationLink` / route entries pointing to either
- `Auto-Pair Both` button component
- `Connect Left` / `Connect Right` button components
- `Independent` / `Combined` toggle (capture-view variant only — pill-row mode toggles stay)
- `LOAD` / `UNLOAD` buttons (capture-view variant only — `LiveWorkoutScreen` weight-tap binding stays)
- `Open Dual Capture` CTA

### Files / components to KEEP and REUSE

- **Background BLE scan logic** — whatever currently powers `Discovered: right · −58 dBm` keeps existing; just route to pill-tap trigger instead of `DualConnectView`.
- **Discovered device row visual** — extract into reusable `DiscoveredDeviceRow` (name + signal strength + Wi-Fi bars), use inside `PairVoltraSheet`.

### New components to ADD

- `PairVoltraSheet` — bottom sheet, only shown when 2+ candidates found. Title: `Pair Voltra — LEFT` (or `RIGHT`). Content: scrollable list of `DiscoveredDeviceRow`. No buttons. Footer per Bug 02 spec.
- `DiscoveredDeviceRow` — reusable row component (name + dBm + bars).

### Files likely to touch (search needed at fix time)

- `VoltraLive/BLE/Dual/MultiDeviceManager.swift` — re-route `requestPairScan(for:)` from sheet-presentation to silent auto-pair + sheet-only-on-multi-candidate
- `VoltraLive/BLE/Dual/MultiDeviceManager+V42.swift` — `scanRequestedSubject` consumer changes
- `VoltraLive/Views/ContentView.swift` — drop any route to `DualConnectView`
- `VoltraLive/Views/LoggingHomeView.swift` (or `WorkoutSelectionScreen.swift`) — pill-row tap handlers wire to silent-scan flow
- Wherever `DualConnectView` is currently invoked (host sheet presentation that consumes `scanRequestedSubject`) — replace with silent-scan + conditional `PairVoltraSheet`

### Doc updates (Karpathy rule, same commit as code)

- `docs/handoff/06_KNOWN_ISSUES.md` — add B67-04 (manual Connect buttons deleted), B67-05 (DualConnectView + DualCaptureView deleted)
- `docs/handoff/03_CURRENT_FEATURE_SPEC.md` — remove all references to `DualConnectView`, `DualCaptureView`, `Auto-Pair Both`, `Independent/Combined` toggle outside pill row, manual Connect buttons. Add silent-scan / bottom-sheet pairing flow.
- `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` — append:
  - **D-B67-1:** Pairing has exactly one entry point: `L`/`R` pills on top control row of `WorkoutSelectionScreen`.
  - **D-B67-2:** "Connect" is never a user-facing verb. Tap = connect.
  - **D-B67-3:** `DualConnectView` and `DualCaptureView` are deleted; their logic absorbs into pill row + `LiveWorkoutScreen`.
  - **D-B67-4:** Pairing state lives in `units` store; no separate "dual capture mode" state exists.
- `docs/handoff/entities/pairing_flow.md` — **NEW** — silent-scan + `PairVoltraSheet` + `DiscoveredDeviceRow` spec
- `docs/handoff/07_FILE_MAP.md` — remove `DualConnectView`, `DualCaptureView`; add `PairVoltraSheet`, `DiscoveredDeviceRow`
- `docs/WORK_LOG.md` — append b67 entry on commit

### Verification

1. Screen recording: cold launch → tap `L` with one Voltra in range → pill paired-active, no screen transition
2. Screen recording: tap `R` with two Voltras in range → bottom sheet → tap row → sheet dismisses → pill paired-active
3. Screen recording: tap `L` with zero Voltras → toast → pill returns to unpaired
4. `git log -- DualConnectView.swift DualCaptureView.swift` shows both files deleted
5. `grep -rni "connect left\|connect right\|auto-pair both\|open dual capture\|independent\|combined" VoltraLive/Views/` returns zero matches
6. `grep -rni "\bload\b\|\bunload\b" VoltraLive/Views/` returns matches **only** in `LiveWorkoutScreen` weight-tap binding context

### Open questions for batch (re-ask user when queue closes)

- **Q4.1 (silent-scan timing):** What's the right scan window before showing the "no Voltra found" toast?
  - (a) **4 seconds** (recommended — long enough to discover but not feel laggy)
  - (b) 2 seconds (snappier; risks missing slow advertisers)
  - (c) 8 seconds (more reliable; feels slow)
  - (d) Indefinite scan with a "scanning…" shimmer on the pill until found or user taps to cancel
- **Q4.2 (single-candidate auto-pair confirmation):** When exactly one Voltra is found and we silently pair it, do we need any user-visible confirmation?
  - (a) **None — pill simply transitions to paired-active** (recommended; matches "no dialog" rule)
  - (b) Brief mint-flash on the pill as feedback (subtle scale + color pulse over ~250ms)
  - (c) Toast: *"Paired with [device name]"*
- **Q4.3 (multi-candidate sheet — sort order):** When the bottom sheet appears with 2+ devices, what order?
  - (a) **Strongest signal first** (recommended)
  - (b) Alphabetical by name
  - (c) Most-recently-paired first (requires persistence)
- **Q4.4 (already-paired-elsewhere edge case):** If user taps `L` while a candidate is already paired to `R`, what happens?
  - (a) **Filter that device out of the discovered list** (recommended — prevents foot-gun)
  - (b) Show device but disabled with "Paired to Right" label
  - (c) Allow re-pair to L; auto-unpair from R
- **Q4.5 (reconnect on app foreground):** When app comes back to foreground after being backgrounded with a paired session, do we silently reconnect?
  - (a) **Yes, silently — pill goes blink-mint while reconnecting, then solid-mint** (recommended)
  - (b) No — user must tap pill to re-establish
- **Q4.6 (LOAD/UNLOAD verification — internal action item, not for user):** Verify that `LiveWorkoutScreen` (V3 single-screen) actually has the weight-number tap → load/unload binding intact. If missing, raise as separate bug.

---

## Bug 06 — One live screen for all modes; extract `VoltraUnitHeader` as shared component

**One-sentence summary:** All live workouts (single, merged, superset) must render through ONE `LiveWorkoutScreen`. Mode is a prop, not a separate view. The cluttered `VL1 ⌘ | L R | SS` reference row + duplicate active row at the top of the live screen must be replaced with the same `VoltraUnitHeader` component used on `WorkoutSelectionScreen` (Bug 03).

### Evidence

| File | Page-badge | What it shows |
|------|------------|---------------|
| `bugs/04-dual-capture-view.jpeg` (IMG_2422 — reused from Bug 04+05) | `DualCaptureView` | Legacy two-unit live screen with `Independent`/`Combined` toggle + `LOAD`/`UNLOAD` standalone buttons — the WRONG state |
| `targets/06-live-workout-screen-target.jpeg` (image.jpeg) | (cut off; bottom shows `ContentView` bleed) | The TARGET V3-style live screen — canonical UI for ALL modes |
| `targets/03-header-row-target.jpeg` (IMG_2423 — reused from Bug 03) | n/a (crop) | The shared pill-row header that must replace the current cluttered top of `LiveWorkoutScreen` |

**Note on missing IMG_2425:** The user's paste block referenced `IMG_2425.jpeg` as the WRONG state but it didn't attach. Reusing `bugs/04-dual-capture-view.jpeg` (IMG_2422) since it's the same legacy `DualCaptureView` already captured in Bug 04+05.

### What the V3 target image shows (deconstruction of `targets/06-live-workout-screen-target.jpeg`)

From top to bottom:
1. **DEMO MODE banner** — system feedback, kept regardless
2. **Cluttered top row (TO BE REPLACED with `VoltraUnitHeader`)** — `VL1 ⌘ | L R | SS` reference row + duplicate active row showing `L` mint-filled, `R` dim, `SS` dim. Same pattern Bug 03 kills on `WorkoutSelectionScreen`.
3. **`< End` button + green `V3` badge** — keep
4. **HR row:** red dot + `— bpm` pill + `— kcal` pill — keep (live telemetry from HR pill binding)
5. **Exercise name:** `Back Extension · Set 1` — keep
6. **`RETURN` label + amber progress bar + `SET 1`** — keep
7. **`WEIGHT` card:** `25 lb` + `UNLOADED` pill + `−5 −1 +1 +5` increment row — keep; tap weight number toggles LOAD/UNLOAD (this is where load/unload binding lives, per Bug 04+05 cross-cut)
8. **ECC sub-card:** `ECC 38` value + `+52% on lower` annotation — keep
9. **Nested-row tabs:** `ECC` (active green outline) `│ CHAIN │ INV CHAIN │ DROP` — keep
10. **ECC value row:** `ECC 13 lb` + `−5 −1 +1 +5` increment row — keep
11. **`REPS` card:** `8` — keep
12. **`TOTAL VOLUME` card:** `0 lb` — keep
13. **`⊕ Added plates` button + `○ Pulley` button** — keep
14. **`FORCE · 30 S` card:** `52 lb` + force trace visible — ⚠ **DISPUTED per cross-cutting flag #8 / Bug 09 incoming**: earlier read claimed sine-wave geometry was already correct; user reports it is not. Hold judgment until Bug 09 is logged.
15. **Footer (TO BE FIXED per Bug 02):** verbose b58-era watermark + `ContentView` page-badge bleed-through

### What's right (required behavior)

- **Single `LiveWorkoutScreen` file. One code path for all modes.**
- **Mode is a prop, not a separate screen:**
  - **Single:** the screen as shown in the target image
  - **Merged:** same screen + `TWIN` badge next to weight number + summed weight total + pulley greyed. No top strip. (Restates Rule Two from foolproof doc.)
  - **Superset:** same screen + V1-style horizontal exercise-switcher strip injected ABOVE the V3 chrome, BELOW the `VoltraUnitHeader`. Tapping inactive segment slides to other unit's state. Per-unit rest/idle runs in background on inactive segment.
- **`VoltraUnitHeader`** at the top:
  - Same shared component used on `WorkoutSelectionScreen` (Bug 03)
  - Pills: `L`, `R`, `⋏`/MERGE, `●●`/HR
  - **No `SS` pill on `LiveWorkoutScreen`** — SS toggle lives only in `ASSIGN TO VOLTRA` panel on `WorkoutSelectionScreen`; on the live screen, superset is already active and the V1 switcher strip is the affordance
  - `HR ●●` pill is a **connection toggle**; the existing `— bpm` + `— kcal` row below stays as live telemetry pills (different role, both bound to same HK source)
- **Footer per Bug 02:** left = `LiveWorkoutScreen`, right = `vX.Y.Z (build)`. Nothing else.

### Interaction invariants on `LiveWorkoutScreen`

- Tap `L` or `R` in header pill row → switches active unit, OR pairs new Voltra mid-session via silent-scan + `PairVoltraSheet` (Bug 04+05 flow)
- Tap `⋏` with both L+R paired → toggles MERGE (mutually exclusive with superset)
- Tap `●●` HR pill → opens HK source settings (same as `WorkoutSelectionScreen`)
- Tap weight number on WEIGHT card → toggles UNLOADED/LOADED (this is the `LOAD/UNLOAD` binding that Bug 04+05 said must exist; **this image confirms it does** — see `UNLOADED` pill next to `25 lb`)
- No navigation to a separate `DualCaptureView` or pairing screen from any live workflow

### Files / components to DELETE (mostly already in Bug 04+05)

- `DualCaptureView.swift` — already in Bug 04+05
- The `VL1 ⌘ | L R | SS` compact status strip + duplicate active row currently at top of `LiveWorkoutScreen` — replace with `VoltraUnitHeader`
- Any `Independent`/`Combined` toggle on live screens — already in Bug 04+05
- Any `LOAD`/`UNLOAD` standalone buttons (outside weight-number tap binding) — already in Bug 04+05

### Files to CREATE / EXTRACT

- `VoltraLive/Views/Components/VoltraUnitHeader.swift` — single shared header component. Props: `activeUnitState`, `mergeState`, `hrConnectionState`, `pillSet: HeaderPillSet` enum to control whether `SS` is included (yes on `WorkoutSelectionScreen`, no on `LiveWorkoutScreen`). No SUPERSET toggle exposed on the live-screen variant.
- Possibly rename existing live-screen file to `LiveWorkoutScreen.swift` if it isn't already named that. Verify at fix time.

### Files likely to touch (search needed at fix time)

- `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` — likely the current live screen; may need rename
- `VoltraLive/Views/LoggingHomeView.swift` — currently ships the cluttered top row
- Any `MergedView` / `DualWorkoutView` / `CombinedView` if they exist as separate files — delete and route through `LiveWorkoutScreen` with mode prop
- `VoltraLive/Views/VoltraAssignmentPanel.swift` — may be the source of the `VL1 ⌘ | L R | SS` reference row that needs replacement
- New `VoltraLive/Views/Components/VoltraUnitHeader.swift`

### Doc updates (Karpathy rule, same commit as code)

- `docs/handoff/06_KNOWN_ISSUES.md` — add B67-06 with the three referenced screenshots
- `docs/handoff/03_CURRENT_FEATURE_SPEC.md`:
  - Remove any reference to `DualCaptureView` or any two-unit-specific live screen
  - Add: "All live workouts render through `LiveWorkoutScreen`. Mode (single / merged / superset) is a prop on the screen, not a separate view."
  - Add: "`VoltraUnitHeader` is the shared top-of-screen component used on any screen showing Voltra unit state. `pillSet` prop controls whether `SS` is included."
- `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` — append:
  - **D-B67-5:** `DualCaptureView` is deprecated across all versions. (Already implied by Bug 04+05; restated for completeness.)
  - **D-B67-6:** One live screen. No unit-count branching. Mode is a prop, not a screen.
  - **D-B67-7:** `VoltraUnitHeader` is a shared component; never duplicate inline. Used on `WorkoutSelectionScreen` (with `SS`) and `LiveWorkoutScreen` (without `SS`).
- `docs/handoff/entities/live_workout_screen.md` — **NEW** (or update if present) — single-path live screen + merge-mode diff + superset-mode strip + shared header
- `docs/handoff/entities/voltra_unit_header.md` — **NEW** — shared header spec, pill set prop, three-state HR pill, pairing-tap behavior
- `docs/handoff/07_FILE_MAP.md` — remove `DualCaptureView`; add `VoltraUnitHeader`, `LiveWorkoutScreen` (if renamed)
- `docs/WORK_LOG.md` — append b67 entry on commit

### Verification

1. Cold launch → `LEG DAY` with one Voltra paired → lands on V3 live screen with `VoltraUnitHeader` at top. Screen recording.
2. Both L+R paired + MERGE active → same V3 live screen + `TWIN` badge next to weight + summed weight + pulley greyed. NO Independent/Combined toggle. NO LOAD/UNLOAD standalone buttons. Screen recording.
3. Both L+R paired + SUPERSET active → same V3 live screen + V1 switcher strip injected above V3 chrome. Tap inactive segment → slides to other unit. Screen recording.
4. `git log -- DualCaptureView.swift` shows file deleted.
5. `grep -rni "DualCaptureView\|Independent\|Combined" VoltraLive/Views/` returns zero matches (outside design-doc references).
6. `grep -rn "VoltraUnitHeader" VoltraLive/Views/` shows component used on both `WorkoutSelectionScreen` and `LiveWorkoutScreen` (single shared component, not inline-duplicated).
7. Live screen footer shows `LiveWorkoutScreen` (left) + `v0.4.40 (67)` (right) per Bug 02, no verbose watermark.

### Open questions for batch (re-ask when queue closes)

- **Q6.1 (HR pill vs HR telemetry row):** The `VoltraUnitHeader` has a `●●` HR connection-toggle pill. The live screen ALSO shows a separate `● — bpm — kcal` telemetry row beneath it. Is that intentional dual surfacing (toggle in header, live values in chrome), or should one collapse into the other?
  - (a) **Keep both — toggle in header, live values in chrome** (recommended; they have different roles)
  - (b) Drop telemetry row; show `bpm`/`kcal` inside the `●●` pill expanded (e.g., `120 bpm`)
  - (c) Drop `●●` pill from `VoltraUnitHeader` on `LiveWorkoutScreen`; let the existing telemetry row carry connection state
- **Q6.2 (`pillSet` API):** Should `VoltraUnitHeader` take a typed `pillSet` enum or just individual booleans (`showSS: Bool`)?
  - (a) **Enum** `case workoutSelection // L,R,⋏,●●,SS` / `case liveWorkout // L,R,⋏,●●` (recommended; declares intent)
  - (b) Booleans — more flexible if future screens need other combos
- **Q6.3 (mode-as-prop API):** How is mode passed to `LiveWorkoutScreen`?
  - (a) **Single enum `WorkoutMode { case single, merged, superset(strip: SupersetStripState) }`** (recommended; exhaustive and type-safe)
  - (b) Three booleans (`isMerged`, `isSuperset`, `mergedTwin`)
  - (c) Read directly from `MultiDeviceManager.workoutMode` on every render (no prop)
- **Q6.4 (existing live-screen file naming):** Current file is likely `LiveCaptureViewV2.swift`. Rename to `LiveWorkoutScreen.swift` to match the new naming, or keep filename and just refactor contents?
  - (a) **Rename** to `LiveWorkoutScreen.swift` for clarity (recommended; matches doc updates)
  - (b) Keep current filename; only refactor contents (lower-risk diff)

---

## Bug 07 — Pairing from `ExerciseDetailScreen` (and any non-home screen with the unit header) fails silently; must use shared `PairingCoordinator`

**One-sentence summary:** When a user is on `ExerciseDetailScreen` (the pre-workout exercise history/detail view, e.g., `Back Extension`) and taps the unpaired `R` pill in the embedded `VL1 ⌘ | L R | SS` header, the pill shows a red/amber outlined error state but no BLE pairing actually fires — the Voltra is in range and blinking but never connects. The only working pairing path today is the legacy `DualConnectView`, which Bug 04+05 deletes — so without Bug 07's fix, **mid-flow pairing breaks entirely** in b67.

### Evidence

| File | Page-badge | What it shows |
|------|------------|---------------|
| `bugs/07-mid-workout-pair-fails.jpeg` (IMG_2429) | (cut off; visible bleed in footer) | `ExerciseDetailScreen` for `Back Extension`. Top has cluttered `VL1 ⌘ \| L R \| SS` header with `L` mint-filled (active+paired) and **`R` rendered with a thin red/amber outline** — the failed-pair error state. Below: `< Back` button, `Back Extension` title, `LAST SESSION 25 lb × 10 5 mo. ago / SET 1 25 lb · 10 reps`, full PROGRESS chart (Top Weight, −19 lb · 30d, Apr–Oct), MODE row (Weight active / Band / Damper), MODIFIERS row partial (Eccentric On / Chains / Inverse). Bug 02 footer watermark also present. |
| `bugs/07-legacy-dualconnect-fallback.jpeg` (IMG_2421 — reused from Bug 04+05) | `DualConnectView` | The dead-end legacy screen mid-workout pairing currently falls back to. Already in deletion list (Bug 04+05). |

**Note on screenshot duplication:** The user attached `IMG_2429.jpeg` and `IMG_2430.jpeg` for Bug 07, but they are byte-near-identical — both show the same `ExerciseDetailScreen` failed-pair state. The user's prose described `IMG_2430` as the legacy `DualConnectView` fallback, but it isn't — IMG_2430 is a duplicate of IMG_2429. Reused `bugs/04-dual-connect-idle.jpeg` (IMG_2421 from Bug 04+05) for the legacy-fallback evidence slot since it depicts the actual `DualConnectView` and the prose intent is satisfied.

**New surface this bug exposes:** `ExerciseDetailScreen` was not previously on the list of screens that embed the unit header. Bugs 03 and 06 only addressed `WorkoutSelectionScreen` and `LiveWorkoutScreen`. The `VoltraUnitHeader` extraction must cover this third mount point.

### What's wrong

- The `R` pill on the `ExerciseDetailScreen` unit-header is visually interactive (renders a red/amber outline when tapped or in error state), but the tap does **not** trigger BLE silent-scan + auto-pair.
- No user feedback: no toast, no bottom sheet, no state change. The pill just sits in the error-outline style.
- Voltra hardware is ready (light blinking, in range, advertising) — the app's pairing path simply isn't wired from this surface.
- Today the only path that works is navigating back to `DualConnectView`, which Bug 04+05 deletes. **After b67 lands without Bug 07's fix, mid-flow pairing has zero working paths.**

### What's right (required behavior)

`VoltraUnitHeader` is the **single entry point** for pairing from EVERY screen it appears on:

- `WorkoutSelectionScreen` (Bug 03)
- `LiveWorkoutScreen` (Bug 06)
- `ExerciseDetailScreen` (Bug 07 — newly identified)
- Any future screen that embeds the header

Tapping an unpaired pill from ANY of these surfaces runs the exact same flow as from home (Bug 04+05):

1. Silent BLE scan (~4s)
2. Exactly one candidate → auto-pair, pill paired-active, no dialog, no navigation
3. Multiple candidates → `PairVoltraSheet` slides up over the current screen as a global modal. Tap row → pair → dismiss. **Stay on `ExerciseDetailScreen` / `LiveWorkoutScreen`.**
4. Zero candidates → inline toast, pill returns to unpaired
5. **Never** navigate to a full-screen pairing view. **Never** push `DualConnectView` (it's deleted anyway).

### Root cause hypotheses (to verify at fix time)

Likely one of:
- **Hypothesis A (most likely):** `VoltraUnitHeader` on `ExerciseDetailScreen` is currently rendered as a **display-only** status strip with stub or no-op tap handlers — or its tap handlers route to the now-(soon-to-be)-deleted `DualConnectView`.
- **Hypothesis B:** The BLE scan service requires a foreground scan context that was only initialized inside `DualConnectView.onAppear`, so scans never start from other surfaces.
- **Hypothesis C:** The `units` store mutation path for pairing is scoped to `WorkoutSelectionScreen` state and not reachable from deeper nav stack levels (`ExerciseDetailScreen` is presumably pushed from `WorkoutSelectionScreen` after picking a day + exercise).

Claude should:
1. Confirm which hypothesis is the actual cause.
2. Refactor so `VoltraUnitHeader` always uses the **same pairing action binding** regardless of mount point. The action calls a shared `PairingCoordinator.startPairing(slot:)` method that works from any screen.
3. Ensure `PairingCoordinator` owns the BLE scan lifecycle and presents `PairVoltraSheet` on the currently visible screen via a global modal presenter (not a per-screen `.sheet` modifier).

### Implementation requirements

- `VoltraUnitHeader` has **one** pill-tap handler, injected via environment object or a singleton coordinator. **No screen-specific re-implementations.**
- `PairingCoordinator` (new service, or extend existing `BluetoothService`/`MultiDeviceManager`) exposes:
  - `startPairing(slot: UnitSlot)` — silent scan + auto-pair-or-sheet
  - `activate(slot: UnitSlot)` — toggle active state on already-paired unit
  - `toggleMerge()` / `toggleSuperset()` with mutual exclusion
- `PairVoltraSheet` is rendered by a top-level host (app root or `SheetHost` env object), **NOT** by any individual screen. This guarantees consistent presentation regardless of where the tap originates.
- Any "blocked" scan state (BT off, permissions denied, radio busy) surfaces as a **toast on the current screen**, not a full-screen error view.
- Scan never blocks navigation: user can swipe back / dismiss / change screens during scan, scan auto-cancels.

### Files likely to touch

- `VoltraLive/Views/Components/VoltraUnitHeader.swift` — ensure tap handler uses shared coordinator (created in Bug 06)
- `VoltraLive/Services/PairingCoordinator.swift` — **NEW** — owns scan lifecycle, presents sheet (or extend `MultiDeviceManager` if simpler)
- `VoltraLive/App/VoltraLiveApp.swift` (or root view) — mount global `SheetHost` / `PairVoltraSheet` presenter
- `VoltraLive/Views/ExerciseDetailScreen.swift` (find actual file at fix time) — confirm embeds `VoltraUnitHeader` with the same binding
- `VoltraLive/Views/LiveWorkoutScreen.swift` — same
- `VoltraLive/Views/LoggingHomeView.swift` (or `WorkoutSelectionScreen.swift`) — same
- Delete any legacy routes that push `DualConnectView` from deeper screens (Bug 04+05 covers home; verify nothing in `ExerciseDetailScreen` still references it)

### Doc updates (Karpathy rule, same commit as code)

- `docs/handoff/06_KNOWN_ISSUES.md` — add B67-07 with both screenshots
- `docs/handoff/03_CURRENT_FEATURE_SPEC.md` — add: "Pairing is initiated from `VoltraUnitHeader` on any screen. `PairingCoordinator` owns scan lifecycle. `PairVoltraSheet` is presented globally by `SheetHost` — never owned by an individual screen."
- `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` — append:
  - **D-B67-8:** Pairing action on `VoltraUnitHeader` is identical across every screen it appears on; there are no screen-specific pairing paths.
  - **D-B67-9:** `PairVoltraSheet` is a global modal, not a per-screen navigation destination.
  - **D-B67-10:** Bug 04+05 (delete `DualConnectView`) and Bug 07 (shared pairing from any screen) **must ship in the same release** to avoid breaking mid-flow pairing.
- `docs/handoff/entities/pairing_flow.md` — extend (created in Bug 04+05) to document `PairingCoordinator` API, mid-flow pairing flow, sheet presentation via `SheetHost`, toast fallbacks, "pairing never navigates" rule
- `docs/handoff/entities/voltra_unit_header.md` — specify tap handler injected via `PairingCoordinator`, identical behavior from any mount point, list ALL mount points (`WorkoutSelectionScreen`, `ExerciseDetailScreen`, `LiveWorkoutScreen`)
- `docs/handoff/07_FILE_MAP.md` — register `PairingCoordinator`, `SheetHost`, `PairVoltraSheet`
- `docs/WORK_LOG.md` — append b67 entry tying Bug 07 fix to Bug 04+05 deletion

### Verification

1. Screen recording — `WorkoutSelectionScreen` with L paired, tap `R` with one Voltra in range → pill paired-active, no navigation
2. Screen recording — select `LEG DAY` → land on `ExerciseDetailScreen` with L paired, tap `R` with one Voltra in range → pill paired-active, **stay on `ExerciseDetailScreen`**
3. Screen recording — enter `LiveWorkoutScreen` (active workout) with L paired, tap `R` with **two** Voltras in range → `PairVoltraSheet` slides up over live screen → tap row → sheet dismisses → pill paired-active → **live screen state preserved** (exercise, set count, weight, force trace unchanged)
4. Screen recording — tap `R` with zero Voltras in range from `ExerciseDetailScreen` → toast "No Voltra found..." → pill returns to unpaired → no navigation
5. `grep -rni "DualConnectView" VoltraLive/` returns zero matches
6. `grep -rn "VoltraUnitHeader" VoltraLive/Views/` shows component mounted on `WorkoutSelectionScreen`, `ExerciseDetailScreen`, AND `LiveWorkoutScreen` — all using same `PairingCoordinator` binding

### Open questions for batch (re-ask when queue closes)

- **Q7.1 (sheet presentation context during active workout):** When `PairVoltraSheet` slides up over `LiveWorkoutScreen` mid-workout, what happens to in-progress telemetry (force-trace recording, rep counter)?
  - (a) **Continue uninterrupted; sheet is purely presentational** (recommended; user's mid-set data must not be lost)
  - (b) Pause telemetry while sheet is open; resume on dismiss
  - (c) Reject pair attempts during active set; only allow during rest
- **Q7.2 (red/amber outline current state):** The `R` pill in IMG_2429 has a red/amber outline. Is that an existing intentional "failed pair" visual state, or is it just the default `.errorTint` SwiftUI applied because the tap handler threw?
  - (a) **Default error tint (unintentional)** — fix removes it; pills only have dark/blink-mint/solid-mint states
  - (b) Intentional "pair failed, try again" state — keep it as a fourth pill state
  - (c) Don't know yet — verify in code at fix time
- **Q7.3 (PairingCoordinator vs extending MultiDeviceManager):** Architecture choice:
  - (a) **Extend existing `MultiDeviceManager`** with `startPairing(slot:)` (recommended; less new surface area, MDM already owns BLE state)
  - (b) New separate `PairingCoordinator` service (cleaner separation of concerns; more files to wire)
- **Q7.4 (sheet host mounting):** Where does the global `PairVoltraSheet` host live?
  - (a) **App root view** (recommended; covers every screen, including modals)
  - (b) Root navigation stack only (skips full-screen modals)
  - (c) Per-tab if app gains tabs in future

---

## Bug 08 — Duplicate unit-status rows everywhere → collapse to one shared `VoltraUnitHeader`

**Symptom:** Multiple legacy unit-status surfaces are stacked on top of each other on every screen that mounts `MultiDeviceManager` or `LiveCapture` chrome. The b66 build accidentally kept the *old* surfaces alive while *also* adding the new V4.2 pill row — so the user now sees the same `L` / `R` / `⋏` (HRV) / `●●` (HR) state rendered 2–3 times per screen.

### Evidence

| File | Screen | Duplicate surfaces visible |
|---|---|---|
| `bugs/08-duplicate-status-home.jpeg` | `WorkoutSelectionScreen` | **3 surfaces** — (a) `VOLTRA` wordmark + `LIVE` pill + `Left ● Right ●` pill row at the very top, (b) `VL1 ⌚ | L R | SS` compact strip mid-page, (c) new V4.2 active pill row (`L` / `R` / `⋏` / `●●` / `SS`) below that |
| `bugs/08-duplicate-status-live.jpeg` | `LiveWorkoutScreen` (V3 target) | **2 surfaces** — (a) `VL1 ⌚ | L R | SS` reference strip across the top, (b) new V4.2 active pill row directly underneath |
| `bugs/08-duplicate-status-detail.jpeg` | `ExerciseDetailScreen` | **2 surfaces** — (a) `VL1 ⌚ | L R | SS` reference strip, (b) new V4.2 active pill row underneath |
| `targets/08-consolidated-header.jpeg` | (target for all three) | **1 surface** — single `VoltraUnitHeader` row: `L` / `R` / `⋏` / `●●` (no `SS` per Bug 06 rule) |

### What's wrong (current b66 state)

- `WorkoutSelectionScreen` stacks **three** redundant status surfaces (Bug 03 already covers the top wordmark/`LIVE`/`Left●Right●` row deletion — Bug 08 covers the OTHER two surfaces below it).
- `LiveWorkoutScreen` stacks **two**: the `VL1 ⌚ | L R | SS` reference strip is duplicate chrome above the active pill row.
- `ExerciseDetailScreen` stacks **two**: same `VL1 ⌚ | L R | SS` strip + active pill row.
- The `VL1 ⌚ | L R | SS` strip is the SAME legacy `LiveStatusPill` / `LeftRightStatusPill` / `DeviceStatusStrip` chrome that Bug 06 already mandated extracting; it was never actually removed when the new pill row was added.
- `SS` (superset) appears in the legacy strip on all three screens; Bug 06 explicitly forbids `SS` in the new shared header (superset state is in `SupersetSwitcherBanner`, not the unit header).

### What's right (required after fix)

- Each of `WorkoutSelectionScreen`, `LiveWorkoutScreen`, `ExerciseDetailScreen` mounts **exactly one** `VoltraUnitHeader` row.
- `VoltraUnitHeader` content (locked spec):
  - `L` pill — left unit pair status (idle / pairing / paired-active)
  - `R` pill — right unit pair status (same states)
  - `⋏` pill — HRV / breath state
  - `●●` pill — HR (3-state per Bug 03: dark / blinking / solid)
  - **No `SS` pill** (per Bug 06 — superset state lives in `SupersetSwitcherBanner` only)
  - **No `VL1` device label, no `⌚` watch glyph, no `VOLTRA` wordmark, no `LIVE` text pill, no `Left ● Right ●` summary pill** — all redundant chrome.
- All three screens share the same `VoltraUnitHeader` SwiftUI view — single source of truth, no copy-paste variants.

### Implementation requirements

1. Confirm `VoltraUnitHeader.swift` exists as a shared `View` (created in Bug 06 spec). If not yet created, this bug requires creating it.
2. Delete (or `#if false` out) the following legacy surfaces wherever they are mounted:
   - `LiveStatusPill`
   - `LeftRightStatusPill`
   - `DeviceStatusStrip`
   - Any inline `HStack` rendering literal text `"VL1"` / `"VOLTRA Live"` / `"Left ● Right ●"` / `"⌚"` glyph + device label
3. On `WorkoutSelectionScreen`: also delete the top wordmark/`LIVE` pill/`Left●Right●` row that Bug 03 mandates removing — Bug 08 verifies that fix lands.
4. On `LiveWorkoutScreen` and `ExerciseDetailScreen`: replace the `VL1 ⌚ | L R | SS` strip with `VoltraUnitHeader()` mounted at the top of the screen layout.
5. `VoltraUnitHeader` reads state from the same `MultiDeviceManager` observable already used by the active pill row — the active pill row is REPLACED by `VoltraUnitHeader`, not supplemented.
6. Verify no regressions: `WorkoutVoltraPickerSheet` is already deleted (b66); confirm Bug 08 fix does not re-introduce any picker chrome.

### Lint invariant (grep gate)

After Bug 08 fix lands, the following must return **zero matches**:

```bash
grep -rni "VL1\|VOLTRA Live\|Left .* Right .*\|LiveStatusPill\|LeftRightStatusPill\|DeviceStatusStrip\|VoltraWordmark" VoltraLive/Views/
```

(Search is intentionally `Views/` only — the strings may legitimately appear in `Models/`, `Telemetry/`, or test fixtures and should not block.)

### Doc updates (with this fix)

- `docs/handoff/06_KNOWN_ISSUES.md` — close "duplicate status surfaces" entry; add lint-gate as recurring CI check.
- `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` — add ADR: "`VoltraUnitHeader` is the single canonical unit-status surface; no other view may render unit pair / HR / HRV chrome."
- `docs/WORK_LOG.md` — append-only b67 entry referencing Bugs 03/06/07/08 as the consolidated chrome cleanup.

### Verification checklist (post-b67)

1. Cold-launch → `WorkoutSelectionScreen` shows **one** `VoltraUnitHeader` row, nothing above it except the safe-area inset.
2. Tap into `LiveWorkoutScreen` → same `VoltraUnitHeader` row, no `VL1` strip above it.
3. Tap any exercise tile from `WorkoutSelectionScreen` → `ExerciseDetailScreen` shows same `VoltraUnitHeader` row, no `VL1` strip above it.
4. Toggle HK auth on/off → `●●` pill cycles dark / blinking / solid (cross-validates with Bug 03).
5. Pair only `L` unit → `L` pill goes mint-filled, `R` stays dim. Pair only `R` → mirror. Pair both → both mint-filled. (Cross-validates with Bug 04+05 and Bug 07.)
6. Run lint-gate grep above → zero matches.
7. Page badge `LiveWorkoutScreen` / `ExerciseDetailScreen` / `WorkoutSelectionScreen` visible at footer of each (cross-validates Bug 02 footer cleanup).

### Open questions (Bug 08)

- **Q8.1** Does `VoltraUnitHeader` already exist in the codebase from b66 work, or does Bug 08 fix need to *create* it? (Bug 06 spec'd it but the b66 ship may or may not have committed an actual `VoltraUnitHeader.swift` file — need to grep.)
- **Q8.2** When pairing is **active but not yet established** (mid-handshake), should the corresponding `L` or `R` pill show a third intermediate state (e.g., breathing / pulsing) or just stay dim until paired? Bug 06 sign-off reverted breathing-ring on active pills, but mid-handshake state was not explicitly addressed.
- **Q8.3** On `ExerciseDetailScreen` (pre-workout exercise history view), is the `VoltraUnitHeader` interactive (tap = pair, per Bug 07's `PairingCoordinator`), or read-only (display state only, pairing must happen on a parent screen)? Bug 07 spec implies tap-to-pair from `ExerciseDetailScreen` is required — confirm.
- **Q8.4** Does Bug 08 fix go in the same b67 release as Bugs 03/04+05/06/07, or should it be split? Recommendation: same release — they are entangled (each one re-touches the same view files) and shipping them piecemeal will cause merge conflicts.

---

## Bug 10 — Force curve on `LiveWorkoutScreen` is not a sine wave; restore earlier sine-wave geometry with log-fade history overlay

> **⚠ NUMBERING NOTE:** User paste block labeled this entry as **Bug 10**, even though the queue placeholder for the sine-wave bug was previously slot **Bug 09**. Going with the user's numbering — Bug 09 is now skipped/reserved (see Q10.5 below). The skip is explicit so future search for Bug 09 finds this note.

> **⚠ SCREENSHOT ID SWAP CONFIRMED (5th paste block in a row):** User paste block referenced `IMG_2433.jpeg` as the broken `FORCE · 30 S` panel. Verification: `IMG_2433` is actually a different `FORCE` panel — spiky polyline, peak `38.3 lb`, axis labels `43/32/21/10/0 lb`, NO `BOTTOM` dashed floor, NO `· 30 S` in title. The image matching the user's prose description ("blocky/flat-top polyline + `BOTTOM` dashed floor") is `IMG_2432`. Both saved as evidence — same bug, two different live-screen states.

### The problem in one sentence

The `FORCE` panel on `LiveWorkoutScreen` currently renders as raw sensor samples (blocky polyline / spiky polyline depending on rep activity) instead of one clean sine wave per rep with prior reps fading behind via logarithmic opacity.

### Evidence

| File | What it shows |
|---|---|
| `bugs/10-force-curve-broken-30s-panel.jpeg` (saved from `IMG_2432`) | `FORCE · 30 S` panel during/post-rep — blocky flat-top polyline, mint+orange overlapping fills, `BOTTOM` dashed floor at zero, no per-rep separation, no axis labels visible |
| `bugs/10-force-curve-broken-spiky.jpeg` (saved from `IMG_2433`) | Different `FORCE` panel state on `LiveWorkoutScreen` (`Back Extension · Set 1`, IDLE, target 10 reps, weight `25 lb`, ECC `+13`) — spiky polyline, peak `38.3 lb`, axis ticks `43/32/21/10/0 lb`, header reads `● Pull ● Return  peak 38.3 lb`, no `BOTTOM` floor, no `· 30 S` in title |

### What's wrong (per evidence)

- The curve is a polyline of raw sensor samples per phase — `ForceChartView.swift` plots `ChartPoint` per `ForceSample` with phase-colored segments. This produces a literal sample-time line, not a parametric per-rep shape.
- Eccentric vs concentric phases share the same canvas with no per-rep envelope; reps bleed into one continuous trace.
- No history overlay of prior reps with logarithmic opacity fade.
- The two screenshots show DIFFERENT axis chrome (`· 30 S` window + `BOTTOM` floor in IMG_2432 vs lb-tick axis + Pull/Return legend + peak readout in IMG_2433) — implying TWO different `Force*` views are mounted in different contexts. Need to confirm which is live on `LiveWorkoutScreen` post-Bug 06 consolidation.
- `BOTTOM` dashed floor and y-axis scaling are fine; rep geometry is the bug.

### What's right (required behavior, per user spec)

1. **Per-rep shape:** one full sine wave per rep.
   - Concentric half = rising half (0 → π/2 → π mapped to peak force)
   - Eccentric half = falling half (π → 3π/2 → 2π)
   - Peak amplitude = rep's peak force; time axis normalized per rep.
2. **History overlay:** all prior reps of the current set overlaid on the same canvas.
   - Logarithmic opacity fade: newest ≈100%, oldest ≈15%.
   - Cap at ≈8 overlay reps visible at once.
3. **ECC / CHAIN fill:**
   - ECC active → eccentric half rendered with higher fill opacity, darker shade.
   - CHAIN / INV CHAIN active → gradient mirrors or amplifies the rising half.
4. **Y-axis:** auto-fits to `peak × 1.2` with 20% headroom floor (keep current).
5. **X-axis:** `· 30 S` window stays; rep shapes laid out in time, not tiled.

### Codebase reconnaissance (already run)

Git history search results from this session, captured here so the next agent doesn't repeat the work:

```
git log --all --oneline -- "*ForceCurve*" "*force_curve*"
  59a3c05 feat(v4): KI-11 force-curve full spec — 80% line, peak dots, legend (b60-prep)
  592131f b59 v0.4.37: hotfix — route to V2 when both Voltras paired

git log --all -S "sine" --oneline -- VoltraLive/
  fef3d6d feat(demo): Demo Mode + structured trace (v0.4.6.3 / build 26)
```

Current force-curve files in tree:
- `VoltraLive/Views/ForceChartView.swift` (Swift Charts, raw sample polyline, phase-colored segments — b58/b66 mainline)
- `VoltraLive/Logging/Views/V2/ForceChartV2.swift` (V2 variant, presumably what KI-11 / 59a3c05 enhanced)

Doc: `docs/handoff/design/force_curve.md` exists (need to re-read its current contents before editing — user paste block claims it documents sine-wave geometry; current code path doesn't match that, so the doc is either out of date or aspirational).

### ⚠ Critical finding — "earlier sine-wave commit" may not exist

**The git search found no commit where the live force chart rendered as parametric sine waves.** What it found:
- `fef3d6d` (Demo Mode, build 26, v0.4.6.3) uses `sin(progress * .pi)` — but that is the **demo data synthesis** envelope (generates fake force samples for demo mode), NOT the **rendering layer**.
- `59a3c05` (KI-11) added 80% line, peak dots, legend chip on top of `ForceChartV2` — still raw-sample-polyline data path underneath.
- `ForceChartView.swift` has been a `Swift Charts` line chart over `ChartPoint` per-sample since at least v0.4.5 ("chart now spans the entire set (no 30s rolling window)") — **never** parametric per-rep.

**Implication:** The "earlier working sine-wave geometry" the user remembers may be (a) demo-mode-only synthesis confused with live render, (b) a never-shipped design from `force_curve.md`, or (c) genuinely earlier than `fef3d6d` (build 26) in a commit not captured by the `*ForceCurve*` / `*force_curve*` glob. Need user input before implementing — see Q10.1.

### Implementation requirements (once Q10.1 is resolved)

- Rendering function takes: array of per-rep `{ peakForce, eccDuration, conDuration, phase }` plus current live rep's partial samples.
- Per-rep path = `sin(t)` parametric over rep time range, scaled to peak force.
- Previous reps rendered first with log-faded opacity; current rep on top at 100%.
- ECC phase shading driven by current `ECC` / `CHAIN` / `INV CHAIN` / `DROP` state from the nested row.
- Do **NOT** change the data pipeline or sensor smoothing — only the path geometry.
- Likely files to touch:
  - `VoltraLive/Views/ForceChartView.swift` (or `ForceChartV2.swift` — depends on which is live on `LiveWorkoutScreen` post-Bug 06)
  - `docs/handoff/design/force_curve.md` (update to reflect restored geometry + new ADR)

### Verification checklist

1. Screen recording of live workout with 5+ reps showing each rep as a distinct sine shape, older reps visibly faded behind current.
2. Screenshot at rep 8 showing ≈8 overlays visible with oldest at ≈15% opacity.
3. Screenshot with ECC mode active showing eccentric half darkened/fuller.
4. `git log -p -- VoltraLive/Views/ForceChartView.swift` shows the restored sine-path function (or new `drawRep(path:phase:peak:opacityIndex:)`).
5. No regressions to y-axis auto-fit, `BOTTOM` floor, or `· 30 S` window.

### Doc updates (ship in same commit as code per Karpathy rule)

- `docs/handoff/06_KNOWN_ISSUES.md` — Bug 10 entry referencing both evidence files.
- `docs/handoff/design/force_curve.md` — update:
  - Rep geometry: sine wave per rep, concentric rising + eccentric falling
  - Overlay: ≤8 prior reps with log opacity fade
  - ECC/CHAIN shading rules
  - Reference commit SHA of restored implementation
- `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` — ADR: "Force curve rep geometry is a sine wave per rep with log-faded history overlay; flat polyline rendering of raw samples is a regression that ships disabled."
- `docs/handoff/entities/live_workout_screen.md` — reference `force_curve.md` for `FORCE · 30 S` panel spec.
- `docs/WORK_LOG.md` — append entry with restored commit SHA.

### Cross-cutting flag #8 reconciliation

Flag #8 currently reads `DISPUTED`. With Bug 10 logged, it can be flipped to `BROKEN` — the b66 V3 target image (Bug 06 evidence) does NOT in fact render proper sine waves; that earlier reading of `targets/06-live-workout-screen-target.jpeg` was incorrect. F1 telemetry-rule skip from b66 is **not** validated and is now subsumed by Bug 10. Flag #8 will be rewritten when this entry is committed.

### Open questions (Bug 10)

- **Q10.1 (BLOCKER for implementation):** Where is the "earlier working sine-wave geometry"? Three options to pick from:
  - **A.** Search tag history (`release/v0.4.3x` branch tags) for the last build where the chart was sine-shaped — I haven't gone tag-by-tag yet because git history search showed only sample-polyline implementations back to v0.4.5.
  - **B.** Reimplement from scratch following the spec in `docs/handoff/design/force_curve.md` (need to re-read that doc — it may already contain the formula).
  - **C.** User points to a specific commit SHA they remember.
  - **D.** It never actually shipped — the user is recalling Demo Mode (`fef3d6d` `sin(progress * .pi)` envelope) and conflating it with live render. In which case implementation = port the demo synthesis to a render-layer overlay.
- **Q10.2:** Which `Force*` view is mounted on `LiveWorkoutScreen` post-Bug 06? `ForceChartView` or `ForceChartV2`? Bug 06 spec said "one live screen"; need to confirm which chart it uses.
- **Q10.3:** Two evidence screenshots show two different chart chromes. Which is the canonical post-Bug 06 chart? The `FORCE · 30 S` + `BOTTOM` floor variant (IMG_2432) or the `● Pull ● Return  peak 38.3 lb` + axis ticks variant (IMG_2433)? Both must be reconciled to one chart per Bug 06.
- **Q10.4:** Per-rep sine — should the current in-progress rep (incomplete) be rendered partially as a growing sine arc, or held at zero until the rep completes and then drawn? Smoother UX = partial arc; cleaner code = post-rep only.
- **Q10.5 (numbering):** Going forward, is this Bug 10 (user's labeling) or Bug 09 (queue's prior placeholder)? I went with **Bug 10** here. If user prefers Bug 09, easy renumber — just swap the section header. The next bug from the user's tease is **Bug 11** (3-digit weight overlap) which assumes Bug 10 numbering stuck.
- **Q10.6:** Bug 02 footer-clutter reproduces in IMG_2433 (`v0.4.39 (66) · b66: V4.2 ASSIGN TO VOLTRA panel + superset switcher (HARDWARE-QA-PENDING)` overlapping the `Eccentric / Band / Pause` modifier chip row). Already covered by Bug 02 cross-cutting flag #9; logging here as additional evidence.

---

## Bug 11 — (PLACEHOLDER, awaiting screenshot)

**User tease:** "3-digit weight number overlaps the icon / increment buttons at high weights."

**Note:** P1-1 in b66 work log claims a "3-digit weight + TWIN badge overlap fix" already shipped. Bug 11 may be a regression of that fix on a *different* surface (the `UPCOMING SET` panel weight cell vs the live in-set weight cell), or it may be the same surface re-broken.

**Action:** User to send (a) screenshot of the live workout screen at a 3-digit weight (100, 225, etc.) showing the overlap, (b) one-sentence on whether the overlap is on `UPCOMING SET` panel or in-set live row → I'll produce the Bug 11 entry. Target solution: dynamic font scaling, `minFontScale ≈ 0.6`, right-edge fade truncation below the floor.

---

## Verification (applies once batch is fixed)

Required screenshots after b67 build:
1. Cold launch → `WorkoutSelectionScreen` directly (Bug 01)
2. Header contains **only one row** of 4–5 pills matching IMG_2423 (Bug 03)
3. `VOLTRA` wordmark, `Live` text, `LIVE` pill, `Left ● Right ●` pill, gear icon, and duplicate sub-row are **all gone** (Bug 03)
4. `●●` HR pill cycles through dark → blinking → solid as HK auth toggled (Bug 03)
5. Footer = page-name (left) + version (right), nothing else (Bug 02)
6. No "Connect" / "Auto-Pair Both" / "Idle" buttons remaining anywhere (Bug 04, when received)
