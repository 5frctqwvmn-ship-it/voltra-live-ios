# Handoff Prompt — UI Layout V4 Implementation (Karpathy LLM Wiki Method)

> **Track marker:** This file lives in the **GPT-5.5 implementation track**
> repository (`5frctqwvmn-ship-it/voltra-live-ios-gpt-5-5`), copied from
> `5frctqwvmn-ship-it/voltra-live-ios`. The original repository remains the
> Claude-orchestrated **fallback** and must not be modified by work performed
> from this prompt. All commits, branches, and PRs from this prompt go to the
> GPT-5.5 copy only.

Purpose: One-shot prompt for a fresh Perplexity Computer instance with zero prior context. The new agent follows the Karpathy LLM Wiki pattern: compile knowledge once into versioned markdown, consult those files on every subsequent call, never hold knowledge only in context.

Save this prompt to: docs/handoff/09_NEXT_AGENT_PROMPT.md

## GPT-5.5 Track Marker

This repository is the GPT-5.5 implementation track copied from `5frctqwvmn-ship-it/voltra-live-ios`. The original repository remains the Claude-orchestrated fallback and must not be modified by work performed from this prompt.

🤖 PROMPT STARTS HERE — Copy everything below into the new computer

You are a coding agent inheriting an in-progress iOS app project. Treat the GitHub repo as the source of truth, not chat memory. You have no prior context on this project: everything you need is in the repo.

You are working in the GPT-5.5 implementation track. The original `5frctqwvmn-ship-it/voltra-live-ios` repository is preserved as the Claude-orchestrated fallback. Do not modify the original fallback repo from this track.

You will operate under the Karpathy LLM Wiki pattern. Read this section before doing anything else.

### Operating Philosophy — Karpathy LLM Wiki Method

You are a knowledge compiler, not a search engine. Instead of re-deriving knowledge from raw sources every session, you incrementally build and maintain a persistent wiki: a structured, interlinked collection of markdown files that compounds over time.

### The Prime Directive

NEVER hold knowledge only in your context window. Every insight, synthesis, entity, decision, comparison, or finding MUST be written to a file in the wiki. If it's not in a file, it doesn't exist. Your memory is the filesystem.

### Three-Layer Architecture

This repo already maps onto the Karpathy three-layer model. Respect the boundaries.

#### Layer 1 — raw/ (Immutable Sources)

Read-only archive. You read from here but NEVER modify.

- docs/handoff/screenshots/ — UI bug repros, V2/V3 baselines, Tonal/Beyond Power captures
- docs/handoff/research/sources/ — pasted excerpts and links to external references
- Any .har, .log, .json dumps from device sessions

If you need to ingest a new external reference (Tonal blog post, Beyond Power help article, a new screenshot), save the raw content here first with a filename like YYYY-MM-DD_source-slug.md — never inline paraphrase into synthesis docs without an archived source.

#### Layer 2 — wiki/ (Compiled Knowledge — Your Workspace)

Mutable. This is where synthesis lives. The existing handoff docs ARE the wiki:

- docs/handoff/00_START_HERE.md → wiki index
- docs/handoff/01_PROJECT_STATE.md → current state snapshot
- docs/handoff/02_ARCHITECTURE.md → system model
- docs/handoff/03_CURRENT_FEATURE_SPEC.md → active work order
- docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md → decision log (append-only)
- docs/handoff/05_BUILD_TEST_DEPLOY.md → runbook
- docs/handoff/06_KNOWN_ISSUES.md → bug tracker
- docs/handoff/07_FILE_MAP.md → code index
- docs/handoff/08_GIT_HISTORY_SUMMARY.md → narrative git log
- docs/handoff/10_OPEN_QUESTIONS.md → unresolved items
- docs/handoff/design/force_curve.md → domain-specific design reference
- docs/handoff/design/ → add new design refs here (dual-unit bar, rest timer, etc.) as you compile them
- docs/handoff/entities/ → create if you discover atomic concepts worth isolating (e.g., dropset_state_machine.md, twin_mode_sync.md, force_time_rendering.md). Cross-link with relative markdown links.
- docs/WORK_LOG.md → append-only change journal (the wiki changelog)

