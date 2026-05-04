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

---

## 2026-05-02 — B74-F11 Commit 2 (root overlay + viewer + share + screen tags)

**Decision (small Commit 1 file edit):** added `CaseIterable`
conformance to `RecorderCategory` in
`VoltraLive/Recorder/RecorderEvent.swift` so the viewer's filter
chips can iterate categories. The change is single-line, additive,
and backwards-compatible with the Codable representation.

**Why:** the viewer needs to enumerate categories to render its
filter row; without `CaseIterable` we'd hand-list them, and any
future category added to the enum would silently fail to surface a
chip.

**How to apply:** future enums consumed by SwiftUI iteration should
declare `CaseIterable` from the start.

**Decision (toggle placement):** the recorder dot uses
`.padding(.bottom, 36)` so it sits above the existing build-badge
chip in the same bottom-trailing safe area. Both overlays share that
corner; the dot is the outer overlay (declared on the WindowGroup
ContentView chain after `.onChange(of: scenePhase)`) and the chip is
the inner one (applied on `ContentView` via `.buildBadgeOverlay()`).

**Decision (build-badge gesture order):** triple-tap declared
**before** the existing single-tap on the chip so SwiftUI's
gesture-disambiguation prefers the higher count. Single-tap still
cycles the debug grid as before, with a ~250 ms delay introduced by
the disambiguation window. Spec accepts this; needs QA verification
on device.

**Cross-refs:** `SESSION_RECORDER_SPEC.md` "Activation" + "Toggle" +
"UI Mount"; `SessionRecorderToggle.swift`,
`SessionRecorderViewer.swift`, `VoltraLiveApp.swift`,
`Views/BuildBadgeOverlay.swift`.

---

## 2026-05-02 — B74-F11 Commit 3 (instrumentation + loud guards)

**Decisions:**

- **Layered BLE write events.** `VoltraWriter.send` emits
  `ble.write.tx` with the high-level intent label
  (e.g. `"base=120"`); `VoltraBLEManager.writeControlFrame` emits
  another `ble.write.tx` with the actual bytes. Reviewers reading
  the export should expect both per writer-driven write — that's
  intentional layering (intent vs. transmission), not a duplicate.

- **`HKSource.name` and `bundleIdentifier` use `unsafeRaw`
  passthrough.** Per the spec these are the only redactor
  passthrough call sites for HK data. Rationale: those are
  developer-controlled identifiers (e.g. `"Apple Watch"`,
  `"com.apple.health"`), not user PII. All other HK sample
  metadata is typed (`.int`/`.double`) which doesn't flow through
  the redactor.

- **Loud-guard sweep limited to user-visible paths.** Converted 9
  guards across `LoggingHomeView`, `LiveCaptureViewV2`,
  `LiveCaptureView`. Left silent: programmer-facing delta-clamp
  invariant (`adjustDropStep` line 1641), `.onAppear`/`.onChange`
  observer guards, `attach(ble:)` writer-init invariant, and the
  two `VoltraWriter` cooperative-cancellation/flush guards. Per
  spec wording "user-visible paths only."

- **ActionScope wrap diff style.** Function bodies wrapped via
  `SessionRecorder.shared.action(...)` helper but the inner body
  is NOT re-indented. The wrapper sits at the same indent level as
  the original body. Swift tolerates the misindentation; the diff
  stays surgical (would otherwise touch every line of every
  wrapped function).

- **V1 (`LiveCaptureView`) wrapped for parity.** `sendLoad` and
  `sendUnload` got the same `action()` wrap as V2 even though V1
  is a rollback artifact reachable only via the kill switch.
  Cheap (2 small functions); benefit is uniform recorder coverage
  if a user ever flips back to V1.

- **`VoltraLiveApp` scenePhase observer extended (pause gate #6
  approved).** Existing `recorder.persist()` call retained;
  added `lifecycle.appBackground`/`lifecycle.appForeground` events
  alongside it via a `switch` on `newPhase`.

- **10k buffer overflow during long live sessions is by design.**
  At ~10–50 Hz `ble.notify.rx` rate, ~3 minutes of live BLE
  activity will start dropping the oldest events. FIFO + current-
  session bias is correct for debugging. Documented in WORK_LOG
  risks.

**Cross-refs:** `SESSION_RECORDER_SPEC.md` "Instrumentation Scope"
+ "Hard Stops" + "Verification Contract"; `VoltraBLEManager.swift`,
`VoltraWriter.swift`, `Dual/MultiDeviceManager.swift`,
`HealthKitStore.swift`, `VoltraLiveApp.swift`, `LoggingHomeView.swift`,
`LiveCaptureViewV2.swift`, `LiveCaptureView.swift`,
`07_FILE_MAP.md`, `03_CURRENT_FEATURE_SPEC.md` §10.

