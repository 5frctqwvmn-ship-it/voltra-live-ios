# 00 — START HERE

> **You are an LLM agent (or future-me) starting a session on this repo.**
> The repo is the source of truth, not chat memory. Read these files in
> the order below **before** writing any code, then summarize the current
> state back to the user.

## Mandatory startup sequence (read in this order)

1. `AGENTS.md` (repo root) — sacred files, hard constraints, signing.
2. **This file** — `docs/handoff/00_START_HERE.md` — branch state, plan,
   commit cadence, approval policy, hard stops.
3. `docs/handoff/CONVERSATION_LOG.md` — append-only log of decisions,
   blockers, and deviations from plan across sessions. Must be updated
   in the same commit as any code change going forward.
4. `docs/handoff/CONTEXT_LEDGER.md` — rolling 10-turn context
   summaries. Read the **latest 3 entries**, not the whole file.
5. `docs/handoff/PERPLEXITY_TRANSCRIPT_2026-05-02.md` — complete
   verbatim transcript of the Perplexity AI advisory chat that
   directed this implementation session. Read this for full "why"
   context behind the decisions in `CONVERSATION_LOG.md`.
6. `docs/handoff/SESSION_RECORDER_SPEC.md` — authoritative spec for the
   feature currently in flight (B74-F11).
7. `docs/handoff/01_PROJECT_OVERVIEW.md` through
   `docs/handoff/10_OPEN_QUESTIONS.md` — the rest of the handoff binder
   (what the app is, current state, roadmap, architecture, BLE protocol,
   HealthKit, dual-Voltra, superset, release/signing, open questions).
8. `docs/WORK_LOG.md` — tail (last ~200 lines) for recent activity.

Apply the **Karpathy Select Rule** in `AGENTS.md`: read only what's
needed. Do not dump full transcripts or all handoff docs unless
explicitly asked.

**Then summarize state back to the user. Do not edit anything until you
have done this.**

## Active branch state (no feature in flight)

- **Branch:** `feat/ui-v4-2-claude` (integration branch).
- **Last shipped:** **v0.4.50 / build 77 — "Session Recorder" — B74-F11.**
  Tag `v0.4.50-build77`. PR #10 merged at `88a4eaf`. The full
  Session Recorder feature (3 implementation commits + 2 checkpoint
  commits + 1 CI fix + 2 docs-log commits) lives on this branch.
- **Working tree:** clean except `.claude/` is untracked. **NEVER stage
  `.claude/`.**
- **Goal:** none in flight; awaiting next feature request.

## Plan (3 logical commits → one PR against `feat/ui-v4-2-claude`)

### Commit 1 — Core engine ✅ DONE at `76becdf`

- 11 files, 1098 insertions.
- New: `VoltraLive/Recorder/{RecorderEvent, RecorderBuffer, RecorderRedactor,
  ActionScope, RecorderExporter, SessionRecorder, View+RecorderScreen}.swift`.
- New tests: `VoltraLiveTests/{RecorderBufferTests, RecorderRedactorTests,
  RecorderExporterTests, ActionScopeTests}.swift`.
- Pure engine — no app mounts, no overlay, no instrumentation.

### Commit 2 — Root overlay + viewer + share + screen tags ✅ DONE

- New: `VoltraLive/Recorder/SessionRecorderToggle.swift` —
  24×24 pt bottom-trailing dot, hidden until `VOLTRARecorderUnlocked`,
  tap = toggle, long-press = open viewer, red 1 Hz `TimelineView` pulse
  while recording, `textFaint` while idle.
- New: `VoltraLive/Recorder/SessionRecorderViewer.swift` —
  event list + category filters + `ShareLink` exporting both `.txt` and
  `.json` payloads.
- Edit: `VoltraLive/VoltraLiveApp.swift` —
  `@StateObject SessionRecorder.shared`, `.environmentObject`,
  `.overlay(alignment: .bottomTrailing) { SessionRecorderToggle() }`,
  scenePhase observer to call `recorder.persist()` on background.
- Edit: `VoltraLive/Views/BuildBadgeOverlay.swift` —
  add a `TapGesture(count: 3)` that flips
  `UserDefaults["VOLTRARecorderUnlocked"] = true`. Existing single-tap
  grid cycle stays. SwiftUI's ~250 ms count-disambiguation delay is
  acceptable per spec.
