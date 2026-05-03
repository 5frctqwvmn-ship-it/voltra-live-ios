# AGENTS.md

> **Purpose:** Fast-path context for any LLM agent (or future session) working on this repo.
> Read this file **before** modifying anything. It encodes the constraints, sacred files, and
> success criteria that make this project work on real hardware.
>
> Style guide: [Karpathy Guidelines](https://pyshine.com/Andrej-Karpathy-Skills-LLM-Coding-Guidelines/) —
> Think Before Coding · Simplicity First · Surgical Changes · Goal-Driven Execution.

## Mandatory startup

1. Read this file in full.
2. Read `docs/handoff/00_START_HERE.md` and follow its startup sequence
   (it points you at the rest of the handoff docs and `docs/WORK_LOG.md`).
3. **Repeat the user's request back** before writing any code (Karpathy method).
4. After **any meaningful change**, append an entry to `docs/WORK_LOG.md` and
   update the relevant `docs/handoff/*.md` doc **in the same commit** as the
   code change. The repo is the source of truth — chat history is not.
5. Reference secrets by **name only**. Never paste secret values into any file.

---

## What this is

VOLTRA Live is a native iOS app that mirrors live workout telemetry from a
Beyond Power VOLTRA cable machine over BLE, logs sets to a local SwiftData
store, and overlays HealthKit data (heart rate, active calories) during sessions.

- iOS bundle ID: `com.voltralive.app` (PRODUCT_NAME: "VOLTRA Live")
- Test bundle ID: `com.voltralive.app.tests` (PRODUCT_NAME: "VoltraLiveTests")
- Min iOS: 17.0
- Connected GitHub user: `5frctqwvmn-ship-it`
- Repo: <https://github.com/5frctqwvmn-ship-it/voltra-live-ios>

**Watch companion is deferred to v1.2** — see "Deferred / known follow-ups" section.

## The hard constraint (do not violate)

The sacred protocol files are **off-limits** without explicit user approval —
see "Sacred files" below. The 9 `BOOTSTRAP_WRITES` are byte-identical to the
official iPad app capture and must not change.

**Control writes — current policy (April 2026):** the user has explicitly
approved control writes (target weight, eccentric, chains, mode, and the
upcoming LOAD/UNLOAD), gated through `VoltraLive/BLE/VoltraWriter.swift`.
This supersedes earlier read-only framing. **All** new control writes must:

1. Go through `VoltraWriter` (or, for dual-device, `MultiDeviceManager`).
2. Be triggered by an explicit user action — never auto-issued in the background.
3. Use new files for new payload builders (e.g.
   `VoltraControlFrames+<Feature>.swift`). Sacred protocol files are still untouchable.
4. Be documented in `docs/handoff/05_BLE_AND_PROTOCOL.md` in the same commit.

If a request is ambiguous about a write, **stop and surface the assumption**
before coding.

## Sacred files (do not modify without explicit user approval)

| Path | Why sacred |
|---|---|
| `VoltraLive/Protocol/VoltraProtocol.swift` | Wire-format constants verified on hardware 2026-04-15. Mutating any byte breaks connection. |
| `VoltraLive/Protocol/TelemetryExtractor.swift` | 0xAA decode logic. Mutating offsets makes the FORCE/REPS/PHASE tiles silently wrong. |
| `VoltraLive/Protocol/PacketParser.swift` | Frame parser, mirrors JS reference. |
| `VoltraLive/Protocol/FrameAssembler.swift` | Stream defragmenter. |
| `.github/workflows/build.yml` | Working unsigned IPA build. 4 fixes needed to get it green originally — do not regress. *(Exception: 2026-04-25 surgical edit to pin iOS app name after Watch target added — `'VOLTRA Live.app'` instead of `'*.app'`.)* |

If you must modify a sacred file:
1. State the assumption that the change is necessary.
2. Add or update a test in `VoltraLiveTests/ProtocolGoldenTests.swift` that pins the new expected behavior.
3. Run `xcodebuild test -scheme VoltraLive` locally before pushing.

## Source of truth

Reverse-engineered protocol reference (Apache-licensed):
<https://github.com/dylanmaniatakes/Beyond-Power-Voltra-Android>

Key wire facts:

- Service UUID: `e4dada34-0867-8783-9f70-2ca29216c7e4`
- 9 (not 10) BOOTSTRAP_WRITES
- 0xAA telemetry layout: phase @ offset 2 · setCount @ 3 · repCount uint16-**BE** @ 4–5 · forceTenthsLb uint16-**LE** @ 11
- Set-complete heuristic: `phase == .idle AND force < 5 AND reps > 0 AND idle ≥ 4000ms`

## Project layout

```
voltra-ios/
├── VoltraLive/                   # iOS app (SwiftUI)
│   ├── Protocol/                 # SACRED — wire format
│   ├── Views/
│   ├── Assets.xcassets/          # App icon (3 nested teal triangles, #00d4aa on #0a0e0c)
│   └── Info.plist
├── VoltraLiveTests/              # Protocol golden-fixture tests
│   └── ProtocolGoldenTests.swift # MUST stay green or release.yml fails
├── .github/workflows/
│   ├── build.yml                 # Unsigned dev IPA on every push
│   └── release.yml               # Tag-triggered TestFlight + dry-run dispatch
├── project.yml                   # XcodeGen — single source of truth for Xcode config
├── VALIDATION.md                 # First-TestFlight-run checklist (run on real hardware)
└── AGENTS.md                     # this file
```

## CI architecture

| Trigger | Workflow | What runs |
|---|---|---|
| Every push | `build.yml` | Unsigned dev IPA, attached to "latest" release |
| `workflow_dispatch` (dry_run=true, default) | `release.yml` | Tests + signed archive + IPA artifact. **Skips upload.** Use this to validate signing config without burning a TestFlight build number. |
| `workflow_dispatch` (dry_run=false) | `release.yml` | Tests + signed archive + TestFlight upload (manual override). |
| Tag `v*.*.*` | `release.yml` | Tests + signed archive + TestFlight upload + GitHub release. |

## Required GitHub secrets (for release.yml)

User must add these once Apple Developer enrollment is approved:

| Secret | Source |
|---|---|
| `APPLE_TEAM_ID` | <https://developer.apple.com/account> → Membership Details (10-char alphanumeric) |
| `APPLE_API_KEY_ID` | App Store Connect → Users and Access → Integrations → Team Keys (10-char) |
| `APPLE_API_ISSUER_ID` | Same page, top of Team Keys section (UUID) |
| `APPLE_API_PRIVATE_KEY` | The `.p8` file contents — entire file including `-----BEGIN PRIVATE KEY-----` lines |
| `KEYCHAIN_PASSWORD` | Any random string — only used inside the macOS-15 runner |

API key role: **App Manager**.

## Workflow rules for agents (Karpathy-style)

1. **Surface assumptions before coding.** If the request is ambiguous, list 2–3 interpretations and ask.
2. **Surgical changes only.** Do not reformat, do not "improve" adjacent code, do not add type hints to code you didn't touch.
3. **No drive-by refactors.** Even if you see something you'd write differently, leave it alone unless the user asks.
4. **Declarative > imperative.** Don't fix bugs blind — write a failing test first, then make it pass.
5. **Boundary set.** `Protocol/` is sacred (see above). The 9 BOOTSTRAP_WRITES are byte-identical to the iPad capture.
6. **Single commit per feature.** Group related file changes; don't sprinkle.
7. **Honor the unsigned build path.** `CODE_SIGNING_REQUIRED: NO` is intentional — it lets `build.yml` produce dev IPAs without a Team ID. Don't remove these settings.
8. **`WatchTelemetryMessage` is duplicated** between `VoltraLive/Bridge/PhoneWatchBridge.swift` and `VoltraWatch/WatchTelemetryStore.swift` (no shared framework). They MUST stay in sync. The enum cases use identical raw `String` values for JSON round-tripping.

## Voltra Brain & Agent Organization (Karpathy Method)

### Filesystem-as-Memory

- Your memory is the filesystem. If a decision, blocker, or
  architectural detail is not written to a markdown file in
  `docs/handoff/`, it does not exist.
- Treat the LLM as the CPU and the repo's markdown files as your RAM.
- Never hold durable knowledge only in chat context.
- Two-plane architecture:
  - **Perplexity "Voltra Brain"** = Orchestrator / Control Plane (no
    repo access).
  - **Claude Code** = Execution Plane (no visibility into Perplexity
    chat).
  - **User** = bridge between the two planes.

### Context Health Check (mandatory, every response)

Every agent response that performs or plans repo work must end with
**exactly one** of:

- `Context is good.`
- `Context is degrading.`
- `Context is dangerously low.`

Definitions:

- **Good:** enough active context to continue safely; < 6 turns since
  last summary.
- **Degrading:** context is getting long or fragmented; 6–9 turns
  since last summary. Warn user.
- **Dangerously low:** ≥ 10 turns since last summary, or agent is
  losing track of prior decisions. Stop feature work immediately and
  write a context checkpoint before continuing.

### 10-Turn Auto-Summary Protocol

After every 10 user↔agent back-and-forths, the agent must
automatically:

1. Pause current work.
2. Generate a compact rolling summary.
3. Append it to `docs/handoff/CONTEXT_LEDGER.md`.
4. Stage and commit the update to Git before writing any more code.

The summary must include:

- Timestamp
- Current branch and head SHA
- Active goal
- Decisions made since last summary
- Files changed or planned
- Commands run or awaiting approval
- Blockers / risks
- Next exact action
- Context health assessment

If context becomes "dangerously low" before turn 10, trigger the
summary early.

For the Perplexity control-plane: Voltra Brain will produce a
paste-ready summary block after every 10 turns. The user pastes it to
Claude Code, which appends it to `CONTEXT_LEDGER.md`.

### Handoff-doc enforcement (mandatory, every code commit)

Every commit that changes code MUST include, in the same commit:

- `docs/WORK_LOG.md` — append an entry (always, no exceptions).
- `docs/handoff/00_START_HERE.md` — update if branch, head SHA,
  completed state, or next step changed.
- `docs/handoff/CONVERSATION_LOG.md` — append if a new decision,
  blocker, workaround, or deviation from plan occurred.
- `docs/handoff/CONTEXT_LEDGER.md` — append if 10-turn checkpoint
  reached or context health degrading / dangerous.

Do not commit code without updating these docs. If asked for a
code-only commit, append a `WORK_LOG` entry explaining why docs were
deferred.

### Karpathy Select Rule

When starting a task, read only what's needed in this order:

1. `AGENTS.md`
2. `docs/handoff/AGENT_WORKFLOW.md` (universal workflow rules)
3. `tasks/lessons.md` (most recent ~10 entries — self-improvement loop)
4. `tasks/todo.md` (current task plan, if any)
5. `docs/handoff/00_START_HERE.md`
6. Current feature spec (e.g., `SESSION_RECORDER_SPEC.md`)
7. `docs/handoff/CONVERSATION_LOG.md` (tail only)
8. `docs/handoff/CONTEXT_LEDGER.md` (latest 3 entries)
9. `docs/WORK_LOG.md` (tail only)

Do **NOT** read full transcripts or all handoff docs unless explicitly
asked. **Select, don't dump.**

### Karpathy Leash Constraints

Every substantive instruction from Voltra Brain to Claude Code must
include:

1. **Clear instruction** — what to do, step by step.
2. **Constraints** — explicit "do not" list.
3. **Scope** — which files / branches are in / out of bounds.
4. **Stopping criteria** — when to stop and report back.

Claude Code must refuse to proceed if any of the four is missing and
ask the user to supply it.

## Universal agent workflow (added 2026-05-03 — sticky for all agents)

Full spec: **`docs/handoff/AGENT_WORKFLOW.md`** — every agent
must read it at session start alongside this file (Karpathy
Select Rule, step 1).

Non-negotiables, repeated here so they cannot be missed:

1. **Plan first.** For any non-trivial task (3+ steps or any
   architectural decision), write the plan to `tasks/todo.md`
   as a markdown checklist BEFORE writing code. Get user
   approval on the plan. Tick items as you work. Add a
   `## Review` block when done.
2. **Verification before done.** Never mark a task complete
   without proving it works — tests run, logs checked, diff
   against `main` reviewed when relevant. "Would a staff
   engineer approve this?" is the bar.
3. **Self-improvement loop.** After ANY user correction,
   append a structured entry to `tasks/lessons.md` (mistake →
   trigger → correction → rule for next time). Skim recent
   entries at session start.
4. **Subagent strategy.** Offload research, exploration, and
   parallel analysis to subagents to keep the main context
   clean. One task per subagent.
5. **Demand elegance (balanced).** For non-trivial changes,
   pause and ask "is there a more elegant way?" before
   committing. Skip for simple obvious fixes — do not
   over-engineer.
6. **Autonomous bug fixing.** Bug reports get fixed, not
   discussed. Point at the failing log/test, then resolve it.
   Go fix failing CI without being told how.
7. **Core principles.** Simplicity first, no laziness (find
   root causes, not temporary patches), minimal impact (only
   touch what's necessary).

These rules **stack on** the existing Karpathy workflow rules
(§"Workflow rules for agents") and handoff-doc enforcement —
they do not replace them. When in doubt, sacred-files rules
win, then this section, then `AGENT_WORKFLOW.md`.

## Cost-awareness convention (user preference, persistent)

The user wants visibility into how token-heavy each action is. Apply both rules below on every task:

### Lite / medium / heavy bucketing

Before running any action that's **medium** or **heavier**, flag it inline with a bucket label so the user can intercept. Lite actions don't need flagging — they're the noise floor.

- **Lite** (~1× baseline): a chat reply, a file read/edit/write, one web search, one URL fetch, a memory read/write, a single shell command or git op.
- **Medium** (~3–10×): a `browser_task`, one default-model `run_subagent` on a small task, a CI polling loop (each poll is lite but a 14-iter × 2-loop ship is medium overall), basic image generation, loading a skill with helpers. **A normal ship cycle (commit → push → dry-run → tag → ship → poll both) is medium.**
- **Heavy** (~20–100×): `wide_research` / `wide_browse` with 10+ entities, a long Opus/GPT-5 subagent run, deep multi-source research, building a full website, video generation, extended-context subagents.
- **Very heavy** (~100×+): premium video at full quality / multi-minute clips, multi-model councils run by the agent itself, massive wide_research jobs (50+ entities deep).

After heavier actions, give a one-line cost callout (e.g. "this ship was medium: 2 polling loops + several file reads").

These buckets are mental-model order-of-magnitude only. The agent does not have a per-action credit meter; the user's Computer settings/billing page is the source of truth for actual numbers. Never invent specific credit counts.

### Council/heavy-research delegation (default)

The user has a Perplexity model council on their own account. **By default, when a task would benefit from a model council OR from heavy research (multi-frontier-model comparison, deep multi-source synthesis, comparing many entities), DRAFT the prompt for the user to run themselves and save it as a markdown file in `docs/handoff/COUNCIL_*_PROMPT.md`** instead of running the heavy work on Computer credits.

The council prompt must be self-contained:
- All facts/context grounded in real code and file contents (read the files first — don't paraphrase from memory)
- Hypotheses already ruled out, with evidence for each
- An explicit **"How to respond"** section specifying response structure, length cap, and any required sections (root cause, verification step, fix recommendation, confidence level, backup hypothesis, citations)
- Copy/paste-ready below a `---` line so the user can grab it without editing

The user runs the prompt and reports back the answer; the agent acts on it. **Only run the heavy work directly on Computer when the user explicitly says "do it yourself" or "do the work yourself."**

This convention also lives in the user's persistent memory and applies across all sessions and any future agent that picks up this repo.

## Known caveats / future migrations

- **`altool` is being deprecated** by Apple. Still works in Xcode 16; migrate to `xcrun notarytool` before Apple removes support.
- **Web prototype is abandoned** — `voltra-live/` (sibling dir) exists but is no longer the path forward. Native is canonical.

## Deferred / known follow-ups

### Apple Watch companion (v1.2)

Attempted in commit `fd89ea4`, rolled back in commit `<watch-rollback>` after 4 CI failures.
Root cause: XcodeGen's `dependencies: - target: VoltraWatch, embed: true` on the iOS target
compiled the watchOS sources as part of the iOS build phase (`error: no such module 'WatchKit'`),
not just embedding the pre-built artifact.

**To revisit cleanly:**
1. Use a **separate Xcode project** for VoltraWatch (`xcodegen` per-platform), not a separate target in the same project. iOS host references the Watch project as an external dependency.
2. OR use Xcode's native "Add Watch App" wizard (don't try to xcodegen this) and commit the generated `.xcodeproj` directly.
3. Either way, do it in a clean PR with a green CI baseline. The hardening done in this commit (`AGENTS.md`, `VALIDATION.md`, protocol tests, dry-run path) survives the rollback and helps for the retry.

**What's already done (and re-usable when Watch returns):**
- `WatchTelemetryMessage` JSON schema design (5Hz force throttle, 1Hz rest tick)
- `PhoneWatchBridge` Combine wiring (saved in git history at `fd89ea4`)
- VALIDATION.md Watch lines (S2, C4, R3, R4, P5, F4, SC2, SC3, SC4) — mark SKIP until Watch ships
- App icon design (re-usable for Watch with role-sized renders: 88x88, 100x100, 102x102, 108x108, 117x117 @2x)

## How to know your changes are good

1. `xcodegen generate` succeeds with no errors.
2. `xcodebuild test -scheme VoltraLive -destination 'platform=iOS Simulator,name=iPhone 15'` passes.
3. CI `build.yml` stays green on push.
4. CI `release.yml` dry-run produces an IPA artifact.
5. The 4 assertions in `VALIDATION.md` still hold when the user runs against real hardware.

If any of these regress, **revert** rather than try to fix forward. The protocol layer is more
important than any feature.

## Audit cadence (added post-b54)

External audits stress-test the handoff documentation by asking an
independent agent to attempt a black-box rebuild from docs alone.
Prompts live in `docs/audits/`. See `docs/audits/README.md` for the
full setup.

**Run an audit when any of these triggers fire:**

1. Before tagging any release `v0.5.0` or higher.
2. After any commit that touches `docs/handoff/` and changes ≥ 100
   lines across ≥ 3 files in one go (high churn = high risk of
   inconsistency).
3. After any architectural change to a sacred-adjacent area (BLE
   write path, SwiftData migrations, routing source of truth).
4. On user request, ad hoc.

**How to log an audit run:**

Append a `## AUDIT — YYYY-MM-DD — <model> — Flavor <X>` entry to
`docs/WORK_LOG.md` with: the model used, repo HEAD at audit start,
verdict score, and the path to the run subdirectory under
`docs/audits/runs/`. Do not edit past audit outputs — they're
append-only history.

**Do not run audits from a chat interface without filesystem access.**
The prompts require reading dozens of repo files directly. Use
Claude Code, Cursor, Antigravity, or Codex CLI.

## Post-build QA checklist (added b58 — sticky for all builds)

Sticky user requirement: after every TestFlight build ships, the
agent must run a **post-build verification checklist** in the
same message as the ship confirmation. No exceptions.

**Format:**

1. List every feature, fix, or addressable item shipped in this
   build (sourced from the build's spec or `WORK_LOG.md` entry).
2. Ask the user a 2-option multiple-choice question for each
   item, using `ask_user_question`:
   - "Working as intended"
   - "Not working as intended"
   ("Other" is auto-included by the tool — no need to add it.)
3. Up to 4 items per `ask_user_question` call (tool limit).
   For builds with > 4 items, send sequential calls.
4. For each item the user marks **"Not working as intended"**,
   follow up with **another** `ask_user_question` containing
   targeted multiple-choice options about what specifically is
   wrong (e.g. "the gradient renders in the wrong direction",
   "the label overlaps the polyline", "the toggle does nothing").
   Always leave room for "Other" (auto-included) so the user can
   describe in free text.

**Persistence:**

- Append every QA pass to `docs/handoff/QA_LOG.md` (append-only),
  one section per build. Format:
  ```
  ## bNN — vX.Y.Z-buildNN — YYYY-MM-DD
  ### Items shipped
  - <feature/fix 1>
  ### User responses
  - Item 1: Working as intended
  - Item 2: Not working as intended → <follow-up answer>
  ### Actions taken
  - <linked KI-N entry, fix commit, or deferred>
  ```
- Confirmed regressions (items marked "Not working as intended"
  that we cannot fix in the same session) **must** be added to
  `docs/handoff/06_KNOWN_ISSUES.md` as a new `KI-N` entry, with
  the user's follow-up details captured verbatim.

**Why this exists:**

The user is the only one running the app on real hardware. CI
green + altool 5-gate verification proves the build *uploaded*,
not that the *features work*. This checklist closes that gap.
