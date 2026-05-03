# tasks/lessons.md — self-improvement log

> Append-only log of mistakes, corrections, and the rules that
> prevent them. Required by `docs/handoff/AGENT_WORKFLOW.md`
> §3 "Self-Improvement Loop" and Task Management #6.
>
> **When to add an entry:** any time the user corrects an
> agent. Even small corrections.
>
> **Format per entry:**
>
> ```
> ## YYYY-MM-DD — short-name
>
> **Mistake:** what the agent did wrong, in one sentence.
>
> **Trigger:** what input / situation caused it.
>
> **Correction:** what the user said to fix it.
>
> **Rule for next time:** the durable rule the agent should
> follow forever. Phrase it as an imperative ("Always X" /
> "Never Y").
>
> **Where else this applies:** other situations the same rule
> covers.
> ```
>
> **Session start ritual:** every agent must skim this file
> (most recent ~10 entries) before writing any code on a fresh
> session, per AGENT_WORKFLOW.md §3.

---

## 2026-05-03 — file-bootstrap

**Mistake:** N/A — this is the genesis entry. Establishing the
log so future corrections have a home.

**Trigger:** User provided a workflow-rules image and asked
"how can we incorporate this into our project so that all
agents and computers follow these instructions."

**Correction:** Land the rules in repo source-of-truth
(`AGENTS.md` pointer + `docs/handoff/AGENT_WORKFLOW.md`
long-form) and create the `tasks/` files the rules reference,
so no agent writes to a path that doesn't exist.

**Rule for next time:** When a user-supplied spec references
file paths, create those files (or map them to existing repo
paths and document the mapping) in the same commit that lands
the spec. Never leave a rule pointing at a non-existent file.

**Where else this applies:** any future workflow doc, AGENTS.md
extension, or onboarding spec that names a path.
