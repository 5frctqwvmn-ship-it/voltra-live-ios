# 00 — START HERE

> **You are an LLM agent (or future-me) starting a session on this repo.**
> Read these handoff docs **before writing any code**. Then summarize the
> current state back to the user before proceeding (Karpathy method).

This folder is the **durable source of truth** for VOLTRA Live iOS. Chat
history is ephemeral — anything that should survive across sessions lives here.

## ⚠️ Schema note (updated 2026-05-04)

This repo has two overlapping handoff schemas that grew over time. **Use only the files listed in the index table below.** Files marked DEPRECATED should be ignored — they contain stale build numbers and superseded content. They have not been deleted so git history is preserved, but agents must not read them as authoritative.

**DEPRECATED — do not read:**
- `01_PROJECT_OVERVIEW.md` (superseded by `02_CURRENT_STATE.md` + `04_ARCHITECTURE.md`)
- `03_ROADMAP.md` (superseded by `03_CURRENT_FEATURE_SPEC.md`)
- `06_HEALTHKIT.md` (superseded by `06_KNOWN_ISSUES.md`)
- `B52_DIAGNOSIS.md` (build-specific artifact, no longer actionable)

**AUTHORITATIVE files to read on every cold start (in order):**
1. `AGENTS.md` (repo root) — sacred files, hard constraints, signing.
2. `00_START_HERE.md` — this file.
3. `02_CURRENT_STATE.md` — what shipped, what's broken.
4. `03_CURRENT_FEATURE_SPEC.md` — current feature spec.
5. `04_DECISIONS_AND_CONSTRAINTS.md` — key decisions and constraints.
6. `05_BLE_AND_PROTOCOL.md` — wire format, control writes.
7. `06_KNOWN_ISSUES.md` — active bugs and known issues.
8. `07_DUAL_VOLTRA.md` — dual-device spec.
9. `09_NEXT_AGENT_PROMPT.md` — cold-start prompt, current task.
10. `09_RELEASE_AND_SIGNING.md` — version bumps, CI, secrets.
11. `10_OPEN_QUESTIONS.md` — blocked on user input.
12. `docs/WORK_LOG.md` (tail — last 200 lines) — recent activity.

Then summarize state back to the user. Then start work.

**Last shipped: v0.4.52 build 82.** Tag `v0.4.52-build82`. Uploaded to TestFlight 2026-05-04. Delivery UUID: 496678a7-ab0b-4a7d-b08a-d1077c315fb7.

> If `02_CURRENT_STATE.md` shows a different latest build than this line, the file is stale — trust `git log` and `gh run list` over either source and surface the discrepancy to the user before coding.

## Mandatory commit discipline

- After **any meaningful change**, append an entry to `docs/WORK_LOG.md` (date/time UTC, goal, files changed, what changed, verification, risks, next step) and commit it **in the same commit** as the code change.
- If the change touches a topic owned by a handoff doc (architecture, BLE, decisions, dual-Voltra, releases, secrets, open questions), update that doc in the **same commit**.
- Never rely on chat history for facts that should live in repo.

## Mandatory ship discipline (Karpathy method)

**Every ship must update the durable state, not just append to history.** A fresh agent must be able to read 4 files (`AGENTS.md` → `00` → `02` → `03`) and know the current state without reading the WORK_LOG.

On every successful ship, in the SAME commit as the version bump:

1. **`docs/handoff/02_CURRENT_STATE.md`** — overwrite the "Latest shipped build", "What works today", and "Recent tags" sections to match HEAD.
2. **`docs/handoff/03_CURRENT_FEATURE_SPEC.md`** — move the just-shipped item from "Next up" to "Done".
3. **`docs/handoff/00_START_HERE.md`** — update the "Last shipped" line.
4. **`docs/handoff/09_NEXT_AGENT_PROMPT.md`** — update "Where things stand" to reflect the new build.
5. **Topic docs** — update only the ones whose subject area changed.
6. **`docs/WORK_LOG.md`** — append the build entry.

## Mandatory TestFlight ship-verification (5 gates)

A TestFlight ship is **not** considered shipped until ALL five are confirmed:

1. Release workflow polled to `conclusion: success`.
2. Raw job log pulled via `gh api`.
3. altool step shows wall-clock duration ≥ 20 seconds.
4. altool log contains a positive success marker: `UPLOAD COMPLETED SUCCESSFULLY`, `No errors uploading`, `package was successfully uploaded`, or `successfully uploaded`.
5. altool log contains zero `ERROR:`, `Failed to upload package`, or parenthesised numeric error code lines.

## Mandatory secrets discipline

- Reference secrets by **NAME ONLY**. Never paste values, p8 contents, tokens, or signing material into any file.
- If you see a secret value in chat, do not commit it. Stop and tell the user.

## Sacred files (do not modify without explicit user approval)

- `VoltraLive/Protocol/VoltraProtocol.swift`
- `VoltraLive/Protocol/TelemetryExtractor.swift`
- `VoltraLive/Protocol/PacketParser.swift`
- `VoltraLive/Protocol/FrameAssembler.swift`

New protocol-adjacent code goes in **new files only**.

## Karpathy method

Before doing anything, **repeat the user's request back** so they can correct your understanding. Don't just start executing.

## Cost-awareness convention

Flag medium-or-heavier actions inline (lite / medium / heavy / very heavy). For heavy research, draft a self-contained prompt at `docs/handoff/COUNCIL_*_PROMPT.md` for the user to run; only execute on Computer when the user explicitly says "do it yourself."

## Index of authoritative handoff docs

| File | Owns |
|---|---|
| `00_START_HERE.md` | This file. Startup sequence. |
| `02_CURRENT_STATE.md` | What's shipped, known bugs, build numbers. |
| `03_CURRENT_FEATURE_SPEC.md` | Current feature spec and V-release history. |
| `04_ARCHITECTURE.md` | Module map, data flow, key types. |
| `04_DECISIONS_AND_CONSTRAINTS.md` | Key decisions, constraints, rationale. |
| `05_BLE_AND_PROTOCOL.md` | Wire format, control writes (incl. LOAD/UNLOAD). |
| `06_KNOWN_ISSUES.md` | Active bugs, KI entries. |
| `07_DUAL_VOLTRA.md` | Dual-device spec. |
| `08_SUPERSET.md` | Superset spec. |
| `09_NEXT_AGENT_PROMPT.md` | Cold-start prompt, current task, open issues. |
| `09_RELEASE_AND_SIGNING.md` | Version bumps, tags, CI, secrets (names only). |
| `10_OPEN_QUESTIONS.md` | What's blocked on user input right now. |
| `11_AGENT_ROLES.md` | Agent role definitions. |
| `B74_BUG_QUEUE.md` | Bug queue (still active reference). |
| `QA_LOG.md` | Post-build QA checklist log. |

`docs/WORK_LOG.md` lives one level up — append-only journal of every change.
