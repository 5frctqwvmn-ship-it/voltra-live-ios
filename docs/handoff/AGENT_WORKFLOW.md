# AGENT_WORKFLOW.md — universal workflow rules for all agents

> Source-of-truth for **how** every agent operating on this repo
> should work, regardless of platform (Perplexity Computer,
> Claude Code, Cursor, ChatGPT, future agents). Origin: user
> spec captured 2026-05-03 ("Workflow Orchestration / Task
> Management / Core Principles").
>
> Pointer in `AGENTS.md` — this is the long-form. The
> short-form non-negotiables live there.
>
> If a rule here conflicts with `AGENTS.md` or a sacred-files
> rule, the sacred-files rule wins. Otherwise this file is
> binding.

---

## Workflow Orchestration

### 1. Plan Node Default

- Enter plan mode for ANY non-trivial task (3+ steps or
  architectural decisions).
- If something goes sideways, STOP and re-plan immediately —
  don't keep pushing.
- Use plan mode for verification steps, not just building.
- Write detailed specs upfront to reduce ambiguity.

### 2. Subagent Strategy

- Use subagents liberally to keep the main context window
  clean.
- Offload research, exploration, and parallel analysis to
  subagents.
- For complex problems, throw more compute at it via
  subagents.
- One task per subagent for focused execution.

### 3. Self-Improvement Loop

- After ANY correction from the user: update `tasks/lessons.md`
  with the pattern.
- Write rules for yourself that prevent the same mistake.
- Ruthlessly iterate on these lessons until mistake rate drops.
- Review lessons at session start for the relevant project.

### 4. Verification Before Done

- Never mark a task complete without proving it works.
- Diff behavior between `main` and your changes when relevant.
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness.

### 5. Demand Elegance (Balanced)

- For non-trivial changes: pause and ask "is there a more
  elegant way?"
- If a fix feels hacky: "Knowing everything I know now,
  implement the elegant solution."
- Skip this for simple, obvious fixes — don't over-engineer.
- Challenge your own work before presenting it.

### 6. Autonomous Bug Fixing

- When given a bug report: just fix it. Don't ask for
  hand-holding.
- Point at logs, errors, failing tests — then resolve them.
- Zero context switching required from the user.
- Go fix failing CI tests without being told how.

---

## Task Management

1. **Plan First** — Write plan to `tasks/todo.md` with checkable
   items.
2. **Verify Plan** — Check in before starting implementation.
3. **Track Progress** — Mark items complete as you go.
4. **Explain Changes** — High-level summary at each step.
5. **Document Results** — Add review section to `tasks/todo.md`.
6. **Capture Lessons** — Update `tasks/lessons.md` after
   corrections.

---

## Core Principles

- **Simplicity First** — Make every change as simple as
  possible. Impact minimal code.
- **No Laziness** — Find root causes. No temporary fixes.
  Senior developer standards.
- **Minimal Impact** — Changes should only touch what's
  necessary. Avoid introducing bugs.

---

## How this composes with existing repo conventions

This file does **not** replace existing rules in `AGENTS.md`;
it adds to them. The combined order of precedence when an agent
starts a session:

1. Sacred files / hard constraints (`AGENTS.md` §"The hard
   constraint", §"Sacred files").
2. Karpathy Select Rule reading order (`AGENTS.md` §"Karpathy
   Select Rule") — read **this file** as part of session start
   alongside `AGENTS.md` and `docs/handoff/00_START_HERE.md`.
3. Workflow Orchestration §1–6 above.
4. Task Management 1–6 above.
5. Core Principles above.
6. Handoff-doc enforcement (`AGENTS.md` §"Handoff-doc
   enforcement").
7. Post-build QA checklist (`AGENTS.md` §"Post-build QA
   checklist").

Mappings to existing files (so agents never write to a path
that doesn't exist):

| Rule | Repo file |
|---|---|
| Self-Improvement Loop (§3), Capture Lessons (TM #6) | `tasks/lessons.md` |
| Plan First / Track Progress / Document Results (TM #1, #3, #5) | `tasks/todo.md` |
| Verification Before Done (§4) | `docs/WORK_LOG.md` "Verification" line per entry |
| 10-turn auto-summary | `docs/handoff/CONTEXT_LEDGER.md` (existing) |
| Decisions / blockers / deviations | `docs/handoff/CONVERSATION_LOG.md` (existing) |
| Known issues / regressions | `docs/handoff/06_KNOWN_ISSUES.md` (existing) |

`tasks/` is a sibling to `docs/`, not under it. The two
directories serve different purposes:

- `tasks/` — **active, mutable** working state for the *current*
  task (todo list + accumulated lessons).
- `docs/handoff/` — **append-mostly historical** record of how
  the project got here.

Both are repo source-of-truth. Both must be committed.
