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
