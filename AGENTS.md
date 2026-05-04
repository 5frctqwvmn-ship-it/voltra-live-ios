# AGENTS.md

> **Purpose:** Fast-path context for any LLM agent (or future session) working on this repo.
> Read this file **before** modifying anything. It encodes the constraints, sacred files, and
> success criteria that make this project work on real hardware.
>
> Style guide: [Karpathy Guidelines](https://pyshine.com/Andrej-Karpathy-on-LLM-Agents-and-Code/)

---

## 1. Repo at a glance

| Item | Value |
|---|---|
| App | VOLTRA Live — iOS companion for the VOLTRA smart barbell |
| Tech | Swift / SwiftUI / CoreBluetooth / HealthKit / SwiftData |
| CI | GitHub Actions (`build.yml` unsigned, `release.yml` signed + TestFlight) |
| Runner | `macos-26` / Xcode `26.2` / iPhoneOS SDK `26.2` |
| Branch model | Long-lived feature branch `feat/ui-v4-2-claude`; no PR merge to `main` per sticky rule |
| Current build | See `docs/handoff/01_PROJECT_OVERVIEW.md` top line |

---

## 2. Read order on session start

Before writing a single line of code, read **in this order**:

1. `AGENTS.md` ← you are here
2. `docs/handoff/00_START_HERE.md`
3. `docs/handoff/01_PROJECT_OVERVIEW.md`
4. `docs/handoff/02_CURRENT_STATE.md`
5. `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` (ADRs)
6. `docs/handoff/09_RELEASE_AND_SIGNING.md`
7. `docs/WORK_LOG.md` (tail — last 20 entries)
8. Any file mentioned in `02_CURRENT_STATE.md`'s "Active cycle" section

Do **not** rely on chat history for facts that should live in the repo.
If you notice a fact only exists in chat, write it to the appropriate
doc immediately.

---

## 3. Sacred files — never modify without explicit user instruction

These files encode the hardware protocol. A wrong edit can brick a
live workout or corrupt BLE frames silently.

- `VoltraLive/Protocol/VoltraProtocol.swift`
- `VoltraLive/BLE/TelemetryExtractor.swift`
- `VoltraLive/BLE/PacketParser.swift`
- `VoltraLive/BLE/FrameAssembler.swift`
- `.github/workflows/release.yml`
- `.github/workflows/build.yml`

Also treat as sacred (no silent edits):

- `VoltraLive/BLE/VoltraWriter.swift` — command encoding
- `VoltraLive/BLE/WriterRouter.swift` — mode-dispatch logic
- Any file that includes `DemoTraceLogger.Event` cases

---

## 4. Mandatory behaviors in every coding task

### 4a. Session start

1. Read the files listed in §2.
2. Summarize the current state back to the user **before** making changes:
   - Last shipped build + version
   - Active branch + HEAD SHA
   - What the active cycle is trying to do
   - Any open known issues relevant to the task
3. State which ADRs govern the area you're about to touch.

### 4b. After ANY meaningful change

Append an entry to `docs/WORK_LOG.md` with:

```
## YYYY-MM-DD HH:MM UTC — <one-line goal>

- **Files changed:** path/one, path/two
- **What changed:** Short factual description.
- **Verification:** What you ran or observed (build, test, manual on device).
- **Risks:** Anything that could break or that you didn't fully test.
- **Next step:** The next thing the next session should do.
```

Commit `docs/WORK_LOG.md` **in the same commit** as the change.

### 4c. Decision / architecture / spec changes

Update the relevant `docs/handoff/*.md` file **in the same commit**
as the code change. Do not defer.

### 4d. Version bump discipline

See `docs/handoff/09_RELEASE_AND_SIGNING.md` §"Three places to bump".
Version bump is always the **final** commit of a release cycle, after
all scope has landed. Never bump mid-cycle.

---

## 5. Voltra Brain & Agent Organization (Karpathy Method)

### Role split

| Role | Agent | What they do |
|---|---|---|
| Control plane | Perplexity (this session) | Spec, architecture, release decisions, ADRs, push approval |
| Execution plane | Claude / GPT | Write code, run tests, commit, push |

The control plane agent (Perplexity) issues instructions; the execution
plane agent implements them. Neither overrides the other's decisions
without explicit user approval.

### Context protocol

Every agent response that does repo work must end with one of:

- `Context is good.` — sufficient context to continue
- `Context is degrading.` — >60 % of context window used; checkpoint soon
- `Context is dangerously low.` — checkpoint NOW before writing more code

Every 10 turns (or sooner if health drops), the execution agent appends
a structured summary to `docs/handoff/CONTEXT_LEDGER.md` and commits
before writing more code.

### Leash constraints

Every instruction from the control plane to the execution plane must
include:

1. **Clear instruction** — what to do
2. **Constraints** — what NOT to do (scope fence)
3. **Scope** — which files may be touched
4. **Stopping criteria** — when to stop and report back

---

## 6. CI / release discipline

### Push policy

- **Never push to `main` directly.** All work stays on `feat/ui-v4-2-claude`
  (or a short-lived feature branch that PRs into it).
- **Never force-push** a branch that has been pushed to origin.
- **Never merge `feat/ui-v4-2-claude` into `main`** without explicit
  user instruction.

### Ship policy

1. All scope for the cycle must land before any version bump.
2. Version bump is a single commit touching only `project.yml`,
   `VoltraLive/Info.plist`, `docs/handoff/01_PROJECT_OVERVIEW.md`,
   and `docs/handoff/02_CURRENT_STATE.md`.
3. After bump, trigger `release.yml` with `dry_run=false`.
4. Apply the 5-gate altool ship verification (see `09_RELEASE_AND_SIGNING.md`).
5. Report back with Delivery UUID before calling anything "shipped".

### build.yml is sacred

`build.yml` runs on every push and produces the unsigned dev IPA.
Do not edit it without explicit user instruction. One documented
exception: 2026-04-25 surgical edit pinning `'VOLTRA Live.app'`
(not `'*.app'`) after a Watch target was briefly added.

---

## 7. Code style constraints

- **Minimum diff.** Touch only the files required for the task.
  Do not reformat, re-indent, or rename outside the change surface.
- **No silent guards.** If a guard fires in a user-visible path,
  the app must show feedback. Convert `guard … else { return }` to
  a loud `guard` with a `rec.guardTrip(...)` call (Session Recorder)
  or a visible UI error.
- **No new `@AppStorage` keys** without documenting them in
  `docs/handoff/03_CURRENT_FEATURE_SPEC.md`.
- **No new `Info.plist` keys** without documenting them and updating
  `project.yml`.
- **No new entitlements** without explicit user instruction.
- **Actor isolation (Swift 6 strict concurrency).** Members on
  extensions of `@MainActor` classes are NOT automatically
  main-actor-isolated. Annotate explicitly with `@MainActor`.
  `PassthroughSubject` static lets should be `nonisolated` so
  non-main-actor subscribers can still emit.

---

## 8. Known sharp edges

| # | Edge | Detail |
|---|---|---|
| E1 | xcodegen rewrites `Info.plist` | `project.yml` is source of truth. If the two disagree, CI ships the `project.yml` version silently. |
| E2 | altool exits 0 on Apple rejection | Always verify the 5-gate checklist, not just CI green. |
| E3 | Combined-mode step parity | `±5/±1` in Independent, `±6/±2` in Combined per b47. Read `CombinedParity.swift`. |
| E4 | CloudKit disabled | `cloudKitDatabase: .none`. Do not re-enable until v2 store is stable (see `09_RELEASE_AND_SIGNING.md §CloudKit`). |
| E5 | SwiftUI overlay env-object propagation | `.overlay { Content() }` does NOT inherit env-objects from the modifier chain. Re-inject explicitly. See KI-13. |
| E6 | `liveCaptureUIVersion` AppStorage | `"v1"` is the emergency rollback kill switch (b71+). `""` and `"v2"` both route to V2. |
| E7 | `VOLTRAFeatureLabel` | A `String` in `Info.plist` / `project.yml` displayed in the build-badge chip. Set to the feature name on every ship, cleared (`""`) when no feature is active. |

---

## 9. Post-build QA checklist (user runs on device, agent records)

After every TestFlight ship, the user runs this checklist on real
hardware and reports results back to the agent. The agent records
results in `docs/handoff/QA_LOG.md`.

**Format for each item:** Pass / Fail / Not tested / Deferred

### Core hardware path

1. Cold launch → `LoggingHomeView` (not `ConnectView`) appears.
2. Tap a weight number → LOAD command fires, device beeps, weight
   shows on screen.
3. Tap again → UNLOAD command fires, device releases.
4. Drop set: arm drop, tap LOAD, cascade steps down correctly.
5. Combined mode: weight tap fires to both sides simultaneously.
6. ECC mode: ECC stepper adds eccentric offset to device command.
7. Chains: chains lb stepper adds to both sides in Combined;
   inverse chains sends negative payload.
8. Chain swap (superset): SWAP button fires the 7-step swap flow,
   device loads incoming side, outgoing unloads.

### Force chart

9. Live set shows force curve updating in real time.
10. `lastFinalizedSamples` shown after set ends.
11. Superset secondary trace visible when chain is active.

### Session Recorder (b77+)

12. Triple-tap build badge → recorder dot appears bottom-trailing.
13. Tap dot → recording starts (red pulse).
14. Long-press dot → viewer opens with event timeline.
15. Share button → ShareLink exports `.txt` + `.json`.
16. scenePhase background → `last_session.json` written to App Support.

### Debug grid (b72+)

17. Single-tap build badge → grid overlay appears (`.base` density).
18. Further taps cycle through `.half` → `.quarter` → `.max` → `.off`.
19. Scroll a list → row labels travel with content (b74 fix).

### Regression guards

20. L / R header pills show correct connection state.
21. Health signal dot: faint pre-auth; normal color post-auth + live HR.
22. Build number visible on every screen.

**Any "Fail" result** must be filed as a new `KI-N` entry in
`docs/handoff/06_KNOWN_ISSUES.md` as a new `KI-N` entry, with
the user's follow-up details captured verbatim.

**Why this exists:**

The user is the only one running the app on real hardware. CI
green + altool 5-gate verification proves the build *uploaded*,
not that the *features work*. This checklist closes that gap.
