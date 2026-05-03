# 09_NEXT_AGENT_PROMPT

> Read this first. Cold-start prompt for the next agent picking up
> VOLTRA Live iOS post-b78. Skim, then read the docs in the order at
> the bottom **before writing any code**.

## Where things stand (post-b78)

**Last shipped:** v0.4.51 / build 78 — "Session Recorder (launch
fix)" — B74-F11 hotfix. Tag `v0.4.51-build78`. Release run
[25268455532](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25268455532)
green in 7m40s. Delivery UUID `3433cd79-fb4a-48db-9c70-b3e0289740e1`.
altool wall-clock 28s, all 5 gates PASS. Merge SHA `32f9300` on
`feat/ui-v4-2-claude`.

**Active cycle:** **Authoritative Device State + Telemetry Collector
v2.** Docs-first, **no Swift yet.** The full spec landed in
`03_CURRENT_FEATURE_SPEC.md`. Hypotheses live in `06_KNOWN_ISSUES.md`
(KI-23, KI-24) and `10_OPEN_QUESTIONS.md` (OQ-T1 … OQ-T8). Until the
user explicitly says "go", do not modify Swift. The next two work
items are both audit / research:

  1. **BLE characteristic audit** — enumerate every advertised
     service / characteristic on the VOLTRA peripheral, mark each as
     read / notify / indicate / write, and identify any candidate
     status characteristic we are not currently subscribed to. Output
     lands in `05_BLE_AND_PROTOCOL.md` under "BLE characteristic
     audit (post-b78)". Resolves OQ-T4 and informs OQ-T1, OQ-T3,
     OQ-T5.
  2. **Shared decoder abstraction (additive)** — design a decoder
     layer that lives **alongside** the existing
     `VoltraLive/Protocol/` pipeline, not in place of it. The
     existing pipeline must keep producing exactly what it produces
     today; the new decoder is additive and must round-trip raw
     bytes for any field still flagged as hypothesis (OQ-T1, OQ-T3).
     ADR V4-D26 (in `04_DECISIONS_AND_CONSTRAINTS.md`) captures the
     additive-only constraint.

## Read before writing code

Required (in this order):

  1. `AGENTS.md` — repo behavior contract for agents.
  2. `docs/handoff/00_START_HERE.md`
  3. `docs/handoff/01_PROJECT_OVERVIEW.md`
  4. `docs/handoff/02_CURRENT_STATE.md` — current shipped build, active
     cycle, verification status.
  5. `docs/handoff/03_CURRENT_FEATURE_SPEC.md` — Telemetry v2 spec is
     prepended; the V4 b58 LiveCapture spec is preserved below the
     "# Historical" demarcator for reference.
  6. `docs/handoff/04_ARCHITECTURE.md`
  7. `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` — read to ADR
     V4-D26.
  8. `docs/handoff/05_BLE_AND_PROTOCOL.md` — pay attention to the
     post-b78 audit-plan section.
  9. `docs/handoff/06_KNOWN_ISSUES.md` — KI-13 through KI-26 are the
     post-b78 set.
 10. `docs/handoff/10_OPEN_QUESTIONS.md` — OQ-T1 through OQ-T8 block
     the cycle.
 11. `docs/WORK_LOG.md` — last 2-3 entries for ship narrative.

Optional / skim if context calls for it:

  - `docs/handoff/QA_LOG.md` — post-build QA passes A–G (b78 entries
    pending).
  - `docs/handoff/B74_BUG_QUEUE.md` — the F1–F11 backlog that drove
    builds 75–78.
  - `docs/handoff/B52_DIAGNOSIS.md` — referenced for historical
    context on legacy capture issues.
  - `docs/handoff/11_AGENT_ROLES.md` — release-only mode definition
    and rules.
  - `docs/handoff/09_RELEASE_AND_SIGNING.md` — 5-gate altool verify
    procedure.
  - `docs/handoff/03_ROADMAP.md`
  - `docs/handoff/06_HEALTHKIT.md`
  - `docs/handoff/07_DUAL_VOLTRA.md`
  - `docs/handoff/08_SUPERSET.md`

