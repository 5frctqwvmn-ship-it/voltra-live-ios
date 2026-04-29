# VOLTRA Live iOS — External Audit Prompt A (Black-Box Reproduction)

**Flavor:** A — pure black-box rebuild from spec only.
**Token cost:** very heavy (~100×+ a typical chat turn).
**Recommended models:** Claude Opus 4.7, Gemini 3 Pro, GPT-5.
**Run environment:** agentic coding tool with filesystem access
(Claude Code, Cursor, Antigravity, Codex CLI). A chat interface
without repo access cannot run this prompt.

This prompt asks an independent agent to attempt to rebuild the app
from documentation alone, then report what was missing. The goal is
**not** working code — it's surfacing gaps, ambiguities, and
contradictions in the handoff documentation by trying to use it as
a build spec.

See `docs/audits/README.md` for when to run, how to log runs, and
where to put outputs.

---

## PROMPT BEGINS — paste everything below this line into the agent

You are an independent agent auditing a project by attempting to
rebuild it from its documentation alone. The goal is **not** to
ship working code — the goal is to surface gaps, ambiguities, and
contradictions in the handoff documentation by trying to use it as
a build spec.

## Ground rules

1. **You may read only these paths in the repo:**
   - `docs/handoff/00_START_HERE.md` through `docs/handoff/10_OPEN_QUESTIONS.md`
   - `docs/handoff/B52_DIAGNOSIS.md` and any other `docs/handoff/*.md`
   - `docs/WORK_LOG.md`
   - `AGENTS.md`
   - `README.md` if it exists
   - On the `design-studio` branch only: `design-system/ui-kit.html`,
     `design-system/colors_and_type.css`, `design-system/preview/*.html`.
     If the `design-studio` branch has been renamed or removed, search
     `git branch -a` for any branch matching `*design*` or `*studio*`
     and use the most recent one; if none exist, note this in your
     output and proceed without the design-system files.
   - `project.yml` (for build configuration shape only — not as
     architecture reference)

2. **You may NOT read:**
   - Any `.swift` file
   - `Info.plist`, `*.entitlements`, asset catalogs
   - Any commit diffs, PR descriptions, issues, or release notes
     outside the paths above
   - Any external Voltra hardware documentation

3. **You may NOT execute the existing app or its tests.** Treat the
   Swift source as if it does not exist.

4. **Do not modify any file in the repo.** Write your output as new
   files under `/tmp/voltra-audit/` only.

5. **Declare your reads.** Before you start Phase 1, write
   `/tmp/voltra-audit/00_reads.md` listing every file path you intend
   to read, with one line per file in the format
   `<path> — <reason>`. After each phase, append a `READ` line for
   any file you actually opened that wasn't on the original list,
   with the reason. This declaration is how the human verifies your
   coverage was complete and your conclusions are grounded. If a doc
   isn't in your reads list, claims about its contents are not
   credible.

## What you are building

A native iOS app called VOLTRA Live that pairs over BLE with one or
two VOLTRA strength-training devices, captures live telemetry
(force, reps, phase, ROM, velocity, power), logs sets to SwiftData,
integrates with HealthKit (HR + active calories), and supports a
"superset" workflow with two paired devices and chain-swap between
exercises. There is a V1 live-capture UI and a V2 redesign that
ships as opt-in.

## Your task

### Phase 0 — Declare reads

Write `/tmp/voltra-audit/00_reads.md` per rule 5 above, listing
every doc path you intend to consult. Update it after each phase.

### Phase 1 — Read the docs cold (no skipping)

Read the docs in order: `00 → 01 → 02 → … → 10`, then
`WORK_LOG.md` (this is long and append-only — skim for structure,
read recent entries in detail), then `AGENTS.md`. Then read the
`design-system/` files on the design-studio branch (or its
fallback per rule 1).

After reading, write `/tmp/voltra-audit/01_understanding.md`
containing:
- A one-paragraph plain-English description of what the app does.
- A list of every distinct subsystem you identified, in the order
  you'd build them.
- For each subsystem: which doc(s) cover it, and a confidence
  score 1–5 for "I could rebuild this from the docs alone."
- A list of every file path the docs mention, marked as either
  "spec'd" (enough detail to rebuild) or "named-only" (mentioned
  but not specified).

### Phase 2 — Attempt the rebuild as a written specification

Do **not** write Swift. Instead, write a build specification an
iOS engineer could implement without further questions. Save as
`/tmp/voltra-audit/02_rebuild_spec.md`.

The spec must cover, in this order:

1. **Module / file layout** — every file you'd create, its
   responsibilities, and its public surface. Cross-reference
   against the file paths the docs claim exist; flag any you'd
   add that the docs don't mention, and any the docs mention that
   you can't justify from spec.

