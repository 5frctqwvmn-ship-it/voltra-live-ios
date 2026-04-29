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

**Last shipped: v0.4.32-build54 ("V2 spec match"), HEAD `eae659f`.** If `02_CURRENT_STATE.md` shows a different latest build than this line, the file is stale — trust `git log` and `gh run list` over either source and surface the discrepancy to the user before coding.

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