> **GPT-5.5 track note:** The actual handoff filenames in this copy currently
> use the original numbering scheme (e.g. `01_PROJECT_OVERVIEW.md` +
> `02_CURRENT_STATE.md` instead of `01_PROJECT_STATE.md`;
> `04_ARCHITECTURE.md` instead of `02_ARCHITECTURE.md`;
> `09_RELEASE_AND_SIGNING.md` instead of `05_BUILD_TEST_DEPLOY.md`; and
> `07_FILE_MAP.md` / `08_GIT_HISTORY_SUMMARY.md` do not yet exist). The
> Karpathy roles above describe the **target** wiki shape. Map each role to
> the closest existing file when reading, and either create the missing
> canonical files or document the mapping in `00_START_HERE.md` before
> writing code. Do not silently rename existing files.

#### Layer 3 — Your context window (Working Memory — Ephemeral)

Transient. Everything in your context window will be lost. The wiki is the only durable memory. Before you finish any logical unit of work, ask yourself: "Is every insight I just derived written to a wiki file?" If no, write it before moving on.

### Wiki Maintenance Rules (non-negotiable)

Read before write. At the start of every task, read the wiki index (00_START_HERE.md) plus any topic-relevant files. Summarize current state back to the user in chat before making changes. This proves the wiki is internally consistent.

Write as you think. Do not batch doc updates to the end of a session. Every meaningful insight, decision, or finding goes to a wiki file in the same commit as the code change (or standalone commit if no code changed).

Compile, don't dump. Wiki entries are synthesis, not transcripts. When you learn something from a raw source or a chat exchange, distill it into the wiki with citations back to raw/. Never paste 50 lines of raw content into a wiki doc.

Cross-link aggressively. When one wiki file references a concept that has its own file, link it: [dropset state machine](entities/dropset_state_machine.md). Linked knowledge compounds; isolated knowledge rots.

Append-only logs, mutable specs. WORK_LOG.md, 04_DECISIONS_AND_CONSTRAINTS.md, and 08_GIT_HISTORY_SUMMARY.md are append-only: never rewrite history there. 03_CURRENT_FEATURE_SPEC.md, 06_KNOWN_ISSUES.md, 07_FILE_MAP.md, and design docs are mutable: update in place as reality changes.

Lint the wiki. Before you close a session or open a PR, run a self-check: broken links, stale file references, contradictions between docs, entries in 10_OPEN_QUESTIONS.md that are now resolved, entries in 06_KNOWN_ISSUES.md that are now fixed. Fix or flag them.

Chat is not persistence. If a fact only exists in your chat exchange with the user, write it to the wiki immediately. Future instances of you will not see the chat.

New sub-agents orient via the wiki, not you. If you spawn or hand off to another agent, point it at 00_START_HERE.md and the relevant entity/design docs: not at a chat summary. Your first loyalty is to the next agent reading these files cold.

### Self-Check Before Every Commit

- Did I read the relevant wiki files before making changes?
- Is every new insight, decision, or finding written to a wiki file?
- Did I cross-link new entities to existing files?
- Did I update the mutable specs (feature spec, known issues, file map) to match reality?
- Did I append to WORK_LOG.md?
- Are there raw sources I ingested that aren't archived in raw/?
- Would a brand-new agent reading only the wiki understand what I did and why?

If any answer is "no," fix it before committing.

## Step 0 — Orient yourself (MANDATORY before writing any code)

Read these files in this exact order. Do not skip. Do not skim. After each file, write a one-sentence summary of what you learned to your own scratch notes.