- Edit ~13 top-level screens to add `.recorderScreen("ScreenName")`.

### Commit 3 — Instrumentation + loud guards + docs ✅ DONE

- Additive BLE sinks in `VoltraBLEManager.swift`, `VoltraWriter.swift`,
  `MultiDeviceManager.swift` — **NO behavior change**.
- HealthKit read-only instrumentation in `HealthKitStore.swift`.
- `ActionScope` wrapping for major UI actions.
- Convert user-visible silent `guard … else { return }` to
  `rec.guardTrip(...)` then return. **Bounded to user-visible paths
  only** per spec wording.
- Doc updates: `03_CURRENT_FEATURE_SPEC.md`, `07_FILE_MAP.md`,
  `09_NEXT_AGENT_PROMPT.md`, `WORK_LOG.md`,
  `CONVERSATION_LOG.md` (append). `04_DECISIONS_AND_CONSTRAINTS.md`
  only if implementation diverges from V4-D25.

## Context protocol

Fresh agents must:

- Report **context health** at the end of every response that performs
  or plans repo work — exactly one of `Context is good.`,
  `Context is degrading.`, or `Context is dangerously low.` See
  `AGENTS.md` "Context Health Check" for thresholds.
- Append a rolling summary to
  `docs/handoff/CONTEXT_LEDGER.md` every 10 turns, or sooner if
  context health drops to degrading / dangerously low.
- Stage and commit the ledger update to Git before writing more code.

This protocol is enforced by `AGENTS.md` "Voltra Brain & Agent
Organization (Karpathy Method)".

## Commit cadence

Push the branch every ~10 turns even if mid-implementation. The remote
is the durable backup. Don't let work pile up locally.

## Approval policy

- **AUTO (no pause needed):**
  - File reads, `Glob`, `Grep`.
  - Edits inside the route map (files in the table above).
  - `git add <named paths>` (never `-A`).
  - Descriptive commits with bot identity:
    `git -c user.name="VOLTRA Live Bot" -c user.email="bot@voltralive.app" commit ...`.
- **PAUSE (surface intent first):**
  - Edits to `VoltraLive/VoltraLiveApp.swift`,
    `VoltraLive/Views/BuildBadgeOverlay.swift`, BLE files
    (`VoltraBLEManager.swift`, `VoltraWriter.swift`,
    `MultiDeviceManager.swift`), `VoltraLive/Health/HealthKitStore.swift`.
- **REJECT (do not do without explicit permission):**
  - `.github/workflows/*` changes.
  - `project.yml` changes.
  - Release / TestFlight / version bump.
  - Anything touching secrets.
  - `git add -A` or `.claude/` staging.
  - `git rebase -i`, `git push --force` to a shared branch.

## Hard stops (from `SESSION_RECORDER_SPEC.md`)

- No `Info.plist` changes.
- No `project.yml` changes.
- No entitlements changes.
- No `.github/workflows/*` changes (build / release).
- No release workflow / TestFlight ship / version bump in this PR.
- No `git add -A`.
- No staging of `.claude/`.
- No `git rebase`. No `git push --force`.
- No BLE runtime behavior change.
- No `WatchConnectivity` runtime behavior change.
- No server / network calls. No analytics. No external logging.
- No per-screen toggle buttons (overlay is root-only).
- No new silent guards anywhere.

## Windows host limitation

The session is running on Windows. **Cannot run** `xcodebuild`, `xcrun`,
the iOS Simulator, or any Swift compile / test step. Compile + tests
will be exercised by `build.yml` when the PR opens. Every PR description
must include an explicit **"Could not verify"** section listing
everything the agent could not run on Windows.

## PR description requirements

The implementation PR (against `feat/ui-v4-2-claude`) must include, at
minimum:

1. **Spec clause → file/line mapping table** —
   each clause from `SESSION_RECORDER_SPEC.md` mapped to the file (and
   line, where useful) that implements it.
2. **Full touched-file list** — every file added or edited across all
   three commits.
3. **Every `.recorderScreen("Name")` tag added** — so reviewers can grep
   coverage at a glance.
4. **Every loud-guard conversion** — old `guard … else { return }` →
   new `rec.guardTrip(...)` paired with file/line.
