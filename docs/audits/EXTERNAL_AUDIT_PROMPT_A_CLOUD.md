# VOLTRA Live iOS — External Audit Prompt A (Cloud Agent Version)

**Flavor:** A — pure black-box rebuild from spec only.
**Variant:** Cloud — self-contained, paste-and-go for any cloud
agent with shell + git access (Claude Code cloud, ChatGPT Codex
cloud, Devin, Cursor Background Agents, etc.).
**Token cost:** very heavy.

This is the same audit as `EXTERNAL_AUDIT_PROMPT_A.md` but rewritten
to be runnable in a fresh sandbox with no prior context. The agent
clones the repo itself, manages its own working directory, and
returns outputs as a single deliverable.

See `docs/audits/README.md` for governance, when to run, and how to
log runs.

---

## PROMPT BEGINS — paste everything below this line into the cloud agent

You are an independent auditor. You have shell access and a fresh
sandbox. Your job is to attempt to rebuild a real iOS app from its
documentation alone — without reading any of its Swift source — and
report what was missing or wrong in the docs.

The goal is **not** working code. The goal is to find gaps,
ambiguities, and contradictions in the documentation by trying to
use it as a build spec. Be adversarial. Diplomacy here is the enemy.

## Step 0 — Sandbox setup

Run these commands first, in order:

```bash
mkdir -p /tmp/voltra-audit
cd /tmp/voltra-audit
git clone https://github.com/5frctqwvmn-ship-it/voltra-live-ios.git repo
cd repo
git log --oneline -1 > /tmp/voltra-audit/HEAD.txt
git branch -a > /tmp/voltra-audit/branches.txt
```

If the clone fails with an auth error, stop and report — do not
attempt to proceed without the repo. The user will provide
credentials and re-run.

After the clone succeeds, all of your audit outputs go in
`/tmp/voltra-audit/` (NOT inside the cloned repo). Your working
directory for reading is `/tmp/voltra-audit/repo`.

## Read scope — ALLOWED

Inside `/tmp/voltra-audit/repo`, you may read **only**:

- `docs/handoff/00_START_HERE.md` through `docs/handoff/10_OPEN_QUESTIONS.md`
- `docs/handoff/B52_DIAGNOSIS.md` and any other `docs/handoff/*.md`
- `docs/WORK_LOG.md`
- `docs/audits/README.md` (for context on this audit's role —
  do NOT read the prompt files in `docs/audits/`, those would tell
  you what the audit is looking for and bias your findings)
- `AGENTS.md`
- `README.md` if it exists at the repo root
- `project.yml` (build configuration shape only — not as
  architecture reference)

For the V2 design source: switch to the `design-studio` branch in a
**separate worktree** so you don't disturb the main checkout:

```bash
cd /tmp/voltra-audit/repo
git worktree add /tmp/voltra-audit/design-studio design-studio
```

If the `design-studio` branch doesn't exist, run:

```bash
git branch -a | grep -iE 'design|studio'
```

Pick the most recent matching branch and use that. If nothing
matches, note this in your output and proceed without the design
files.

In the design-studio worktree, you may read only:
- `design-system/ui-kit.html`
- `design-system/colors_and_type.css`
- `design-system/preview/*.html`

## Read scope — FORBIDDEN

You may NOT read:

- Any `.swift` file anywhere in the repo
- `Info.plist`, `*.entitlements`, asset catalogs, `*.xcassets`
- Any commit diffs, PR descriptions, GitHub issues, or release
  notes outside the allowed paths above
- The contents of `docs/audits/EXTERNAL_AUDIT_PROMPT_A*.md` or any
  other audit prompt — these would prime your findings
- Any external Voltra hardware documentation
- The `.git` directory contents beyond the `git log` and
  `git branch` invocations in Step 0

To enforce this, before each phase, run:

```bash
echo "Files I plan to open this phase:" >> /tmp/voltra-audit/00_reads.md
```

