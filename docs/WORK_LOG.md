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


---

## 2026-04-28 — b49 (v0.4.27/49) — Unified flow + HK fix

One ship bundling: the HealthKit first-launch prompt fix the council
diagnosed, the unified Independent/Superset flow refactor the user
asked for after b48 hands-on testing, and a bundle of telemetry display
bug fixes from the same b48 feedback round.

**HealthKit fix (council-diagnosed):**

Council answer matched the b48 deferred hypothesis: the App Store
provisioning profile has the full HealthKit capability bundle stamped
on it (all three keys: `.healthkit`, `.healthkit.access`,
`.healthkit.background-delivery`), but the app-side entitlements only
declared `.healthkit = true`. iOS 17+ silently rejects the HK
authorization request when the embedded entitlements don't match what
the profile granted, with no Settings → Health row, no first-launch
prompt, nothing.

Fix is app-side only: declare all three keys in the entitlements file
to match the profile. Empty `<array/>` on `.access` per Apple's
developer docs (no usage strings required when array is empty;
.share/.read are gated by the in-app `requestAuthorization` call which
already names the types correctly).

- `VoltraLive/VoltraLive.entitlements`: added
  `com.apple.developer.healthkit.access = <array/>` and
  `com.apple.developer.healthkit.background-delivery = true`.
- `.github/workflows/release.yml`: hardened the CI "Verify embedded
  entitlements" step. Old version did a substring grep on the binary
  plist, which silently passed when the profile injected the key but
  the app didn't declare it. New version uses `plistlib` to parse the
  embedded entitlements XML and asserts ALL THREE keys present with
  exact key match (no false positives from substring overlap).

**Unified flow refactor:**

User feedback after b48: "Independent mode and Superset are
functionally identical when there are 2 paired Voltras. Superset is
just a TAG, like a rolling dot. Don't make me pick a mode." The b46–b48
WorkoutMode picker is gone. Flow is now: pair Voltras → day tile →
exercise screen. WorkoutMode is auto-derived from paired-device count
(1 paired → singleLeft/singleRight, 2 paired → independent). Combined
stays as a same-bar use case via a "Merge" button on the exercise
screen (b47 math is unchanged underneath).

The Superset tag is a toggle in the exercise screen's top panel that
locks at first set start. SWAP rebuilt as a full exercise-context swap:
auto-end the in-flight set, navigate to the other entry's screen, auto-
LOAD the incoming side and UNLOAD the outgoing one. Same exercise on
both sides is now allowed.

- `VoltraLive/Logging/Views/LoggingHomeView.swift`: `commitStart()`
  auto-derives `workoutMode` from paired count.
- `VoltraLive/BLE/Dual/MultiDeviceManager.swift`: added `supersetTag`,
  `supersetTagLocked`, `lockSupersetTag()`, `hasActiveSupersetChain`,
  `soloVoltraConnected`. Fixed a duplicate `let entry` compile error
  in `appendSupersetEntry()`.
- `VoltraLive/Logging/Views/ExerciseDetailView.swift`: `dualVoltraTopPanel`
  shows a slot picker + Merge button + Superset tag dot whenever both
  Voltras are paired, regardless of mode. `addAnotherExerciseButton`
  renamed from "Add Another Superset" since it works in both flows.
  Removed the `inSupersetMode` shim — everything reads
  `showsDualVoltraPanel` (paired count).
- `VoltraLive/Logging/Views/ExerciseStartView.swift`: mirror — gates only
  on dual-paired, not workoutMode.
- `VoltraLive/Logging/Persistence/LoggingStore.swift`: exposed
  `cascadeIntervalSecondsForUI` and `cascadeIdleFinalizeSecondsForUI`
  for UI sync; added `switchActiveInstanceByExerciseName(_:)` so SWAP
  can flip the LoggingStore's active instance to the other exercise.
- `VoltraLive/Logging/Views/LiveCaptureView.swift`: rebuilt
  `swapSupersetSide()` as a full context swap (force-finalize → unload
  outgoing → flipSlot → switchInstance → restore weight → push state →
  load incoming). Added `.onChange(of: session.currentSet != nil)` →
  `mdm.lockSupersetTag()` so the tag locks at set 1 start.

**Telemetry display bug fixes (b48 hands-on):**

1. Drop-set bars sync. b48 hardcoded `4.0` for the cascade interval
   progress bar but the actual cascade interval is `2.0`. Bars now
   read `cascadeIntervalSecondsForUI` so the visual matches the timer.
   `VoltraLive/Logging/Views/LiveCaptureView.swift`.
2. Rest activation timer −2s. Rest was anchoring to `Date()` at set
   end, but the IDLE_GRACE window already burned 2s of "no movement"
   before the boundary fired, so the user saw a 2s lag before the
   timer started moving. Backdate `restStartedAt` by 2.0s in
   `SessionStore.finalizeSet`.
3. Reps + force display in Independent and Superset modes. b48
   regression: `onLeftTelemetry`/`onRightTelemetry` were ALWAYS routing
   into `SessionStore.handleLiveSample` regardless of `supersetActiveSlot`,
   so the inactive side's telemetry kept overwriting reps/peak. Now
   only the active slot's stream feeds SessionStore in `.independent`
   and `.superset` modes. `.combined` still merges both via the virtual
   twin. `VoltraLive/VoltraLiveApp.swift`.
4. Force graph: 2 distinct labeled traces during a superset.
   `SessionStore.lastFinalizedByExercise: [String: [ForceSample]]` is
   populated at the end of `LoggingStore.autoLogTelemetrySet` keyed by
   the active instance's exercise name. `ForceChartView` got optional
   `secondarySamples` + `primaryLabel` + `secondaryLabel` parameters and
   renders the secondary as a dimmed dashed trace behind the primary
   phase-colored trace, with the two exercise names in the legend.
   `LiveCaptureView.forceChart` wires it on whenever a 2+ chain is
   active and the other entry has a stashed trace.
5. Set logging supersetTag session metadata. New
   `WorkoutSession.supersetTag: Bool` SwiftData field (additive,
   default false) is stamped from `mdm.supersetTag` right before
   `endSession()`. Per-exercise attribution already works correctly
   via SWAP flipping the active ExerciseInstance — each LoggedSet
   inherits the correct exercise from `instance` at insert time.

**Files changed:**

- VoltraLive/VoltraLive.entitlements (HK fix)
- .github/workflows/release.yml (CI verify hardening)
- VoltraLive/Logging/Views/LoggingHomeView.swift (auto-derived workoutMode)
- VoltraLive/BLE/Dual/MultiDeviceManager.swift (tag, lock, helpers, dup-fix)
- VoltraLive/Logging/Views/ExerciseDetailView.swift (dualVoltraTopPanel)
- VoltraLive/Logging/Views/ExerciseStartView.swift (paired-count gate)
- VoltraLive/Logging/Persistence/LoggingStore.swift (UI helpers, switchInstance, lastFinalizedByExercise population)
- VoltraLive/Logging/Views/LiveCaptureView.swift (drop-bar sync, full SWAP, tag lock, force-chart 2-trace, supersetTag session-end stamp)
- VoltraLive/Session/SessionStore.swift (rest -2s backdate, lastFinalizedByExercise dict)
- VoltraLive/VoltraLiveApp.swift (active-slot telemetry routing)
- VoltraLive/Logging/Model/LoggingModels.swift (WorkoutSession.supersetTag additive field)
- VoltraLive/Views/ForceChartView.swift (secondarySamples/labels)
- VoltraLive/Info.plist + project.yml (bumped to 0.4.27/49, label "Unified flow + HK fix")

**Closed deferred items:**
- HealthKit first-launch prompt (council-diagnosed, fixed in this build).

**Cost callout for this build:** medium. Multi-file refactor with one
SwiftData additive-field migration, one Charts API extension, no
subagents, single dry-run + ship cycle.

**Test plan after TestFlight install:**

1. Fresh install → HK prompt appears at first launch.
2. VOLTRA Live appears under Settings → Health → Data Access & Devices.
3. HR/kcal flow live during a workout.
4. Pair 1 Voltra → day tile → exercise screen → only that side, no picker.
5. Pair 2 Voltras → day tile → exercise screen → L/R picker + Merge + Superset tag dot.
6. Tap Merge → b47 Combined math live.
7. Add second exercise → auto-assigns unused side → Superset tag visible.
8. Toggle Superset ON → start set 1 → tag locks (read-only after).
9. Reps + force display live during the set on the active side only.
10. Drop-set timer matches progress bar (2s = 2s).
11. Rest timer starts immediately at set end (no 2s lag).
12. Force graph: 2 distinct labeled traces with exercise names.
13. Tap SWAP mid-set → set auto-ends, app loads other exercise's screen, new side auto-LOADs.
14. Set 2 logs under correct exercise name.
15. End session → SwiftData WorkoutSession.supersetTag = true; post-workout shows the tag.

## 2026-04-28 16:21 UTC — b50 (v0.4.28/50) — Chain routing fix

User reported on b49 hands-on: with two Voltras paired and a 2-exercise
chain, (a) the SWAP/active-side banner was missing entirely at the top
of LiveCapture, (b) LOAD wrote the same weight to both Voltras instead
of just the active one, (c) reps/force never displayed once a chain
was active, and (d) with a single Voltra paired, LOAD pushed the wrong
resistance — the device kept the previous session's value rather than
resetting to the exercise's starting weight. Diagnosis: the b49
unified-flow auto-derives `workoutMode = .independent` for any
2-Voltra session, and several routing paths still switched on
`workoutMode` instead of the chain. Cache reset on session entry was
also absent. Fixes:

1. **Chain-first routing principle.** Whenever `mdm.hasActiveSupersetChain`
   (chain.count ≥ 2), both writer fan-out and LOAD/UNLOAD fan-out
   target `mdm.supersetActiveSlot` only, bypassing `workoutMode`
   entirely. Implemented in `WriterRouter.apply` and in
   `MultiDeviceManager.slotsForWorkoutMode()` (now chain-first
   short-circuit at the top of both).
2. **Banner gate fix.** `LiveCaptureView` previously gated the
   SWAP/active-side banner on `mdm.workoutMode == .superset`, which
   the b49 unified flow never sets. Now gated on
   `mdm.hasActiveSupersetChain`.
3. **`appendSupersetEntry` realignment.** Previously only set
   `supersetActiveSlot` for the FIRST entry in a chain, so subsequent
   appends left the active slot stale and reps/force never displayed
   on the newly-added exercise. Now always sets
   `supersetChainIndex = chain.count - 1` and
   `supersetActiveSlot = slot` whenever an entry is appended.
4. **Writer cache reset on session entry.** `VoltraWriter.applied`
   cache persisted across sessions, so a 1-Voltra LOAD found "no
   delta" and the device kept its previous value. Now
   `writerRouter.resetAppliedState()` plus
   `mdm.leftWriter.resetAppliedState()` and
   `mdm.rightWriter.resetAppliedState()` are called on
   `LiveCaptureView.onAppear` (every time) and on
   `ExerciseDetailView.onAppear` (first-init only via a
   `@State didReset` guard).

**Files changed:**

- VoltraLive/BLE/WriterRouter.swift (chain-first routing)
- VoltraLive/BLE/Dual/MultiDeviceManager.swift (chain-first
  slotsForWorkoutMode + appendSupersetEntry always realigns active slot)
- VoltraLive/Logging/Views/LiveCaptureView.swift (banner gate on
  hasActiveSupersetChain; onAppear writer-cache reset)
- VoltraLive/Logging/Views/ExerciseDetailView.swift (first-init
  writer-cache reset)
- VoltraLive/Info.plist + project.yml (bumped to 0.4.28/50, label
  "Chain routing fix")

**Verification:** code review only; awaiting TestFlight install.

**Risks:** chain-first short-circuit changes the behavior of
`slotsForWorkoutMode()` for any future caller that explicitly wanted
fan-out while a chain was active; none today, but flag in code review.

**Cost callout for this build:** lite. Five-file targeted fix, no
subagents, no migrations.

**Not a bug (avoid chasing in next session):** App showing 95 lb total
when device shows 70 base + 25 ecc is correct — app shows total,
device shows components separately.

**Test plan after TestFlight install:**

1. Pair 2 Voltras, start a session, add a 2nd exercise (auto-assigns
   to the unused side, chain length = 2).
2. Banner with SWAP/Merge/Superset tag dot appears at the top of the
   exercise screen — the b49 regression where it was missing entirely
   should be gone.
3. Tap LOAD on set 1 of the active exercise — only the active-side
   Voltra's resistance changes; the other Voltra's weight is
   untouched.
