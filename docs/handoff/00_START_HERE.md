# 00 — START HERE

> **You are an LLM agent (or future-me) starting a session on this repo.**
> Read these handoff docs **before writing any code**. Then summarize the
> current state back to the user before proceeding (Karpathy method).

This folder is the **durable source of truth** for VOLTRA Live iOS. Chat
history is ephemeral — anything that should survive across sessions lives here.

## Mandatory startup sequence

1. Read `AGENTS.md` (repo root) — sacred files, hard constraints, signing.
2. Read `docs/handoff/01_PROJECT_OVERVIEW.md` — what the app is.
3. Read `docs/handoff/02_CURRENT_STATE.md` — what shipped, what's broken.
4. Read `docs/handoff/03_ROADMAP.md` — what's next and why.
5. Read `docs/handoff/10_OPEN_QUESTIONS.md` — anything blocked on user input.
6. Skim `docs/WORK_LOG.md` (tail — last 200 lines is enough) — recent activity in append-only form.
7. Summarize state back to the user. Then start work.

**Last shipped: v0.4.34-build56 ("V2 mods + rest timer + V1 restore").** b56 takes the b55 V2 LiveCaptureView and (a) fixes the bug where ECC / CHAIN / INV CHAIN tiles were unselectable (their `onTap` was nil so `disabled(onTap == nil)` killed taps), (b) replaces the V1 modal `DropSetConfigureSheet` with a tap-arms-deeper-on-each-tap + long-press-cancels + idle-fires interaction (each tap deepens the step `−5 → −10 → −15 → −20…`), (c) adds INV CHAIN as a first-class fourth mod with its own `LoggingStore.upcomingInverseLb / upcomingInverseEnabled` fields and protocol-level `VoltraModifiers.inverse` writeback (CHAIN and INV CHAIN are mutually exclusive — you can't lighten and add through the ROM at the same time), (d) replaces the active phase-strip during rest with a new `RestTimerBarV2` that does a continuous HSL sweep `green(140°,70%,45%) → amber(40°,90%,50%) → red(0°,80%,50%)` and blinks on overtime with a `+MM:SS` overtime counter, (e) restyles the WEIGHT card so tapping the big number toggles hardware LOAD/UNLOAD (reusing V1's `sendLoad`/`sendUnload` opcode path) and turns green when loaded, (f) replaces the b55 hardcoded `maxFCeiling: 160` chart Y-axis with a parent-driven `yAxisMaxLb = max(workingLb, eccEffective) × 1.3` that animates smoothly when weight or ECC changes, (g) ECC range expanded from 0–300 to 5–400 lb working per user direction, and (h) ports the V1 affordances under the chart **verbatim** — pulley-mode chip, added-plates picker, `LOGGED SETS` swipeable list, Next-exercise NavigationLink, and End-session button — into a new `V1RestoreSection` so V2 reaches feature parity with V1 below the fold. New files: `V2/RestTimerBarV2.swift`, `V2/NestedModRowV2.swift`, `V2/ModStepperRowV2.swift`, `V2/V1RestoreSection.swift`. Deleted: `V2/DropSetConfigureSheet.swift`, `V2/DropSetBannerV2.swift`, `V2/DropRowV2.swift`, `V2/TopBannerV2.swift`. `LiveCaptureViewV2.swift` was rewritten end-to-end (~850 lines) and `ForceChartV2.swift` gained the `yAxisMaxLb` parameter. The `private` on V1's `SwipeableSetRow` was promoted to file-internal so V2's `V1RestoreSection` can reuse it.

**Prior shipped: v0.4.33-build55 ("V2 single-Voltra LiveCapture").** b55 rewrote the V2 LiveCaptureView to match the design-handoff render after a sign-off pass on `voltra-v2-preview/index.html`. b54's "V2 spec match" turned out to be a 2x2 tile grid that didn't actually match `screenshots/A1-states.png` — b55 ports the signed-off web preview to SwiftUI: header → phase strip (always-visible) → optional rest row → WEIGHT card with stepper + DROP row → 4-up mod tiles → REPS + TOTAL VOLUME → FORCE chart. New V2-only DROP-SET creation flow: tap DROP mod tile to open `DropSetConfigureSheet`. **b55 had to ship twice** — the first push went green on CI but did not reach TestFlight because (a) `project.yml` was the version source of truth and still said `0.4.32 / 54`, so xcodegen overwrote the bumped `Info.plist`, and (b) the release-workflow's altool success-grep was Application-Loader-era and missed `Failed to upload package` / `ERROR: [ContentDelivery.Uploader` / `(-19232)` style errors. The b55-fix commit moved version-of-truth to `project.yml` and hardened the workflow with a 3-layer altool guard (failure-grep, ≥10s wall-clock duration, mandatory positive `UPLOAD COMPLETED SUCCESSFULLY` marker). See WORK_LOG b55-fix entry. If `02_CURRENT_STATE.md` shows a different latest build than this line, the file is stale — trust `git log` and `gh run list` over either source and surface the discrepancy to the user before coding.

## Mandatory commit discipline

- After **any meaningful change**, append an entry to `docs/WORK_LOG.md` (date/time UTC, goal, files changed, what changed, verification, risks, next step) and commit it **in the same commit** as the code change.
- If the change touches a topic owned by a handoff doc (architecture, BLE, health, dual-Voltra, releases, secrets, open questions), update that doc in the **same commit**.
- Never rely on chat history for facts that should live in repo.

## Mandatory ship discipline (Karpathy method)

**Every ship must update the durable state, not just append to history.** A fresh agent must be able to read 4 files (`AGENTS.md` → `01` → `02` → `03`) and know the current state without reading the WORK_LOG.

