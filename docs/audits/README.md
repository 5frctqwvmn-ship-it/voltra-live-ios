# docs/audits/

Governance tooling — distinct from `docs/handoff/`.

`docs/handoff/` is the per-task scanning surface every working agent
reads on every job. It must stay focused on project state.

`docs/audits/` is for periodic governance: prompts that ask outside
agents to stress-test the docs, plus the recorded outputs of those
runs. Working agents do not need to read this directory.

## Layout

- `EXTERNAL_AUDIT_PROMPT_A.md` — Flavor A: black-box reproduction
  audit. The agent rebuilds the app spec from documentation alone,
  with the Swift source hidden, then reports gaps. **Local variant**
  — assumes the agent already has the repo checked out and is
  running with filesystem access (Claude Code, Cursor, Antigravity,
  Codex CLI on your machine).
- `EXTERNAL_AUDIT_PROMPT_A_CLOUD.md` — Same audit, **cloud variant**.
  Self-contained: the agent clones the repo itself, manages its own
  working directory, returns outputs as a tarball with SHA-256.
  Use this for cloud agents (Claude Code cloud, ChatGPT Codex cloud,
  Devin, Cursor Background Agents) where you can't pre-stage files.
- `runs/` — recorded outputs of past audit runs. One subdirectory
  per run, named `YYYY-MM-DD-<model>-<flavor>/`, containing the four
  output files the audit prompt produces (`01_understanding.md`,
  `02_rebuild_spec.md`, `03_gaps.md`, `04_verdict.md`) plus a
  `metadata.json` recording the model, repo HEAD, and start/end times.

## When to run

See `AGENTS.md` "Audit cadence" section. Default triggers:

1. Before any release tagged `v0.5.0` or higher.
2. After any commit that touches `docs/handoff/` and changes
   ≥ 100 lines across ≥ 3 files in one go (high churn = high risk
   of inconsistency).
3. After any architectural change to a sacred-adjacent area
   (BLE write path, SwiftData migrations, routing source of truth).
4. On request, ad hoc.

## How to run

Pick an agentic coding environment with filesystem access — Claude
Code, Cursor, Antigravity, Codex CLI. Chat-interface models without
repo access cannot run these prompts; they require reading dozens
of files directly.

Recommended models: Claude Opus 4.7, Gemini 3 Pro, GPT-5. Avoid
mini/lite tiers — audit value is in reasoning quality, not throughput.

For cloud agents, paste the contents of `EXTERNAL_AUDIT_PROMPT_A_CLOUD.md`
between the `PROMPT BEGINS` and `PROMPT ENDS` markers as the task. The
agent does the rest. For local agents, use `EXTERNAL_AUDIT_PROMPT_A.md`.

Do not run the same prompt twice with the same model in the same
week; you'll get correlated answers. For a second opinion, use a
different provider.

## Logging a run

Every run gets a `WORK_LOG.md` entry under a new "AUDIT" section
header, with: date, model, flavor, repo HEAD at audit time, verdict
score, and the path to the run subdirectory. The audit outputs
themselves are append-only — never edit a past run's files.