4. Force/reps display live on the active side only.
5. Tap SWAP — banner highlights the other side, that exercise's set
   begins, LOAD now writes only to the newly active Voltra.
6. End session and start a fresh single-Voltra session — first LOAD
   writes the correct exercise starting weight to the device, not the
   stale value from the previous session.

## 2026-04-28 18:55 UTC — b51 (v0.4.29/51) — Telemetry + UI fixes

User reported on b50 hands-on: with two Voltras paired, reps and force
never displayed in any 2-Voltra mode (chain or merge); single-Voltra
worked. Plus a list of 10 UI corrections: resistance tile conflated
base + ecc + chains into one number, ± stepper appeared to change
all overlays, no way to toggle ecc/chains motors without losing
values, chain auto-started on the second-added exercise (B) instead
of the first (A), couldn't tell which Voltra was active during reps,
SWAP button placement was unclear, drop-set weights landed on
fractional pounds (e.g. 92.5), Merge with odd totals split unevenly
across the two Voltras, the always-on HK badge on Home didn't
reflect anything actionable, and the Connected pill said "Left
connected" / "Connected" instead of just side-with-dot. All 11 fixes
in one build:

1. **Telemetry root-cause.** `LiveCaptureView` reads `ble.telemetry`
   for the reps + force tiles, but `bleManager.telemetry` is only
   ever updated when the singleton itself decodes BLE frames (i.e.
   single-Voltra pairings). With 2 Voltras, frames decode in
   `multi.left` / `multi.right`, fire `onLeftTelemetry` /
   `onRightTelemetry`, route through `telemetryHandler` → SessionStore
   only — never touching `bleManager.telemetry`. Fix: added a public
   `VoltraBLEManager.ingestRoutedTelemetry(_:)` that wraps the
   private `mergeTelemetry`, and the unified `telemetryHandler`
   in `VoltraLiveApp` now calls it on every routed packet (both per-
   side handlers and the combined virtual-twin handler). One change
   covers chain mode AND merge mode.
2. **Resistance tile redesign.** Headline = base weight only (Voltra
   concentric, after pulley multiplier). Eccentric and chains overlays
   render as separate rows below the headline. Pre-b51 the headline
   was `perRepTotalLb` (base + ecc + plates) so the displayed number
   jumped whenever any overlay changed.
3. **± stepper now visibly changes only the base.** No code change to
   `adjustWeight` itself (it was already correct under the hood) —
   the user's perception was driven by (2). Fixed by (2).
4. **Tap-to-toggle motor on/off.** New `LoggingStore` flags
   `upcomingEccEnabled` and `upcomingChainsEnabled`; tapping the
   ecc icon (`arrow.down.to.line`) or chains icon (`link`) flips
   the flag and re-pushes device state. The lb value is preserved
   when off (strikethrough + dim), restored on tap-on.
5. **Chain start ordering.** `appendSupersetEntry` previously set
   `supersetActiveSlot` to the slot of the just-appended entry,
   meaning the chain started at exercise B (the second add). Now
   when chain.count >= 2 the active slot snaps back to chain[0]'s
   slot (exercise A, the first add). Single-entry behavior unchanged.
6. **Active-side indicator.** Banner active card now has a pulsing
   accent dot, "ACTIVE • LEFT/RIGHT" label, accent-tinted background,
   and accent stroke. Inactive side stays dim.
7. **SWAP button placement.** Already between the two side cards;
   redesigned as a circular accent button with a left-right arrow so
   the action reads visually as "swap left ↔ right."
8. **Drop-set whole-number rounding.** Cascade `roundingLb` changed
   from 2.5 → 1.0 in both live cascade math and preview math.
   Combined mode keeps 2.0 so the per-side split is even. Pulley-
   mode device coordinate re-round also moved to 1.0.
9. **Merge even-snap.** Tapping Merge in `ExerciseDetailView` now
   snaps `pendingPlannedWeightLb`, `upcomingEccLb`, and
   `upcomingChainsLb` to the next even integer before flipping
   `mdm.workoutMode = .combined`. ± stepper continues to enforce
   even via `CombinedParity.enforce` while merged.
10. **Home: real-time telemetry pulse pill.** Replaces the always-on
    HK badge. Reads `ble.telemetry.lastUpdate`; lights LIVE when
    the last packet was within 2s, WAIT when stalled, IDLE when
    nothing is paired. A 1 Hz timer drives freshness check via
    `@State now`. Tap = HK re-prompt (preserving b35's recovery path).
11. **Home: side-aware Connected pill.** When 1 Voltra paired, shows
    `Left •` or `Right •` (no word "Connected"). When both paired,
    shows `Left •` and `Right •` side-by-side. Legacy single-device
    fallback still says "Voltra •".

**Files changed:**

- VoltraLive/BLE/VoltraBLEManager.swift (public ingestRoutedTelemetry)
- VoltraLive/VoltraLiveApp.swift (telemetryHandler mirrors into bleManager)
- VoltraLive/Logging/Persistence/LoggingStore.swift (upcomingEccEnabled,
  upcomingChainsLb, upcomingChainsEnabled, drop cascade rounding 2.5→1.0)
- VoltraLive/Logging/Views/LiveCaptureView.swift (resistance tile
  redesign, modOverlayRow, banner stronger active indicator, SWAP
  redesign, push state honors enabled flags + chains)
- VoltraLive/BLE/Dual/MultiDeviceManager.swift (chain start at index 0
  when count >= 2)
- VoltraLive/Logging/Views/ExerciseDetailView.swift (Merge even-snap,
  surface chains via upcomingChainsLb)
- VoltraLive/Logging/Views/LoggingHomeView.swift (telemetryPulsePill,
  side-aware connectionPill, 1 Hz pulseTimer)
- VoltraLive/Info.plist + project.yml (bumped to 0.4.29/51, label
  "Telemetry + UI fixes")

**Verification:** code review only; awaiting TestFlight install. The
b50-era DropSetCascadeTests still pass mathematically since 5 lb
steps already land on whole numbers; the rounding change only
affects fractional outputs.

**Risks:**
- Resistance tile minHeight stayed at 88pt but now hosts up to 4
  vertical elements (headline, ecc row, chains row, subline). If a
  user has all four populated, the tile may exceed 88pt and reflow
  the grid. Acceptable; LazyVGrid handles unequal heights.
- Pre-b51 sessions in flight will have `upcomingEccEnabled = true`
  by default; no migration needed.

**Cost callout for this build:** medium. 11 changes across 7 files,
including UI redesigns and one root-cause fix.

**Test plan after install:**

1. **Telemetry on 2 Voltras (the big one).** Pair both, start a
   chain (A then B), tap Start → reps + force tiles update on the
   active side. SWAP → tiles continue updating on the new active
   side. Same with Merge: reps + force show summed from both sides.
2. **Chain starts on A.** Pick A, then "Add Another Exercise", pick
   B, tap Start → banner says "ACTIVE • LEFT" (or whichever side A
   was assigned), not B's side.
3. **Active side is unmistakable.** Pulsing dot + accent fill on
   active card; inactive is dim.
4. **Resistance tile.** Headline = base weight only. Tap +5 → only
   the headline changes; ecc/chains rows stay at their values.
5. **Ecc / chains tap-to-toggle.** Tap the down-arrow icon → ecc row
   strikes through and dims, motor disengages on the device.
   Tap again → restores the same value, motor re-engages.
6. **Drop-set whole numbers.** Start a drop cascade from 100 lb →
   weights are 95, 90, 85... no 92.5 / 87.5.
7. **Merge even-snap.** On pre-start screen with base 65, tap Merge
   → base snaps to 66; per-side split is 33 / 33 not 32.5 / 32.5.
8. **Home pulse pill.** With a Voltra streaming, dot pulses LIVE.
   Power off the Voltra → pill drops to WAIT within 2s. Unpair →
   IDLE.
9. **Home connected pill.** 1 Voltra paired → just `Left •` or
   `Right •`. Both paired → `Left • Right •`. Neither → `Not paired`.

---

## b52 — Chain logging + summary (v0.4.30 / build 52)

**Tag:** v0.4.30-build52
**Feature label:** Chain logging + summary

**The five b51 hands-on issues this build fixes**

After b51 install the user reported, while running a 2-Voltra chain
session:

- **A.** During supersets, sets are logging under the wrong exercise.
- **B.** With both Voltras paired, opening exercise A on the LEFT
  Voltra also loads A onto the RIGHT, even though only LEFT is
  supposed to be active. Same when adding a second exercise B —
  both flip to B even though A is supposed to stay parked on
  the other side.
- **C.** Summary screen lacks per-exercise heart rate, calories,
  total volume, peak/avg force.
- **D.** When chaining, the pre-start screen still defaults to the
  most recently picked exercise (B). It should land on the chain
  HEAD (A) since that's what the user lifts first.
- **E.** Chain summary only shows sets from the LAST exercise (the
  rest disappear), and rows aren't labeled with which exercise
  they belong to.

User picks for the open product questions: peak force per set + average
peak across sets; all five issues + summary telemetry land in one
medium-cost build (b52); HK snapshot at instance end (no live polling).

**Root cause analysis, in one paragraph**

`LoggingStore.activeInstance` is a single pointer that only flips when
the SWAP button explicitly calls `switchActiveInstanceByExerciseName`.
But `mdm.supersetActiveSlot` (which routes BLE writes and, since b51,
attributes telemetry to a side) can change without SWAP being tapped —
e.g. on chain entry-2 add, or via the slot indicator. So
`activeInstance` (the SwiftData side) and `supersetActiveSlot` (the BLE
side) drift out of sync, and telemetry-detected sets end up under
whichever instance was active at session-start instead of the one the
user is actually lifting (Issue A → reproducible 100% of the time when
the user adds a second chain entry without tapping SWAP). `WriterRouter`
broadcasts to BOTH Voltras unless `mdm.hasActiveSupersetChain` is true,
which requires `supersetChain.count >= 2` — so a 1-entry chain (the
state right after picking A but before adding B) routes via the
`.independent` fall-through which writes to both connected devices
(Issue B). And the chain HEAD-snap restore that b51 wired into
ExerciseStartView doesn't propagate down to LoggingStore — the user
sees "Set 1 — A" labeling but `activeInstance` still points at B
(Issue D, the LoggingStore mirror of A).

The summary regression (Issues C+E) is a separate gap: there's no
per-instance HR/kcal/volume/peak rollup, and `markdownExport` was
already grouping by instance — so E "only records last activity" is
actually a downstream effect of A (sets attributed to the wrong
instance => only the last instance has any sets), not its own bug.
With A fixed, E1 ("only last activity recorded") falls out for free.
E2 ("sets unlabeled") is a presentation gap fixed by adding a per-row
exercise tag in the rebuilt cards.

**Code changes (5 files modified, 1 new doc)**

1. **`MultiDeviceManager.hasAnySupersetChainEntry: Bool`** — new
   predicate (count ≥ 1, both connected). Distinct from the
   pre-existing `hasActiveSupersetChain` (count ≥ 2, both
   connected) which gates SWAP-style routing. The 1-entry case
   needs to route to the active slot only, not broadcast.
2. **`WriterRouter.apply`** — replace the `if hasActiveSupersetChain`
   guard with `if hasAnySupersetChainEntry`. Result: a chain with one
   entry now writes to the active slot only, not both Voltras
   (Issue B).
3. **`LiveCaptureView`** — `.onChange(of: mdm.supersetActiveSlot)`
   now calls `switchActiveInstanceByExerciseName(entry.exerciseName)`
   when no set is currently mid-rep, so the SwiftData
   activeInstance follows BLE side flips (Issues A + E1). And in
   `.onAppear`, when `mdm.supersetChain.count >= 2`, we restore
   activeInstance + pendingPlannedWeightLb + cascade re-anchor +
   push the chain HEAD's planned state to the device (Issue D).
4. **`HealthKitStore.snapshotInstance(start:end:) async`** — new
   windowed snapshot returning `InstanceSnapshot(avgHR, kcal)`.
   Uses `HKStatisticsQuery.discreteAverage` for HR and
   `.cumulativeSum` for active energy. `#if !canImport(HealthKit)`
   fallback returns nil so the `WITH_HEALTHKIT=0` build path
   compiles.
5. **`ExerciseInstance` schema** — additive fields
   `avgHRDuringInstance: Double? = nil`,
   `kcalDuringInstance: Double? = nil`. SwiftData migration is
   safe (defaults present, optional types). Plus computed
   rollups: `totalReps`, `totalVolumeLb`, `peakForceLb`,
   `avgPeakForceLb`, `duration`.
6. **`LoggingStore`** — `wire()` now takes an optional
   `healthStore: HealthKitStore?`. `finalizeActiveInstance`
   captures the instance reference, then fires an async
   `Task { @MainActor }` that awaits `snapshotInstance` and
   writes avg HR + kcal onto the instance and saves the context.
   Failure (HK denied / unavailable / no samples in the window)
   leaves the fields nil — the summary view tolerates missing
   values. **Side effect**:
   `switchActiveInstanceByExerciseName` now matches by name
   regardless of `endedAt` and *re-opens* a paused chain entry
   (clears `endedAt`) so chain navigation back to A after going
   to B keeps logging into A correctly. The final `endedAt` is
   stamped at `endSession()`.
7. **`ExportSheet`** — new `instanceCard(_:)` rendered in a
   `ForEach` above the markdown blob. Each card shows the
   instance ordinal + exercise name + equipment, a list of set
   rows (`Set N — w × reps — peak`), and a rollups row
   (`REPS / VOL / PEAK / AVG PK / DUR`) with an optional
   `AVG HR / KCAL` row beneath when HK captured them. Each set
   row carries the exercise name as a trailing dim tag so
   chain-summary scanning is unambiguous (Issue E2).
8. **`markdownExport`** — adds `Peak lb` column to the per-set
   table, a `Totals:` line per exercise (sets, reps, vol, peak,
   avg peak, duration), and a `Vitals:` line when HR/kcal are
   present. Section headers now include the order index
   (`1. Belt Squat (Voltra)`).
9. **`docs/handoff/B52_DIAGNOSIS.md`** — new 274-line root-cause
   doc keeping the multi-source mental model in one place for
   the next session.

**Sacred files untouched.** No changes to `VoltraProtocol.swift`,
`TelemetryExtractor.swift`, `PacketParser.swift`,
`FrameAssembler.swift`.

**SwiftData migration**: additive only. New fields default to nil,
existing rows decode unchanged.

**Cost callout for this build:** medium. 5 source files changed +
1 new HK API + an additive SwiftData migration + a partial export
view rewrite. No protocol or BLE state-machine churn.

**Test plan after install**

1. **Pair both Voltras → pick A on LEFT → Start.** Banner says
   `ACTIVE • LEFT`, only the LEFT Voltra applies the load (Issue B).
2. **Add Another Exercise → pick B on RIGHT → Start.** Pre-start
   screen says SET 1 with A's name (chain HEAD), only the RIGHT
   Voltra applies B's load (Issues B + D).
3. **Run a few sets on A, SWAP, run sets on B, SWAP back, more sets
   on A.** All sets attribute correctly — no orphaned sets in B's
   instance, no sets misfiled (Issue A).
4. **End Session.** Summary now shows two cards, one per chain
   entry. Each card lists its sets, with weight × reps + peak,
   plus the rollup row (REPS / VOL / PEAK / AVG PK / DUR). Avg HR
   + kcal show below the rollups if Apple Watch was paired
   (Issue C). Each set row tagged with its exercise name so chain
   attribution is unambiguous (Issue E2). The markdown blob
   beneath includes the `Totals:` + `Vitals:` lines per exercise
   for share-link export.
5. **No regression**: solo (non-chain) sessions still work — single
   instance card, no chain banner, telemetry attributes correctly.

---

## Build 53 (v0.4.31, "V2 preview + chain fixes") — 2026-04-28

**Goal: Two-pronged build.** (1) Fix the chain-routing bugs the
user surfaced after b52 ("first exercise loads both Voltras"
on superset start, header showing exercise 2 while ACTIVE banner
loads exercise 1, SWAP auto-loading the new side dangerously,
summary mislabels and EXERCISES count zeroed). (2) Land the V2
LiveCaptureView preview as a separate code path the user can opt
into without touching V1. Combined into one build for ~30% cost
savings vs shipping b53 + b54 separately, per user direction.

### Chain-routing fixes

**Root cause from screenshots (IMG_2384, IMG_2385).** The header
read `activeInstance.exercise.name` while the ACTIVE banner +
WriterRouter routed off `mdm.supersetActiveSlot` /
`hasAnySupersetChainEntry`. Those two source-of-truth paths could
disagree the moment the chain mutated, e.g. on first exercise add
when only one chain entry existed and the b52 fallback predicate
broadcast to BOTH writers. The fix is to move routing onto a
per-instance field so the header and the writer always agree.

**Architecture change: per-instance `assignedVoltra`.**

1. `ExerciseInstance` (SwiftData) gets `assignedVoltraRaw: String?`
   plus a typed `assignedVoltra: DeviceSlotAssignment?` accessor.
   Additive migration; existing rows decode as nil → falls through
   to b52 chain-predicate routing for backward compat.
2. New enum `DeviceSlotAssignment { left, right, both }` in
   `DualMode.swift` with `.projectedSlot` (`.both → .left` for
   chain-entry storage) and human label.
3. `WriterRouter.apply(_:mdm:assignment:)` takes an optional
   assignment. When non-nil it routes by it directly (left → left
   writer, right → right writer, both → broadcast). When nil it
   falls back to the b52 chain predicate. Added
   `unload(slot:mdm:)` that pushes weight=0 to a single writer.
4. `LiveCaptureView` and `ExerciseDetailView` now pass
   `assignment: logging.activeInstance?.assignedVoltra` at every
   `apply` call site. The header for chain sessions reads
   `"Superset · {head} · HR {bpm} · {day}"` using the live HR.
5. `ExerciseStartView`'s superset slot picker is now 3-way (Left
   / Right / Both), driven by `DeviceSlotAssignment.allCases`. On
   commit it persists the choice to `activeInstance.assignedVoltra`
   AND appends the chain entry with the projected slot.
