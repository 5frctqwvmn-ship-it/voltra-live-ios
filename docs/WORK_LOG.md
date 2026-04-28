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
- **What changed:** Created the durable handoff doc structure mandated by the
  user's "durable context rule". Backfilled state from session memory and
  chat: build 25→29 history, drop-set regression, HR snapshot bug, missing
  active-calories bug, dual-Voltra spec (3-button connect, Independent +
  Combined modes, LOAD/UNLOAD payloads, watchdog), superset spec
  (deferred to build 31), workout-creation Group dropdown, warmup phase,
  CloudKit re-enablement procedure, signing/secrets (names only),
  3-place version bump rule, ≤3-component Apple version rule.
  Reconciled `AGENTS.md` "READ-ONLY" claim with current reality: control
  writes through `VoltraWriter` are explicitly approved (April 2026).
- **Verification:** No code changes; docs only. Working tree review:
  all 11 handoff files plus WORK_LOG plus AGENTS.md reconciliation.
- **Risks:** None to runtime. Risk that I missed a fact from a prior
  session — if so, future sessions should add it to the right handoff doc
  and log it here.
- **Next step:** Resume build 30 starting with the drop-set regression
  investigation. Suspect file `VoltraLive/Session/DropBoundary.swift`;
  cross-reference `SetSuggestionEngine.swift` `anchorLb`. Add a regression
  test before fixing (declarative > imperative).

## 2026-04-27 17:35 UTC — Resolve warmup default-weight open question

- **Files changed:** `docs/handoff/03_ROADMAP.md`, `docs/handoff/10_OPEN_QUESTIONS.md`.
- **What changed:** User answered the warmup default question. Rule:
  starting weight is the **last warmup used for that exercise**; on the
  first-ever warmup for an exercise, fall back to **50% of working weight**.
  Persistence lives in `LoggingStore` (per-exercise). Recorded the rule in
  `03_ROADMAP.md` build-30 step 4 and removed the question from
  `10_OPEN_QUESTIONS.md`.
- **Verification:** Docs only. Working tree review.
- **Risks:** None.
- **Next step:** Same as previous entry — begin drop-set regression
  investigation. Warmup is no longer blocked.

## 2026-04-27 17:55 UTC — Drop-set regression: investigation + pinning tests

- **Files changed:** `VoltraLive/Logging/Persistence/LoggingStore.swift`
  (DEBUG-only test hooks at end), `VoltraLiveTests/DropSetCascadeTests.swift`
  (new), `docs/handoff/02_CURRENT_STATE.md`, `docs/handoff/10_OPEN_QUESTIONS.md`.