## Karpathy method (mandatory)

Before writing anything, **summarize the current repo state back to
the user** and confirm the next move. They will catch
misunderstandings before you waste a build. Restate:

  - the last shipped build + UUID,
  - the active cycle (Telemetry v2, docs-first),
  - which step you intend to start (BLE audit, then shared decoder),
  - the no-Swift gate.

Wait for the user to say "go" before opening any Swift file.

## Hard rules (do not violate)

### Sacred files — DO NOT MODIFY

  - `VoltraLive/Protocol/VoltraProtocol.swift`
  - `VoltraLive/Protocol/TelemetryExtractor.swift`
  - `VoltraLive/Protocol/PacketParser.swift`
  - `VoltraLive/Protocol/FrameAssembler.swift`
  - `.github/workflows/build.yml`

The Telemetry v2 decoder must be **additive**: a new module that
runs alongside the existing pipeline. Do not replace, fork, or
shadow any of the sacred files. Any field that conflicts with what
the existing pipeline emits is resolved per the conflict-resolution
section of the spec — not by editing the existing extractor.

### Release-only mode

Per `11_AGENT_ROLES.md`: no feature code, no implementation, no new
feature PRs unless the user explicitly says **"Ship PR #N as build
X"**. The Telemetry v2 cycle is in its docs phase; opening Swift
without that go-ahead violates the role.

### Other invariants

  1. **5-gate ship verification.** CI green is not enough. Pull the
     run log, confirm altool ≥ 20 s, "UPLOAD COMPLETED SUCCESSFULLY"
     marker, zero ERROR lines, Delivery UUID captured.
  2. **`gh` CLI for GitHub.** Never use a browser for this repo. Bot
     identity:
     `git -c user.name="VOLTRA Live Bot" -c user.email="bot@voltralive.app"`
  3. **`docs/WORK_LOG.md` is append-only.** Same-commit doc updates
     for any meaningful code change.
  4. **`_tmp/archive/` must NOT be touched.**
  5. **No micro-drops.** DROP must always be a multiple of 5 lb.
  6. **CHAIN and INV CHAIN are mutually exclusive** at the UI layer.
  7. **User has no Mac.** All signing is CI-only.
  8. **Preserve previous builds.** All commits and build tags are in
     git history. Use `git log --all` and `git tag` before asking
     "where is the old code".
  9. **Pulley in Twin Mode: grey, don't hide** (V4-D5).
 10. **One TestFlight build per V-spec.** Don't split a numbered
     V-release across multiple builds unless the user says so.

## When the user gives the go for Telemetry v2

Implement in the order pinned in `03_CURRENT_FEATURE_SPEC.md`
(10-step implementation order). The first two are doc/audit; only
from step 3 onward does Swift get touched, and only in additive
modules. Per spec, schemaVersion advances 1 → 2 additively (existing
consumers must keep working).

For every meaningful change:

  1. Append `docs/WORK_LOG.md` (same commit).
  2. Update the relevant `docs/handoff/*` file (same commit).
  3. Promote any hypothesis to constant **only after** the
     corresponding OQ-T entry is resolved with hardware evidence.

## Current open issues (post-b78)

See `06_KNOWN_ISSUES.md`. Highlights:

  - **KI-13** — recorder launch crash root cause (closed by b78
    re-injection; regression test in place).
  - **KI-15 / KI-16 / KI-17** — recorder shape / ordering /
    capacity issues to clean up in v2.
  - **KI-18 / KI-19 / KI-20** — semantic event gaps that Telemetry
    v2 closes.
  - **KI-21 / KI-22** — drift in ecc/conc/chains and missed load
    drops, both decoder problems.
  - **KI-23 / KI-24** — `0x03` and `2b010100` hypothesis bytes.
  - **KI-25** — controls missing `ui.tap` events.
  - **KI-26** — BLE characteristic audit needed (Step 1).