6. **SWAP no longer auto-LOADs.** The new side gets an unload
   (weight=0) so the cable is safe to grab, but the LOAD step is
   removed — the user manually taps LOAD after switching machines.
   Prevents the dangerous "I just walked over and the device
   already loaded itself" surprise from the b52 video.

### Session rollups + summary fixes

7. `WorkoutSession` gets `avgHRSession`, `minHRSession`,
   `maxHRSession`, `kcalSession` (Double?), plus computed
   `distinctExerciseCount`, `totalVolumeLb`, `peakForceLbSession`,
   `duration`. `endSession()` fires an async HK snapshot via the
   new `HealthKitStore.snapshotSession(start:end:)` (HK + non-HK
   stub).
8. `ExportSheet` adds a `sessionVitalsCard` (AVG HR / KCAL / TOTAL
   VOL / DUR with min-max HR header) ABOVE the per-exercise cards,
   and a `comparisonCard` showing VOL/PEAK/DUR deltas vs the most
   recent prior session of the same `dayTypeRaw`. EXERCISES tile
   now uses `distinctExerciseCount` (was zeroed in b52).
9. `markdownExport` is rewritten with a fixed-width `formatRow`
   helper (set 4 / label 14 / weight 9 / ecc 8 / reps 5 / peak 9)
   so the share-link table no longer wraps mid-row, and adds a
   `Session HR:` line under Duration when HR is present.

### V2 preview

10. **NEW** `LiveCaptureContainer.swift` — wraps V1/V2 selection.
    Reads `@AppStorage("liveCaptureUIVersion")`. On first launch
    (empty value) presents `LiveCaptureUIPickerSheet` with two
    cards (V1 RECOMMENDED default, V2 Preview). `shouldUseV2`
    requires uiVersion == "v2" AND NOT bothPaired AND chain<2 — so
    V2 always falls back to V1 for dual-Voltra or chain sessions.
11. **NEW** `LiveCaptureViewV2.swift` — single-Voltra clean
    redesign using `VoltraColor` / `VoltraFont` tokens. Layout:
    header card → 2x2 tile grid (REPS / PEAK / HR / REST) → force
    chart (same `ForceChartView` as the dashboard) → plan card +
    one-tap LOG SET CTA. No chain UI, no SWAP, no drop cascade,
    no nudge chips. The toolbar shows a `V2` accent pill so the
    user can tell which screen they're on.
12. `ExerciseDetailView.swift:116` and `ExerciseStartView.swift:81`
    now navigate to `LiveCaptureContainer()` instead of
    `LiveCaptureView()`. The `#Preview` inside `LiveCaptureView`
    is unchanged (V1 preview only).

**Sacred files untouched.** No changes to `VoltraProtocol.swift`,
`TelemetryExtractor.swift`, `PacketParser.swift`,
`FrameAssembler.swift`.

**SwiftData migration**: additive only. `assignedVoltraRaw` and
the four session HK rollup fields default to nil; existing rows
decode unchanged. b52 chain-predicate routing is preserved as the
nil fallback so any in-flight session upgraded to b53 keeps
working without forcing the user to reassign.

**Cost callout for this build:** medium-heavy. 9 source files
changed + 2 new files (Container, V2) + extension to WriterRouter
+ HK snapshot API + ExportSheet rewrite. No protocol or BLE
state-machine churn. Combined cost ~30-35% under shipping b53 and
the V2 preview as separate builds.

**Test plan after install**

1. **Solo session, V1.** Skip the picker (Use V1). Live screen
   should look identical to b52. End a session: summary shows the
   new sessionVitalsCard + comparisonCard if a prior arm-day exists,
   EXERCISES tile shows the right count, markdown export table is
   clean and unwrapped.
2. **Solo session, V2.** Pick V2 on the first-launch sheet. The
   live screen should be the new clean layout with the V2 pill in
   the toolbar. LOG SET should commit a row with the right reps +
   peak. Backing out and re-entering should keep V2 (uiVersion
   persisted).
3. **Pair both Voltras → pick A on LEFT → Start.** Even if the
   user opted into V2, the container falls back to V1 because
   bothPaired==true. ACTIVE banner says `ACTIVE • LEFT`, only the
   LEFT Voltra applies the load.
4. **Add Another Exercise → pick B on RIGHT (or BOTH) → Start.**
   Header shows `Superset · A · HR {n} · {day}`. Only the
   selected slot applies B's load (or BOTH writers if user picked
   Both).
5. **Run sets on A, SWAP.** New side unloads to 0. NO automatic
   LOAD — the user must tap LOAD after grabbing the cable. SWAP
   back continues working.
6. **End session.** Summary shows session vitals card, comparison
   to last arm day (if any), per-exercise cards, and a markdown
   table whose set rows do NOT wrap mid-row.

---

## Build 54 (v0.4.32, "V2 spec match") — 2026-04-28

**Goal: hotfix b53.** The V2 screen I shipped in b53 did NOT match
the design-studio spec the user pulled in (branch HEAD 74d0d3b9,
files under `design-system/`). I built V2 from the resumed-context
summary instead of opening the spec, so it shipped as a generic
clean screen with the wrong tile set (REPS / PEAK / HR / REST) and
no phase-tinted PHASE tile, no HR+KCAL paired pulse-dot strip, and
no CompareStripView. The user (correctly) called this out: "the
preview doesn't look anything like the screen shot from the Claude
studio". This build is the fix.

### What changed

1. **`VoltraLive/Views/VoltraTheme.swift`** — added the missing
   tokens from `design-system/colors_and_type.css`:
   `pullWash` (rgba(0,212,170,.12)), `returnWash`
   (rgba(255,184,77,.12)), `fresh` (rgb(51,217,102)),
   `freshStale` (rgb(89,89,89)). These are required by the
   PHASE tile background tint and the HR/KCAL pulse-dot freshness
   indicator, both spec'd in `ui-kit.html`.

2. **`VoltraLive/Logging/Views/LiveCaptureViewV2.swift`** — full
   rewrite to a 1:1 port of `design-system/ui-kit.html`. Layout
   top \u2192 bottom:
   - **Header strip**: LIVE kicker + exercise name + day pill +
     SET N pill.
   - **Primary 2x2 grid (REPS / PHASE / FORCE / REST)** \u2014 the
     canonical four tiles per `design-system/preview/index.html`
     principle 06. Mono tabular numerals at 72px, label is 11px
     uppercase +2 tracked. PHASE tile uses a phase-tinted wash
     background that animates on phase change. FORCE value tints
     to the live phase color.
   - **HR / KCAL secondary pair** \u2014 28px mono value, icon
     (heart for HR, flame for KCAL), pulse dot that blinks at
     1Hz when the HK sample is < 5s old, flat grey when stale.
   - **CompareStripView** \u2014 3 cells (LAST \u00B7 REPS / BEST
     \u00B7 FORCE / TARGET) with deltas vs the active instance's
     prior set + best-ever peak. Empty cells render \u2014.
   - **Force chart card** \u2014 reuses `ForceChartView` (same
     30s rolling phase-segmented waveform the dashboard renders).
   - **PLAN + LOG SET** \u2014 single 50px primary CTA, disabled
     opacity 0.4 per spec, color `#002b22` text on accent fill.

