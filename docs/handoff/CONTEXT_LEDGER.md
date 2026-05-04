# Context Ledger — Compact Decisions Log

> Supplement to `04_DECISIONS_AND_CONSTRAINTS.md`. This file records
> decisions made in Perplexity sessions (not Claude/Computer sessions)
> and any context that exists ONLY in chat history and not yet in code.
> Append new entries at the bottom. Never delete existing entries.

---

## 2026-04-28 — Cost-awareness convention established

- Every medium-or-heavier action must be flagged inline as
  lite / medium / heavy / very heavy with a one-line cost callout.
- Heavy research tasks are delegated to Perplexity model council.
  Agent drafts a self-contained prompt at `docs/handoff/COUNCIL_*_PROMPT.md`
  for the user to run. Agent acts on the result.
- Only run heavy work directly on Computer when user says
  "do it yourself."

---

## 2026-04-28 — One-feature-per-build rule established

- Each TestFlight build has exactly one `VOLTRAFeatureLabel`.
- User can test each fix in isolation and give one-word feedback.
- Exception: user can say "batch" to override for a single build.

---

## 2026-04-28 — Chain-first routing principle

- Whenever `mdm.hasAnySupersetChainEntry == true` (chain.count ≥ 1,
  both Voltras connected), all write fan-out targets
  `mdm.supersetActiveSlot` only, bypassing `workoutMode` entirely.
- Implemented in `WriterRouter.apply` and `MultiDeviceManager.slotsForWorkoutMode`.

---

## 2026-04-28 — Combined-mode even-weight invariant

- In `.combined` mode, `pendingPlannedWeightLb` must always be an
  even integer.
- Round DOWN on mode-switch entry (35 → 34, never 36).
- ±2 lb small nudger, ±6 lb large nudger.
- Drop-cascade step = 6 lb in combined, 5 lb elsewhere.

---

## 2026-04-28 — SWAP no longer auto-LOADs

- When SWAP fires, the incoming side receives `weight=0` (unload).
- The user must manually tap LOAD after grabbing the cable.
- Rationale: prevents "device already loaded itself" surprise.

---

## 2026-04-28 — V2 LiveCaptureView gate

- V2 renders ONLY when: single Voltra paired, no chain entries
  (`mdm.supersetChain.isEmpty`), user opted in via `@AppStorage`.
- Any dual-Voltra pairing OR any chain entry silently falls back to V1.

---

## 2026-04-28 — HealthKit entitlement fix (b49)

- iOS 17+ rejects HK auth if embedded entitlements don't match
  what the provisioning profile granted.
- Fix: all three HK entitlement keys must be declared in
  `VoltraLive.entitlements`:
  - `com.apple.developer.healthkit = true`
  - `com.apple.developer.healthkit.access = <array/>`
  - `com.apple.developer.healthkit.background-delivery = true`

---

## 2026-04-29 — Unified flow: WorkoutMode auto-derived

- `LoggingHomeView.commitStart()` auto-derives `workoutMode` from
  paired-device count. User never picks a mode manually.
- 1 paired → singleLeft or singleRight.
- 2 paired → independent (NOT combined by default).
- Combined is opt-in via "Merge" button on ExerciseDetailView.

---

## 2026-05-01 — B74 bug queue opened

- Last shipped: v0.4.46 / build 73.
- B74 items: F1 (auto-connect by name), F2 (Mirror mode), F3
  (Merge/Mirror semantic split), F4 (V2 weight truncation), F5
  (merge minus-weight left-favored), F6 (isolate tap broken),
  F7 (misc polish), F8 (HR dot redesign), F11 (Session Recorder).
- F1 PR exists on `fix/b74-f1-lr-name-autoconnect`.
- F8 code exists on `feat/b74-f8-watch-presence-indicator`.
- F11 spec exists at `docs/handoff/SESSION_RECORDER_SPEC.md`.

---

## 2026-05-02 — Session Recorder spec approved

