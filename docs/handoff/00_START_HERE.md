# 00 — START HERE

> **You are an LLM agent (or future-me) starting a session on this repo.**
> The repo is the source of truth, not chat memory. Read these files in
> the order below **before** writing any code, then summarize the current
> state back to the user.

---

## ⚠️ CRITICAL — READ THIS BEFORE TOUCHING ANY FILE ⚠️

**`main` is NOT the source of truth for active development.**

`main` is frozen at **v0.4.37 / build 59**. It has not been updated
since b59 shipped. Do NOT read source files from `main` to understand
current app behavior, current bug locations, or current API shapes.

**All builds b60 and later live on one branch:**

```
feat/ui-v4-2-claude
```

Last verified HEAD: `33f57e64d421946fc9ad16a6e1f5ca480cc7a11d`
Last shipped to TestFlight from this branch: **v0.4.52 / build 82**

**Every file read, every bug diagnosis, every code write for b83 and
beyond must target `feat/ui-v4-2-claude`.** If you read a file from
`main` and use it to make a decision, you are working from code that is
23+ builds out of date. This has already caused one agent to write 9
files with the wrong BLE param IDs, duplicate state, and compile errors.

**How to verify you are on the right branch before reading any source
file:**

1. Check that `project.yml` → `CURRENT_PROJECT_VERSION` is **≥ 60**.
   If it reads `59`, you are on `main`. Stop and switch to
   `feat/ui-v4-2-claude`.
2. Check that `MARKETING_VERSION` is **≥ 0.4.38**.
   If it reads `0.4.37`, same problem.

---

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

## Active branch state (Telemetry v2 first slice in flight, post-b82)

- **Branch:** `feat/ui-v4-2-claude` (integration branch).
- **Last shipped to TestFlight:** **v0.4.52 / build 82.** Tag
  `v0.4.52-build82`, TestFlight delivery UUID
  `496678a7-ab0b-4a7d-b08a-d1077c315fb7`.
- **`main` is frozen at b59 / v0.4.37.** Do not use it as a source of
  truth for anything. See the ⚠️ warning at the top of this file.
- **In flight on the branch (not shipped).**
  - Telemetry v2 docs alignment commit `6a3162b`.
  - BLE characteristic audit commit `2636b49`.
  - **Telemetry v2 first Swift slice** (this commit) — additive
    BLE frame decoder + `DeviceState` reducer + base-weight
    confirmation handling. See `03_CURRENT_FEATURE_SPEC.md`
    "Recommended implementation order" steps 2 / 3 / 5 / 7 for the
    partial-status breakdown.
- **Working tree:** clean except `.claude/` is untracked. **NEVER stage
  `.claude/`.**
- **Goal:** ship the Telemetry v2 base-weight slice end-to-end (data
  path landed; LiveCaptureView UI bind to
  `VoltraBLEManager.deviceState.baseWeightLb?.value` is the next
  follow-up commit before this is release-worthy).

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

**v0.4.52 / build 82.** Tag `v0.4.52-build82`. TestFlight delivery UUID
`496678a7-ab0b-4a7d-b08a-d1077c315fb7`. See `02_CURRENT_STATE.md` for
the full feature summary and open bug queue.

**Prior shipped: v0.4.51 / build 78 — "Session Recorder (launch fix)" —
B74-F11 hotfix.** Re-injects `SessionRecorder` env-object directly
on `SessionRecorderToggle()` inside the root `.overlay` closure in
`VoltraLiveApp.swift`. b77 shipped a SwiftUI
`EnvironmentObject.error()` launch crash because
`.overlay { content }` creates a composite where `content` is a
SIBLING of the modified view — env-objects on the modifier chain
do NOT propagate to the overlay's content. New
`VoltraLiveTests/RecorderLaunchSmokeTests.swift` pins the fix via
`UIHostingController` mount + force-layout. Tag `v0.4.51-build78`.
KI-13 in `06_KNOWN_ISSUES.md`.

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

---

## Smart Coach Unlock Contract (2026-05-04)

| Tap count | Target | Action |
|---|---|---|
| 4 taps | Version badge chip | Toggles `VOLTRASmartCoachUnlocked` (UserDefaults). Enables coaching card + Smart Coach. Repeating disables. |
| 3 taps | Version badge chip | Sets `VOLTRARecorderUnlocked = true`. Enables SessionRecorder. |
| 1 tap | Version badge chip | Cycles debug grid density. |

Key file: `VoltraLive/FeatureFlags.swift` — `smartCoachUnlockUserDefaultsKey`.
Spec: `03_CURRENT_FEATURE_SPEC.md` §Smart Coach unlock.
Current state: `02_CURRENT_STATE.md`.