…and append every path you actually open. If you find yourself
wanting to open a forbidden file, stop and document the temptation
in `03_gaps.md` instead — that's exactly the kind of gap the audit
is looking for.

You may NOT execute the app or its tests. Treat the Swift source
as if it does not exist. You may use `ls`, `find`, `wc`, and similar
tools on Swift files to count or list them, but never `cat`, `head`,
`tail`, `grep` their contents, or any tool that reveals contents.

## Output discipline

All five output files go in `/tmp/voltra-audit/`:

- `00_reads.md` — declared and actual reads (see Phase 0)
- `01_understanding.md` — what you learned from the docs
- `02_rebuild_spec.md` — the spec you'd hand an iOS engineer
- `03_gaps.md` — five sections A–E
- `04_verdict.md` — one-page reproducibility verdict

Cite doc references inline as
`(02_CURRENT_STATE.md §"Mode handling matrix")` or with line
numbers when quoting. Quote verbatim when flagging contradictions.
Be specific — "the threading model is unclear" is useless;
"04_ARCHITECTURE.md line 62 says telemetry flows to LiveCaptureView
but doesn't state whether the @Published update happens on the BLE
delegate queue or the main actor" is useful.

## What you are auditing

A native iOS app called VOLTRA Live. It pairs over BLE with one or
two VOLTRA strength-training devices, captures live telemetry (force,
reps, phase, ROM, velocity, power), logs sets to SwiftData, integrates
with HealthKit (HR + active calories), and supports a "superset"
workflow with two paired devices and chain-swap between exercises.
There is a V1 live-capture UI and a V2 redesign that ships as opt-in.

That description is all the priming you get. Everything else, you
get from the docs.

## Phase 0 — Declare your reads

Create `/tmp/voltra-audit/00_reads.md`. List every file path you
intend to read across all phases, one per line, format:

```
<path> — <reason>
```

After each subsequent phase, append a `[PHASE N ACTUAL]` block
listing every file you actually opened during that phase, with
reason. If a file isn't in your reads list, claims about its
contents are not credible. This is how the human verifies your
coverage.

## Phase 1 — Read the docs cold

Read in this order: `docs/handoff/00 → 01 → … → 10`, then any
other `docs/handoff/*.md` files, then `docs/WORK_LOG.md` (long and
append-only — skim for structure, read recent entries in detail),
then `AGENTS.md`. Then read the design-system files in the
design-studio worktree.

Write `/tmp/voltra-audit/01_understanding.md` containing:

- A one-paragraph plain-English description of what the app does.
- A list of every distinct subsystem you identified, in the order
  you'd build them.
- For each subsystem: which doc(s) cover it, plus a confidence
  score 1–5 for "I could rebuild this from the docs alone."
- A list of every file path the docs mention (Swift or otherwise),
  marked as "spec'd" (enough detail to rebuild) or "named-only"
  (mentioned but not specified).

## Phase 2 — Write the rebuild specification

Do **not** write Swift. Write a build specification an iOS engineer
could implement without further questions. Save as
`/tmp/voltra-audit/02_rebuild_spec.md`, covering in this order:

1. **Module / file layout** — every file you'd create, its
   responsibilities, public surface. Cross-reference against file
   paths the docs claim exist; flag any you'd add that the docs
   don't mention, and any the docs mention that you can't justify
   from spec.
2. **Data model** — every SwiftData `@Model`, every field with
   type and nullability, relationships, defaults. Mark each field
   additive vs structural. Flag anywhere the docs describe a field
   without specifying type, nullability, or default.
3. **BLE protocol surface** — the four "sacred" files are
   off-limits to modify. Write the public-API signatures and
   behaviors you'd consume from them. If you can't, say so.
4. **Live data flow** — telemetry frame → UI tile update, drawn
   as a sequence. Flag every step where docs leave timing,
   threading, or buffering unspecified.