---

## Session: 2026-05-03 — Telemetry v2 first Swift slice (base-weight decoder)

### Decision

- **User decision.** Proceed with Telemetry v2 as the main track;
  defer the drop-set stuck UI bug (KI-19). Telemetry/device-state
  foundation should help debug + fix drop sets later.
- **Scope landed in this commit.** Additive BLE frame decoder,
  `DeviceState` + reducer, pending/confirmed source attribution,
  `device.state.change` semantic recorder event — all scoped to
  **base weight only**.
- **Explicitly deferred.** Drop-set stuck bug, eccentric / chains /
  mode decode, `LoadState` + stream-gap detection, treating `0x03`
  as unloaded/fault, export compression / session summary, removing
  duplicate `ble.write.tx` events.

### Why base-weight first

- Highest-confidence hypothesis: `setBaseWeightPayload(N)` produces
  `01 00 86 3E <lo> <hi>` (uint16-LE) per the captured iPad frames
  in `VoltraControlFramesTests`. The May-2026 hardware session
  observed `86 3e 5f / 14 / 0f` substrings, which decode to
  95 / 20 / 15 lb under that rule. Byte-vector parity with the
  writer side pins the hypothesis — see new `05_BLE_AND_PROTOCOL.md`
  §"Base-weight confirmation byte layout" and resolved OQ-T0 in
  `10_OPEN_QUESTIONS.md`.
- It also directly addresses the highest-impact known issue
  (KI-20: machine-side dial changes not reaching the app).

### Sacred-files invariant

Verified zero edits to `VoltraProtocol.swift`,
`TelemetryExtractor.swift`, `PacketParser.swift`,
`FrameAssembler.swift`, `.github/workflows/build.yml`. The legacy
0xAA telemetry pipeline keeps emitting exactly what it emits today;
the new decoder runs alongside it on the same `FrameAssembler`
output and writes to a separate `@Published deviceState`.

### Out-of-scope intentionally

- LiveCaptureView's base-weight tile does NOT yet read
  `deviceState.baseWeightLb?.value`. Closing KI-20 end-to-end
  needs that UI bind in a follow-up commit so revert granularity
  stays one wire-change per commit.
- `xcodebuild test` not run in this session (Linux sandbox, no
  Swift toolchain). Tests included with the slice; CI / hardware
  verification gates the next commit.

---

## Session: 2026-05-03 — Telemetry v2 base-weight UI bind (LiveCaptureViewV2)

### Starting situation