2. **Data model** — every SwiftData `@Model` class, every field
   with type and nullability, every relationship, every default
   value. Note which fields are additive (safe to add to existing
   stores) vs structural (would require migration). Flag anywhere
   the docs describe a field but don't specify type, nullability,
   or default.

3. **BLE protocol surface** — the four "sacred" files are
   off-limits to modify, but the docs should tell you their public
   API. Write the function signatures and behaviors you'd consume
   from them. If you can't, say so.

4. **Live data flow** — telemetry frame arrives → … → UI tile
   updates. Draw it as a sequence. Flag every step where the docs
   leave timing, threading, or buffering behavior unspecified.

5. **Logging & set boundaries** — when does a set start, when does
   it finalize, what attributes a `LoggedSet` to which
   `ExerciseInstance`, and how does drop-set anchoring work. The
   docs flag a known bug here — describe what the bug is and what
   the intended behavior is.

6. **Superset / chain handling (b53 architecture)** — the routing
   source of truth, the 3-way Left/Right/Both picker, the chain
   array's role, what SWAP does step-by-step, the header rewrite
   rule, the session rollups. This is the most recently changed
   subsystem; it's the highest-risk area to rebuild.

7. **HealthKit integration** — entitlement keys required, auth
   flow, what samples are read, the snapshot-only bug.

8. **LiveCapture V1/V2 split** — the gate logic, the AppStorage
   key, the conditions under which V2 falls back to V1, and a
   description of V2's layout you could hand to a designer to
   mock up. The V2 design source is `design-system/ui-kit.html`
   on the design-studio branch — describe the layout from that
   file directly, not from any doc paraphrase.

9. **Build, signing, CI** — version bump locations (the docs say
   there are three), the release workflow shape, the dry-run
   path, the tag format, the bot-identity git config.

10. **Sacred files and other "do-not-touch" rules** — list
    everything the docs say not to modify and why.

### Phase 3 — Gap report

Save as `/tmp/voltra-audit/03_gaps.md`. **Five sections, A–E:**

**A. Ambiguities** — places where the docs admit two or more
valid interpretations. For each, state the interpretations and
pick the one you'd implement, with reasoning.

**B. Missing specifications** — things you couldn't write in the
rebuild spec because the docs don't cover them. For each, state
what's missing and how blocking it would be in practice (would
you ship without it? guess? ask?).

**C. Internal contradictions** — places where two docs disagree,
or where one doc disagrees with itself across sections. Quote
both sides verbatim with file + line references.

**D. Dead references** — files, symbols, branches, commits, or
external resources the docs mention that you'd expect to find
but the documentation never fully resolves.

**E. Silent contracts** — invariants you inferred the code must
rely on (threading, ordering, timing, idempotence, etc.) that no
doc states explicitly. These are the most dangerous gaps because
they only surface when broken.

### Phase 4 — Reproducibility verdict

Save as `/tmp/voltra-audit/04_verdict.md`. One page max.

- **Overall confidence** that an iOS engineer could ship a
  functionally-equivalent app from these docs alone, scored 1–5
  with one paragraph of justification.
- **Top 5 highest-leverage doc improvements** — the smallest doc
  edits that would most increase reproducibility.
- **Riskiest subsystem to rebuild blind** — the one most likely
  to ship subtly wrong, and why.
- **A "smell test" line** — if you had to bet whether the
  existing Swift source matches the docs, would you bet yes or no,
  and on what evidence.

## Output discipline

- All five output files written to `/tmp/voltra-audit/`
  (`00_reads.md`, `01_understanding.md`, `02_rebuild_spec.md`,
  `03_gaps.md`, `04_verdict.md`).
- Cite doc references inline as
  `(02_CURRENT_STATE.md §"Mode handling matrix")` or with line
  numbers when quoting.
- Quote verbatim when flagging contradictions; paraphrase when
  summarizing.
- Be specific. "The threading model is unclear" is useless. "Doc
  04 line 62 says telemetry flows to LiveCaptureView but doesn't
  state whether the @Published update happens on the BLE delegate
  queue or the main actor" is useful.
- Do not be diplomatic about gaps. The point of this exercise is
  to find them.

## When you're done

Report back with:
1. The five file paths you wrote.
2. Your verdict score (1–5).
3. The single most important gap you found.
4. Confirmation that `00_reads.md` is current — every file you
   actually read appears in it.

Do not summarize the docs back. Do not restate the project
description. Do not offer to fix anything — that's a separate
job. Just audit.

## PROMPT ENDS

---

## Changelog

- **2026-04-28** — Initial version. Fixed A–E section count (Phase 3
  header now says "Five sections" matching the A–E definitions).
  Added Phase 0 declare-reads requirement so coverage is verifiable.
  Added design-studio branch fallback. Bumped output file count
  from four to five (added `00_reads.md`).