On every successful ship, in the SAME commit as the version bump:

1. **`docs/handoff/02_CURRENT_STATE.md`** — overwrite the "Latest shipped build", "What works today", and "Recent tags" sections to match HEAD. If the build changed mode handling, regenerate the mode matrix.
2. **`docs/handoff/03_ROADMAP.md`** — move the just-shipped item from "Next up" to "Done" with its tag and label. Add anything new the build surfaced.
3. **`docs/handoff/00_START_HERE.md`** — update the "Last shipped" line.
4. **Topic docs** (`04_ARCHITECTURE.md`, `05_BLE_AND_PROTOCOL.md`, `06_HEALTHKIT.md`, `07_DUAL_VOLTRA.md`, `08_SUPERSET.md`, `09_RELEASE_AND_SIGNING.md`) — update only the ones whose subject area changed in this build. Do not update them speculatively.
5. **`docs/WORK_LOG.md`** — append the build entry.

If you skip steps 1-4, the next agent's session-resume summary will be wrong, which is exactly how b53 shipped a broken V2 (the prior session's summary claimed design-studio was "fetched" while the handoff docs said the latest build was b29; the resuming agent trusted the summary instead of opening the source).

## Mandatory external-spec discipline

If a build ports an external spec (HTML, CSS, design doc, screenshot, RFC, etc.), **open and read the spec verbatim before writing any code.** Do not rely on prose summaries from prior sessions. Cite the exact file path and commit hash of the spec in the WORK_LOG entry. b53 violated this rule and produced a build that did not match its claimed source.

## Mandatory TestFlight ship-verification (added b55-fix)

A TestFlight ship is **not** considered shipped until all five of these are confirmed. CI green is a necessary but **not sufficient** signal — Xcode 26's `xcrun altool` can exit 0 while Apple rejects the upload.

1. Release workflow polled to `conclusion: success`.
2. Raw job log pulled via `gh api -H "Accept: application/vnd.github.raw" repos/<owner>/<repo>/actions/jobs/<job_id>/logs`.
3. The "Upload to TestFlight via altool" step shows wall-clock duration ≥ 20 seconds. A 4-second altool exit means the request never reached Apple's servers (this is the b55 silent-fail signature).
4. The altool log contains a positive success marker — one of: `UPLOAD COMPLETED SUCCESSFULLY`, `No errors uploading`, `package was successfully uploaded`, `successfully uploaded`.
5. The altool log contains zero `ERROR:`, `Failed to upload package`, `ERROR: [ContentDelivery`, or parenthesised numeric error code (`(-NNNNN)`) lines.

If any of (1)–(5) fails, report "build status unconfirmed, investigating" — never "shipped". The release.yml workflow now enforces (3)–(5) inside the altool step itself (see `.github/workflows/release.yml:679–732`), so a re-shipped b55-fix-and-later build that turns the workflow green has by definition passed all three checks. (1)–(2) are still on the agent.

This rule exists because in the b55 first-ship, CI reported green and the agent told the user the build had shipped. The user pulled up TestFlight, did not see the build, and corrected the agent: "You've been trained to process. Are you sure you sent it?" They were right. Don't repeat that.

## Mandatory secrets discipline

- Reference secrets by **NAME ONLY**. Never paste values, p8 contents,
  tokens, or signing material into any file.
- If you see a secret value in chat, do not commit it. Stop and tell the user.

## Sacred files (do not modify without explicit user approval)

See `AGENTS.md` "Sacred files" section. Recap:

- `VoltraLive/Protocol/VoltraProtocol.swift`
- `VoltraLive/Protocol/TelemetryExtractor.swift`
- `VoltraLive/Protocol/PacketParser.swift`
- `VoltraLive/Protocol/FrameAssembler.swift`

New protocol-adjacent code goes in **new files only**.

## Karpathy method

Before doing anything, **repeat the user's request back** so they can correct
your understanding. Don't just start executing.

## Cost-awareness convention

The user wants visibility into how token-heavy each action is, AND prefers
to run heavy research / model-council prompts on their own Perplexity
account instead of burning Computer credits.

See **AGENTS.md → "Cost-awareness convention"** for the full rules:
- Flag medium-or-heavier actions inline (lite / medium / heavy / very heavy)
- For heavy research and model councils, DRAFT a self-contained prompt at
  `docs/handoff/COUNCIL_*_PROMPT.md` for the user to run; only execute the
  heavy work on Computer when the user explicitly says "do it yourself."

Existing council prompts in this repo:
- (none open right now — the HK council was answered and the prompt
  deleted in the same commit as the b49 fix, per the "answered →
  delete" rule.)

## Index of handoff docs

| File | Owns |
|---|---|
| `00_START_HERE.md` | This file. Startup sequence. |
| `01_PROJECT_OVERVIEW.md` | What the app is, who it's for, hardware. |
| `02_CURRENT_STATE.md` | What's shipped, known bugs, build numbers. |
| `03_ROADMAP.md` | Build 30 plan, deferred work, ordering rationale. |
| `04_ARCHITECTURE.md` | Module map, data flow, key types. |
| `05_BLE_AND_PROTOCOL.md` | Wire format, control writes (incl. LOAD/UNLOAD). |
| `06_HEALTHKIT.md` | HR + active calories streaming, current bugs. |
| `07_DUAL_VOLTRA.md` | Dual-device spec (3-button connect, Independent/Combined). |
| `08_SUPERSET.md` | Superset spec (deferred to build 31). |
| `09_RELEASE_AND_SIGNING.md` | Version bumps, tags, CI, secrets (names only). |
| `10_OPEN_QUESTIONS.md` | What's blocked on user input right now. |

`docs/WORK_LOG.md` lives one level up — append-only journal of every change.