- **What changed:** Investigated the user-reported `100 → 80 → 64` drop-set
  regression. Static analysis of `54b33b3` shows the production cascade goes
  through `cascadeAnchoredDeviceWeight` which is anchor-correct at every
  tier; the only function that produces `100 → 80 → 64` is the unused
  `cascadeNextWeight(from:tier:)` at tier 4, and `bumpCascadeTier` caps at
  tier 3. Could not reproduce the bug from the code as committed.
  Wrote a regression test file pinning the anchor-correct ladder at tiers
  1–3 plus a hypothetical tier 4 (matching the user's verbal description),
  plus a live-cascade simulation that drives `startDropSet` + `bumpCascadeTier`
  and asserts `64` never appears in `dropChainPlannedLb`. Added DEBUG-only
  test hooks (`makeForTesting`, `testFireCascadeStep`) at the end of
  `LoggingStore.swift` so prod binaries are unaffected.
  Updated `02_CURRENT_STATE.md` with the full investigation summary and
  added the open question to `10_OPEN_QUESTIONS.md` requesting a precise
  user repro (build number on screen, tap sequence, tile-vs-history).
- **Verification:** Local static checks of symbols and `@MainActor`
  isolation. Will trigger a release.yml dry-run after this commit to
  confirm the test suite builds and passes on macos-26 / Xcode 26.2.
- **Risks:** If the user can reproduce live, the bug is likely in a path
  I didn't trace (or in a stale binary). Tests do NOT yet fix anything —
  they only pin the current intended behavior. If the live cascade truly
  produces `64`, one of these tests will fail and pinpoint the location.
- **Next step:** Trigger release.yml dry-run to confirm tests build/pass.
  Then ask the user for repro details. While waiting, move forward to the
  HealthKit live-streaming task (build 30 priority #2) since the drop-set
  fix is now blocked on user input.

---

## 2026-04-27 14:05 PDT — Drop-set fix: tier bump is preview-only (build 30)

- **Goal:** Fix the user-reported drop-set bug: tapping the active tile to
  adjust the drop %/lb was lowering the weight on every tap. User sent
  screenshots IMG_2241–2244 showing the regression: tap 1 → DROP 2/95 lb,
  tap 2 → DROP 3/80 lb, tap 3 → DROP 4/55 lb. Three taps fired three drops.
- **Root cause:** `bumpCascadeTier()` in `LoggingStore.swift` was calling
  `fireNextCascadeStep()` directly. Combined with `startDropSet`'s own
  immediate fire, every tap fired a drop AND advanced the tier label, so
  the tile became unusable as a tier selector. The cascade *math* was
  always anchor-correct (no compounding) — that part of my prior
  investigation was right; the bug was strictly UX/wiring, not arithmetic.
  My screenshots-confirmed ladder 100 → 95 → 80 → 55 is exactly what
  `cascadeAnchoredDeviceWeight` produces at tier 1 step 1, tier 2 step 2,
  tier 3 step 3 — the user's verbal "100 → 80 → 64" was an approximation
  of what they thought they were seeing.
- **Fix:** `bumpCascadeTier()` now ONLY rolls the tier 1→2→3→1 and resets
  the 4s fuse. It no longer calls `fireNextCascadeStep`. `startDropSet`'s
  immediate fire of drop #2 stays (that's the desired "TAP TO START"
  feel — confirmed by IMG_2241→2242). The 4s fuse remains the sole
  trigger for committing further drops once the cascade is active.
  Tile gesture comment in `LiveCaptureView.swift` updated to match.
  User confirmed this behavior via question prompt before I wrote code.
- **Files changed:**
  - `VoltraLive/Logging/Persistence/LoggingStore.swift` — `bumpCascadeTier`
    no longer fires; doc comment updated to call out the build-30 change.
  - `VoltraLive/Logging/Views/LiveCaptureView.swift` — tile gesture
    comment updated from "fire an immediate drop" → "PREVIEW ONLY".
  - `VoltraLiveTests/DropSetCascadeTests.swift` — replaced
    `testLiveCascade_BumpedTier_DoesNotCompound` (which assumed bump fires)
    with `testLiveCascade_BumpedTier_DoesNotFireDrop` (asserts chain stays
    `[100, 95]` after start + 3 tier bumps). Added
    `testLiveCascade_FuseFiresAtCurrentTier_AnchorRelative` to verify the
    fuse still commits drops at the tier current at fire-time.
  - `VoltraLive/Info.plist`, `project.yml` — bumped 0.4.7/29 → 0.4.8/30
    in all three required places (Info.plist + project.yml settings +
    project.yml info.properties).
- **Verification:** Static review only (no Mac). The new regression tests
  encode the exact pre-fix ladder (80, 55) as forbidden values in
  `dropChainPlannedLb`, so any reintroduction of the bug fails the suite.
  Will trigger release.yml dry-run after commit to validate on macos-26.
- **Risks:** The 4s fuse may now feel slow if the user wants to chain
  drops faster than once-per-4s after bumping to a deeper tier. Possible
  follow-up: add a "fire now" gesture (double-tap or a small fire button)
  if user reports the new behavior feels too passive. Long-press still
  cancels, unchanged.
- **Next step:** Commit the fix + version bump, push, trigger dry-run,
  then move to HealthKit live HR/kcal streaming (build-30 priority #2).

---

## 2026-04-27 14:25 PDT — HealthKit live streaming + PulseDot freshness indicator (build 30)

- **Goal:** Build 30 priority #2 (live HR streaming) + #3 (live kcal
  streaming) + #4 (PulseDot fresh-data indicator). User confirmed they
  start an Apple Workout app session on the Watch before each VOLTRA
  session, so HR + active-energy samples ARE being written to the shared
  HealthKit store; the iPhone just isn't being woken to read them.
- **Root cause:** `HealthKitStore` had `HKAnchoredObjectQuery` with
  `updateHandler` set up correctly, but without `enableBackgroundDelivery`
  the system doesn't reliably wake the iPhone process for samples written
  by the paired Watch. The initial seed callback fires (the user's
  observed snapshot), then no further updates arrive.
- **Fix:** Added `enableBackgroundDeliveryForTypes()` called once after
  authorization succeeds and on every `start()` (idempotent). Calls
  `store.enableBackgroundDelivery(for:frequency: .immediate)` for both
  `.heartRate` and `.activeEnergyBurned`. The existing anchored-query
  pipeline is unchanged otherwise.
- **PulseDot:** New SwiftUI view at
  `VoltraLive/Logging/Views/PulseDot.swift`. Pulses green at ~1.4 Hz while
  data is fresh (≤8s since last sample), fades to faint grey when stale
  or never. TimelineView ticks 4×/s so no host redraw needed. Pure view,
  no env deps.
- **Wiring:** `HealthKitStore` gained two new @Published timestamps:
  `lastHRSampleAt` and `lastKcalSampleAt`, set inside the existing
  `handleHRSamples` / `handleKcalSamples` callbacks. The `tile()` helper
  in `LiveCaptureView` got a new optional `freshnessIndicator: Date??`
  parameter (double-optional so omission means "no dot", `.some(nil)`
  means "show dot in stale state"). HR + KCAL tiles pass the respective
  store timestamps.
- **Files changed:**
  - `VoltraLive/Health/HealthKitStore.swift` — `enableBackgroundDeliveryForTypes`,
    `lastHRSampleAt`, `lastKcalSampleAt`, comments updated.
  - `VoltraLive/Logging/Views/PulseDot.swift` — NEW file.
  - `VoltraLive/Logging/Views/LiveCaptureView.swift` — `tile()` gains
    `freshnessIndicator` param; HR + KCAL tile call sites pass it.
- **Verification:** Static review only (no Mac). Will trigger a release.yml
  dry-run after commit. The risk surface is small: background delivery
  has been HealthKit-stable since iOS 8, and PulseDot is a leaf view.
- **Risks:** (a) If the user has denied HealthKit auth, `enableBackgroundDelivery`
  succeeds-no-op and the dot stays grey — same effect as before, no
  regression. (b) The 1.4 Hz pulse may feel busy; can drop to 1.0 Hz if
  user feedback says so. (c) Initial seed callback fires for ALL samples
  in [sessionStartDate, now], which on session re-entry could double-count
  kcal — but anchor-based queries de-duplicate via `kcalAnchor`, so this
  is correct.
- **Next step:** Commit, push, dry-run. Then move to warmup mode (priority #4).

---

## 2026-04-27 18:32 UTC — Warmup phase auto-detect (build 30 priority #5)

- **Goal:** When the user starts logging on a new exercise, default the Set
  Log sheet to Warm-Up mode and pre-fill the weight to the last warmup the
  user logged for that exercise. If they've never logged a warmup, fall
  back to 50% of the most recent working set, rounded to the nearest 5 lb.
- **Spec source:** `docs/handoff/10_OPEN_QUESTIONS.md` (resolved earlier this
  session) and `docs/handoff/03_ROADMAP.md` priority #5.
- **Implementation:**
  - `LoggingStore.lastWarmup(for:)` — NEW. Same shape as `lastSet(for:)` but
    filters fetched LoggedSets by `mode == .warmUp`. fetchLimit raised to
    200 because warmups are rarer than working sets.
  - `LoggingStore.lastWorkingSet(for:)` — NEW. Returns the most recent
    non-warmup set on the exercise; used as the 50% fallback anchor.
  - `LoggingStore.isFirstSetOfActiveInstance` — NEW computed bool. True
    when there's an active instance, `setNumberForCurrentInstance == 1`,
    AND `inst.sets` is empty. The trigger predicate.
  - `SetLogView.prefillIfNeeded()` — modified. Adds an `autoWarmup` step
    before the existing weight/eccentric/reps/chains prefill. When
    autoWarmup is true: sets `mode = .warmUp` and `label = "Warm-Up"`,
    inserts a new weight branch (telemetry > lastWarmup > 50% of
    lastWorkingSet rounded to 5 > pendingPlannedWeightLb), and skips the
    "copy mode/label from last set" branch so yesterday's working mode
    doesn't override our chosen warmup mode.
- **Telemetry priority:** When `pendingTelemetrySet.peakLb > 0`, telemetry
  still wins over the warmup default. Rationale: telemetry means the rep
  actually happened at that weight (the user is logging from a Voltra set
  that fired); we trust real data over auto-defaults. The warmup mode chip
  remains selected regardless — the user can always tap Working to
  override if they skipped the warmup.
- **Schema:** No new fields. Reuses the existing `LoggedSet.mode` column
  (raw value `"warm_up"`) so the migration is zero-cost.
- **Files changed:**
  - `VoltraLive/Logging/Persistence/LoggingStore.swift` — added
    `lastWarmup`, `lastWorkingSet`, `isFirstSetOfActiveInstance` after the
    existing `lastSet(for:)` at line 989.
  - `VoltraLive/Logging/Views/SetLogView.swift` — `prefillIfNeeded()`
    rewritten with autoWarmup branch + 5-lb-rounded 50% fallback.
  - `VoltraLiveTests/WarmupAutoDetectTests.swift` — NEW. Pins the trigger
    predicate (no active instance / set #1 alone is not enough) and the
    nil-modelContext fallthrough contract.
- **Verification:** Static review + new unit tests. Will dry-run
  release.yml after commit.
- **Risks:** (a) The 5-lb rounding could be wrong for very light
  exercises (e.g. 10 lb working → 5 lb warmup which is fine, but 8 lb
  working → 0 lb after rounding 4 down to nearest 5). Acceptable because
  the user can always edit the field. (b) If a user has logged warmups
  manually as Working in the past, lastWarmup returns nil and we fall
  back to 50% — also acceptable. (c) Telemetry still overrides: if the
  Voltra fires a rep before the user opens the sheet, the detected peak
  force becomes the prefill weight regardless of warmup mode. Pre-build-30
  behavior preserved.
- **Next step:** Commit, push, dry-run. Then dual-Voltra (priority #6) —
  restore from `.dual-voltra-wip/` per `07_DUAL_VOLTRA.md`.
- **Verification update:** Dry-run `25012670021` PASSED in 4m41s.

---

## 2026-04-27 18:42 UTC — Dual-Voltra restoration (build 30 priority #6, scaffolding only)

- **Goal:** Move the four dual-Voltra source files from
  `.dual-voltra-wip/` (gitignored) into the real source tree so they
  compile, and add the supporting `connectKnown` /
  `retrievePeripheralFromOwnCentral` entry points the WIP code expects on
  `VoltraBLEManager`. Deliberately NOT yet wired into UI — a separate
  follow-up commit will add the 3-button Connect screen and the dual
  capture screen.
- **Files added:**
  - `VoltraLive/BLE/Dual/DualMode.swift` — `DualMode`,
    `DeviceSlot`, `CombinedMath` (split + aggregate helpers).
  - `VoltraLive/BLE/Dual/MultiDeviceManager.swift` — owns 2
    `VoltraBLEManager` + 2 `VoltraWriter`, watchdog, telemetry fan-out,
    `CombinedTelemetry` struct.
  - `VoltraLive/BLE/Dual/VoltraDiscoveryScanner.swift` — separate
    `CBCentralManager` instance for tap-to-assign discovery; never
    auto-connects.
  - `VoltraLive/Protocol/VoltraControlFrames+LoadUnload.swift` —
    `loadPayload()` / `unloadPayload()` (PARAM_BP_SET_FITNESS_MODE 0x3E89,
    values 0x0005 / 0x0004) per Android reference.
- **VoltraBLEManager additions:**
  - `connectKnown(identifier:fallback:)` — resolves a peripheral via
    `central.retrievePeripherals(withIdentifiers:)` first, falls back to
    the raw `CBPeripheral` if iOS hasn't cached the identifier yet, defers
    to `didUpdateState` if BT is still warming up. Additive only — the
    existing single-device `connect(to:)` path is untouched, so the
    single-Voltra flow has zero regression risk.
  - `retrievePeripheralFromOwnCentral(identifier:)` — used by the
    Combined-mode reconnect watchdog so `MultiDeviceManager` never has
    to touch the private `central` instance.
- **Sacred files unchanged:** `VoltraProtocol.swift`,
  `TelemetryExtractor.swift`, `PacketParser.swift`, `FrameAssembler.swift`
  not touched. The new LOAD/UNLOAD payloads are in a NEW `extension`
  file, not edits to `VoltraControlFrames.swift`.
- **Verification:** Static review only. Will dry-run release.yml after
  commit to catch compile errors. WIP file references
  (`paramWritePayload`, `uint16Le`, `CMD_PARAM_WRITE`,
  `BLEConnectionState.isConnected`,
  `Telemetry.{forceLb,repCount,phase,peakPowerWatts}`,
  `VoltraDeviceState.weights.{baseLb,eccentricLb,chainsLb}`,
  `VoltraWriter(writeFrame:log:)`,
  `VoltraFrameBuilder.build(cmd:payload:seq:)`) all confirmed to exist
  with matching signatures in current code before the move.
- **Risks:** (a) `MultiDeviceManager` files compile but are NOT yet
  referenced from `VoltraLiveApp.swift` or `ConnectView.swift` — dead
  code at runtime in this commit. That's intentional: the dry-run
  validates that the new code at least compiles in isolation before
  wiring it into the UI surface (which is a much larger change). The
  current commit ships the same user-visible behavior as build 30
  through the warmup commit. (b) The MDM's reconnect loop holds the
  outer `[weak self]` via the Task and re-captures inside
  `await MainActor.run` — reviewed as correct, both early-exits hit if
  `self` is gone. (c) Sacred-file rule: extension file does not modify
  any of the four sacred files — it's a NEW file under `Protocol/`.
- **Next step:** Commit + dry-run. Once green, follow up with
  3-button ConnectView + DualCaptureView wiring (much larger UI commit
  with its own dry-run), plus tests for `CombinedMath.splitWeight`
  (odd-total → left-rounds-up). Then Group dropdown (priority #7) and
  tag v0.4.8-build30.

## 2026-04-27 — fix(dual-voltra): \u{XXXX} brace form in string literals (07ffbad)

- **Why:** Dry-run `25012935170` failed at 53s with 6 Swift compile errors:
  `\u2014`, `\u2192`, `\u2026` are NOT valid Unicode escape syntax inside
  Swift string literals. Swift requires the brace-delimited form
  `\u{XXXX}`. (The bare form is a relic of other languages — Swift
  rejects it specifically to disambiguate from regex-style escapes.)
- **Lines fixed in `MultiDeviceManager.swift`:**
  - 272: reconnect status message — em dash + ellipsis
  - 364–365: combined-mode addLog — right arrow ✕2
  - 368, 371: single-side addLog — right arrow ✕2
- **Doc comments left as-is** — they're not parsed for escapes, so the
  `\u2192` in `DualMode.swift:82` doc comment is harmless.
- **Verification:** Grep for `"[^"]*\\u[0-9A-Fa-f]{4}[^{]` across the new
  Dual/ + Protocol/ files returns only the doc-comment line. Triggered
  dry-run `25013122194` immediately after push.

## 2026-04-27 — feat(dual-voltra UI): DualConnectView + DualCaptureView

- **What ships:** Dual-Voltra is now reachable from the existing
  `ConnectView` via a small "Pair 2 Voltras (beta)" link below the
  Demo Mode button. Single-device flow is unchanged: same Connect
  button, same auto-route into `LoggingHomeView` when one Voltra
  pairs through `bleManager`. The dual flow lives entirely in its
  own navigation stack and uses `MultiDeviceManager` (newly injected
  as an environment object in `VoltraLiveApp`).
- **Files added:**
  - `VoltraLive/Views/Dual/DualConnectView.swift` — discovery list
    powered by `VoltraDiscoveryScanner`, tap-to-select rows, and a
    3-button action bar:
      • "Connect Both (auto-pair top 2)" — picks the two strongest
        RSSI hits and assigns Left = strongest, Right = second.
      • "Connect Left" / "Connect Right" — connect the currently
        selected discovery to that slot.
    Shows per-slot status with a colored dot, a Disconnect link
    when paired, and a yellow error banner mirroring
    `MultiState.errorReconnecting`.
  - `VoltraLive/Views/Dual/DualCaptureView.swift` — post-pair view
    with a Mode toggle (Independent | Combined), two device cards
    (Force / Reps / Phase), an additional Combined virtual-twin
    card when in Combined mode, and a LOAD / UNLOAD action row.
    Telemetry is held on a small `DualCaptureViewModel`
    `ObservableObject` so the view is safe across re-renders.
- **MultiDeviceManager change:** added objectWillChange rebroadcast
  from each child `VoltraBLEManager`. Without it, SwiftUI views that
  read `mdm.left.connectionState` would not redraw when the child's
  `@Published` state changed — only `mdm.state` and `mdm.mode` would
  trigger refreshes. Two `.sink { self?.objectWillChange.send() }`
  subscriptions in `observeConnections()` close that gap.
- **VoltraLiveApp.swift:** added `@StateObject private var multi =
  MultiDeviceManager()` and `.environmentObject(multi)`. The single
  `bleManager` and its telemetry router are unchanged — dual flow
  does NOT yet write to `LoggingStore` (build 31 task).
- **Sacred files:** untouched. ConnectView is a new branch in body
  using a `NavigationStack`, but the existing single-device button
  + status logic is byte-for-byte unchanged inside the new `content`
  computed property.
- **Risks:** (a) The dual flow's telemetry is display-only this build.
  Independent users who walk into DualCaptureView won't see their
  reps logged into the workout history — the entry point is labeled
  "(beta)" so the expectation matches. Single-device users following
  the normal Connect button get the full LoggingStore experience as
  before. (b) The `mdm.onCombinedTelemetry` hook fires on EVERY
  per-device packet (even in Independent mode) — view filters via
  `if mdm.mode == .combined` so it just gets ignored. Cheap.
- **Next:** Dry-run on main; if green, the build-30 dual-Voltra UI
  surface is in. Then merge the parallel agent's Group-dropdown PR,
  tag `v0.4.8-build30`, push tag.

## 2026-04-27 — feat(logging): inline custom-day flow (build 30 #7)

- **Why:** Original "workout-creation Group dropdown" task was bounced
  back by the parallel agent as ambiguous (3+ readings). User picked
  option 2: keep the existing 4-tile DayType picker untouched, just
  make the "Custom" day flow more discoverable inline. Pulled the
  work back into the lead-agent thread to avoid further round-trips
  (PR #2 from `feat/new-exercise-day-picker` was the wrong scope and
  has been closed).
- **What ships:** Tapping the Custom tile in `LoggingHomeView` now
  expands an inline card directly below the day-tile grid instead
  of pushing a modal sheet. The card has:
    • A textfield (focuses automatically after a 150ms delay so
      SwiftUI has time to insert it into the hierarchy)
    • A Start button (disabled until the trimmed label is non-empty)
    • A wrapping chip row of recently-used custom labels — tapping
      a chip starts a session immediately (zero typing for repeats)
  Tapping the Custom tile again collapses the card. Submit (Return
  key) on the textfield also starts the session.
- **Files changed:**
  - `VoltraLive/Logging/Persistence/LoggingStore.swift`:
    new `recentCustomLabels(limit:)` helper. Bounded fetch (300
    sessions max), trims whitespace, skips empty labels, dedupes
    while preserving most-recent-first ordering. Safe nil-context
    fallthrough mirrors the existing `lastSet` / `lastWarmup`
    pattern.
  - `VoltraLive/Logging/Views/LoggingHomeView.swift`:
    - Replaced `showingCustom` (sheet) with `showingCustomInline`
      (inline expander) + `@FocusState customFieldFocused`.
    - Removed the `customSheet` body and its `.sheet(isPresented:)`
      wiring entirely (no longer reachable).
    - Added `inlineCustomCard` + `recentChip` + `startCustom`.
    - Custom tile now toggles the inline expander instead of
      presenting a modal; tile foreground swaps to the accent color
      and the subtitle updates while the expander is open.
  - `VoltraLiveTests/RecentCustomLabelsTests.swift` NEW:
    pins distinct + recency ordering, whitespace handling, the
    `limit` parameter, ignoring of preset (non-custom) sessions,
    and the no-context safety fallthrough. Uses an in-memory
    `ModelContainer` matching the production schema for the
    SwiftData-backed cases.
- **Schema:** No change. `WorkoutSession.customLabel: String?`
  already exists and is what the helper queries.
- **Sacred files:** untouched.
- **Single-device flow:** unchanged. The 4 preset day tiles
  (Leg / Back / Chest / Arm) still call `logging.startSession`
  with the same args and route into `ExercisePickerView` exactly
  as before. Existing customLabel data round-trips through the
  new chip row without any migration.
- **Next:** Dry-run on main; if green, build 30 has shipped both
  remaining priorities (#6 dual-Voltra UI and #7 inline custom-day).
  Then tag `v0.4.8-build30` and push tag.

## 2026-04-27 — fix(test): force cloudKitDatabase=.none in RecentCustomLabelsTests

Build 30 dry-run `25019492252` failed: every test that called `makeStoreWithContext()`
hung for ~55s and tripped the xctest watchdog (logged as "Restarting after
unexpected exit, crash, or test timeout"). Only `_NoModelContext_ReturnsEmpty`
passed because it never instantiates a ModelContainer.

Root cause: `ModelConfiguration(schema:isStoredInMemoryOnly:)` defaults
`cloudKitDatabase` to `.automatic`. On the simulator the CloudKit mirror has
no entitlements and stalls during init.

Fix: match `VoltraLiveApp.modelContainer.v2Config` exactly — explicitly pass
`cloudKitDatabase: .none` (and a name + allowsSave for parity).

Files changed:
- VoltraLiveTests/RecentCustomLabelsTests.swift (makeStoreWithContext)

## 2026-04-27 — fix(test): pure-helper-only RecentCustomLabelsTests (no ModelContainer)

Dry-run `25020027973` (with cloudKitDatabase: .none) STILL hung the same way —
each test that called `makeStoreWithContext()` waited ~30s and tripped the
xctest watchdog. The hosted xctest target's in-memory ModelContainer init is
fundamentally unhappy in this CI environment.

Switched approach: extracted dedupe/trim/limit logic into a pure static helper
`LoggingStore.distinctRecentCustomLabels(from:limit:)` that takes
[String?] (newest-first) and returns the ordered distinct list. The DB-backed
`recentCustomLabels()` is now a thin wrapper that fetches sessions ordered
by startedAt desc and forwards `customLabel` values to the helper.

Tests:
- Kept the no-context safety test (verifies `recentCustomLabels()` returns []
  when modelContext is nil — this is what LoggingHomeView relies on during
  startup / previews).
- Replaced 4 SwiftData-backed tests with 6 pure-helper tests covering empty
  input, nil-skip, distinct+order, trim+empty-skip, limit, trim/dedupe combo.

Files changed:
- VoltraLive/Logging/Persistence/LoggingStore.swift (extracted helper)
- VoltraLiveTests/RecentCustomLabelsTests.swift (rewrote)

## 2026-04-27 — Build 31 begins (v0.4.9-build31)

User reported 8 issues in build 30:
1. ⚠️ Group dropdown on custom-day creation never shipped (got dropped when parallel agent went sideways)
2. Demo mode missing — needs Skip/Try Demo button on connect
3. HR not working at all (regression)
4. No Apple Watch / HealthKit prompt on home screen
5. Dual-Voltra "Pair 2 (beta)" button broken (no scan, all buttons static) + sizing
6. Drop-set re-edit bug (changing % mid-drop-set bugs out)
7. Load/unload button missing on sets
8. Back-button while in workout needs third "just go back" option

### Commit batch 1: HR diagnosis + CI entitlement verification

User confirmed: never saw HealthKit permission prompt in build 30 even with
Apple Workout running on Watch. That points to either
  (a) auth flow wrapping `hasRequestedAuthorization` suppression too early, or
  (b) HealthKit entitlement not embedded in the signed IPA (silent strip).

Fixes:
- HealthKitStore.start(): always call requestAuthorization (Apple-side
  idempotent), only flip hasRequestedAuthorization in the completion, add
  console logging so we can see in Console.app what's happening live.
- release.yml: NEW step "Verify embedded entitlements (HealthKit, iCloud)"
  unzips the signed IPA and runs codesign -d --entitlements :-, hard-fails
  if com.apple.developer.healthkit or com.apple.developer.icloud-services
  is missing. This catches the silent regression class going forward.

If the new CI step FAILS, the mobileprovision in APPLE_PROFILE_MOBILEPROV
needs HealthKit re-enabled in Apple Developer portal.

Files changed:
- VoltraLive/Health/HealthKitStore.swift
- .github/workflows/release.yml
- VoltraLive/Info.plist (version bump 0.4.8 -> 0.4.9)
- project.yml (version bump 30 -> 31 in 2 places)

## 2026-04-27 — Process change: ONE feature per build, labeled

User asked to switch from batched builds to one-feature-per-build so they
can test each fix in isolation and tell me succinctly what works/doesn't.

NEW: Info.plist key `VOLTRAFeatureLabel` shows up in the corner badge next
to the version, e.g. "v0.4.9 (31) · HR test". Update the label in BOTH
VoltraLive/Info.plist AND project.yml info.properties for every build.

Build plan (sequential, one feature per build):
- b31 "HR test" — HR auth retry + entitlement verification (THIS BUILD)
- b32 "Demo mode" — Skip-Try-Demo button + ContentView routing fix
- b33 "Group dropdown" — picker on inline custom card (4 presets + Custom)
- b34 "Back peek" — third option on workout back-confirm
- b35 "Drop-set re-edit" — fix mid-drop-set weight change bug
- b36 "Load/unload" — visible button on each set row
- b37 "Watch chip" — HealthKit chip on home + Settings entry
- b38 "Dual fix" — make Pair 2 actually scan + work, equal sizing

The b32+ fixes are stashed locally as `stash@{0}: b31-extras: ...` ready
to bring back one at a time once b31 ships clean.

### Build 31 ships

CI dry-run 25022146919 PASSED, including the new entitlement verification
step. So HealthKit IS embedded in the signed binary - the build 30 HR
regression is NOT an entitlement strip. The remaining hypothesis is that
the auth completion handler path was suppressing re-prompts. Build 31 fix
addresses that and adds console logging so we can see what's happening on
device this time.

Files changed for label system:
- VoltraLive/Views/BuildBadgeOverlay.swift (read VOLTRAFeatureLabel)
- VoltraLive/Info.plist (NEW key, set to "HR test")
- project.yml info.properties (NEW key, set to "HR test")

## 2026-04-27 — b32 "Demo mode"

User feedback on b30: "Demo mode does nothing. Should auto-take me to the
next screen, not make me connect a Voltra to get into the tile section."

Two real bugs:
1. The Demo Mode button on ConnectView was a small secondary text-styled
   chip, easy to miss.
2. Even when tapped, ContentView only routed to LoggingHomeView based on
   ble.connectionState.isConnected - it never checked demo.isActive. So
   demo flipped on but the user stayed stuck on Connect.

Fixes:
- ConnectView: replaced the secondary DemoModeButton with a primary
  full-width "Skip - Try Demo" call-to-action with play.rectangle icon.
- ContentView: now routes to LoggingHomeView when ble.isConnected OR
  demo.isActive, with a comment explaining why.

Files changed:
- VoltraLive/Views/ConnectView.swift
- VoltraLive/Views/ContentView.swift

## 2026-04-27 — b35 "HK prompt"

User reported on b31 testing: still NO HealthKit permission prompt on device.
That rules out the auth-suppression hypothesis from b31 — the real problem is
the call site. `health.start()` only fires inside LiveCaptureView.onAppear,
so a user who installs the app and opens it without immediately starting a
workout never gets the prompt.

Fixes for b35:
1. New `HealthKitStore.requestAuthIfNeeded()` — eagerly calls
   requestAuthorization without spinning up queries.
2. `VoltraLiveApp.onAppear` calls it on first launch so the system sheet
   appears as soon as the home screen renders.
3. New tappable `healthPill` on the home header next to the connection
   pill: amber "HK ask" before prompting, blue "HK on" after, green "HK
   live" when fresh samples arrive (< 30s). Tap re-prompts so the user
   can recover if the system sheet never appeared.

This is build 35, label "HK prompt".

Files changed:
- VoltraLive/Health/HealthKitStore.swift (new requestAuthIfNeeded)
- VoltraLive/VoltraLiveApp.swift (onAppear calls requestAuthIfNeeded)
- VoltraLive/Logging/Views/LoggingHomeView.swift (healthPill + env object)
- VoltraLive/Info.plist (0.4.12 -> 0.4.13, 34 -> 35, label "HK prompt")
- project.yml (same bumps in 2 places)

## 2026-04-27 — b36 "Load/unload"

User-reported (b30): "no load/unload button on sets". The protocol payloads
(VoltraControlFrames+LoadUnload.swift) and MultiDeviceManager API existed
since b29 but the single-device VoltraBLEManager had no public method, so
the LiveCaptureView couldn't fire them.

Fixes:
- NEW VoltraBLEManager+LoadUnload.swift: sendLoad() / sendUnload() that
  frame the existing payloads via VoltraFrameBuilder + writeControlFrame,
  using a per-class ad-hoc seq starting at 0xC000 to stay clear of
  VoltraWriter's counter (matching MultiDeviceManager's pattern).
- LiveCaptureView upcoming-set card now has a Load/Unload button pair
  below the mode chips. Disabled when not connected or in demo mode.

Files changed:
- VoltraLive/BLE/VoltraBLEManager+LoadUnload.swift (new)
- VoltraLive/Logging/Views/LiveCaptureView.swift (loadUnloadRow)
- VoltraLive/Info.plist (0.4.13 -> 0.4.14, 35 -> 36, label "Load/unload")
- project.yml (same bumps in 2 places)

## 2026-04-27 — b37 "HK settings"

User asked for a HealthKit/Watch chip on home AND in settings. b35 added
the home chip; b37 adds the Settings entry. New "APPLE WATCH / HEALTHKIT"
section in DebugView shows availability, auth state, current HR, last
sample age, and session kcal, with a re-request button so the user can
recover from a missed prompt without leaving the app.

Files changed:
- VoltraLive/Logging/Views/DebugView.swift (new section + env object)
- VoltraLive/Info.plist (0.4.14 -> 0.4.15, 36 -> 37, label "HK settings")
- project.yml (same bumps in 2 places)

## 2026-04-27 — b38 "Drop re-edit"

User-reported (b30): "drop-set re-edit bug — changing weight mid-drop-set
bugs out." Root cause: adjustWeight() in LiveCaptureView mutated
pendingPlannedWeightLb directly. During an active cascade,
nextCascadeWeight() always uses chainAnchorLb (frozen at startDropSet) and
cascadeStepIndex, so the next 4s tick would snap the device back to the
original anchor's stepped weight, silently undoing the user's edit.

Fix: new LoggingStore.reanchorCascadeIfActive(toLb:) re-anchors the
chain to the new weight and resets stepIndex to 0. adjustWeight() now
calls it after every nudge. No-op when no drop set is active, so single
sets are unchanged.

Files changed:
- VoltraLive/Logging/Persistence/LoggingStore.swift (new method)
- VoltraLive/Logging/Views/LiveCaptureView.swift (call from adjustWeight)
- VoltraLive/Info.plist (0.4.15 -> 0.4.16, 37 -> 38, label "Drop re-edit")
- project.yml (same bumps in 2 places)

## 2026-04-27 — b39 "Dual fix"
Dual-Voltra Connect screen sat empty showing "Scanning..." forever; "Connect Both (auto-pair top 2)" button label wrapped awkwardly and was visually heavier than the per-device buttons.
Root cause (scan): `VoltraDiscoveryScanner.start()` returned early when `central.state != .poweredOn` (the normal case at first call since CoreBluetooth init is async). `centralManagerDidUpdateState` only flipped published `state` to `.idle` on poweredOn; it never actually invoked `central.scanForPeripherals(...)`. Net result: scan was requested but never began.
Fix (scan): added `startRequested: Bool` flag, factored the actual scan call into a private `beginScanning()` helper, and made `centralManagerDidUpdateState` call `beginScanning()` when poweredOn arrives if `startRequested` was set. `start()` now sets the flag and either begins immediately or waits for the delegate callback.
Fix (button): shortened "Connect Both (auto-pair top 2)" -> "Auto-Pair Both" and gave `buttonLabel` a `minHeight: 44` with `lineLimit(1)` + `minimumScaleFactor(0.85)` so the three buttons render at consistent height.
Files changed: VoltraLive/BLE/Dual/VoltraDiscoveryScanner.swift, VoltraLive/Views/Dual/DualConnectView.swift, VoltraLive/Info.plist, project.yml, docs/WORK_LOG.md

## 2026-04-27 — b40 "Connect unify"
Single Connect entry point. The old flow forced the user into one of two doors before they knew what was nearby: a big "Connect to VOLTRA" button that auto-grabbed the first Voltra it saw (no choice over which one), OR a separate "Pair 2 Voltras (beta)" link that pushed to DualConnectView. User feedback: "When I hit connect to Bluetooth, it doesn't give me an option of which one to connect to if there are two available... There's a Connect to Voltra button as it is today, you hit that, it brings you to a new menu that shows available voltras. You can either click one or both."

Changes:
- New `VoltraLive/Views/UnifiedConnectSheet.swift`: discovery list backed by VoltraDiscoveryScanner with multi-select. Tap one row -> "Connect" (single mode, routes through ble.connectKnown). Tap two rows -> "Connect Both" (dual mode, routes through mdm.connectBoth, first tap = LEFT, second = RIGHT). FIFO replacement if a 3rd row is tapped.
- `ConnectView`: replaced `ble.startScan()` direct call with sheet present. Removed the "Skip - Try Demo" full-width button and the "Pair 2 Voltras (beta)" tertiary link. Demo mode now lives only in the Debug sheet (gear icon on home).
- `ContentView`: routing gate now also flips to LoggingHomeView when `mdm.left` or `mdm.right` is connected (not only the legacy single-device manager). This is what makes both single- and dual-pair flows land on the same home screen instead of a separate Dual Capture screen.
- `LoggingHomeView.connectionPill`: dual-aware label. "Left + Right" when both MDM slots are paired, "Left connected" / "Right connected" when one slot, falls back to legacy "Connected" / "Not connected" otherwise. Passive label only -- selection of which Voltra is active for a workout still happens pre-workout (b42).

DualConnectView and DualCaptureView are no longer reachable from the UI but the files remain in the project; b41 will rewire MDM telemetry into the unified pipeline and b42 will add the pre-workout Voltra picker, after which those files can be removed.

Files changed: VoltraLive/Views/UnifiedConnectSheet.swift (new), VoltraLive/Views/ConnectView.swift, VoltraLive/Views/ContentView.swift, VoltraLive/Logging/Views/LoggingHomeView.swift, VoltraLive/Info.plist, project.yml, docs/WORK_LOG.md

## 2026-04-27 — b41 "Dual telemetry"
After b40 unified the connect flow, the dual-pair path landed users on the regular logging home screen — but the per-side telemetry hooks (`mdm.onLeftTelemetry` / `onRightTelemetry` / `onCombinedTelemetry`) were only ever wired inside DualCaptureView.onAppear, which the new flow no longer reaches. Result: paired both Voltras, home shows "Left + Right connected", but starting a workout produced zero phase/reps/force on the live tile.

Root cause: the live pipeline (SessionStore.handleLiveSample + LoggingStore.noteTelemetryActivity) is fed exclusively by `bleManager.onTelemetry` (single-device) plus the synthetic Demo path. MDM's hooks were dangling unless DualCaptureView was on screen.

Fix: wire MDM telemetry into the same `telemetryHandler` closure used by the single-device manager, in VoltraLiveApp's onAppear right after the bleManager hook is set.
- onLeftTelemetry: forwards Left telemetry through telemetryHandler ONLY when right is not connected (so we don't double-count alongside the combined fanout below).
- onRightTelemetry: symmetric for right when left is not connected.
- onCombinedTelemetry: only fires through telemetryHandler when BOTH sides are connected; converts CombinedTelemetry into a Telemetry struct (force=sum, reps=sum, peakPower=sum, phase = whichever side is non-idle, prefer left). This gives the user a virtual-twin reading on the existing live tile.

Net effect with two Voltras paired: the live tile, rep counter, and drop-cascade timers all see merged readings. With one paired (single-device through MDM), that side passes through unchanged.

Sacred files (Telemetry struct in TelemetryExtractor.swift) are not modified — the merged struct is populated via memberwise property assignment after `Telemetry()`.

Files changed: VoltraLive/VoltraLiveApp.swift, VoltraLive/Info.plist, project.yml, docs/WORK_LOG.md

## 2026-04-27 — b42 "Voltra picker"
Pre-workout Voltra mode picker. User direction: "having them dual mode by default is not by intent. I want to be able to pair them and then engage with them separately. The Voltra should be selected pre-workout (not inside LiveCaptureView)."

Changes:
- `DualMode.swift`: new `WorkoutMode` enum with four cases: `.singleLeft`, `.singleRight`, `.independent`, `.combined`. Each case has `label`, `subtitle`, and `icon` for the picker UI.
- `MultiDeviceManager`: new `@Published var workoutMode: WorkoutMode = .singleLeft`. Default is single-left so pairing both does NOT auto-engage dual mode.
- `VoltraLiveApp` telemetry routing: `multi.onLeftTelemetry` / `onRightTelemetry` / `onCombinedTelemetry` now consult `multi.workoutMode` when both sides are connected. .singleLeft -> only left forwarded; .singleRight -> only right; .independent -> both raw; .combined -> merged virtual-twin reading. Single-side connection still passes through unchanged.
- New `VoltraLive/Views/WorkoutVoltraPickerSheet.swift`: full-sheet picker with one row per mode (icon + label + subtitle). Selection sets `mdm.workoutMode` then calls `onConfirm()`.
- `LoggingHomeView`: new `beginStart(dayType:customLabel:)` indirection. When both Voltras are paired, taps on day tiles or the custom-day Start route through the picker sheet first; otherwise startSession runs immediately. New `PendingStart` struct carries the (dayType, customLabel?) tuple across the sheet boundary.

Sacred files (Telemetry struct, VoltraProtocol, etc.) unchanged.

Files changed: VoltraLive/BLE/Dual/DualMode.swift, VoltraLive/BLE/Dual/MultiDeviceManager.swift, VoltraLive/VoltraLiveApp.swift, VoltraLive/Views/WorkoutVoltraPickerSheet.swift (new), VoltraLive/Logging/Views/LoggingHomeView.swift, VoltraLive/Info.plist, project.yml, docs/WORK_LOG.md

## 2026-04-27 — b43 "Drop floor"
**Problem:** Drop-set cascade returned weights below the Voltra hardware minimum (5 lb single, 10 lb effective on pulley). User reported the cascade pushing the device to 2.5 lb / 0 lb during deep drops. Also asked us to verify the percentage-vs-flat math was actually picking the larger drop — they suspected only flat numbers were firing.

**Root cause:**
- `cascadeAnchoredDeviceWeight` only blocked `nextEffective <= 0`, so anchor=20 / tier=2 / step=2 returned 0 lb. No hardware floor.
- The percent-vs-flat math was already correct (`max(perStepLb, anchorEffective × perStepPct)` at line 621) — but at anchor ≤ 100 lb, both produce the same step, so users couldn't see the percent path firing visually. Pinned with a unit test.

**Fix:**
- Added `deviceFloorLb: Double = 5.0` parameter to `cascadeAnchoredDeviceWeight`. Result is clamped at the floor AFTER mapping back to device coordinates — so pulley mode (multiplier=2) gets a 5 lb device floor = 10 lb effective floor, matching the user-stated 10–400 lb pulley range.
- Degenerate case: if anchor itself is already below the floor, return anchor unchanged so caller stops firing.
- Caller stop-condition (`next >= prev`) already handles the sticky-floor case — once we hit 5 lb, the next step also clamps to 5, `next >= prev` triggers, cascade stops.
- Updated comments on `nextCascadeWeight` and `previewNextCascade` to document the new behavior.
- Added 4 unit tests:
  1. Single-mode floor clamp from low anchor (a=20, tier=2)
  2. Pulley-mode floor clamp from low anchor (a=30 device / 60 effective, tier=3)
  3. Percent-beats-flat at high anchor (a=200, tier=1 → 10 lb steps not 5)
  4. Sub-floor anchor stalls cleanly

**Files changed:**
- VoltraLive/Logging/Persistence/LoggingStore.swift (cascadeAnchoredDeviceWeight + 2 callers)
- VoltraLiveTests/DropSetCascadeTests.swift (+4 tests)
- VoltraLive/Info.plist + project.yml (bumped to 0.4.21/43, label "Drop floor")

**Note for b44:** restore-anchor-on-finalize/cancel is queued next. When the rest timer kicks in or hold-to-cancel fires, the device should be pushed back to `chainAnchorLb` so it doesn't stay at 5 lb floor.

## 2026-04-27 — b44 "Drop reset"
**Problem:** When a drop-set chain finished (rest timer fired) or was cancelled (hold-to-cancel), the Voltra stayed parked at whatever weight the last cascade step pushed — often the 5 lb floor after b43. The user came back from rest to a device still set to 5 lb and had to manually crank it back up to their working weight.

**Root cause:**
- `finalizeCascade` only stopped timers and forwarded to SessionStore — it never sent a final BLE write to restore the anchor weight.
- `cancelDropSet` cleared internal state including `chainAnchorLb` and `dropPushWeight` but never used them to push the anchor back first.

**Fix:**
- `finalizeCascade`: capture `dropPushWeight` and `chainAnchorLb` BEFORE handing off to SessionStore (which will trigger autoLogDropChain → tear-down). If both are valid, push the anchor over BLE so the device is at the working weight by the time rest starts.
- `cancelDropSet`: same pattern — push anchor BEFORE clearing state, and also reset `pendingPlannedWeightLb` so the UI weight tile reflects the restore.
- Both paths leave the existing tear-down sequence intact; the new push happens in the narrow window between `stopCascadeTimers()` and state clearing.

**Files changed:**
- VoltraLive/Logging/Persistence/LoggingStore.swift (cancelDropSet + finalizeCascade)
- VoltraLive/Info.plist + project.yml (bumped to 0.4.22/44, label "Drop reset")

## 2026-04-27 — b45 "Mega fix" (batched fixes A–I)

**Context:** User explicitly asked: *"batch everything to use the least amount of tokens and just do one build"* — overrides the one-feature-per-build cadence for this build.

**Bugs addressed (batch of 9, mapped to feedback letters A–I):**

- **A — Dual-Voltra workout doesn't apply weight / no telemetry.** Single-Voltra worked because LiveCaptureView writes through `LiveWriterHolder.attach(ble:)` which addresses the legacy single-device manager directly. With both slots paired, weight changes hit `ble` (which has no peripheral) and never reached either Voltra.
  - **Fix:** new `VoltraLive/BLE/WriterRouter.swift` ObservableObject. `apply(_:mdm:)` inspects `mdm.workoutMode` + slot connection state and routes:
    - Combined → `mdm.applyCombined(state)` (CombinedMath split per-side)
    - singleLeft / singleRight → that slot's writer only
    - Independent → both slot writers (mirror)
    - One slot paired → that slot only
    - Neither slot paired → fall back to legacy single `ble` writer (preserves single-Voltra path).
  - LiveCaptureView and ExerciseDetailView now use `WriterRouter` instead of `LiveWriterHolder`. Both views gained `@EnvironmentObject var mdm: MultiDeviceManager`.

- **B — HealthKit prompt missing on launch / "re-authorize" unclear.** Several users land in `.notDetermined` and Apple won't let an app re-prompt once dismissed; the only path is iOS Settings → Privacy → Health.
  - **Fix:** DebugView now has an "Open Settings (Privacy → Health)" button using `UIApplication.openSettingsURLString` deep-link, plus an explanatory line above the existing "Re-authorize" row.

- **C — Demo Mode missing from first screen.** ConnectView lost its DemoModeButton in the dual-pair UI rework.
  - **Fix:** restored `DemoModeButton(source: .prePair)` wired through `DemoTelemetryBridge.shared.handler`.

- **D — RSSI bouncing in discovery list.** `VoltraDiscoveryScanner.didDiscover` re-sorted the discovered list strongest-first on every advertisement, and instantaneous RSSI swings ±10 dBm at rest. Order flipped continuously and the dBm number jittered.
  - **Fix:** EMA smoothing in `VoltraDiscoveryScanner`. New field `rawRssi` preserves the latest advertisement; `rssi` is now `0.25*raw + 0.75*previous` (seeded with raw on first sight). UI reads `.rssi` so all callers (UnifiedConnectSheet, dual pair view) get smoothed values for free with no caller changes.

- **E — Cascade interval too long + no "BOTTOM" indicator.** `cascadeIntervalSec` was 4 s, which the user found too slow once they were in the rhythm. Also, after the b43 floor clamp the chain would sit on a static "5" with no visual cue that it was at the floor.
  - **Fix 1:** `cascadeIntervalSec: 4.0 → 2.0`.
  - **Fix 2:** new `@Published var cascadeAtFloor: Bool` set inside `nextCascadeWeight()` when no further progress is possible. LiveCaptureView's drop-set tile shows "BOTTOM" (in danger color) instead of the "5" digit when this flag is set, with subline "5 lb floor — finalizing".

- **F — Drop-set reset still broken after b44.** b44 pushed the anchor back over BLE on finalize but left `pendingPlannedWeightLb` parked at the floor, so the next set's weight tile read 5 lb. Root cause: `forceFinalizeCurrentSet` triggers `autoLogDropChain` which clears `chainAnchorLb` BEFORE the new restore line could read it.
  - **Fix:** `finalizeCascade` now captures `chainAnchorLb` into a local *before* invoking `forceFinalizeCurrentSet`, then assigns `pendingPlannedWeightLb = anchor` after. UI now correctly shows the anchor weight on the next set.

- **G — Tier-bump math wrong (30 → 25 → 10 → 5).** When `bumpCascadeTier` fired, `cascadeStepIndex` carried over, so the next `nextCascadeWeight()` call computed step 2 of tier 2 from the original anchor: 30 − 10×2 = 10. Skipped 20.
  - **Fix:** `bumpCascadeTier()` now re-anchors `chainAnchorLb = lastDropped` and resets `cascadeStepIndex = 0`. Ladder now produces clean monotonic descents (e.g. 30 → 25 → 15 → 5). Will gather user feedback after testing.

- **H — Pulse-dots not blinking.** PulseDot's `freshWindow` was 8 s, but HealthKit background delivery is bursty (sometimes 10–14 s between samples even when actively streaming). Dots rarely got the chance to display "fresh".
  - **Fix:** `freshWindow: 8.0 → 15.0` seconds. Tracks HK's actual cadence.

- **I — Want HR + kcal merged + Load/Unload tile freed.** The 2×3 metrics grid had separate HR and KCAL tiles; user wanted one slot reclaimed for device controls.
  - **Fix:** new `healthMergedTile` (HR headline + kcal subline, pulse-dot tracks the freshest of the two HK timestamps) replaces both. New `loadUnloadTile` with two equal-width buttons routes through MDM when any dual slot is paired (so Combined splits per-side, Independent mirrors, single-slot fires only that side); falls back to the legacy `ble.sendLoad/sendUnload` when no MDM slots are paired.

**Files changed:**
- VoltraLive/BLE/WriterRouter.swift (NEW)
- VoltraLive/BLE/Dual/VoltraDiscoveryScanner.swift (RSSI EMA smoothing)
- VoltraLive/Logging/Persistence/LoggingStore.swift (E + F + G + cascadeAtFloor flag)
- VoltraLive/Logging/Views/LiveCaptureView.swift (mdm env, WriterRouter, healthMergedTile, loadUnloadTile, BOTTOM indicator)
- VoltraLive/Logging/Views/ExerciseDetailView.swift (mdm env, WriterRouter)
- VoltraLive/Logging/Views/PulseDot.swift (freshWindow 8 → 15 s)
- VoltraLive/Logging/Views/DebugView.swift (Settings deep-link)
- VoltraLive/Views/ConnectView.swift (restored DemoModeButton)
- VoltraLive/Info.plist + project.yml (bumped to 0.4.23/45, label "Mega fix")

**Test plan after TestFlight install:**
1. Pair only one Voltra (left slot) → run a workout, confirm weight changes apply and telemetry streams (regression check for A's fallback path).
2. Pair both Voltras in Combined → confirm weight splits per-side and both Voltras receive load updates.
3. Pair both in Independent → confirm both mirror.
4. Trigger a drop-set chain from 30 lb, let it cascade naturally → expect 30 → 25 → 20 → 15 → 10 → 5 → BOTTOM, then on next set the weight tile shows 30 (not 5).
5. Cascade interval should now feel snappy (~2 s between auto-drops).
6. Open DebugView, verify "Open Settings" deep-link lands on iOS Privacy → Health.
7. Confirm DemoModeButton visible on first ConnectView screen.
8. Watch RSSI in dual-pair sheet — dBm number should drift smoothly, not jitter.
9. Confirm HR/KCAL merged tile renders and pulse-dot stays green when Watch is streaming.
10. Tap LOAD / UNLOAD buttons in the live grid; verify Combined splits per-side (50% each).

---

## b46 — v0.4.24 (build 46) — "Resistance + HK"

**Date:** 2026-04-28
**Goal:** Fix the main HK workflow blocker, then add resistance nudgers + tile reorder + state-aware LOAD button + parity HR/KCAL. User feedback after b45 testing: HR/kcal had been intermittent (then "randomly started working"), and the iOS Settings page for VOLTRA Live had no Health row at all (only Bluetooth/Siri/Search/Cellular Data). Per user: "Hold off on iteration until you fix the main workflow." Fix HK first.

**Fixes & features:**

- **A — HealthKit entitlement, root cause of intermittent HR/kcal.** The `VoltraLive.entitlements` file declared `com.apple.developer.healthkit.access` with an empty `<array/>` value. That key is for clinical health-records access (HKClinicalTypeIdentifier.* — allergies, lab results, etc.), not for the HKQuantityType samples we actually use (heart rate, active energy). When present-but-empty, iOS treats the app as declaring the capability without exercising any of its features, which (a) prevents the Health row from appearing in the app's iOS Settings page and (b) appears to contribute to intermittent HKAnchoredObjectQuery delivery for our HR / active-energy queries.
  - **Fix:** removed the empty `healthkit.access` key entirely. Standard HR / active-energy reads only require `com.apple.developer.healthkit = true` + the two `NSHealth*UsageDescription` Info.plist strings, all of which are already in place. Added a long inline XML comment on the entitlements file documenting the diagnosis so this isn't re-added by mistake. **Caveat:** if the App Store provisioning profile in the Apple Developer portal also has `healthkit.access` baked into it, the IPA may still carry it through profile injection — the dry-run "Verify embedded entitlements" step will surface this. If so, the user will need to regenerate the App Store profile in the portal so the next build picks up the corrected entitlements.

- **B — RESISTANCE tile gains inline nudgers (mid-set weight changes).** User wanted the ability to add/subtract weight live during a set without leaving the live grid.
  - **Fix:** new `resistanceNudgerTile` replaces the passive RESISTANCE readout. Big monospaced headline still shows current weight in lb, with the per-rep/total-volume subline preserved (`{perRep} × {reps} reps`). Below that, a 2×2 grid of compact buttons: `−5 / +5` on top row, `−1 / +1` on bottom. Each button calls the existing `adjustWeight(±n)` helper which already does `pendingPlannedWeightLb = next; reanchorCascadeIfActive(toLb:); pushUpcomingStateToDevice()` — so writes route through `WriterRouter` (Combined/Independent/single all handled) and re-anchor any in-flight drop-cascade. No new code path, just inline UI on a previously-passive tile.

- **C — Tile grid reordered left-to-right per user spec.** b45 had RESISTANCE / FORCE / LOAD-UNLOAD top, REPS / REST / DROPSET middle, HR-KCAL / TOTAL-VOL bottom. User wanted reading order to flow left-to-right starting from RESISTANCE.
  - **Fix:** rewrote `tileGrid` body into 4 rows of 2: Row 1 = RESISTANCE±  +  LOAD/UNLOAD; Row 2 = REPS  +  DROP SET; Row 3 = FORCE  +  REST; Row 4 = HR/KCAL  +  TOTAL VOL. Same VStack/HStack structure, just shuffled.

- **D — LOAD/UNLOAD is now one state-aware toggle, not two buttons.** User: "It shouldnt say load and unload on the tile, it should say load when the wieght is unloaded and change to unload when the wieght it loaded."
  - **Fix:** new `loadUnloadTile` reads a new `@State deviceLoaded: Bool` flag (default `false` → "LOAD" shown at session start). Tap "LOAD" → calls `sendLoad()` and flips flag to `true` (label → "UNLOAD"). Tap "UNLOAD" → calls `sendUnload()` and flips back. Color shifts: accent when LOAD is shown (action available), textDim when UNLOAD is shown (already-loaded state). **Limitation:** the Voltra protocol does not broadcast load-state in telemetry (`Telemetry` struct in `TelemetryExtractor.swift` has no load field), so the flag tracks local belief only. If the user manually disconnects the cable or yanks the weight, the flag goes stale until the next tap. Acceptable until firmware exposes load-state.

- **E — HR/KCAL parity sizing per user feedback.** b45 merged HR + kcal into a single tile but kcal was rendered as a small subline; user said "kcal number is too small in the picture it should be similar in side and have it's own blinking indicator" and "i think hr and kcal text can be smaller with the acutal bpm and kcal numbers being the most proinate."
  - **Fix:** replaced `healthMergedTile` with new `healthDualTile` — one tile, HStack with a thin vertical separator. Left half: small "HR" label + own pulse-dot reading `health.lastHRSampleAt` + 28pt monospaced number (BPM) + small "bpm" unit. Right half: same structure for KCAL — small "KCAL" label + own pulse-dot reading `health.lastKcalSampleAt` + 28pt monospaced number + small "kcal" unit. Labels deliberately small, numbers prominent.

**Files changed:**
- VoltraLive/VoltraLive.entitlements (removed empty healthkit.access; added explanatory XML comment)
- VoltraLive/Logging/Views/LiveCaptureView.swift (tile reorder, resistanceNudgerTile, compactNudger, healthDualTile, state-aware loadUnloadTile, @State deviceLoaded)
- VoltraLive/Info.plist + project.yml (bumped to 0.4.24/46, label "Resistance + HK")

**Test plan after TestFlight install:**
1. Settings → VOLTRA Live → confirm a Health row now appears (alongside Bluetooth/Siri/Search/Cellular Data). Tap it → expect HR + Active Energy toggles, both green.
2. Run a 5-minute logged session with Watch on wrist actively streaming → HR + kcal numbers should update steadily with their pulse-dots both green.
3. Mid-set, tap RESISTANCE −5 / +5 / −1 / +1 nudgers → weight number on RESISTANCE tile should change immediately, both Voltras (or single, depending on pair mode) should reflect. If a drop-cascade is mid-flight, it should re-anchor to the new value.
4. Verify left-to-right tile order: Row 1 RES + LOAD, Row 2 REPS + DROP, Row 3 FORCE + REST, Row 4 HR/KCAL + TOTAL VOL.
5. Tap LOAD → label flips to UNLOAD, weight loads. Tap UNLOAD → label flips back to LOAD, weight unloads.
6. HR/KCAL tile: both numbers should be the same large (28pt) size, each with its own blinking pulse-dot, with "HR" / "KCAL" / "bpm" / "kcal" rendered as small caption text.

## b47 — v0.4.25 (build 47) — "Combined parity"

**Date:** 2026-04-28
**Goal:** Fix the LOAD/UNLOAD-only-fires-one-Voltra bug, enforce even-weight parity in Combined mode (per-side split must be equal), and ship a Superset workout mode (alternates between left and right Voltra as exercise A / exercise B). User explicitly bundled b47+b48 ("Combined parity" + "Superset") into this single build.

**User direction (verbatim, this session):**
- Combined mode: "when the Voltras are combined, you're only allowed to have even numbers, so it can split evenly."
- LOAD/UNLOAD bug: "if i hit unload it only unloads one of them" — fix so both fire in Combined.
- Drop-set step in combined: −6 lb (matches +6 nudger for symmetry).
- Round-on-entry: round DOWN (35 → 34) — never add weight the user didn't ask for.
- "make sure there is a super set mode in the build youre working on now."
- Stand-mode + dampers + bands behavior in Combined: deferred (low priority).
- Autonomy: "im going to sleep now, if you need to ask me a question before pushing this build, just do what you would recommend instead of asking me."

**Fixes & features:**

- **A — LOAD / UNLOAD only fires one Voltra in Combined.** Root cause: `MultiDeviceManager.sendControlPayload` was reusing the same `VoltraProtocol.encodeFrame(...)` output across both peripherals back-to-back. CoreBluetooth (and/or the firmware on the receiving end) appears to coalesce or drop a second write whose bytes (and `seq`) are identical to the previous one when issued in quick succession. Symptom: only one Voltra reacted to LOAD/UNLOAD; the other stayed at its prior state.
  - **Fix:** `sendControlPayload` now builds a SEPARATE frame per recipient with its own `seq` (so the bytes differ). Each side's writer schedules its own write through its own queue, and a debug-only log prints `[MDM] LOAD->left seq=N ; LOAD->right seq=N+1` so we can confirm both fired. Same path is used for stand-toggle and damper writes, which inherits the fix for free.

- **B — Combined-mode parity enforcement (even total weight only).** New file `VoltraLive/BLE/Dual/CombinedParity.swift` centralizes the rule:
  - `smallStepLb(for: WorkoutMode)` → 2 in Combined, 1 elsewhere.
  - `largeStepLb(for: WorkoutMode)` → 6 in Combined, 5 elsewhere.
  - `roundDownToEven(_:)` for Int and Double.
  - `combinedDropStepLb: Double = 6.0`.
  - `enforce(_:mode:)` floors to nearest even pound when mode requires parity, passes through otherwise.
  - `WorkoutMode.requiresEvenWeight: Bool` (true only for `.combined`) drives all the call sites.
  - **Resistance nudgers:** `resistanceNudgerTile` and the upcoming-card weight nudger now read `let small/large = CombinedParity.{small,large}StepLb(for: mdm.workoutMode)` outside the ViewBuilder block and render `−large/+large` on top, `−small/+small` on bottom. Combined shows ±6 / ±2; everything else shows ±5 / ±1.
  - **Drop-set cascade step:** `LoggingStore.cascadeAnchoredDeviceWeight` now takes optional `baseLb` / `basePct` / `roundingLb` parameters (defaults preserve the legacy 5.0 / 0.05 / 2.5 behavior). `nextCascadeWeight()` and `previewNextCascade()` pass `baseLb=6.0, roundingLb=2.0` when a new `combinedModeActive: Bool` published flag is true. The flag is pushed by LiveCaptureView via `LoggingStore.applyWorkoutMode(_:)` in `.onAppear` and `.onChange(of: mdm.workoutMode)`.
  - **Mode-switch rounding:** `enforceCombinedParityOnEntry()` in LiveCaptureView fires when the user enters Combined mode and rounds the standing planned weight DOWN to the nearest even pound (35 → 34). Defensive `CombinedParity.enforce(...)` call inside `adjustWeight(_:)` catches any path that bypasses the nudgers.

- **C — Superset workout mode.** New `case superset` in `WorkoutMode` (label "Superset", subtitle explaining A/B alternation, icon `arrow.left.arrow.right`). Picker shows the option only when both slots are paired (gating already handled by the existing dual-slot mode picker, which lists every WorkoutMode case). New state on `MultiDeviceManager`:
  - `supersetActiveSlot: DeviceSlot = .left` (user opens at exercise A on the left Voltra).
  - `supersetLeftWeightLb` / `supersetRightWeightLb` (per-side pending weight memory across SWAPs).
  - `supersetLeftExercise` / `supersetRightExercise` (per-side exercise label memory).
  - `flipSupersetActiveSlot()` toggles `.left ↔ .right`.
  - `slotsForWorkoutMode()` helper returns `[active]` for superset, `[both]` for combined/independent, `[that one]` for single-slot — so LOAD/UNLOAD in superset writes to BOTH (we want both Voltras pre-loaded), state writes go ONLY to the active side.

  **Routing (`WriterRouter.swift`):** new `.superset` branch under `(true, true)` routes weight-state writes to `mdm.supersetActiveSlot` only.

  **Telemetry (`VoltraLiveApp.swift`):** added `.superset` cases to the two non-exhaustive `switch m.workoutMode` blocks in `onLeftTelemetry` / `onRightTelemetry` — telemetry forwards from the active side only (so HR/force/reps reflect the exercise the user is doing right now, not the unused side).

  **UI (`LiveCaptureView.swift`):** new `supersetBanner` view rendered between the header and `tileGrid` whenever `mdm.workoutMode == .superset`. Shows:
  - **NOW** chip on the active side (accent color) with the exercise label + current weight.
  - **SWAP** button in the middle.
  - **NEXT** chip on the inactive side (dimmed) with the exercise label + stored weight.
  - `swapSupersetSide()` saves the outgoing pending weight to `mdm.supersetLeft/RightWeightLb`, calls `flipSupersetActiveSlot()`, then restores the incoming side's stored weight to `logging.pendingPlannedWeightLb` and pushes new state to the device.

- **D — Combined drop-set step is now −6 lb with even ladder.** Per user spec, drop-cascade in Combined uses 6 lb steps (matching the large nudger) and floors to the nearest even pound at every tier so totals stay even all the way to BOTTOM. Example from 30 lb: 30 → 24 → 18 → 12 → 6 → BOTTOM. Independent / single keep the legacy −5 lb step.

**Files changed:**
- VoltraLive/BLE/Dual/CombinedParity.swift (NEW — parity helpers, even-step constants, mode-aware enforce)
- VoltraLive/BLE/Dual/DualMode.swift (added `.superset` case + `requiresEvenWeight` computed prop)
- VoltraLive/BLE/Dual/MultiDeviceManager.swift (per-side seq for control payloads — LOAD/UNLOAD fix; superset state + flip + slotsForWorkoutMode helper)
- VoltraLive/BLE/WriterRouter.swift (`.superset` routing → active side only)
- VoltraLive/Logging/Persistence/LoggingStore.swift (combinedModeActive flag + applyWorkoutMode; cascadeAnchoredDeviceWeight params; previewNextCascade + nextCascadeWeight pass baseLb=6/roundingLb=2 in combined)
- VoltraLive/Logging/Views/LiveCaptureView.swift (mode-aware nudger steps; enforceCombinedParityOnEntry; supersetBanner; swapSupersetSide; onAppear/onChange push mode to LoggingStore)
- VoltraLive/VoltraLiveApp.swift (`.superset` telemetry routing in two switches)
- VoltraLive/Info.plist + project.yml (bumped to 0.4.25/47, label "Combined parity")

**Deferred (carried to a later build):**
- **Stand mode in Combined** doubles instead of splitting (each Voltra stands to 60 instead of 30/30 split). User flagged as low priority.
- **Dampers in Combined** — level 1 maps to level VIII per side; user flagged as low priority.
- **Bands in Combined** — same family of issues. Low priority.
- **HealthKit permission prompt** still doesn't fire on session start despite the b46 entitlement fix. The fix did help delivery (HR/kcal now flow steadily per user feedback), but the in-Settings Health row appearance and the first-launch system prompt still need investigation. Likely related to the `healthkit.access` key being baked into the App Store provisioning profile in the developer portal — needs profile regen.
- **Independent mode HR slight delay** — user OK with this.

**Test plan after TestFlight install:**
1. Pair both Voltras → mode picker should now show **Superset** alongside Combined / Independent. Pick Superset. Banner should appear above the grid with NOW (active, accent), SWAP, NEXT (dimmed). Initial active = LEFT.
2. Tap **SWAP** → active flips to RIGHT, weight retargets to right Voltra's stored value, banner sides swap.
3. Pair both → pick **Combined**. Tap UNLOAD → BOTH Voltras unload (was the bug). Tap LOAD → BOTH load.
4. In Combined: nudgers should show **−6 / +6** (top row) and **−2 / +2** (bottom row). Tap any → weight stays even.
5. Switch from Independent at an odd weight (e.g. 35) into Combined → on entry, weight rounds DOWN to 34.
6. In Combined start drop-cascade from 30 lb → expect 30 → 24 → 18 → 12 → 6 → BOTTOM (even steps only).
7. Switch to Independent → nudgers should be **−5 / +5** and **−1 / +1** again.
8. Single-Voltra and singleLeft / singleRight modes should still work (no regressions).


## b48 — v0.4.26 (build 48) — "Superset chain"

**Date:** 2026-04-28
**Goal:** Iterate on b47's Superset MVP based on the user's first hands-on feedback. Make Superset a real chain-builder: assign each exercise to a specific Voltra at the per-exercise screen, add an "Add Another Superset" CTA that pops back to the day-tile screen so the user can chain N exercises together, surface the real exercise names on the live banner, and fix LOAD/UNLOAD so it only fires the active Voltra in Superset mode.

**User direction (verbatim, this session):**
- "the moment you select the first part of the superset, you just sign it. you will need to assign it to the Voltra. and then after that, to main menu. we have the main menu with the tile selection where it says leg day, back day, chest day, arm day so that you can select your next set."
- "instead of start set It should be there should be another button under it. it says Add Another Superset. and then that should take you back up to the main tile screen."
- "you also need to wait. to indicate which Voltra. this specific activity is going to use. he should be able to select that. so it should be in the superset mode right under the title of the set she show you right or left? Voltra and you just click one therou activate."
- "and then to the very bottom it should have a 'add another superset'. and that'll take you out back to the main tile screen without having to select the superset again. so that you can chain these activities together and then select to write Voltra to sighted you, and you swap back and forth."
- "Swapping back and forth mechanism I see works well." (preserve)
- "you have now exercise A that should be... the name of the exercise. the other name of the exercise [should show, not 'A/B']."
- "Unload Tonsion isn't tied to whatever exercise A or B it's on, it unloads both of them, which is not the intended behavior." → LOAD/UNLOAD active-side only in Superset.
- "I also didn't get the prompt for the health kit." (deferred again — see below)
- Autonomy: "you let it all. I'm going to bed, so use your discretion. to keep it going without needing my input."

**Fixes & features:**

- **A — Per-exercise Voltra assignment in Superset.** ExerciseDetailView (the screen that opens after picking an exercise from a day tile) now shows an "ASSIGN TO VOLTRA" picker at the very top when `mdm.workoutMode == .superset`, with two big LEFT / RIGHT buttons. The user taps one to bind THIS exercise to a specific Voltra slot. A small chip shows "#N IN CHAIN" once the chain has at least one entry so the user knows where they are. The picker pre-selects LEFT for even-indexed entries and RIGHT for odd ones, so a user who just taps through gets natural alternation. Same UI added to ExerciseStartView for the alternate flow.

- **B — "Add Another Superset" CTA chains exercises.** Right under the "Start set N" button, when in Superset mode, ExerciseDetailView (and ExerciseStartView) now shows an "Add Another Superset" button. Tapping it stamps THIS exercise into the chain (`mdm.appendSupersetEntry`), then bumps `mdm.supersetReturnToHomeTick`. LoggingHomeView watches that tick and unwinds the navigation stack back to the day-tile screen. The user is now back at "leg day / back day / chest day / arm day" without ever leaving Superset mode — they pick another exercise, assign it to a Voltra, and either chain again or hit Start to enter the live grid.

- **C — Real exercise names on the live banner.** The Superset banner in LiveCaptureView now reads `mdm.activeSupersetEntry?.exerciseName` and `mdm.nextSupersetEntry?.exerciseName` for the NOW and NEXT chips respectively. So instead of the b47 stub "Exercise A / Exercise B", the user sees "Back Squat / Bent-Over Row" (or whatever they picked). Falls back to the old per-side label cache if the chain isn't populated, then to A/B if nothing is set.

- **D — LOAD/UNLOAD in Superset = active side only.** `MultiDeviceManager.slotsForWorkoutMode()` previously routed LOAD/UNLOAD to BOTH sides in Superset (bundled with combined/independent). Per b48 user feedback, that unloaded the OTHER exercise's Voltra mid-rest, which broke the chain. Now Superset routes to `[supersetActiveSlot]` only. Combined still hits both — the b47 "fires both sides" fix for combined LOAD/UNLOAD is preserved.

- **E — Chain data model in MultiDeviceManager.** New nested struct `SupersetChainEntry { id, exerciseName, slot, plannedWeightLb }`. New published props `supersetChain: [SupersetChainEntry]`, `supersetChainIndex: Int`, `supersetReturnToHomeTick: Int`. New methods `appendSupersetEntry`, `clearSupersetChain`, `requestSupersetReturnToHome`, `flipSupersetActiveSlot` (now chain-aware: 2+ entries → advance index modulo length; <2 entries → toggle left/right as before). Computed `activeSupersetEntry` and `nextSupersetEntry` for view consumption.

- **F — SWAP is chain-aware.** LiveCaptureView's `swapSupersetSide` now restores weight from `mdm.activeSupersetEntry?.plannedWeightLb` first, falling back to the per-side weight cache. So in a chain of 3+ exercises, each exercise remembers its own starting weight and SWAP cycles through them in order.

- **G — Chain lifecycle.** Chain clears on session end (LoggingHomeView watches `sessionExitTick` and calls `mdm.clearSupersetChain()`). Chain also clears when the user changes WorkoutMode in the picker (WorkoutVoltraPickerSheet drops the chain on mode-change confirmation).

**Files changed:**
- VoltraLive/BLE/Dual/MultiDeviceManager.swift (chain model, append/clear, return-home tick, chain-aware flip + active/next computed props, slotsForWorkoutMode case for superset = active only)
- VoltraLive/Logging/Views/ExerciseDetailView.swift (supersetSlotPicker, addAnotherSupersetButton, commitChainEntryFromCurrentState, default-slot pre-select on appear)
- VoltraLive/Logging/Views/ExerciseStartView.swift (same UI for the smart-start screen)
- VoltraLive/Logging/Views/LiveCaptureView.swift (banner reads chain entry names, swap restores chain entry weight)
- VoltraLive/Logging/Views/LoggingHomeView.swift (onChange: mdm.supersetReturnToHomeTick → pop to root; onChange: sessionExitTick → also clearSupersetChain)
- VoltraLive/Views/WorkoutVoltraPickerSheet.swift (clearSupersetChain on mode change)
- VoltraLive/Info.plist + project.yml (bumped to 0.4.26/48, label "Superset chain")

**Deferred (still — see b47 entry):**
- **HealthKit first-launch prompt.** User confirmed again in b48 feedback: "I also didn't get the prompt for the health kit on the soil as well." HR/kcal continue to flow from the b46 entitlement fix, but the system permission prompt + the in-Settings Health row still don't appear. Likely cause is the App Store provisioning profile in the Apple Developer portal still has `com.apple.developer.healthkit.access` baked in, which the IPA inherits even though our local entitlements file doesn't declare it. Action item for next build: regenerate the App Store provisioning profile in the portal, or write a build-time check that strips the profile-injected `healthkit.access` key from the embedded entitlements before re-signing. The dry-run "Verify embedded entitlements" step has been showing this clean for the local file — the discrepancy is between local entitlements vs. profile-injected.
- **Stand-mode in Combined doubles instead of splits.** Low priority.
- **Dampers in Combined map level 1 → level VIII per side.** Low priority.
- **Bands in Combined.** Same family. Low priority.

**Test plan after TestFlight install:**
1. Pair both Voltras → mode picker → Superset → Start Workout.
2. Tap LEG DAY tile → pick "Back Squat" exercise → land on the exercise screen.
3. Verify the new "ASSIGN TO VOLTRA" picker at the top with LEFT / RIGHT buttons. Pick LEFT.
4. Verify a new "Add Another Superset" button appears below the existing Start button.
5. Tap "Add Another Superset" → app pops back to the day-tile screen ("PICK A DAY"). You should still be in Superset mode (no need to re-pick).
6. Tap BACK DAY tile → pick "Bent-Over Row" → land on its exercise screen. The slot picker should auto-pre-select RIGHT (alternation). Verify "#2 IN CHAIN" appears in the picker header.
7. Tap "Start set 1" instead of Add Another → you land on the live grid.
8. Banner above the grid should read NOW: Back Squat (LEFT, accent) and NEXT: Bent-Over Row (RIGHT, dimmed). Real names, not "Exercise A / B".
9. Tap UNLOAD → ONLY the LEFT Voltra unloads. Right stays loaded. (b48 fix.)
10. Tap SWAP → banner flips to NOW: Bent-Over Row (RIGHT) / NEXT: Back Squat (LEFT). Weight retargets to whatever you picked for the row.
11. Tap UNLOAD again → only RIGHT unloads now.
12. Optional: chain a third exercise and verify SWAP cycles 1 → 2 → 3 → 1 → 2 → ...
13. Switch to Combined → confirm chain is cleared and combined routing still hits both sides on LOAD/UNLOAD (b47 regression check).


---

## 2026-04-28 — Post-b48: cost-awareness convention + HK council prompt

Not a build. Documentation/process change while waiting for user to run
the HealthKit council prompt.

**User established a persistent preference, applies to all future sessions
and any agent picking up this repo:**

1. **Cost-awareness bucketing.** Flag every medium-or-heavier action
   inline as lite / medium / heavy / very heavy before running, with a
   one-line cost callout after heavier ones. Buckets are mental-model
   order-of-magnitude only — no specific credit counts ever (the agent
   does not have a per-action meter; user's Computer settings/billing
   page is the source of truth).
2. **Council/heavy-research delegation by default.** The user has a
   Perplexity model council on their own account. When a task would
   benefit from a model council OR from heavy multi-source research, the
   agent DRAFTS a self-contained prompt at
   `docs/handoff/COUNCIL_*_PROMPT.md` for the user to run. The user runs
   it and reports back; the agent acts on the result. Only run heavy
   work directly on Computer when the user explicitly says "do it
   yourself" or "do the work yourself."

**Files changed:**
- `AGENTS.md`: new top-level section "Cost-awareness convention (user
  preference, persistent)" with the full bucketing rubric and council
  delegation rule.
- `docs/handoff/00_START_HERE.md`: pointer to the AGENTS.md section so
  agents reading docs in order also catch it; index of existing council
  prompts.
- `docs/handoff/COUNCIL_HEALTHKIT_PROMPT.md` (new): self-contained
  council prompt for the b47/b48-deferred HealthKit
  prompt-on-fresh-install bug. Includes confirmed facts (entitlements
  file contents, Info.plist HK strings, CI verify-step proof that
  `com.apple.developer.healthkit` IS embedded in the signed IPA, app-side
  code calling `requestAuthorization` from `WindowGroup.onAppear`),
  hypotheses already ruled out, 7 candidate root causes, and an explicit
  "How to respond" section asking for: most likely root cause, a
  pre-build verification step, fix recommendation for b49, confidence
  level, backup hypothesis, citations. Capped at ~800 words for council
  efficiency.

**Also stored in user memory** (carries across sessions even if this repo
is cloned fresh by another agent) under
`preferences.research.heavy_tasks`.

**Status:** Awaiting user to run `COUNCIL_HEALTHKIT_PROMPT.md` in their
Perplexity model council and report back. b49 plan will be derived from
the council's recommendation. No other b49 features in flight.

**Cost callout for this change:** lite. File reads, two edits, one
markdown write, one memory write, one commit/push. No subagents, no
polling loops, no model calls beyond this conversation.
