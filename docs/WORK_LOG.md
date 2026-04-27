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