1. AGENTS.md — how agents must behave in this repo
2. docs/handoff/00_START_HERE.md
3. docs/handoff/01_PROJECT_STATE.md
4. docs/handoff/02_ARCHITECTURE.md
5. docs/handoff/03_CURRENT_FEATURE_SPEC.md ← the V4 spec; your primary work order
6. docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md
7. docs/handoff/05_BUILD_TEST_DEPLOY.md
8. docs/handoff/06_KNOWN_ISSUES.md
9. docs/handoff/07_FILE_MAP.md
10. docs/handoff/08_GIT_HISTORY_SUMMARY.md
11. docs/handoff/10_OPEN_QUESTIONS.md
12. docs/handoff/design/force_curve.md — force curve visual design reference
13. docs/WORK_LOG.md — skim last 10 entries to understand recent direction
14. docs/handoff/screenshots/ — especially weight-overlap-v3.jpeg and the V2 baseline screenshots
15. docs/handoff/entities/ — if it exists, read every file

After reading, write a ~200-word summary back to the user confirming:

- What the app is (Voltra iOS companion app for Beyond Power VOLTRA strength-training hardware)
- What layout V4 is trying to accomplish
- What's currently broken (P0 items)
- What reference apps guide design decisions (Tonal + Beyond Power Voltra)
- Your proposed order of operations
- Any wiki inconsistencies or stale entries you noticed while reading

Do not start coding until the user confirms your summary is correct.

## Step 1 — The Work Order

You are building UI Layout V4 of the live-workout screen. The full spec is in docs/handoff/03_CURRENT_FEATURE_SPEC.md.

### P0 (Must ship — blocks the build)

#### P0-1. Fix Dropsets (state-machine port, not redesign)

Current bug: when DROP is armed, the 2-second idle triggers the rest timer instead of dropping the weight.

Root cause hypothesis: idle handler evaluates rest-timer branch before dropset-armed branch. Audit ordering.

Required behavior:

- DROP armed + 2s idle → weight drops by configured decrement; idle does NOT start rest timer.
- Each subsequent idle drops again until weight reaches 5 lb (bottom set).
- After bottom set completes (or idles out), system transitions to rest timer.
- First tap on DROP arms (default −5). Second tap disarms cleanly.
- Port the previous working state machine verbatim. Search git history; reference commits in docs/handoff/08_GIT_HISTORY_SUMMARY.md.

Wiki task: after porting, create/update docs/handoff/entities/dropset_state_machine.md documenting the state diagram, idle-branch ordering, and bottom-set transition.

#### P0-2. Force Curve Redesign (Tonal-style)

Current bug: curve is a single confusing line; doesn't distinguish ECC from CON; doesn't rescale.

Full visual spec: docs/handoff/design/force_curve.md. Follow it exactly.

Requirements:

- Force-time polyline (time X, force Y), 30-second rolling window.
- Y-axis auto-fits to peak × 1.2, 20% headroom floor, 1–2 s eased rescale.
- Dual-band fill under the polyline: CON (primary, ~35% opacity) vs. ECC (warm accent, ~55% opacity).
- Vertical gradient inside fills encodes ROM direction: ECC darker at bottom, CHAIN mirrored (darker at top), INV CHAIN inverse.
- Dotted horizontal reference line at 80% of set peak force (Tonal pattern).
- Per-rep peak dots with value labels.
- Inline CON / ECC labels on first rep of each set, fade after 3s or rep 2.
- Rep stacking: all reps of current set overlaid, logarithmic fade, cap ~8, reset on set end.

Wiki task: update docs/handoff/design/force_curve.md with any implementation details discovered during build.

#### P0-3. Dual-Voltra Top Bar (fix V1 fallback bug)

Current bug: with 2 Voltras connected, app routes to V1 layout even when 1 unit is active.

Required:

- V3 layout is the universal base. Unit count only toggles the new <DualUnitBar />.
- Bar: [● L 118 bpm] [⇄ MERGE] [● R 118 bpm] above existing V3 chrome.
- Active unit pill filled; inactive outlined. Tap to switch focus with horizontal slide animation.
- MERGE toggles Twin Mode: pills fuse to [● L+R 200 lb base · 400 lb max], weight shows combined total, TWIN badge next to weight, increments mirror to both units, pulley greys out, plates apply symmetrically.
- Unmerge restores each unit's last-known state.
- Per-unit state: weight, ecc, chain, invChain, dropset, forceHistory, restTimer, idleState, repCount, exercise.
- Rest timer and idle detection run per-unit in Independent mode.
- 1-unit case: bar hidden, zero vertical space consumed.
- Visual consistency: reuse V3 pill shape, radius, dot tokens, typography, spacing.
- Root-cause fix: find the numConnectedUnits > 1 branch routing to legacy V1; route both cases to V3; only bar visibility differs.

Wiki task: create docs/handoff/entities/twin_mode_sync.md documenting auto-sync semantics, merge/unmerge lifecycle, and pulley-disable rationale.

### P1 (Ship if time allows)

#### P1-1. Weight text overlap bug (docs/handoff/screenshots/weight-overlap-v3.jpeg)

3-digit weights overlap adjacent icons.

Dynamic font scaling, values 5–400 lb fit one line. minFontScale ≈ 0.6. Right-edge fade truncation below floor.

Test values: 5, 20, 120, 150, 200, 400 TWIN.

#### P1-2. Rest-timer first-engage miss

First idle of session fails; works on subsequent idles.

Likely idle detector not armed before first pull completes. Audit init order.

### Carry-over from V3 (must remain intact — do not regress)

- Unified nested-row increments: −5 −1 +1 +5 for ECC/CHAIN/INV CHAIN/DROP. DROP clamps to multiples of 5 (±1 no-op).
- Pulley: tap doubles weight across all values; increments adjust displayed (post-pulley) value; engine halves internally.
- Loaded button: tap weight number physically loads/unloads; green + ✓ LOADED pill active, UNLOADED inactive.
- Rest timer: 2s idle trigger, L→R sweep, continuous HSL interp (green hsl(140,70%,45%) → amber hsl(40,90%,50%) at 50% → red hsl(0,80%,50%) at 85%), blinking warn + REST · OVER + +MM:SS on overflow, exits on next pull.
- Connected status dot leads top-right telemetry cluster (1-unit case).
- Header: V2 dial removed; watermark auto-injected from CI (fallback: "V3"); exercise-name scroll (5s truncated → scroll → reset, loop).
- End Set, Previous Sets, Add Next Exercise restored from old UI in V3 style.

## Step 2 — Reference Apps (for any tradeoff this spec doesn't answer)

When you hit a UI question not answered here, default to how these apps handle it rather than inventing. Archive any new reference material in raw/ and cite in your wiki synthesis.

- Tonal — primary reference for force visualization, ECC/CON rendering, dropset UX, rep tracking, connected-hardware UX. See docs/handoff/design/force_curve.md.
- Beyond Power VOLTRA (native) — primary reference for dual-unit "Twin Mode" mental model, L/R naming, pairing, auto-sync semantics.

Do not invent novel UI patterns if Tonal or Beyond Power already solved the problem. Mirror, cite, and record the decision in docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md.

## Step 3 — Build, Test, Deploy

Follow docs/handoff/05_BUILD_TEST_DEPLOY.md exactly. Loop:

git pull → confirm branch per repo convention.

git checkout -b feat/ui-v4-<short-name>.

Implement one P0 at a time. Build after each logical change.

Run the testing matrix below for each P0.

Commit with clear message per repo convention. Every commit that changes behavior also updates the wiki in the same commit.

Open a PR. Do not merge to main without user sign-off.

### Testing Matrix (run all)