3. **`VoltraLive/Logging/Views/LiveCaptureContainer.swift`** \u2014
   tightened the V2 gate. Was `mdm.supersetChain.count >= 2`,
   now `!mdm.supersetChain.isEmpty`. Reasoning: a user mid-add
   of the second chain exercise has count == 1 and is already
   mentally in chain mode, but V2 has no chain affordances. We
   should fall back to V1 the moment any chain entry exists.

### Mode handling matrix (post-b54)

| Scenario | Renders |
|---|---|
| 1 Voltra paired, no chain, V1 chosen | V1 |
| 1 Voltra paired, no chain, V2 chosen | **V2** |
| 1 Voltra paired, chain has \u22651 entry | V1 (was V2 if count=1, regression-fixed) |
| 2 Voltras paired, Independent | V1 |
| 2 Voltras paired, Combined | V1 |
| 2 Voltras paired, Superset chain | V1 (b53 chain fixes apply here) |

V2 is single-Voltra-no-chain only by design. Every other shape
silently falls back to V1, so the b53 chain fixes (per-instance
`assignedVoltra`, 3-way Left/Right/Both picker, "Superset \u00B7
{head} \u00B7 HR \u00B7 {day}" header, no SWAP auto-LOAD) all keep
working untouched.

**Sacred files untouched.** No changes to `VoltraProtocol.swift`,
`TelemetryExtractor.swift`, `PacketParser.swift`,
`FrameAssembler.swift`. No model migration. No BLE state-machine
changes.

**Cost callout:** lite. One file rewrite + one container line +
4 color tokens + version bump. No protocol churn, no SwiftData
churn, no new HK API.

**Test plan**

1. **Solo session, V2 chosen.** Live screen shows the 2x2 PHASE
   grid \u2014 PHASE tile background tints teal during PULL,
   amber during RETURN, plain during TRANSITION/IDLE. FORCE tile
   value color follows the live phase color.
2. **HR / KCAL pulse dots.** With Apple Watch paired, dots blink
   green at 1Hz when fresh; pull the watch off, dots go flat grey.
3. **CompareStrip after first set.** LAST cell shows rep delta
   ("+2 vs last" green / "-1 vs last" amber / "= last" dim).
   BEST cell shows force delta vs all-time peak for this exercise.
   TARGET shows planned weight + "on track".
4. **Mid-set chain start.** Add a second exercise to the chain.
   The moment that second entry appears, V2 should silently swap
   to V1 (b54 gate change). Backing out of the chain returns V2.
5. **Both Voltras paired.** V2 never renders even if opted in
   (bothPaired fallback unchanged from b53).

---

## b55 (v0.4.33-build55) — V2 single-Voltra LiveCaptureView, full design-handoff match

**Why.** b53 / b54 had shipped a V2 LiveCaptureView that did not
match the design handoff. The b54 V2 was a 2x2 REPS / PHASE / FORCE
/ REST tile grid with HR + KCAL pills and a CompareStrip — clever,
but unrelated to what `screenshots/A1-states.png` and
`screenshots/A1-drop2.png` (the design team's reference render)
actually specified. Before writing any Swift, we rendered a static
HTML preview at `voltra-v2-preview/index.html` of all six artboards
(three rest-timer states × drop-set off/on), iterated on the
phase-strip / force-chart / drop-set rules, and got user sign-off
on that render. b55 ports that signed-off render to SwiftUI.

**What ships.**

- **Layout (top → bottom).** Header (End / connection pill +
  exercise · set / HR + KCAL pulse pills) → Top banner (always-
  visible phase strip + optional rest row) → Drop-set banner (when
  manual drop sequence armed) → WEIGHT card (mono number + ±5/±1
  steppers + embedded DROP row) → Mod tile row (ECC / CHAIN / INV
  / DROP, tap DROP to configure) → Small tile row (REPS / TOTAL
  VOLUME) → FORCE · 30s chart card.
- **Phase strip is ALWAYS visible.** PULL → full-width teal glow.
  RETURN → full-width orange glow. IDLE under-rest → dim half-fill
  teal. IDLE over-rest → full-width WARN orange. The strip persists
  through the rest window — that was the central error in the b53/b54
  V2: rest swallowed the strip.
- **Rest row.** Sits beneath the strip with a 1px hairline divider
  when `restElapsedSeconds > 0`. Under preset: green REST + timer.
  Over preset: orange REST · OVER + +MM:SS, both blink at 1Hz. The
  drop-set banner does NOT blink — only over-rest does.
- **Force chart (`ForceChartV2`).** Three modes: ACTIVE (phase-
  segmented polyline of last 30s, tip dot in current phase color),
  RESTING (empty — only the BOTTOM dashed danger-color marker), and
  IDLE-NO-DATA (sparse 5-sample up-tick from BOTTOM, anchored to
  the leftmost ~14% of the canvas, colored by current phase). The
  IDLE-NO-DATA mode mirrors the web preview's `buildForceHistory`
  function and tells the user the line is alive even before they
  start a rep.
- **Drop-set creation flow.** Tapping the DROP mod tile opens
  `DropSetConfigureSheet`, which lets the user enter FROM / TO /
  STEP and previews the resolved descending step list. On confirm,
  we stuff the list onto `LoggingStore.manualDropSequence` and push
  the head weight to the device via the same `WriterRouter` path
  V1 uses. The DROP banner + DROP row appear automatically.
- **`LoggingStore` additions.** `manualDropSequence: [Double]?` and
  `manualDropIndex: Int = 0`. Cleared on `endSession()` and
  `cancelDropSet()`. Distinct from the existing
  `dropChainPlannedLb` auto-cascade machinery — `dropChainPlannedLb`
  is timer-fired on long-press; `manualDropSequence` is finalize-
  driven from the V2 sheet.

**Files.**

- New: `Logging/Views/LiveCaptureViewV2.swift` (rewritten, 600 lines)
- New: `Logging/Views/V2/TopBannerV2.swift` (210 lines)
- New: `Logging/Views/V2/DropSetBannerV2.swift` (105 lines)
- New: `Logging/Views/V2/DropRowV2.swift` (98 lines)
- New: `Logging/Views/V2/ForceChartV2.swift` (238 lines)
- New: `Logging/Views/V2/DropSetConfigureSheet.swift` (283 lines)
- Modified: `Logging/Persistence/LoggingStore.swift`
  (+ `manualDropSequence`, `manualDropIndex`; resets in
   `cancelDropSet` and `endSession`)
- Modified: `Info.plist` (0.4.33 / 55, label "V2 single-Voltra
  LiveCapture")
- Deleted: `Logging/Views/LiveCaptureViewV2_b54.swift.OLD` (b54 backup)

**Container untouched.** `LiveCaptureContainer.swift` already had
the first-launch picker + `@AppStorage("liveCaptureUIVersion")` +
`shouldUseV2` gate (false when bothPaired or hasChain ≥ 1) from
b54. b55 leaves all of that alone — V2 is still opt-in, V1 is still
the default, and every shape that isn't single-Voltra-no-chain
silently falls back to V1.

**Sacred files untouched.** No changes to `VoltraProtocol.swift`,
`TelemetryExtractor.swift`, `PacketParser.swift`,
`FrameAssembler.swift`. No SwiftData model migration. No BLE
state-machine changes.

**Test plan**

1. **Single Voltra paired, V2 chosen.** Live screen matches the
   web-preview render: header strip → phase strip + label →
   WEIGHT card → mod tiles → REPS + TOTAL VOLUME → FORCE chart.
   No 2x2 grid, no CompareStrip, no PHASE tile.
2. **Idle phase strip.** PULL idle shows full-width teal line.
   RETURN idle shows full-width orange line. Force chart is
   sparse single up-tick in matching phase color.
3. **Resting under preset.** Strip becomes half-fill teal, label
   "IDLE" faint; rest row appears under hairline with green REST +
   timer. Force chart goes empty (BOTTOM marker only).
4. **Resting over preset.** Strip turns warn orange full-width;
   rest row blinks 1Hz with orange REST · OVER + +MM:SS.
5. **Tap DROP mod tile.** Configure sheet opens, FROM defaults to
   current weight. Adjust TO / STEP, see live preview. Confirm →
   sheet dismisses, DROP banner appears between header and WEIGHT
   card, DROP row appears inside WEIGHT card. Device weight pushed
   to head value.
6. **Cancel drop-set (long-press DROP tile, V1 cascade) or end
   session.** `manualDropSequence` cleared, banner + row vanish.
7. **Mid-session chain add.** Second exercise added → V2 silently
   swaps to V1 (container gate unchanged).

**Cost callout.** Medium. Six new SwiftUI files (~1530 lines), one
LoggingStore addition (+15 lines + 2 resets), one Info.plist bump.
No protocol churn, no SwiftData migration, no new HK API.


## 2026-04-29 — b55-fix (v0.4.33 / 55) — TestFlight upload fix: project.yml override + altool silent-fail guard

**What broke and why this entry exists.** The b55 push at commit
`6f45640` reported CI green on both Build IPA (`25089160910`) and
Release-to-TestFlight (`25089164206`), so I told the user the build
shipped. The user pulled up TestFlight and the build was not there.
They pushed back — "I don't see this build on TestFlight. I don't
see it. You've been trained to process. Are you sure you sent it?"
— and they were right. The Release workflow's altool step had
exit-code-zeroed and the success-grep had matched, but the upload
had in fact failed at Apple's side.

I pulled the raw `altool` log via
`gh api repos/.../actions/jobs/73511287096/logs` and found, at line
1996 of the 2068-line log:

```
ERROR: [ContentDelivery.Uploader.10175EFA0] The provided entity
includes an attribute with a value that has already been used
(-19232) The bundle version must be higher than the previously
uploaded version: '54'.
ERROR: [altool.10175EFA0] Failed to upload package.
```

…followed 28 lines later by my own workflow's misleading
`altool upload succeeded.` echo at line 2024. Two independent
defects had to line up for that to happen, and both are fixed in
this entry.

### Defect 1 — `project.yml` was the version source of truth, not `Info.plist`

xcodegen regenerates `VoltraLive.xcodeproj` from `project.yml` at
the start of every CI build. Two places in `project.yml`
hard-coded the version:

- Lines 64–65 — `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
  build settings on the `VoltraLive` target. xcodebuild's
  `expandbuildsettings` step on Info.plist substitutes these
  values into the binary's plist, so they win over anything in
  the repo's `Info.plist`.
- Lines 92–93 — Info.plist `CFBundleShortVersionString` /
  `CFBundleVersion` properties. xcodegen also rewrites the
  on-disk `VoltraLive/Info.plist` from this `info.properties`
  block on every regeneration.

The b55 commit only bumped `VoltraLive/Info.plist` to
`0.4.33` / `55`. The CI job ran `xcodegen generate`, which
overwrote my Info.plist back to `0.4.32` / `54`, and built/signed
an IPA whose `CFBundleVersion` was `54`. Apple rejected the
upload because build 54 was already on TestFlight from the
previous ship.

**Fix:** bumped `project.yml` to `0.4.33` / `55` in **both**
places (lines 64–65 build settings and lines 92–93
`info.properties`), and updated the `VOLTRAFeatureLabel` at line
96 to `"V2 single-Voltra LiveCapture"` to match `Info.plist`.
The repo `Info.plist` was already on `0.4.33` / `55`, so the two
sources are now consistent. Going forward, **`project.yml` is
the source of truth for version**; `Info.plist` is the mirror
that xcodegen writes.

### Defect 2 — release.yml altool success-detection was Application-Loader-era

The pre-fix grep at `.github/workflows/release.yml:701` was:

```bash
if grep -qiE 'UPLOAD FAILED|Validation failed|ERROR ITMS-' \
   /tmp/altool.log; then
  echo "::error::altool reported a failure..."
  exit 1
fi
echo "altool upload succeeded."
```

That regex catches Application-Loader-era and ITMS-validator
failures, but Xcode 26's `xcrun altool` upload pipeline (which
internally calls `avtool` / `ContentDelivery.Uploader`) emits a
totally different failure vocabulary:

- `Failed to upload package.`
- `ERROR: [ContentDelivery.Uploader.<addr>] ...`
- `ERROR: [altool.<addr>] ...`
- `(-19232)`, `(-19241)` — parenthesised numeric error codes

None of those match `UPLOAD FAILED|Validation failed|ERROR ITMS-`,
so the grep returned non-match, the workflow echoed "altool upload
succeeded.", the step exited 0, and the workflow turned green.
This is exactly the failure mode tracked in upstream
`fastlane/fastlane#29743` (Xcode 26 silent-fail) — the avtool
migration broke every CI pipeline that was relying on exit-code
or pre-Xcode-26 grep patterns.

A second, independent smoking gun was timing: the altool step
took **4 seconds** wall-clock (03:22:05 → 03:22:09). A real IPA
upload to ASC takes 20s–2min minimum. A 4-second altool exit
means the request never made it onto the wire.

**Fix (`.github/workflows/release.yml:679–732`).** Three layers
of defense, all of which must pass before the step echoes
success:

1. **Failure-marker grep, expanded.** Now matches:

   ```
   UPLOAD FAILED|Validation failed|ERROR ITMS-
   |Failed to upload package
   |ERROR: \[ContentDelivery
   |ERROR: \[altool
   |\(-[0-9]+\)
   ```

   On match, the step prints the offending lines (with `grep -n`)
   for the build log and exits 1.

2. **Wall-clock duration sanity check.** Capture
   `UPLOAD_START=$(date +%s)` before altool, `UPLOAD_END` after,
   and fail if `UPLOAD_SECS < 10`. The 4-second silent-fail case
   is rejected even if the failure-marker grep somehow misses.

3. **Positive success marker required.** Real successful
   altool/avtool uploads always print one of:

   ```
   UPLOAD COMPLETED SUCCESSFULLY
   No errors uploading
   package was successfully uploaded
   successfully uploaded
   ```

   The step now requires one of those to be present in
   `/tmp/altool.log`. Absence ⇒ fail, regardless of exit code or
   error grep result.

Only after all three checks pass does the step echo the final
"altool upload succeeded (duration ${UPLOAD_SECS}s, success
marker present)." line.

### Behavioral correction (sticky for all future TestFlight ships)

I had told the user b55 shipped on the strength of CI's green
checkmark alone. The user's correction:

> "I don't see this build on TestFlight. I don't see it. You've
> been trained to process. Are you sure you sent it?"

Going forward — recorded here for every future build — a
TestFlight ship is **not** considered shipped until I have:

1. Polled the Release workflow to `conclusion: success`.
2. Pulled the raw job log via `gh api ... /actions/jobs/<id>/logs`.
3. Verified the altool step log shows wall-clock duration ≥ 20s.
4. Verified the altool step log contains a positive success
   marker (`UPLOAD COMPLETED SUCCESSFULLY` or equivalent).
5. Verified the altool step log contains zero `ERROR:` /
   `Failed to upload package` / `(-NNNNN)` lines.

Anything less and the report to the user is "build status
unconfirmed, investigating," not "shipped."

### Files touched in this fix

- `project.yml` — lines 64–65, 92–93, 96 (version + label)
- `.github/workflows/release.yml` — lines 679–732 (Upload to
  TestFlight via altool step, hardened)
- `docs/WORK_LOG.md` — this entry
- `docs/handoff/00_START_HERE.md` — last-shipped + lessons
- `docs/handoff/04_ARCHITECTURE.md` — CI ship-verification
  protocol noted

No app-side code change. No protocol / Sacred-file change. No
SwiftData migration. The b55 V2 LiveCaptureView code from the
prior commit (`6f45640`) is unchanged — only the version source
of truth and the CI ship-verification logic moved.

**Test plan.**

1. Re-tag `v0.4.33-build55` at the new fix commit, push.
2. Watch Release workflow. The xcodegen step should now write
   `0.4.33` / `55` into the Xcode project, and the archive's
   embedded Info.plist should carry `CFBundleVersion = 55`.
3. The altool step should run for ≥ 20s and the log should
   contain `UPLOAD COMPLETED SUCCESSFULLY` (or equivalent).
4. ASC build history should show `0.4.33 (55)` as a new
   processing build within ~5 minutes of step completion.
5. Negative test, deferred — next time altool fails (e.g.
   another duplicate-version, a cert expiry), the workflow must
   now exit 1 and surface the matching error lines in the build
   log.

**Cost callout.** Tiny. Two YAML/yml edits and a doc append.
No app code shipped.



## b56 — v0.4.34 (build 56) — V2 mods + rest timer + V1 restore

**Date (UTC):** 2026-04-29
**Tag:** `v0.4.34-build56`
**Goal.** Make the V2 LiveCaptureView functionally complete for
in-gym testing: every modifier tile (ECC, CHAIN, INV CHAIN, DROP)
must be selectable and visibly armed; the DROP redesign per the
b56 spec (no menu, tap-to-arm, idle-fires, tap-deeper-step,
long-press-cancel); the rest timer that sweeps through three
HSL-interpolated stops; the hardware Loaded button; the auto-
scaling force-curve Y-axis; ECC weight range expanded to
5–400 lb; and verbatim restore of the V1 pulley/added-plates/
logged-sets/bottom-actions block under the chart.

### What changed (8 items)

1. **All four modifier tiles selectable.**
   ECC, CHAIN, INV CHAIN, DROP all toggle on tap. INV CHAIN ↔ CHAIN
   are mutually exclusive (selecting one clears the other on the
   upcoming set). The b55 selectability bug where ECC/INV CHAIN
   chips appeared but didn't engage is fixed by routing every
   tile through one shared `LoggingStore.upcoming…` write.

2. **DROP redesign per spec.**
   No more configure sheet, no menu. First tap arms DROP at
   −5 lb. Each subsequent tap (before idle finalize) re-arms
   deeper: −5 → −10 → −15 → −20 …. Long-press on the DROP tile
   cancels the arm. On idle finalize, the head set is saved and
   `manualDropSequence = [head, dropTarget]` is queued so the
   next set begins at the dropped weight automatically. This
   replaces b55's V1-style timer-cascade `startDropSet` with a
   simpler finalize-driven path.

3. **INV CHAIN promoted to first-class tile.**
   New `upcomingInverseLb` / `upcomingInverseEnabled` fields on
   LoggingStore (lines 61–71). Wire-protocol unchanged: writes
   inverse weight to `chainsLb` AND sets `inverse: true` on
   VoltraWeights — there is no separate `inverseLb` field on the
   protocol struct.

4. **RestTimerBarV2 (NEW, 207 lines).**
   HSL 3-stop sweep — green at start, yellow at mid-rest, red
   when over target — interpolated in HSL space so the gradient
   reads cleanly. Anchored under the force chart, hidden during
   active sets.

5. **Hardware Loaded button.**
   Tap on the big weight number sends LOAD/UNLOAD over BLE.
   Routing: if `mdm.state != .idle` (MultiState enum) the
   write goes to `mdm.load` / `mdm.unload`; otherwise to
   `ble.sendLoad` / `ble.sendUnload`. Same opcodes V1 already
   uses (per handoff/05).

6. **ForceChartV2 Y-axis auto-scale.**
   New `yAxisMaxLb` parameter on `ForceChartV2.init` replaces
   the hardcoded 160-lb ceiling. LiveCaptureViewV2 computes
   `max(currentWorkingLb, eccentricOverloadLb) * 1.3` as
   headroom. Smooth animated rescale (`.animation(.easeInOut)`)
   so the curve doesn't jump on weight-change.

7. **ECC range 5–400 lb.**
   `ModStepperRowV2` clamp helper for the ECC row enforces the
   new working range (was 0–300 in b55). −10 / −5 / +5 / +10
   buttons saturate at the bounds.

8. **V1RestoreSection (NEW, 358 lines) — verbatim port.**
   The pulley-ratio chip, added-plates picker, logged-sets list
   (with swipe-to-delete via the now-file-internal
   `SwipeableSetRow`), and the bottom-action row (End Set,
   Previous Sets, Add Next Exercise) are ported from
   LiveCaptureView.swift sections 1561 / 1648 / 1781 / 1935 with
   no behavior change — only restyled for the V2 layout. Sits
   directly under the force chart.

### Files changed

**New (5):**
- `VoltraLive/Logging/Views/V2/RestTimerBarV2.swift` (207)
- `VoltraLive/Logging/Views/V2/NestedModRowV2.swift` (139)
- `VoltraLive/Logging/Views/V2/ModStepperRowV2.swift` (143)
- `VoltraLive/Logging/Views/V2/V1RestoreSection.swift` (358)

**Modified:**
- `VoltraLive/Logging/Persistence/LoggingStore.swift` — added
  `upcomingInverseLb` + `upcomingInverseEnabled` (lines 61–71)
- `VoltraLive/Logging/Views/V2/ForceChartV2.swift` — `yAxisMaxLb`
  parameter, animated rescale (~277 lines)
- `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` — full
  rewrite to 845 lines: new layout, all 4 mod tiles selectable,
  DROP tap-arms-deeper + long-press-cancels + idle-fires,
  hardware-load tap on weight number, INV CHAIN ↔ CHAIN
  mutual exclusion, V1RestoreSection mounted under chart
- `VoltraLive/Logging/Views/LiveCaptureView.swift` — promoted
  `SwipeableSetRow` from `private` to file-internal so
  V1RestoreSection can reuse it
- `project.yml` — version 0.4.34/56 in 3 places (lines 64–65,
  92–93, 96 label)
- `VoltraLive/Info.plist` — version 0.4.34/56 + label
  "V2 mods + rest timer + V1 restore"
- `docs/handoff/00_START_HERE.md` — last-shipped paragraph
  rewritten for b56
- `docs/handoff/02_CURRENT_STATE.md` — date, latest build, V2
  layout description, recent tags
- `docs/handoff/04_ARCHITECTURE.md` — V2 LiveCapture section
  expanded with b56 details

**Deleted (4 obsolete):**
- `VoltraLive/Logging/Views/V2/DropSetConfigureSheet.swift`
- `VoltraLive/Logging/Views/V2/DropSetBannerV2.swift`
- `VoltraLive/Logging/Views/V2/DropRowV2.swift`
- `VoltraLive/Logging/Views/V2/TopBannerV2.swift`

### Sacred files: untouched

`VoltraProtocol.swift`, `TelemetryExtractor.swift`,
`PacketParser.swift`, `FrameAssembler.swift` — no edits.

### Verification (CI altool 5-gate)

Following the sticky correction from b55:

1. Release workflow polled to `conclusion: success`.
2. Job log pulled via `gh api .../actions/jobs/<id>/logs` to
   `/tmp/release_log_b56.txt`.
3. Wall-clock duration ≥ 20s.
4. Positive success marker present (`UPLOAD COMPLETED
   SUCCESSFULLY` or equivalent).
5. Zero `ERROR:` / `Failed to upload package` / `(-NNNNN)`
   lines in altool log.

Only after all five gates pass does this build get reported to
the user as shipped.

### Risks

- **DROP idle-fires timing** — the finalize handler that queues
  `manualDropSequence = [head, next]` runs on `mdm.state ==
  .idle`. If the rep sensor reports idle before the final eccentric
  fully completes, the head set could save short. Mitigated by
  reusing the same idle-debounce window V1 uses.
- **INV CHAIN wire format** — writing inverse weight into
  `chainsLb` while CHAIN is also non-zero would mean two
  competing tensions at the firmware level. UI mutual-exclusion
  prevents this; if a future feature ever needs both, the
  protocol struct will need a real `inverseLb` field.
- **ForceChartV2 back-compat** — `yAxisMaxLb` parameter has a
  default of 160 to keep any future caller of ForceChartV2
  working without rewrite. LiveCaptureViewV2 always passes the
  computed value.
- **V1RestoreSection styling drift** — port is verbatim-functional
  but visual styling was lightly adapted to the V2 dark layout.
  If anything looks off in TestFlight, fall back to the V1
  modifiers and re-port.

### Cost callout

Medium-or-heavier. Five new SwiftUI files (~847 new lines), a
~277-line ForceChartV2 modification, an ~845-line
LiveCaptureViewV2 rewrite, version bump, doc updates across
three handoff files. No protocol or Sacred-file changes, no
SwiftData migration.

### Next step

Watch the b56 build land in TestFlight processing within ~5
minutes of altool's success marker, then the user installs and
verifies the eight items above against the b56 spec screenshot.
If anything is off, the next build is a targeted patch — not
another full rewrite of LiveCaptureViewV2.

---

## b57 — V3 LiveCaptureView rewrite (v0.4.35-build57)

### Summary

V3 UI overhaul of the live-capture screen. Eight deliverables
tracked, all landed:

1. **Force chart §1 — dynamic Y-axis.** Ceiling = max(working,
   working+ECC, working+CHAIN, working+ECC+CHAIN) × 1.2, with
   60-lb floor. 1.5s ease on changes. Recomputes live as the
   user adjusts weight or arms/disarms mods.
2. **Force chart §1a — rep history overlay.** Up to 8 most
   recent reps drawn behind the live curve with logarithmic
   fade `opacity = max(0.10, 1/(1+ln(repsAgo+1)))`. Resets on
   End Set and on rest expire.
3. **DROP §2 — toggle rewrite.** Tap 1 arms a 5-lb drop and
   expands the nested row + stepper. Tap 2 disarms entirely
   (the nested row collapses, no greyed remnant). 2s idle
   auto-fire reschedules on every adjustment. Increments
   clamped to multiples of 5; ±1 buttons render greyed via
   `dropMode: true` and are no-ops at the handler.
4. **Increment grid §3.** All four nested rows
   (ECC/CHAIN/INV CHAIN/DROP) standardized to −5 / −1 / +1 / +5.
5. **Pulley §4 — relocate, doubling, BLE math.** Pulley + 1-lb
   added-plates dials lifted out of V1RestoreSection into a
   new `PulleyAndPlatesBarV3` mounted directly above the force
   chart. Pulley default 1×, plates default 1 lb. Doubling
   logic ported from commits 8a980d6 / ec71bcc. **BLE math bug
   from b56 fixed:** `pushUpcomingStateToDevice` no longer
   multiplies base/ECC/CHAIN by `pulleyMultiplier` — those
   values are device-frame and the device wants device-frame.
   Display side (WEIGHT card big number, force chart Y axis,
   log storage) continues to multiply.
6. **Rest timer §6 — first-engage fix.** `SessionStore.swift`
   ~line 132 now accepts `cs.peakLb > 10` alongside `cs.reps > 0`
   as engagement evidence. The very first rep of a session no
   longer slips through the arm-check.
7. **Header §7 — V3 chrome.** V2 top dial removed. Inline V3
   watermark. Exercise-name marquee scroll (5s pause → scroll →
   1s pause → reset → loop, no scroll if name fits). Status
   dot replaces the "Connected" button; tap opens a popover
   with the full BLE state string.
8. **Docs.** New files: `03_CURRENT_FEATURE_SPEC.md`,
   `04_DECISIONS_AND_CONSTRAINTS.md`, `06_KNOWN_ISSUES.md`,
   `09_NEXT_AGENT_PROMPT.md`, `research/intensity_metric.md`.
   This work-log entry.

### Files

**New:**
- `VoltraLive/Logging/Views/V2/PulleyAndPlatesBarV3.swift`
- `VoltraLive/Logging/Views/V2/MarqueeText.swift`

**Rewritten:**
- `VoltraLive/Logging/Views/V2/ForceChartV2.swift` — dynamic
  Y-axis ease, rep-history overlay with phase-boundary slicer,
  logarithmic fade.

**Modified:**
- `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` — header
  redesign, DROP toggle, BLE math fix, Y-axis formula, idle
  auto-fire timer, pulley bar mount, V2 dial removed from
  toolbar.
- `VoltraLive/Logging/Views/V2/ModStepperRowV2.swift` — −5/−1/+1/+5
  grid, `dropMode` flag added.
- `VoltraLive/Logging/Views/V2/V1RestoreSection.swift` — pulley
  + plates extracted out (now lives in PulleyAndPlatesBarV3).
- `VoltraLive/Session/SessionStore.swift` — rest-timer
  first-engage fix.

**Untouched:**
- `VoltraProtocol.swift`, `TelemetryExtractor.swift`,
  `PacketParser.swift`, `FrameAssembler.swift` — sacred.

### Cost callout

Medium-or-heavier. 2 new SwiftUI files (~378 lines), 1 full
rewrite (~396 lines), 4 modified files, version bump,
5 new doc files. No protocol or Sacred-file changes.

### Risks at ship

- **2× pulley ±1 snap** — documented in `06_KNOWN_ISSUES.md`
  KI-1. Cosmetic, no firmware impact.
- **DROP idle auto-fire is a no-op slot** — intentional, hook
  reserved for future haptics / pre-write. Documented as KI-2.
- **Marquee scroll in landscape** — only tested in portrait
  this build. Landscape might wrap weirdly if the exercise
  name is exceptionally long. Not blocking; flag if a user
  reports it.

---

## b58 — V4 LiveCapture: dropset port + Tonal force + weight fix + dual-Voltra (v0.4.36-build58)

### Summary

V4 spec landed in **one** ship, per user instruction. Four P0/P1
items, all wired into the V3 LiveCapture screen that shipped in
b57:

1. **P0 Dropset state-machine port.** `LiveCaptureViewV2.swift`
   no longer owns its own drop-step array. `tapDropTile()` and
   `adjustDropStep()` now call `LoggingStore`'s existing cascade
   API (`startDropSet(startingLb:pushWeight:)`,
   `bumpCascadeTier()`, `cancelDropSet()`). The nested DROP row
   reads `dropChainPlannedLb` + `previewNextCascade(from:count:)`
   for the head→next preview. The `dropArmed` flag now sources
   from `logging.dropSetActive`. Closes KI-F3.
2. **P0 Tonal-style force curve.** `ForceChartV2.swift` adds an
   ECC/CON dual-band gradient fill rendered **below** the
   polyline (z-stack order: fill → polyline → labels). Inline
   "ECC" / "CON" labels appear at the phase centroid on the
   current rep only (`repsAgo == 0`). CHAIN mode mirrors the
   gradient (`.topTrailing → .bottomLeading`). Two new init
   params: `eccBandActive: Bool`, `chainMirrorActive: Bool`,
   both defaulting to `false`. Existing single-band call sites
   continue to work unchanged.
3. **P1 Weight cell single-line fix.** WEIGHT card big number
   now `.lineLimit(1)`, `.minimumScaleFactor(0.6)`, with a fade
   gradient mask and `.layoutPriority(1)` plus
   `Spacer(minLength: 4)`. No more wrap-overlap with the WEIGHT
   label. Closes KI-F4.
4. **P0/P1 Dual-VOLTRA Independent + Twin Mode.** When both
   sides are connected (`bothVoltrasConnected`), the V3 header
   swaps to `dualHeaderCluster`: `[ L • ] [ MERGE ] [ • R ]` in
   independent, fused TWIN pill in combined. New `@State
   focusedSlot: DeviceSlot` drives which side gets writes —
   `focusOverrideAssignment` is passed to **both**
   `writerRouter.apply(...)` call sites. TWIN badge sits inline
   next to the weight number when `twinModeActive`.
   `PulleyAndPlatesBarV3` now takes `@EnvironmentObject mdm` and
   greys out the pulley chip in Twin Mode (lock icon, opacity
   0.55, `.disabled(true)`). Chip is **not hidden** —
   discoverability preserved per V4-D5.

### Files

**Modified:**
- `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` —
  `focusedSlot` `@State`; `tapDropTile()`/`adjustDropStep()`
  rewritten against `LoggingStore` cascade; `dropArmed` reads
  `logging.dropSetActive`; nested DROP row uses cascade preview;
  weight cell single-line fix; TWIN badge inline; `headerStrip`
  branches on `bothVoltrasConnected`; new views
  (`dualHeaderCluster`, `sideDot`, `mergeButton`,
  `fusedTwinPill`); new computed props (`bothVoltrasConnected`,
  `twinModeActive`, `focusedBle`, `focusOverrideAssignment`);
  ForceChartV2 invocation passes `eccBandActive`/`chainMirrorActive`;
  both `writerRouter.apply` call sites pass
  `assignment: focusOverrideAssignment`.
- `VoltraLive/Logging/Views/V2/ForceChartV2.swift` — new init
  params; new `eccConFill`, `gradientStops`, `inlinePhaseLabels`,
  `phaseCentroid(...)` helpers; z-order: fill → polyline → labels.
- `VoltraLive/Logging/Views/V2/PulleyAndPlatesBarV3.swift` —
  `@EnvironmentObject mdm`; `twinModeActive` computed; pulley chip
  disabled + lock icon + opacity 0.55 + accessibility label in
  Twin; preview wires `MultiDeviceManager()`.
- `docs/handoff/03_CURRENT_FEATURE_SPEC.md` — V4 spec, §8
  dual-Voltra section.
- `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` — V4-D1 …
  V4-D9 appended.
- `docs/handoff/06_KNOWN_ISSUES.md` — rewritten: 4 open + 4
  fixed (incl. KI-F3 dropset, KI-F4 weight overlap).
- `docs/handoff/07_DUAL_VOLTRA.md` — refreshed from "planned for
  b30" to "Independent + Twin shipped in b58".
- `docs/handoff/09_NEXT_AGENT_PROMPT.md` — points at V4 spec and
  b58 ship, lists hard rules incl. "preserve previous builds"
  and "pulley grey-don't-hide".
- `docs/research/intensity_metric.md` — beefed up with b58
  context: ECC/CON segmentation now free, dropset cascade
  centralized, Twin Mode aggregation declared.

### Sacred files: untouched

`VoltraProtocol.swift`, `TelemetryExtractor.swift`,
`PacketParser.swift`, `FrameAssembler.swift` — unchanged.

### Critical preservation note (sticky)

User correction this session: **all 110 commits and 57+ build
tags are preserved in git history** (`v0.1.0` …
`v0.4.35-build57`). Dropset code archaeology used:
`0d513e4` (b22), `ec71bcc` (b23), `8a980d6` (b24), `aff322f`
(b25), `89d43b3` (b38). Dual-Voltra plumbing from `d08b327`
(b29), `a76994d` (b30), `bb5199e` (b29 tests). Snapshots saved
to `/home/user/workspace/b58_refs/` for cross-session reference.
**Future agents: dig in `git log --all` and `git tag` before
asking the user where prior code is.**

### Cost callout

**Heavy** — heavier than b57. One file rewritten substantially
(`LiveCaptureViewV2.swift`, ~50 lines changed across header,
dropset, weight cell, force-chart wiring, write routing), one
file extended (`ForceChartV2.swift`, +4 helpers / ~70 lines),
one file extended (`PulleyAndPlatesBarV3.swift`, ~15 lines), 7
docs touched. One TestFlight ship per user request ("do the
full v4 build in one build").

### Risks at ship

- **Twin DROP undefined.** DROP tile is hidden when
  `twinModeActive`; no spec yet for cascading both sides
  together. Flag if user asks. Documented in
  `07_DUAL_VOLTRA.md` "Out of scope".
- **Focus toggle UX.** Tapping L/R dot is the only way to
  switch focused side in independent mode. If users expect a
  different interaction (long-press? swipe?), surface and spec.
- **Force-chart fill performance.** ECC/CON gradient renders
  per phase segment per rep. Untested on > 30-rep history;
  fallback is to disable `eccBandActive` for repsAgo > N.
- **Missing screenshot reference.** `weight-overlap-v3.jpeg`
  link from user was unreachable; KI-6 logged. The fix is
  implemented from spec text alone — recheck against the user's
  actual screenshot when they're back online.

---

## b59 — hotfix: route to V2 when both Voltras paired (v0.4.37-build59)

### Why this is a separate build

Post-b58 QA caught a critical regression: with both Voltras paired
on TestFlight (b58, v0.4.36), the user saw the **legacy V1
ACTIVE/NEXT header** instead of the new b58 dualHeaderCluster
(L • / MERGE / • R) — meaning every dual-Voltra change in b58 was
silently invisible. Confirmed via user-supplied IMG_2400 (showing
V1 chrome) and IMG_2401 (Left ● Right ● dots, both connected).

### Root cause

`LiveCaptureContainer.shouldUseV2` (b53/b54) had a stale gate:

```swift
let bothPaired = mdm.left.connectionState.isConnected
    && mdm.right.connectionState.isConnected
return !bothPaired && !hasChain && uiVersion == "v2"
```

When b53 wrote that, V2 was explicitly single-Voltra and falling
back to V1 for two Voltras was correct. b58 made V2 **the only
view with dual-Voltra-aware chrome** (dualHeaderCluster, MERGE
button, fused TWIN pill, focusedSlot routing, pulley grey-out in
Twin) but never updated this gate. Result: V2 was reachable with
one Voltra, but the moment a second paired the container flipped
to V1 — which has zero b58 changes — and hid every dual-Voltra
addition.

This is a pure routing fix. The b58 V2 code itself was correct;
nothing in `LiveCaptureViewV2.swift`, `ForceChartV2.swift`, or
`PulleyAndPlatesBarV3.swift` needed to change.

### Fix

`VoltraLive/Logging/Views/LiveCaptureContainer.swift` —
`shouldUseV2` rewritten:

```swift
let bothPaired = mdm.left.connectionState.isConnected
    && mdm.right.connectionState.isConnected
let hasChain = !mdm.supersetChain.isEmpty
if hasChain  { return false }   // V1 still owns chain/superset
if bothPaired { return true }   // V2 is the only dual-aware view
return uiVersion == "v2"        // single-Voltra: respect preference
```

Doc-comment above the function rewritten to match the new rules.

### Routing matrix (post-b59)

| Voltras paired | Chain entries | Routes to | Reason |
|---|---|---|---|
| 1 | 0 | user pref (V1 or V2) | unchanged |
| 1 | ≥1 | V1 | chain has no V2 affordance |
| 2 | 0 | **V2** (was V1) | only view with dual-Voltra chrome |
| 2 | ≥1 | V1 | chain regression > dual UI gain |

### Files

- `VoltraLive/Logging/Views/LiveCaptureContainer.swift` — gate
  rewritten + doc-comment updated.
- `project.yml` — bumped 0.4.36/58 → 0.4.37/59, feature label.
- `VoltraLive/Info.plist` — same.

### Sacred files: untouched.

### Risks

- Single-Voltra users are unaffected (gate still defers to
  `uiVersion`).
- Chain users are unaffected (chain still routes to V1).
- Dual-Voltra users on V1 preference now get V2. **This is the
  intended behavior of b58.** If they hate the V2 dual UI, they
  can disconnect a Voltra and the gate falls back to their
  preference.
- V1's `LiveCaptureView.swift` still contains its own legacy
  dual-Voltra ACTIVE/NEXT header. We are NOT removing it —
  someone in chain mode with two Voltras still ends up there.
  That code stays as-is for b59; don't churn it.

### Lessons

This is exactly why post-build QA exists (rule established
earlier in this session, now in `AGENTS.md` "Post-build QA
checklist" + `docs/handoff/QA_LOG.md`). CI green and altool
5-gate verification proved b58 *uploaded*; only the user
running on real hardware caught that the dual UI never
rendered. The QA checklist for b58 surfaced this within
hours of ship — exactly the gap it's meant to close.

---

## 2026-04-29 14:52 UTC — chore: GPT-5.5 track handoff pre-flight

### Goal

Pre-flight / fork-prep for the GPT-5.5 implementation track copy
(`5frctqwvmn-ship-it/voltra-live-ios-gpt-5-5`). Mark this repo as the
GPT-5.5 track, save the next-agent handoff prompt (Karpathy LLM Wiki
pattern) into `docs/handoff/09_NEXT_AGENT_PROMPT.md`, and record a
pre-flight verification table for the canonical wiki layout the prompt
expects. **No P0/P1 app changes** — this is metadata + handoff only.
Original Claude-orchestrated repo (`voltra-live-ios`) is untouched and
remains the fallback baseline.

### Files changed

- `AGENTS.md` — added GPT-5.5 track-marker callout block at top.
- `README.md` — added GPT-5.5 track-marker callout block at top.
- `docs/handoff/09_NEXT_AGENT_PROMPT.md` — overwritten with the V4 UI
  Layout handoff prompt (Karpathy LLM Wiki method) plus a GPT-5.5
  track marker section, an in-prompt note that flags the existing
  numbering-scheme mismatch, and a Pre-Flight Verification table
  recording PASS/MISMATCH/MISSING for each expected wiki file.
- `docs/WORK_LOG.md` — this entry.

### What changed

1. **GPT-5.5 track marker** is now visible in three durable locations
   (AGENTS.md callout, README.md callout, 09 handoff prompt header).
   None of them disrupts existing build, signing, or sacred-file
   instructions.
2. **Handoff prompt** now contains the full V4 UI Layout work order
   (P0-1 dropset state machine, P0-2 Tonal-style force curve, P0-3
   dual-Voltra top bar, P1 weight-overlap + first-engage idle) and
   the Karpathy three-layer wiki architecture. The prompt has a
   clear "do not modify the original fallback repo" directive.
3. **Pre-flight verification table** captures the gap between the
   wiki names the prompt expects (`01_PROJECT_STATE`,
   `02_ARCHITECTURE`, `05_BUILD_TEST_DEPLOY`, `07_FILE_MAP`,
   `08_GIT_HISTORY_SUMMARY`) and the actual filenames in this copy
   (`01_PROJECT_OVERVIEW` + `02_CURRENT_STATE`, `04_ARCHITECTURE`,
   `09_RELEASE_AND_SIGNING`, and two missing). Also flags missing
   `entities/`, `screenshots/`, and `raw/` directories. The next
   agent is told NOT to silently rename — propose the rename or add
   a mapping table to `00_START_HERE.md`.

### Verification

- `git remote -v` confirms `origin` →
  `5frctqwvmn-ship-it/voltra-live-ios-gpt-5-5`. The original
  `voltra-live-ios` is not a remote of this clone, so a stray push
  cannot reach it.
- `ls docs/handoff/` confirms the handoff inventory listed in the
  pre-flight table.
- `09_RELEASE_AND_SIGNING.md` contains real `xcodebuild` /
  `xcodegen` / dry-run / tag-push commands — pre-flight item "real
  iOS build commands" passes.
- AGENTS.md sacred-files section, BLE control-write rules, 5-gate
  ship verification, and post-build QA checklist are all unchanged
  by this commit.

### Risks

- **Low.** No code, no protocol, no CI workflow, no Info.plist /
  project.yml touched. Three documentation files modified, one
  appended. Build remains b59 (v0.4.37); no version bump needed
  for a docs-only commit.
- The pre-flight table flags wiki-naming drift the next agent
  must reconcile before writing V4 code. Surfacing it here is the
  fix; not surfacing it would have been the regression.

### Next step

Hand the GPT-5.5 track to the next agent (fresh Perplexity Computer
session). They run Step 0 of `09_NEXT_AGENT_PROMPT.md` cold, summarize
state back to the user, and only then begin V4 implementation —
starting with the wiki-naming reconciliation called out in the
pre-flight table.

---

## 2026-04-29 (later) — feat: dropset arm-only refactor + unified progress bar (b60-prep)

### Goal

Address the b58 post-build QA wave-1 P0 regressions on the V4
DROP tile. Specifically:

- **KI-9 (P0):** DROP tap currently pre-lowers the cable weight;
  user wants tap = arm only, with the actual drop firing after
  the lift goes idle for 2 s. Mirrors gym mental model.
- **KI-8 (P1):** make the dropset countdown visible — surface a
  unified bar that morphs across idle / dropset progress / rest.
- **KI-7 (P1):** confirm cascade interval is 2 s (already shipped
  by b45; doc was stale).
- **KI-10 (P0, partial):** the arm-only refactor likely closes
  the phantom −5 lb mid-rep drop because the only cascade-fire
  path now requires explicit `armDropSet` AND a 2 s sub-floor
  gate. Pre-b60 the engage path could fire on any
  SessionStore-detected idle while a manualDropSequence was in
  flight. Verify on hardware before closing KI-10.

This change ships ONLY the dropset state-machine work and the
unified progress bar. Force curve epic (KI-11) is intentionally
deferred — see "What was NOT touched" below.

### Files changed

- `VoltraLive/Logging/Persistence/LoggingStore.swift`
  - +`dropSetArmed: Bool`, `dropArmedFiresAt: Date?` `@Published`
    fields.
  - +`armDropSet(startingLb:pushWeight:)` — captures anchor +
    writer bridge, sets `dropSetArmed = true`. Does NOT touch
    the cable, does NOT call `beginDropChain`, does NOT start
    timers. Refuses while in arm-cooldown.
  - +`engageArmedDropSet()` (private) — called from
    `noteTelemetryActivity` once the 2 s arm-idle gate clears.
    Re-delegates to `startDropSet` with the captured anchor +
    writer.
  - +`cancelArmedDropSet()` — clears arm flags + 1.5 s cooldown.
    Distinct from `cancelDropSet` because no SessionStore drop
    mode was ever entered.
  - +`cascadeArmIdleSec: Double = 2.0` constant +
    `cascadeArmIdleSecondsForUI` mirror.
  - `noteTelemetryActivity(forceLb:)` now drives the arm gate
    BEFORE the `dropSetActive` guard. Above-floor force resets
    `dropArmedFiresAt`; sub-floor force starts/keeps the
    countdown; once the deadline passes, `engageArmedDropSet`
    fires.
  - `reanchorCascadeIfActive(toLb:)` guard relaxed to
    `dropSetActive || dropSetArmed` so user weight nudges
    between tap-DROP and the first cascade drop are honored.
  - Defensive resets of `dropSetArmed` / `dropArmedFiresAt` in
    `cancelDropSet`, `autoLogDropChain` defensive branch, and
    the autoLogDropChain success path.
- `VoltraLive/Logging/Views/LiveCaptureViewV2.swift`
  - `tapDropTile()` rewritten — now calls `armDropSet` (was
    `startDropSet`). Tap-while-armed disarms.
  - `cancelArmedDrop()` (long-press) branches on active vs.
    armed.
  - `dropArmed` computed property = `dropSetActive ||
    dropSetArmed` so the nested DROP row + 4-up tile render
    armed visuals without distinguishing sub-state.
  - `phaseOrRestBar` now morphs **rest > dropset > phase**.
    New `dropProgressBar` private view renders one of four
    labels (`DROP · ARM` / `· IN` / `· NEXT` / `· BOTTOM`)
    with a 2 s sweep tied to `nextDropFiresAt` or
    `dropArmedFiresAt`. Reuses the ambient `blinkOn` 2 Hz
    republish so we don't spin a second timer.
- `docs/handoff/entities/dropset_state_machine.md` — NEW.
  Entities-layer doc per the V4 prompt (Karpathy wiki). State
  table, transition diagram, engine method index, timer
  constants, telemetry contract, UI binding contract, hardware
  test plan.
- `docs/handoff/06_KNOWN_ISSUES.md` — KI-7 marked resolved
  (already 2 s in code since b45). KI-8 marked resolved (unified
  bar shipped this commit). KI-9 marked resolved (arm-only
  refactor shipped this commit). KI-10 promoted to "needs
  hardware repro post-b60" — the most likely cause is closed
  but verify before deleting.
- `docs/handoff/03_CURRENT_FEATURE_SPEC.md` — §3 DROP tile
  rewritten to describe the b60 arm-only state machine. §1a
  Phase strip OR Rest Timer Bar updated to mention the new
  third state (dropset progress).
- `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` — V4-D10
  appended (arm-only state machine), V4-D11 appended (unified
  bar across three states).
- `docs/handoff/00_START_HERE.md` — added the wiki-name
  mapping table the b59 pre-flight asked the next agent to
  produce. No file renames.
- `docs/handoff/QA_LOG.md` — b59 entry placeholder added so
  hardware QA after this branch ships can fill in the wave-1
  follow-ups.

### What was NOT touched

- **KI-11 (force curve epic).** Out of scope for this branch
  per the user's billing convention "keep features separate
  bills." Force curve full spec stays as documented in
  `docs/handoff/design/force_curve.md` and `06_KNOWN_ISSUES.md`
  KI-11 — next branch.
- **`startDropSet`.** Not deleted — it's now invoked only from
  `engageArmedDropSet`. Keeps the existing snapshot / parity /
  floor logic in one place. Public surface is unchanged so
  V1's `LiveCaptureView` (which still calls `startDropSet`
  directly at line 1118) continues to work.
- **Sacred files.** `VoltraProtocol.swift`,
  `TelemetryExtractor.swift`, `PacketParser.swift`,
  `FrameAssembler.swift` unchanged.
- **`project.yml` / `Info.plist`.** No version bump in this
  branch — version bump + tag happen at ship time, after a
  user sign-off on the PR.

### Verification

- Static review only — no Mac in this environment, so
  `xcodebuild` / `xcodegen` were not run. CI will compile + run
  `VoltraLiveTests/ProtocolGoldenTests.swift` on push (sacred
  files unchanged so the protocol golden tests are guaranteed
  to pass).
- Diff statics:
  - `dropSetArmed`/`dropArmedFiresAt` declared as `@Published`
    so SwiftUI observers refresh.
  - Arm-gate path runs BEFORE the `dropSetActive` guard in
    `noteTelemetryActivity` (verified by re-reading the diff).
  - `engageArmedDropSet` returns immediately after delegating
    to `startDropSet` to avoid double-resetting the timers
    that `startDropSet` itself sets up.
  - `reanchorCascadeIfActive` extension is gated by
    `dropSetArmed` OR `dropSetActive` so callsites in
    `LiveCaptureView.swift` (V1) are unaffected when nothing
    is armed.
  - V1's `LiveCaptureView.swift` calls `startDropSet` directly
    at line 1118 — left intact. V1 behavior is unchanged.

### Risks at ship

- **First-engage edge case:** if the lift goes idle BEFORE
  `noteTelemetryActivity` has been called once after arming,
  `dropArmedFiresAt` won't be set and the engage will wait
  for the first sub-floor packet. In practice every BLE
  session has continuous telemetry so this is moot, but if
  the BLE connection drops mid-arm the cascade silently
  won't engage. Consider a safety fallback if QA reports it.
- **Bar contention:** if the rest timer fires WHILE armed
  (theoretically possible if SessionStore finalizes the set
  via the existing rep+force heuristic before the user has
  a chance to cancel arm), rest takes priority and arm
  silently clears via the `cancelDropSet` path inside the
  finalize branches. Verify on hardware.
- **Twin Mode:** DROP tile is hidden in Twin per V4-D6. The
  arm path never runs in Twin so no Twin-specific code is
  needed. If Twin DROP is later spec'd, we'll need to plumb
  the engage path through `mdm.applyCombined`.

### Cost

**Medium.** ~50 lines changed in LoggingStore (3 new methods +
4 sites of defensive resets), ~110 lines changed in
LiveCaptureViewV2 (rewrote one var + one method, added one new
private view), 1 new entity doc, 5 wiki updates. No CI run
yet — single push + PR open.

### Next step

Open a PR against `main` of the GPT-5.5 repo. User reviews,
signs off, then we tag b60 and ship via the existing release
workflow (see `09_RELEASE_AND_SIGNING.md`). On TestFlight
install, run the b58 QA wave-1 follow-up checklist (KI-7 / 8 /
9 / 10) on hardware. If the phantom −5 lb drop (KI-10) recurs,
we have repro context and can add debug logging on the
resistance-write call sites in a follow-up build.

## 2026-04-29 15:40 UTC — KI-11 force-curve full spec landed (b60-prep)

- **Files changed:** `VoltraLive/Logging/Views/V2/ForceChartV2.swift`,
  `VoltraLive/Logging/Views/LiveCaptureViewV2.swift`,
  `docs/handoff/design/force_curve.md`,
  `docs/handoff/06_KNOWN_ISSUES.md`,
  `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md`,
  `docs/handoff/03_CURRENT_FEATURE_SPEC.md`.
- **What changed:** Closed the seven §-level gaps in
  `force_curve.md` that were tracked as KI-11. New on the chart:
  80% dashed reference line (§3e), per-rep peak dot + lb label
  (§3e), compact mode-aware legend chip top-left (§3g, includes
  new INV CHAIN entry), time-based label fade (§3c), 3-stop
  gradient ROM-band (§3d), stroke-side phase-blend dot at CON↔ECC
  boundaries (§3b). One new optional init arg
  `invChainArmedActive`; parent passes `invArmed` into it.
- **Verification:** Static-only — no Swift toolchain in this
  Linux container. Hand-traced ViewBuilder branch counts in the
  modified body / `activeChart` / ZStack to stay within the 10-view
  limit. Hand-traced gradient-stop math and the
  `labelFadeAlpha(rep:)` boundary cases (3.0 → 1.0, 3.5 → 0.5,
  4.0 → 0.0). CI `build.yml` will be the first real compile gate
  on push.
- **Risks:** No hardware QA yet. Likely-safe rendering surface,
  but four watch-items: (1) older-rep peak labels may visually
  collide on long sets, (2) §3b stroke blend dots may read as
  artifacts on very fast reps, (3) 80% line uses running-set peak
  not historical-set peak (matches Tonal pattern but worth
  confirming on hardware), (4) INV CHAIN fill direction
  intentionally unchanged — see V4-D12.
- **Next step:** User pushes a TestFlight from this branch and
  runs the post-build QA checklist (8 rows in `06_KNOWN_ISSUES`
  KI-F11). If labels collide, dial the `>= 0.30` opacity
  cutoff up. If §3b dots feel artifact-y, drop alpha 0.35 → 0.20
  or remove. Do NOT merge this branch to main without that QA.

---

## b60 — release conduit ship: V4 from GPT-5.5 fork (v0.4.38-build60)

**Date/time:** 2026-04-29 16:30 UTC

**Goal:** Ship V4 work completed by the GPT-5.5 agent's fork to
TestFlight via the original repo's signing pipeline. This session is
a release conduit only — no re-implementation, no wiki re-authoring.

**Source of payload:**
- Fork: `5frctqwvmn-ship-it/voltra-live-ios-gpt-5-5`
- Branch: `feat/ui-v4-dropset-armonly`
- HEAD SHA: `59a3c05`
- Fork PR (informational, not merged): #1
- Fork branch frozen as rollback fallback. Not pushed to.

**History approach:** Linear merge-base. Fork branched from this
repo's `main` at `592131f` (b59 hotfix) with three commits ahead:

| SHA | Subject |
|---|---|
| `a48cf7c` | chore: GPT-5.5 track handoff pre-flight |
| `3f8d41c` | feat(v4): dropset arm-only refactor + unified progress bar (b60-prep) |
| `59a3c05` | feat(v4): KI-11 force-curve full spec — 80% line, peak dots, legend (b60-prep) |

`git checkout -b release/v0.4.38-build60 59a3c05` succeeded cleanly —
no cherry-pick needed. All three fork commits are carried verbatim.

**Files changed in this session (release branch, on top of fork HEAD):**
- `project.yml` — bumped `MARKETING_VERSION` 0.4.37 → 0.4.38,
  `CURRENT_PROJECT_VERSION` 59 → 60.
- `VoltraLive/Info.plist` — bumped `CFBundleShortVersionString` /
  `CFBundleVersion` to match; updated `VOLTRAFeatureLabel` to b60.
- `docs/WORK_LOG.md` — this entry.

**Files NOT changed (by intent — owned by fork commits):**
- `VoltraLive/Logging/Persistence/LoggingStore.swift`
- `VoltraLive/Logging/Views/LiveCaptureViewV2.swift`
- `VoltraLive/Logging/Views/V2/ForceChartV2.swift`
- `docs/handoff/00_START_HERE.md`
- `docs/handoff/03_CURRENT_FEATURE_SPEC.md`
- `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md`
- `docs/handoff/06_KNOWN_ISSUES.md`
- `docs/handoff/QA_LOG.md`
- `docs/handoff/design/force_curve.md`
- `docs/handoff/entities/dropset_state_machine.md`
- `AGENTS.md` (fork added a 7-line note in `a48cf7c`)
- `README.md` (fork added a 5-line note in `a48cf7c`)

All wiki deltas are present on the release branch by virtue of
checking out fork HEAD. No verbatim re-copy was needed since the
checkout IS the verbatim copy.

**Wiki diff vs original `main` @ `592131f`** (informational, no
overwrite needed since we branched from fork HEAD, not main):
- `00_START_HERE.md` — fork added b60-prep startup notes (+25 lines).
- `03_CURRENT_FEATURE_SPEC.md` — fork added §3 dropset arm-only
  + §5 force-curve KI-11 sections (+97 lines total across
  `3f8d41c` and `59a3c05`).
- `04_DECISIONS_AND_CONSTRAINTS.md` — fork added decision records
  for arm-only refactor + KI-11 spec (+110 lines).
- `06_KNOWN_ISSUES.md` — fork updated KI-9 (DROP arm-only resolution
  pending hardware), KI-11 (force-curve spec resolution pending
  hardware) (+89/-52 churn).
- `QA_LOG.md` — fork added b59 QA wave-2 + b60-prep entries.
- `design/force_curve.md` — fork added 24 lines for legend +
  peak-dot + 80% line spec.
- `entities/dropset_state_machine.md` — NEW file from fork (136
  lines), formalizes the b60 arm-only state machine.

**Source of truth for fork-owned content:**
The fork's `docs/WORK_LOG.md` and `docs/handoff/QA_LOG.md` carry
the implementation narrative. The PR description references those;
this WORK_LOG entry deliberately does not re-paste them.

**Verification:**
- Sacred files untouched (`Protocol/*` checked — no fork commits
  modified them).
- Linear history confirmed via `git merge-base` =
  `592131f` (this repo's main HEAD).
- All required wiki files present on branch (8/8).
- Tag `v0.4.38-build60` confirmed unused (`git tag --list` only
  shows up to `v0.4.37-build59`).
- Hardware testing matrix: NOT run this session. The agent has no
  device. All hardware-confirmation items are explicitly marked
  awaiting user QA in the b60 PR + ship message.

**Risks at ship:**
- **Dual-Voltra routing (b59) is still hardware-unconfirmed.** The
  b59 `LiveCaptureContainer.shouldUseV2` rewrite shipped to
  TestFlight on b59 but the user reported the legacy V1
  ACTIVE/NEXT header still surfaced. b60 does NOT touch routing —
  inherits whatever state b59 left. Requires real-hardware QA to
  determine if b60's V4 changes are even reachable.
- **DROP arm-only (KI-9) hardware-unconfirmed.** Fork commit
  `3f8d41c` rewires DROP tap to arm-only (no immediate −5 lb).
  Logic verified by code review only.
- **KI-10 phantom −5 lb during reps.** Not addressed by fork.
  Still open, still hardware-only repro.
- **KI-11 force-curve full spec (legend/peak dots/80% line)** —
  fork commit `59a3c05`. Visual spec compliance hardware-unverified.
- Fork branch frozen at `59a3c05` as rollback fallback. If b60
  TestFlight QA fails, user can revert to b59 and we re-spin from
  the fork's PR #1 with corrections.

**Next step:**
1. Push release branch to origin.
2. Open PR against `main` referencing fork SHA + fork PR #1 + fork
   `WORK_LOG`/`QA_LOG` as testing source-of-truth.
3. Tag `v0.4.38-build60`, push tag, run release.yml.
4. Poll workflow → run 5-gate altool verify → poll App Store Connect
   for processing.
5. Report status to user as **"uploaded to TestFlight, awaiting
   user hardware QA"** — NOT "shipped". Per user explicit
   directive at b60 kickoff: "do not overclaim … b60 should be
   framed as 'uploaded to TestFlight for hardware QA,' not 'done.'"

**Cost callout:** This entire ship cycle is **medium** —
checkout + 2 file edits + WORK_LOG append + commit + push + PR
open + tag + release.yml polling loop + ASC polling loop.

---

## b61 — bump-and-retry after Apple rejected b60 (v0.4.38-build61)

**Date/time:** 2026-04-29 16:42 UTC

**Why this exists:** b60 upload failed at altool with Apple error
`-19232 ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE`:

```
The bundle version must be higher than the previously uploaded
version: '59'. The provided entity includes an attribute with a
value that has already been used.
```

This is App Store Connect telling us build `60` was already taken
on Apple's side (origin unknown — possibly a prior CI run, fork
CI run, or local archive). The 5-gate altool guard caught it at
gate 4 (no positive success marker) and gate 5 (failure regex
matched). CI failed loudly — no false-positive ship.

The b60 tag `v0.4.38-build60` is preserved in repo history as a
failed-upload audit trail per user direction.

**Fix:** single bump commit on top of the b60 release branch.
Same payload (3 fork commits + b60 conduit commit), version 61.

**Files changed (this commit only):**
- `project.yml` — `CURRENT_PROJECT_VERSION` 60 → 61.
- `VoltraLive/Info.plist` — matching `CFBundleVersion`; updated
  `VOLTRAFeatureLabel` to mention the collision.
- `docs/WORK_LOG.md` — this entry.

`MARKETING_VERSION` stays at `0.4.38` per user choice (Option 1
from the bump prompt).

**Source payload unchanged:** still gpt55/feat/ui-v4-dropset-armonly
@ 59a3c05. Same three implementation commits ride this re-ship.

**Verification:**
- Tag `v0.4.38-build61` confirmed unused (no such tag on origin).
- Sacred files still untouched.
- Branch `release/v0.4.38-build60` retained as the working branch
  (no rename — keeps PR #3 stable). Tag and PR title carry the
  build-61 marker; branch name is now slightly stale but harmless.

**Risks:**
- If `61` is ALSO taken on ASC, we'll see the same `-19232` and
  bump to 62. There is no API call from this environment to
  enumerate ASC's existing builds before the fact. User has been
  informed of this.
- All hardware-QA risks from b60 still apply unchanged.

**Next step:**
1. Commit + push to release branch.
2. Tag `v0.4.38-build61`, push tag.
3. Run release.yml, poll, 5-gate verify.
4. If altool succeeds, poll ASC for processing.
5. Report status as "uploaded to TestFlight, awaiting hardware QA."

**Cost callout:** Re-ship adds another medium block (one more
release.yml run + altool + poll). Total session is now medium-heavy.
