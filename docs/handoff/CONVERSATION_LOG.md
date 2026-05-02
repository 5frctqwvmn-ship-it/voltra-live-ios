# CONVERSATION_LOG

Append-only log of decisions, blockers, and deviations from plan across
sessions. The repo is the source of truth — chat memory is not. Every
commit that includes a new decision, blocker, or change of plan must
append an entry here in the same commit.

Newest at the bottom.

---

## Session: 2026-05-02 — B74-F11 Session Recorder implementation kickoff

### Starting situation

- Claude Code launched against worktree
  `.claude/worktrees/silly-rhodes-0e06aa` on branch
  `claude/silly-rhodes-0e06aa`.
- Working directory fixed to that worktree; could not switch to the
  main repo checkout.
- `SESSION_RECORDER_SPEC.md` existed on `origin/feat/ui-v4-2-claude` at
  `29151fb` (merged via PR #9, docs-only).
- Last shipped: v0.4.49 / build 76 ("Health signal indicator" — B74-F8).

### Worktree blocker resolution

- Rejected: closing session and reopening against main checkout (too
  much friction).
- Rejected: checking out `feat/ui-v4-2-claude` inside this worktree
  (would conflict with the main checkout that should hold that branch).
- Chosen:
  `git checkout -b feat/b77-session-recorder origin/feat/ui-v4-2-claude`
  inside the current worktree. Creates a new branch based on the correct
  remote, gives Claude file-tool access, does not touch the main
  checkout.
- Verified: branch tracks `origin/feat/ui-v4-2-claude`; SPEC_OK; tree
  clean except `.claude/` untracked.

### Route map review

- Claude read all `docs/handoff/*` and `AGENTS.md`, produced a full
  route map.
- Route map approved without changes.
- `project.yml` uses directory globs (`path: VoltraLive`,
  `path: VoltraLiveTests`) — new files under those dirs compile
  automatically. **No `project.yml` edit needed.**
- Existing test target at `VoltraLiveTests/` (XCTest) — no new target
  creation needed.
- `11_AGENT_ROLES.md` does NOT exist on this base branch (only on
  `main` / unrelated branches). It is referenced by `B74_BUG_QUEUE.md`
  text but is not load-bearing for this PR. Not authored here.
- `01_PROJECT_OVERVIEW.md` says "current shipping build v0.4.46/73"
  (stale; actual is 76) — **left alone**, out of scope.

### Approved 3-commit plan

**Commit 1 — Core engine (DONE at `76becdf`):**

- `RecorderEvent` (Codable schema), `RecorderBuffer` (actor FIFO,
  10,000 cap), `RecorderRedactor` (peripheral name → UUID; free text
  → `<redacted:len=N>`), `ActionScope` (`@TaskLocal` UUID),
  `RecorderExporter` (`.txt` + `.json` builders, schemaVersion=1),
  `SessionRecorder` (singleton `ObservableObject`, persists to
  `Application Support/SessionRecorder/last_session.json`),
  `View+RecorderScreen` (`.recorderScreen("Name")` modifier).
- Tests: `RecorderBufferTests`, `RecorderRedactorTests`,
  `RecorderExporterTests`, `ActionScopeTests`.
- Pure engine only: no app mount, no overlay, no instrumentation.

**Commit 2 — Root overlay + viewer + share + screen tags:**

- `SessionRecorderToggle`: 24×24 pt bottom-trailing dot, hidden until
  `VOLTRARecorderUnlocked`, tap = toggle, long-press = viewer, red
  1 Hz `TimelineView` pulse while recording, `textFaint` while idle.
- `SessionRecorderViewer`: event list + category filters + `ShareLink`
  exporting both `.txt` and `.json` payloads.
- `VoltraLiveApp.swift`: `@StateObject SessionRecorder.shared`,
  `.environmentObject`, root `.overlay(alignment: .bottomTrailing)`,
  `scenePhase` observer to call `recorder.persist()` on background.
- `BuildBadgeOverlay.swift`: `TapGesture(count: 3)` flips
  `UserDefaults["VOLTRARecorderUnlocked"] = true`. Single-tap grid
  cycle stays. SwiftUI's ~250 ms count-disambiguation delay is
  acceptable per spec.
- `.recorderScreen("ScreenName")` tag on ~13 top-level screens.

**Commit 3 — Instrumentation + loud guards + docs:**

- Additive BLE sinks (`VoltraBLEManager`, `VoltraWriter`,
  `MultiDeviceManager`) — **NO behavior change.**
- HealthKit read-only instrumentation in `HealthKitStore`.
- `ActionScope` wrapping for major UI actions.
- User-visible silent guards converted to `rec.guardTrip(...)`,
  bounded to user-visible paths only per spec wording.
- Doc updates: `03_CURRENT_FEATURE_SPEC`, `07_FILE_MAP`,
  `09_NEXT_AGENT_PROMPT`, `WORK_LOG`, this file (append).
  `04_DECISIONS_AND_CONSTRAINTS` only if implementation diverges
  from V4-D25.

### Key decisions

- Build badge keeps single-tap grid cycle; triple-tap unlock is
  additive (not replace).
- Loud-guard sweep is bounded to user-visible paths only per spec
  wording. Internal / ambient guards in subviews are left alone.
- No new Xcode test target; existing `VoltraLiveTests/` is used.
- `project.yml` directory-glob sources mean no project file edit is
  required for new sources to compile.
- Repo is source of truth, not chat memory.
- `00_START_HERE.md` is the canonical restart path.
- `CONVERSATION_LOG.md` (this file) must be appended in the same
  commit as code changes going forward.

### Risks surfaced

- Cannot run `xcodebuild` on Windows; "Could not verify" section
  required in PR description.
- Handoff docs go stale if not updated in same commit as code.
- SwiftUI triple-tap + single-tap coexistence introduces a ~250 ms
  delay on the single-tap path (built-in gesture disambiguation).
  Needs QA verification on device.

### State at this checkpoint

- Commit 1 landed at `76becdf` — 11 files, 1098 insertions.
- No app mounts, no instrumentation, no overlay yet.
- `.claude/` untracked (do not stage).
- Branch tracks `origin/feat/ui-v4-2-claude`. Not yet pushed.

### Next action for fresh agent

- Read `00_START_HERE.md` + this log + `SESSION_RECORDER_SPEC.md`.
- Summarize state back to user.
- Proceed with **Commit 2** (root overlay + viewer + share + screen
  tags) per the approved plan, unchanged.

### Perplexity control-plane session (2026-05-02)

This implementation was directed by a Perplexity AI advisory chat. The
user pasted Perplexity's recommended prompts into this Claude Code
session. Below is the decision trail from that advisory chat,
preserved so future sessions have full context.

> **Full verbatim transcript:** see
> [`PERPLEXITY_TRANSCRIPT_2026-05-02.md`](PERPLEXITY_TRANSCRIPT_2026-05-02.md)
> for the complete turn-by-turn record. The summary below is the
> distilled decision trail; the transcript file is the authoritative
> "why" for anything ambiguous here.

**Worktree blocker:**

- Claude Code was launched in worktree
  `.claude/worktrees/silly-rhodes-0e06aa` on branch
  `claude/silly-rhodes-0e06aa`.
- Claude reported it could not switch to the main repo checkout and
  offered options to reopen against main checkout or authorize branch
  checkout / `git show` inside the worktree.
- Perplexity advised a third option: create a new implementation
  branch inside the current worktree based on
  `origin/feat/ui-v4-2-claude` using
  `git checkout -b feat/b77-session-recorder origin/feat/ui-v4-2-claude`.
- User approved that approach. Claude executed it. Branch created,
  SPEC_OK confirmed, tree clean except `.claude/`.

**Route map:**

- Perplexity told the user to have Claude read `AGENTS.md` plus
  `docs/handoff/*` and `SESSION_RECORDER_SPEC.md` before editing.
- Perplexity provided the detailed B74-F11 implementation prompt with
  three logical commits, hard stops, doc update requirements, and PR
  requirements.
- Claude produced a full route map.
- Perplexity reviewed the route map and advised the user to approve
  it without changes.

**Approval guidance from Perplexity:**

- **Auto-approve:** file reads, edits under `VoltraLive/Recorder/` and
  `VoltraLiveTests/`, doc edits in the approved route map, named-path
  `git add`, descriptive commits.
- **Pause and verify:** edits to `VoltraLiveApp.swift`,
  `BuildBadgeOverlay.swift`, BLE files, and `HealthKitStore.swift`.
- **Hard reject:** `Info.plist`, `project.yml`, `.github/workflows`,
  entitlements, release / TestFlight, `git add -A`, `.claude/`
  staging, rebase, force-push, secrets.

**Commit 1 approval decisions:**

- Claude asked permission to stage Commit 1 files. Perplexity advised
  "Allow once", not "Always allow".
- Claude asked permission to commit with bot identity. Perplexity
  advised "Allow once".
- Commit 1 landed at `76becdf`.
- Claude then said it was proceeding to Commit 2. Perplexity advised
  the user to pause and create this durable handoff checkpoint first.

**Durable handoff decision:**

- User explicitly clarified they wanted this Perplexity conversation
  itself preserved, not merely the repo state.
- Perplexity clarified Claude cannot see the Perplexity chat unless
  the user pastes the content.
- This section exists to preserve that advisory conversation in Git.

**Two-layer workflow architecture:**

- **Layer 1:** Perplexity AI chat is the control plane. It generates
  prompts, reviews Claude output / screenshots, and advises
  approval / deny decisions.
- **Layer 2:** Claude Code is the execution plane. It reads / writes
  files, runs `git`, and implements code.
- Perplexity has no direct repo access. Claude has no access to the
  Perplexity chat unless the user pastes it.
- Durable state must live in Git, not chat memory.
- To restore context in a fresh Perplexity session, paste
  `docs/handoff/00_START_HERE.md` and
  `docs/handoff/CONVERSATION_LOG.md`.

**Recommendations still in effect:**

- Use "Allow once", not "Always allow", for git staging and commit
  steps.
- After Commit 2 and Commit 3, update `00_START_HERE.md` and append
  `CONVERSATION_LOG.md` in the same commit when state or decisions
  change.
- If Commit 3 runs long, push an intermediate commit per the 10-turn
  safety rule.
- SwiftUI triple-tap plus single-tap coexistence needs QA verification
  on device.

---

## 2026-05-02 — Context protocol and Karpathy method added

**Decision:** add automatic context health checks
(`good` / `degrading` / `dangerously low`), 10-turn rolling summaries
to `CONTEXT_LEDGER.md`, and Karpathy filesystem-as-memory + select +
compress + isolate rules to `AGENTS.md`.

**Why:** the prior backfill (creating the full Perplexity transcript
in one shot) was expensive and brittle. A rolling 10-turn checkpoint
prevents the next session from needing the same recovery dance.

**How to apply:** every agent response that does repo work ends with
a one-line context-health verdict. Every 10 turns (or sooner if
degrading / dangerous), append a structured summary to
`CONTEXT_LEDGER.md` and commit it before writing more code. Read
order in `00_START_HERE.md` updated to put `CONTEXT_LEDGER.md` (latest
3 entries only) before the Perplexity transcript.

**Cross-refs:** `AGENTS.md` "Voltra Brain & Agent Organization
(Karpathy Method)"; `00_START_HERE.md` "Context protocol";
`CONTEXT_LEDGER.md` (new file, empty until first checkpoint).