5. **Logging & set boundaries** — when does a set start and
   finalize, what attributes a `LoggedSet` to which
   `ExerciseInstance`, how does drop-set anchoring work. The docs
   flag a known bug — describe it and the intended behavior.
6. **Superset / chain handling (b53 architecture)** — the routing
   source of truth, the 3-way Left/Right/Both picker, the chain
   array's role, what SWAP does step-by-step, the header rewrite
   rule, the session rollups. Highest-risk subsystem.
7. **HealthKit integration** — entitlement keys, auth flow, samples
   read, the snapshot-only bug.
8. **LiveCapture V1/V2 split** — gate logic, AppStorage key,
   fallback conditions, V2 layout description for a designer to
   mock up. Describe V2 from `design-system/ui-kit.html` directly,
   not from any doc paraphrase.
9. **Build, signing, CI** — version bump locations (docs say
   three), release workflow shape, dry-run path, tag format,
   bot-identity git config.
10. **Sacred files and other "do-not-touch" rules** — list
    everything the docs forbid modifying and why.

## Phase 3 — Gap report

Save as `/tmp/voltra-audit/03_gaps.md`. **Five sections, A–E:**

**A. Ambiguities** — places admitting two or more valid
interpretations. State each interpretation; pick the one you'd
implement, with reasoning.

**B. Missing specifications** — things you couldn't write in the
rebuild spec because the docs don't cover them. State what's
missing and how blocking it would be (would you ship without it?
guess? ask?).

**C. Internal contradictions** — places where two docs disagree, or
a single doc disagrees with itself. Quote both sides verbatim with
file + line references.

**D. Dead references** — files, symbols, branches, commits, or
external resources the docs mention but never resolve.

**E. Silent contracts** — invariants you inferred the code must
rely on (threading, ordering, timing, idempotence) that no doc
states explicitly. Most dangerous category.

## Phase 4 — Reproducibility verdict

Save as `/tmp/voltra-audit/04_verdict.md`. One page max:

- **Overall confidence (1–5)** that an iOS engineer could ship a
  functionally-equivalent app from these docs alone, with one
  paragraph of justification.
- **Top 5 highest-leverage doc improvements** — smallest doc edits
  that most increase reproducibility.
- **Riskiest subsystem to rebuild blind** — most likely to ship
  subtly wrong, and why.
- **Smell test line** — would you bet the existing Swift source
  matches the docs? Yes or no, on what evidence.

## Phase 5 — Package and return

Bundle the deliverables and report back:

```bash
cd /tmp/voltra-audit
tar -czf audit_outputs.tar.gz HEAD.txt branches.txt 00_reads.md 01_understanding.md 02_rebuild_spec.md 03_gaps.md 04_verdict.md
sha256sum audit_outputs.tar.gz > audit_outputs.tar.gz.sha256
ls -la /tmp/voltra-audit/*.md /tmp/voltra-audit/audit_outputs.tar.gz*
```

Then in your final reply to the user, include:

1. The repo HEAD SHA (from `HEAD.txt`).
2. Which design branch you used (`design-studio` or fallback).
3. The five output file paths.
4. The tarball path and its SHA-256.
5. Your verdict score (1–5).
6. The single most important gap you found, in two sentences.
7. Confirmation that `00_reads.md` lists every file you actually
   read.

Do not summarize the docs back. Do not restate the project
description. Do not offer to fix anything. Just audit.

If at any point you violate the read scope (touch a `.swift` file,
read a forbidden path, peek at the audit prompt files), document it
honestly in `03_gaps.md` section E. The audit's value depends on
the human trusting your reads list.

## PROMPT ENDS

---

## Changelog

- **2026-04-28** — Cloud variant of `EXTERNAL_AUDIT_PROMPT_A.md`.
  Self-contained: clones the repo, manages its own working dir,
  bundles outputs as a tarball with SHA-256. Forbids reading other
  audit prompts (priming risk). Uses a `git worktree` for the
  design-studio branch instead of branch-switching. Adds a "if you
  violate scope, document it" honesty clause.