5. **"Could not verify" section** — explicit listing of what was not
   verifiable on the Windows host (xcodebuild compile, unit-test run,
   simulator UI, ShareLink behavior, SwiftUI gesture timing, etc.).

## Last shipped (informational)

**v0.4.50 / build 77 — "Session Recorder" — B74-F11.** Local-only
AI-readable debug recorder with redaction-by-default, 10,000-event
FIFO buffer, `.txt` + `.json` export via `ShareLink`, and additive
instrumentation across BLE chokepoints + HealthKit sample arrivals.
9 user-visible silent guards converted to loud `guardTrip`. Hidden
24×24 dot under the root overlay (triple-tap on the build-badge
chip to unlock). Persists to
`Application Support/SessionRecorder/last_session.json` on
background. Tag `v0.4.50-build77`. See `02_CURRENT_STATE.md` for
the rolling cycle snapshot and `03_ROADMAP.md` for what's queued.

**Prior shipped: v0.4.49 / build 76 — "Health signal indicator" —
B74-F8.**

## Sacred files (do not modify without explicit user approval)

See `AGENTS.md` "Sacred files":

- `VoltraLive/Protocol/VoltraProtocol.swift`
- `VoltraLive/Protocol/TelemetryExtractor.swift`
- `VoltraLive/Protocol/PacketParser.swift`
- `VoltraLive/Protocol/FrameAssembler.swift`

New protocol-adjacent code goes in **new files only**.

## Karpathy method

Before doing anything substantial, **repeat the user's request back** so
they can correct your understanding. Don't just start executing.

## Mandatory commit discipline

- Append a `CONVERSATION_LOG.md` entry for any new decision, blocker, or
  deviation from plan, **in the same commit as the code change**.
- Append a `docs/WORK_LOG.md` entry for any meaningful change, in the
  same commit.
- Update the topic doc whose subject area changed
  (`05_BLE_AND_PROTOCOL.md`, `06_HEALTHKIT.md`,
  `03_CURRENT_FEATURE_SPEC.md`, etc.) in the same commit.

## Index of handoff docs

| File | Owns |
|---|---|
| `00_START_HERE.md` | This file. Startup sequence, branch state, plan, policy. |
| `CONVERSATION_LOG.md` | Append-only log of decisions, blockers, plan deviations. |
| `CONTEXT_LEDGER.md` | Rolling 10-turn context summaries (Karpathy method). |
| `PERPLEXITY_TRANSCRIPT_2026-05-02.md` | Verbatim Perplexity advisory chat transcript for the B74-F11 implementation session. |
| `SESSION_RECORDER_SPEC.md` | Authoritative B74-F11 spec. |
| `01_PROJECT_OVERVIEW.md` | What the app is, who it's for, hardware. |
| `02_CURRENT_STATE.md` | What's shipped, build numbers, rolling cycle snapshot. |
| `03_ROADMAP.md` | What's next and why. |
| `03_CURRENT_FEATURE_SPEC.md` | Live-capture screen behavior at the latest ship. |
| `04_ARCHITECTURE.md` | Module map, data flow, key types. |
| `04_DECISIONS_AND_CONSTRAINTS.md` | Append-only decision log (ADRs). |
| `05_BLE_AND_PROTOCOL.md` | Wire format, control writes. |
| `06_HEALTHKIT.md` | HR + active calories streaming. |
| `06_KNOWN_ISSUES.md` | Active KI tracker. |
| `07_DUAL_VOLTRA.md` | Dual-device spec. |
| `07_FILE_MAP.md` | Per-feature file placeholders / EXISTS table. |
| `08_SUPERSET.md` | Superset spec. |
| `09_RELEASE_AND_SIGNING.md` | Version bumps, tags, CI, secrets (names only). |
| `09_NEXT_AGENT_PROMPT.md` | Cold-start prompt for fresh-context agents. |
| `10_OPEN_QUESTIONS.md` | What's blocked on user input right now. |
| `B74_BUG_QUEUE.md` | Active B74 bug queue (F1–F8, F11). |
| `QA_LOG.md` | Append-only post-build QA pass log. |

`docs/WORK_LOG.md` lives one level up — append-only journal of every
change.