| Scenario | Expected |
|---|---|
| 1 Voltra connected, V3 layout | Renders identically to current V3; no dual bar |
| 2 Voltras, L active, not merged | V3 layout + dual bar; L filled; state binds to L |
| 2 Voltras, R active, not merged | Same; R bound |
| 2 Voltras, MERGE active | Single L+R pill; combined weight; TWIN badge; pulley greyed |
| Merge → unmerge | Each unit restored to last-known state |
| Dropset armed (−5), 2s idle | Weight drops to current−5; no rest timer |
| Dropset ladder until 5 lb | Drops continue to 5 lb, then rest timer engages |
| Dropset toggle (tap DROP twice) | Arms first tap, disarms second |
| Weight 120 / 150 / 200 / 400 display | No overlap; single line; fits container |
| Force curve with ECC active | ECC band taller/darker, bottom-heavy gradient |
| Force curve with CHAIN active | CHAIN band top-heavy gradient, mirrored from ECC |
| Rep 2+ of a set | Previous reps visible with log fade; stack resets on set end |
| Y-axis rescale | Smooth 1–2s ease from 100 → 20 lb |
| First-session idle | Rest timer engages correctly |
| Rest timer exceeded | REST · OVER, +MM:SS, blinking warn |
| Pulley active, ±1 tap | Displayed weight changes by 1; engine sends halved value |
| Pulley in Twin Mode | Greyed out, not clickable |

## Step 4 — Documentation Rules (NON-NEGOTIABLE)

Every meaningful change requires wiki updates in the same commit.

After each logical change, update:

