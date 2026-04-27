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
