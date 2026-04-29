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

8. **Sine-wave FORCE trace is live.** The b66 V3 live screen (target image) already renders the proper sine-wave force curve in the `FORCE · 30 S` card. Validates F1 telemetry-rule skip from b66 — no additional work needed here.

9. **Footer Bug 02 confirmed on multiple screens.** The verbose b58-era watermark `v0.4.39 (66) · b66: V4.2 ASSIGN TO VOLTRA panel + superset switcher (HARDWARE-QA-PENDING)` plus `ContentView` page-badge bleed-through appears on BOTH `WorkoutSelectionScreen` (Bug 02) AND `LiveWorkoutScreen` (visible at bottom of Bug 06 target image). Single fix to `buildBadgeOverlay` removal + `pageBadge` two-sided footer covers all screens.

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
14. **`FORCE · 30 S` card:** `52 lb` + **sine-wave force trace already rendering** — keep (validates F1 telemetry skip)
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

## Bug 07 — (PLACEHOLDER, awaiting screenshot)

**User tease:** "Pairing a second Voltra mid-workout only blinks the light but doesn't actually connect."

**Action:** User to send screenshot or screen-recording description of the live workout screen where they tapped an unpaired `R` (or `L`) from inside an active session and it failed to pair (Voltra in range, blinking, but no connection). One-sentence description of what happened → I'll produce the Bug 07 entry.

---

## Verification (applies once batch is fixed)

Required screenshots after b67 build:
1. Cold launch → `WorkoutSelectionScreen` directly (Bug 01)
2. Header contains **only one row** of 4–5 pills matching IMG_2423 (Bug 03)
3. `VOLTRA` wordmark, `Live` text, `LIVE` pill, `Left ● Right ●` pill, gear icon, and duplicate sub-row are **all gone** (Bug 03)
4. `●●` HR pill cycles through dark → blinking → solid as HK auth toggled (Bug 03)
5. Footer = page-name (left) + version (right), nothing else (Bug 02)
6. No "Connect" / "Auto-Pair Both" / "Idle" buttons remaining anywhere (Bug 04, when received)