- Full spec at `docs/handoff/SESSION_RECORDER_SPEC.md`.
- Local-only, AI-readable, 10,000-event FIFO ring buffer.
- Hidden behind triple-tap on build-badge chip.
- No network, no analytics, no per-screen buttons.
- PII redaction: BLE peripheral names and exercise names → UUIDs.
- Top implementation priority after chain-centric fix.

---

## 2026-05-03 — Chain-centric + inverse-chains bugs identified (this session)

**Chain-centric (`combined` mode) chains-overlay routing bug:**
- When `workoutMode == .combined`, `WriterRouter.apply` was splitting
  base weight evenly but NOT splitting `upcomingChainsLb`.
- Only one Voltra received the chains command.
- **Required fix:** Split `upcomingChainsLb / 2` (rounded to nearest
  2 lb) across both sides in combined mode, same as base weight.

**Inverse-chains routing bug:**
- The chains-overlay toggle sent the same positive-value chains
  payload for both normal and inverse (assist) mode.
- Firmware expects a negative value (or inversion flag) for assist.
- **Required fix:**
  - Add `isInverseChains: Bool = false` to `VoltraDeviceState`
    (additive, no migration).
  - In `LoggingStore` write path, if `isInverseChains == true`, send
    `-upcomingChainsLb` as the chains payload.
  - Add toggle in `ExerciseDetailView` when chains overlay is active.

**Status:** Fix was committed to `feat/ui-v4-2-claude` in the same
commit as this ledger update (2026-05-03 23:40 CDT). No TestFlight
ship — user wants local verification first.

---

## 2026-05-03 — Coaching card spec locked

- Full spec captured in `docs/handoff/09_NEXT_AGENT_PROMPT.md`
  (the COACHING CARD section).
- Implementation priority: P4 (after chain fix + Session Recorder).
- Phase 1: historical anchor only (Rules 0+1), no fatigue dot.
- Phase 2: add Rules 2-5 (delta + fatigue gating).
- Phase 3: live force/power drop-off (dot goes live).
- User confirmed: "Let's write the exact spec, logic, and everything
  that I may need to give to the coding model."

---

## 2026-05-03 — No TestFlight ship until user says so

- User statement (verbatim): *"I don't want to ship anything to
  test flight yet, but do make the updates to patch the chain
  centric and inverse chains to work correctly."*
- Chain-centric + inverse-chains fix is committed.
- All other pending items (Session Recorder, B74 queue, Coaching
  card) are staged but NOT shipped.

---

### Context health: good (checkpoint updated)

---

## CHECKPOINT UPDATE — 2026-05-04 05:00 UTC — KI-21 decoder implemented

- **Branch:** `feat/ui-v4-2-claude`
- **HEAD before this commit:** `278865e`
- **Working tree:** clean after commit

### What changed

KI-21 decoder + state scaffold implemented. No sacred files touched.
No BLE write path changed. No UI bridge wired yet.

Files modified:
- `VoltraLive/BLE/Decoder/VoltraDecodedEvent.swift` — 3 new enum cases
- `VoltraLive/BLE/Decoder/VoltraDecodeTable.swift` — 3 new patterns + .all entries
- `VoltraLive/BLE/State/DeviceState.swift` — 3 new fields + 3 reducer cases

### KI-21 current status

Decoder + state implemented. `device.state.change` will emit for
chains/ecc/inverse on next hardware test. UI bridge NOT YET WIRED —
`VoltraBLEManager` @Published bridges and `LiveCaptureViewV2`
`.onChange` observers still needed (same pattern as KI-20).

### Next exact action

1. Push → CI → verify compile green.
2. Bump build 82, ship TestFlight.
3. Hardware retest: change chains/ecc/inverse on physical VOLTRA,
   confirm `device.state.change` events appear in session recorder.
4. If events appear: add @Published bridges + LiveCaptureViewV2
   .onChange wiring for chains/ecc/inverse. Then build 83.
5. If events do NOT appear: param IDs are wrong — re-examine raw hex.

### Context health: good

*Last updated: 2026-05-04 00:14 CDT*
