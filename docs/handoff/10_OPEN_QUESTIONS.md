# 10 — Open Questions

Things blocked on the user. Resolve before the dependent task can ship.

> When you answer one of these, **delete it from this file in the same
> commit** as the code change that uses the answer. Don't let stale
> questions accumulate.

## b67 — unblocking questions (asked + ANSWERED Apr 29 2026)

Both blocker questions answered before code work began. Recorded
here for traceability; will be deleted in the b67 ship commit per
the top-of-file rule.

### Q10.1 — Sine-wave force-curve geometry source → **ANSWERED: A**

> Reimplement from `docs/handoff/design/force_curve.md` spec.

Decision rationale: git history search returned zero commits where
the live force chart was ever parametric sine; spec doc is the only
remaining source of truth. Options B/C/D rejected.

**Implementation note:** B67-10 fix builds a fresh per-rep sine-wave
renderer using `force_curve.md` as canonical, replacing the
raw-sample polyline path in `ForceChartView.swift` /
`ForceChartV2.swift`. ADR will be added to
`04_DECISIONS_AND_CONSTRAINTS.md` (V4-D13 or next available slot)
in the same commit as the code.

### Q10.5 — Numbering + scope → **ANSWERED: A**

> Keep Bug 10 numbering, ship all 9 in b67.

Decision rationale: bugs are entangled (03/06/07/08 all touch the
same view files; 04+05 must ship with 07 per cross-cutting flag
#11). Bug 09 stays explicitly skipped/reserved. Single release:
**v0.4.40 / build 67**.

Branch stays `feat/ui-v4-2-claude` (continuation, no new branch).

## V2 promotion

### Should V2 become the default?

Status: **needs user answer.**

V2 currently ships as opt-in via the first-launch picker
(`@AppStorage("liveCaptureUIVersion")` empty → user picks). V2 only
renders for single-Voltra-no-chain sessions; everything else falls
back to V1. Once V2 has shipped a couple of stable builds, do we:

a. Flip the default to V2 (existing users who never picked stay on
   whatever they have; new users default to V2).
b. Auto-migrate everyone to V2 on next launch.
c. Keep first-launch picker indefinitely.

Tracking: minimum 2 clean ships of V2 before this question can be
answered. b54 is `1 / 2`.

### Should SWAP's no-auto-LOAD change get an in-app hint?

Status: **needs user answer (UX decision).**

b53 changed SWAP behavior — it no longer pushes the stored weight
back to the newly-active Voltra. Users who learned the b49 SWAP will
find the bar quiet on their first b53 swap. Options:

a. Add a one-time toast/banner the first time SWAP is tapped on b53+.
b. Add a permanent caption under the SWAP button.
c. Document only (release notes / TestFlight description).
d. No change — the empty bar IS the hint.

## Old-store import (carried from b30)

Status: **needs user answer before any importer code is written.**

Build 29 abandoned the old SwiftData store at the legacy URL. The user's
prior session logs are still on disk but not visible in the app. Do they
want them imported, or is the fresh start fine?

If yes: write a one-shot importer that opens the legacy store with a
separate `ModelContainer`, reads all sets, writes them into the v2 store,
then sets a "imported" flag so it doesn't run again.

## Recently closed

### Per-instance Voltra routing (b53)

Resolved in b53. Routing source of truth moved from
`mdm.hasAnySupersetChainEntry(for:)` predicate to
`ExerciseInstance.assignedVoltra` field stamped at exercise-add time.
3-way L/R/Both picker replaces binary L/R. SWAP unloads both sides
without auto-LOAD. See `08_SUPERSET.md`.

### V2 spec match (b54)

Resolved in b54. V2 was rebuilt as a 1:1 port of
`design-system/ui-kit.html` (design-studio branch HEAD `74d0d3b9`),
replacing the b53 generic version that was built from a prose summary
without opening the spec. New rule in `00_START_HERE.md`: external
specs must be opened verbatim before any code is written, with file
path + commit hash cited in WORK_LOG.

### HealthKit first-launch prompt (b47/b48 deferred, b49 closed)

Resolved in b49. Provisioning profile granted all three HealthKit
entitlement keys but the app-side entitlements only declared
`.healthkit`. iOS 17+ silently rejected auth on fresh installs. Fixed
app-side by declaring all three keys; CI verify hardened to assert
them with exact-key match. See `06_HEALTHKIT.md` for the full writeup.

## Process

### "Should we auto-update CloudKit re-enablement?"

Not a user question — a self-imposed gate. Don't re-enable CloudKit until
the v2 store has been stable across at least 2 releases past build 29.
Track the count: **post-b54 → 25 / 2 (well past gate, can re-enable
when desired).**

### Karpathy-method ship discipline (added post-b54)

Not a user question — a process gate. After b53 shipped wrong because
handoff docs were 25+ builds stale, every ship now updates `02`,
`03`, `00`, the relevant topic doc, and `WORK_LOG.md` in the same
commit as the version bump. See `00_START_HERE.md` "Mandatory ship
discipline" section. If a ship lands without doc updates, the next
session should treat that as a bug and back-fill before any new work.