- docs/WORK_LOG.md — append: date/time, goal, files changed, what changed, verification (testing-matrix rows + pass/fail), risks, next step.
- docs/handoff/03_CURRENT_FEATURE_SPEC.md — update sections whose behavior changed.
- docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md — append decisions with rationale and Tonal/Beyond Power citations.
- docs/handoff/06_KNOWN_ISSUES.md — mark resolved, add newly discovered.
- docs/handoff/07_FILE_MAP.md — register new components (<DualUnitBar />, units store module).
- docs/handoff/08_GIT_HISTORY_SUMMARY.md — one-line per meaningful commit.
- docs/handoff/10_OPEN_QUESTIONS.md — log anything needing user input.
- docs/handoff/entities/*.md — create/update atomic concept docs (dropset state machine, twin mode sync, force-time rendering).
- docs/handoff/design/*.md — update design refs with implementation learnings.

If a fact only exists in chat, write it to the wiki immediately.

## Step 5 — Secrets and Safety

- Never commit secrets. Check .gitignore before adding to /config/, /.env*, /keys/.
- Never push to main without explicit approval.
- Never force-push a shared branch.
- If a file looks like an API key, credential, cert, or private key, stop and ask.

## Step 6 — When to Stop and Ask

Stop and ask the user via chat if:

- A required handoff doc is missing or empty.
- Build is broken before any changes (document in 06_KNOWN_ISSUES.md first, then ask).
- A P0 requires a design decision not covered by spec, prompt, or Tonal/Beyond Power precedent.
- You'd need a new dependency, new architectural pattern, or a module outside the live-workout screen.
- Git state is unexpected (detached HEAD, uncommitted changes, conflicting branches).
- The wiki is internally inconsistent (contradicting specs, stale file references, missing cross-links you can't resolve).

Otherwise: proceed autonomously, document as you go, report back with a PR link + testing summary + wiki diff summary.

## Step 7 — Definition of Done

V4 is done when all are true:

- All P0 testing-matrix rows pass on a physical device with 1 and 2 Voltras.
- All V3 carry-over behaviors still work (no regressions).
- docs/handoff/03_CURRENT_FEATURE_SPEC.md reflects final shipped behavior.
- docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md lists every design decision with citations.
- docs/handoff/06_KNOWN_ISSUES.md has dropset, force curve, V1 fallback, weight overlap marked resolved (or documented if deferred).
- docs/WORK_LOG.md has complete change trail.
- docs/handoff/07_FILE_MAP.md lists new <DualUnitBar /> and units store module.
- docs/handoff/entities/dropset_state_machine.md and twin_mode_sync.md exist and are accurate.
- Wiki lint passes: no broken links, no stale references, no contradictions, resolved items closed out.
- PR open with description referencing this prompt + testing results + wiki diff summary.

🤖 PROMPT ENDS HERE

## Pre-Flight Notes for the Current Instance

Before pasting the prompt into a new computer, verify in the repo:

- AGENTS.md exists with durable-context rule and references the Karpathy Wiki method
- docs/handoff/00_START_HERE.md through 10_OPEN_QUESTIONS.md all exist
- docs/handoff/design/force_curve.md exists
- docs/handoff/entities/ directory exists (even if empty — signals the pattern)
- docs/handoff/screenshots/ contains V2 baseline and V3 weight-overlap bug
- docs/WORK_LOG.md exists
- docs/handoff/05_BUILD_TEST_DEPLOY.md has real iOS build commands (not placeholders) — most common handoff failure point
- Consider creating raw/ at repo root (or docs/handoff/raw/) as the immutable sources layer, and seeding it with any Tonal/Beyond Power excerpts already gathered
- Recommended pre-flight test: open a fresh Perplexity Computer, paste only the content between the 🤖 markers, and watch Step 0 run cold. If the new instance can't orient from the wiki alone, the wiki needs more work, not the prompt.

If you want me to generate stub content for AGENTS.md, 00_START_HERE.md, 05_BUILD_TEST_DEPLOY.md, or the empty entities/ seeds, say the word and I'll produce them next.

## Pre-Flight Verification — GPT-5.5 Track (run 2026-04-29)

Snapshot of the GPT-5.5 copy at the time this prompt was saved. The next agent should re-run this check and reconcile any drift before writing code.

| Item | Status | Notes |
|---|---|---|
| `AGENTS.md` | PASS | Durable-context rule + Karpathy method referenced; sacred files listed. |
| `docs/handoff/00_START_HERE.md` | PASS | Startup sequence + ship discipline + 5-gate verification. |
| `docs/handoff/01_PROJECT_STATE.md` | **MISMATCH** | Filename in this copy is `01_PROJECT_OVERVIEW.md`. Snapshot lives in `02_CURRENT_STATE.md`. Map both to the Karpathy `01_PROJECT_STATE` role. |
| `docs/handoff/02_ARCHITECTURE.md` | **MISMATCH** | Architecture lives in `04_ARCHITECTURE.md`. |
| `docs/handoff/03_CURRENT_FEATURE_SPEC.md` | PASS | V4 spec present (also `03_ROADMAP.md` alongside it). |
| `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` | PASS | Append-only decision log. |
| `docs/handoff/05_BUILD_TEST_DEPLOY.md` | **MISMATCH** | No file with this exact name. `09_RELEASE_AND_SIGNING.md` covers build / sign / TestFlight runbook including `xcodebuild` / `xcodegen` / tag-based release commands. Treat that as the build-test-deploy runbook until renamed. |
| `docs/handoff/06_KNOWN_ISSUES.md` | PASS | Active KI tracker. |
| `docs/handoff/07_FILE_MAP.md` | **MISSING** | Not yet authored. Closest equivalent today is the `## Project layout` block in `AGENTS.md`. |
| `docs/handoff/08_GIT_HISTORY_SUMMARY.md` | **MISSING** | Use `git log --oneline` until authored. |
| `docs/handoff/10_OPEN_QUESTIONS.md` | PASS | Present. |
| `docs/handoff/design/force_curve.md` | PASS | Tonal-style force-curve design reference present. |
| `docs/handoff/entities/` directory | **PASS (seeded b60)** | Contains `dropset_state_machine.md`. Add `voltra_assignment_panel.md` next to it when implementing the assignment panel. |
| `docs/handoff/screenshots/` directory | **MISSING (create on first use)** | KI-6 in `06_KNOWN_ISSUES.md` flags missing `weight-overlap-v3.jpeg`. When the user supplies V4.2 screenshots, `mkdir -p docs/handoff/screenshots/` and commit them with descriptive names in the same commit as the implementing code. |
| `docs/handoff/raw/` (immutable sources layer) | **MISSING** | Not seeded. `docs/research/` and `docs/handoff/B52_DIAGNOSIS.md` are the closest existing raw-style archives. |
| `docs/WORK_LOG.md` | PASS | Append-only journal at repo root path `docs/WORK_LOG.md` (one level above `handoff/`). |
| Real iOS build commands in build/test/deploy doc | PASS | `09_RELEASE_AND_SIGNING.md` and `AGENTS.md` contain `xcodegen generate`, `xcodebuild test -scheme VoltraLive ...`, tag-based release flow, dry-run dispatch, 5-gate altool verification. Not placeholders. |

### Track-specific guidance for the next agent

- This repo is the **GPT-5.5 implementation track**, branched from the Claude-orchestrated original. Push only here. Do not touch `5frctqwvmn-ship-it/voltra-live-ios`.
- If the canonical Karpathy filenames (`01_PROJECT_STATE`, `02_ARCHITECTURE`, `05_BUILD_TEST_DEPLOY`, `07_FILE_MAP`, `08_GIT_HISTORY_SUMMARY`) are still missing when you arrive, **do not silently rename existing files** — propose the rename / split in a wiki PR first, or add a mapping table to `00_START_HERE.md` so both schemes resolve.
- Seed `docs/handoff/raw/` the first time you need it, not preemptively.

## V4.2 Clarifications (added 2026-04-29 by Claude release-conduit)

The user pre-resolved the five "missing pieces" questions before the V4.2
implementation pass. These are not open — do not re-ask. Answers below.

### Q1 — Design tokens (where to get the look-and-feel)

**Answer: use [`VoltraLive/Views/VoltraTheme.swift`](../../VoltraLive/Views/VoltraTheme.swift) as the source of truth.**

The repo *does* have design tokens — they're Swift, not Markdown. `VoltraTheme.swift`
(83 lines) was extracted from `styles.css` / `design-system/colors_and_type.css`
and is referenced as the design-tokens layer in [`02_CURRENT_STATE.md` line 65](../handoff/02_CURRENT_STATE.md).

Live token surface (`enum VoltraColor`):

- Backgrounds: `bg #0a0e0c`, `bgElev #11181a`, `bgElev2 #1a2426`, `border #1f2c2e`
- Text: `text #e8f4f1`, `textDim #8aa39e`, `textFaint #4a5f5b`
- Mint accent: `accent #00d4aa`, `accentDim #007a62`, `pull #00d4aa`
- Phase: `returnPhase #ffb84d`, `transition #6c8de0`, `idle`, `warn #ff7a4d`, `danger #ff4d6d`
- Tints: `pullWash`, `returnWash`, `fresh`, `freshStale`
- Phase resolver: `VoltraColor.phase(_ p: VoltraPhase)`

**Rules:**

1. Import via `VoltraColor.*` — do not hardcode hex values in new view code.
2. If V4.2 needs a new token (e.g. `inactiveCardBg`, `assignmentPanelDivider`),
   add it to `VoltraTheme.swift` in the same commit as the view that uses it.
   Do not invent a parallel `tokens.md` file — the Swift file is the canonical store.
3. For radius / spacing / typography that are not yet in `VoltraTheme.swift`,
   extend the file with `enum VoltraRadius`, `VoltraSpacing`, `VoltraType`
   blocks (one PR, additive, logged in WORK_LOG).

### Q2 — Entity docs

**Answer: A. Create each entity doc in the same commit as the related code.**

`docs/handoff/entities/` already exists (seeded b60 with [`dropset_state_machine.md`](./entities/dropset_state_machine.md)). Add new
concept docs alongside it. For V4.2, the expected entity doc is:

- `docs/handoff/entities/voltra_assignment_panel.md` — atomic concept doc for
  the assignment panel (states, transitions, what data drives it). Link it
  from `03_CURRENT_FEATURE_SPEC.md` and `04_DECISIONS_AND_CONSTRAINTS.md` the
  same way the dropset doc is linked.

The pattern is in the [dropset doc header](./entities/dropset_state_machine.md) — copy that linking style.

### Q3 — Screenshots

**Answer: A. Commit renamed screenshots into `docs/handoff/screenshots/` during implementation.**

Directory does not yet exist in the repo. Steps:

1. `mkdir -p docs/handoff/screenshots/` on the first V4.2 commit that consumes a screenshot.
2. Save each user-supplied V4.2 reference image with a descriptive name:
   `assignment-panel-armed.png`, `dropset-active-cascade.png`, etc. No spaces, lowercase, kebab-case.
3. Reference from the relevant entity doc / spec section by relative path.
4. This closes [KI-6 in `06_KNOWN_ISSUES.md`](./06_KNOWN_ISSUES.md) (`weight-overlap-v3.jpeg`) when seeded.

The three V4.2 screenshots the user uploaded for this session are not yet in
the repo — the user will paste them into chat at the start of your session
and expects you to commit them with the implementing code.

### Q4 — Weight buttons while DROP is armed

**Answer: B. Tapping a base-weight button (−5 / −1 / +1 / +5) cancels the dropset, then applies the weight change.**

Rationale: a manual weight tap during armed-DROP is an intentional override.
Locking the weight (current behavior, option C) is a bug, not a feature.
Option A (let both coexist) creates an ambiguous device state because the
dropset cascade math is anchored to the weight at arm time.

**Implementation notes:**

- In [`LoggingStore.swift`](../../VoltraLive/Logging/LoggingStore.swift), the base-weight setters (`bumpWeight(by:)` or equivalent) should
  call the existing dropset cancel path when `dropSetArmed == true || dropSetActive == true`.
- Update [`docs/handoff/entities/dropset_state_machine.md`](./entities/dropset_state_machine.md) to add a new
  transition row: `armed.* → idle (user manually changed base weight)` and
  `active.* → idle (user manually changed base weight — cancels cascade)`.
- Add a [KI entry in `06_KNOWN_ISSUES.md`](./06_KNOWN_ISSUES.md) marked RESOLVED in the same commit so the
  prior locked-buttons behavior is recorded as a fixed bug, not lost history.

### Q5 — Superset top switcher (V1 lift)

**Answer: C. Copy V1 layout/behavior verbatim, recolor with `VoltraTheme` tokens to match V3/V4 mint/dark style.**

The pattern is already established in the repo — b56 ported V1's pulley-mode
chip, added-plates picker, `LOGGED SETS` swipeable list, Next-exercise nav,
and End-session button into `V1RestoreSection.swift` using exactly this
approach (verbatim layout, V3 tokens). Reference files for V4.2 superset
switcher work:

- [`VoltraLive/Logging/Views/V2/V1RestoreSection.swift`](../../VoltraLive/Logging/Views/V2/V1RestoreSection.swift) — the V1-into-V2 port pattern
- [`VoltraLive/Views/WorkoutVoltraPickerSheet.swift`](../../VoltraLive/Views/WorkoutVoltraPickerSheet.swift) — V1 exercise switcher source
- [`VoltraLive/Logging/Views/LiveCaptureViewV2.swift`](../../VoltraLive/Logging/Views/LiveCaptureViewV2.swift) — where the new switcher will mount

Do not rebuild from scratch (option B): the user has explicitly validated the
V1 interaction structure on hardware. Do not copy V1 verbatim including
colors (option A): it will look out of place in V3/V4 dark-mint.

### Reference apps the agent should know about (not in repo)

These are workspace assets the user references in chat but that are not in
the GitHub repo:

- `voltra-v2-preview/index.html` — b55 sign-off render. Layout-of-truth for V2.
  If you need it, ask the user to paste it.
- `voltra-proto` and `voltra-live` shared assets — prior preview iterations.
  Ask the user if you need them.

Do not commit these into the repo unless the user explicitly says to.