- Branch `feat/ui-v4-2-claude` at `da34cd4` ("feat: add base-weight
  device state decoder"). Clean tree.
- KI-20 still "in progress" — decoder + reducer + recorder events
  shipped at `da34cd4`, but no UI consumer of
  `VoltraBLEManager.deviceState.baseWeightLb` yet.
- Token-saver mode: user supplied a precise patch script, so the
  agent did not freelance design.

### Decisions

1. **File path correction.** Patch spec named the V2 view file as
   `VoltraLive/Features/LiveCapture/LiveCaptureViewV2.swift`. The
   actual canonical location in this repo is
   `VoltraLive/Logging/Views/LiveCaptureViewV2.swift` (single V2
   file, no Features/ directory). Edited the real path.
2. **Type-name verification before editing.** Confirmed
   `ConfirmedValue<T>` in `VoltraLive/BLE/State/DeviceState.swift`
   has `.value` and `.source`, and that
   `DeviceStateChangeSource.deviceUnsolicited` is the literal
   enum case in `VoltraLive/BLE/Decoder/VoltraDecodedEvent.swift`.
   No name collisions; patch applied verbatim.
3. **Display intentionally remains driven by local planned
   weight.** The WEIGHT card big number still computes off
   `(logging.pendingPlannedWeightLb ?? 0) * pulleyMultiplier`;
   the bridge writes machine-originated changes INTO that local
   store rather than swapping the display source. Rationale:
   keeps app-side `+/-` taps visually instant; avoids round-trip
   lag through device echo + decoder + reducer + publish on every
   user tap.
4. **Filter is `.deviceUnsolicited` only.** App-issued writes are
   already reflected locally by `adjustWeight`, and
   `appRequestConfirmed` echoes must never feed back into
   `pendingPlannedWeightLb` lest a follow-up tap be clobbered
   mid-flight.
5. **Two-parameter `.onChange(of:_:_:)` form.** Already in use in
   this file at line 340 (`mdm.supersetActiveSlot`); iOS 17
   minimum supports it. No fallback to one-param form needed.
6. **Single observer point** — wired next to the existing
   `.pageBadge`/`.recorderScreen` modifiers on the outermost
   chain in `body`, so the observer lives at the same scope as
   the screen-level lifecycle hooks.

### Out of scope intentionally

- Drop-set stuck fix.
- Eccentric / chains / inverse-chain decode.
- `LoadState` / cutout handling.
- Duplicate `ble.write.tx` cleanup.
- Export summary changes.
- Layout rewrite of `weightCard`.
- Touching `adjustWeight`, `pushUpcomingStateToDevice`,
  `toggleHardwareLoad`, `tapDropTile`, or `WriterRouter.apply`.

### Sacred-files invariant

Verified zero edits to `VoltraProtocol.swift`,
`TelemetryExtractor.swift`, `PacketParser.swift`,
`FrameAssembler.swift`, `.github/workflows/build.yml`,
`project.yml`. No version/build bump.

### Verification

- Static review only. No Swift toolchain in this Linux sandbox;
  `xcodebuild test` must run on macOS/CI.
- `git diff --name-only` shows only the V2 view + four doc files.

### Status

- KI-20 moves from "in progress" to
  "implemented-pending-hardware-verification". NOT fully closed
  until hardware re-verification confirms a dial twist updates
  the WEIGHT tile end-to-end with the recorder armed.

### Not pushed

Per standing rule, the resulting commit is local-only. User must
explicitly request `git push`.

---

## 2026-05-03 — KI-20 visual bridge fix (post-A1 failure)

**Context.** Hardware A1 test on build 79 proved the decoder,
reducer, PendingWriteTracker, and recorder all worked for device-side
20→15 lb change (`device.state.change source=deviceUnsolicited to=15`
confirmed in session `7A15529C-5EA5-4B34-A91A-A07840048ED8`). But the
LiveCapture tile did NOT visually update.

**Decision.** Replace the computed `.onChange` key
(`focusedConfirmedBaseWeightValue = focusedBle.deviceState.baseWeightLb?.value`)
with a dedicated `@Published deviceOriginatedBaseWeightUpdate` on
`VoltraBLEManager`, set only on `.deviceUnsolicited` base-weight
changes. Add `.onAppear` reconciliation. This is the minimal
mechanical fix \u2014 no decoder changes, no behavior changes to the app
write path (B1 continues to work).

**Why not bind tile directly to `deviceState.baseWeightLb?.value`.**
Driving the WEIGHT tile number directly from device state would
introduce perceptible lag on every app `+/-` tap (write \u2192 device
echo \u2192 decoder \u2192 reducer \u2192 publish). The bridge into
`pendingPlannedWeightLb` keeps tap responsiveness while still letting
machine-side dial moves win.

**KI-20 remains OPEN.** Pending hardware retest with the new build.

---

## 2026-05-04 — RC-01/SC-01 coaching card integration

**Context.** Operator supplied `VoltraCoaching_v3.swift` single-file source
for the rest-state Coaching Card + Smart Coach rule engine. Task was to
split it into target files and wire it into LiveCaptureViewV2.

**Key decisions.**

1. All `FeatureFlags` default `false`. `coachingCardEnabled` must be
   manually set to `true` to see any coaching UI. Ships dark until KI-20
   retest passes and coaching is explicitly enabled for a TestFlight build.

2. Fatigue gate will always be `.unknown` until `LoggedSet` gains per-rep
   force fields (`bestRepForceLb`, `lastRepForceLb`). This is correct
   and intentional — `.unknown` gate suppresses aggressive option and
   sets confidence to `.low`. Engine still provides useful recommendations
   based on weight history alone.

3. Buttons route through `adjustWeight(delta:)` not direct property write.
   `adjustWeight` enforces `CombinedParity` + `reanchorCascadeIfActive`.

4. `allExerciseInstances(for:)` added to `LoggingStore` — fetches all
   `ExerciseInstance` rows then filters in Swift to avoid SwiftData
   `#Predicate` issues with optional relationship traversal on
   `inst.exercise?.name`.

5. `SetSnapshotBuilder` fills `bestRepForceLb/lastRepForceLb` with `nil`
   (not synthesized from `peakForceLb`) — keeping the fatigue gate honest.

6. Panel switch uses `AnyView` type erasure inside `forceChartCard`
   (`some View` computed var with two branches of different concrete type).

7. Debounce trigger is `session.restActive` onChange, not device force
   level — consistent with how `phaseOrRestBar` already works.

**What was NOT changed.** Sacred files. KI-20 topology fix. focusedBle
routing. Existing telemetry/recorder. BLE write path. project.yml.
