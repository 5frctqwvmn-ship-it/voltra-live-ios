# 10 — Open Questions

Things blocked on the user. Resolve before the dependent task can ship.

> When you answer one of these, **delete it from this file in the same
> commit** as the code change that uses the answer. Don't let stale
> questions accumulate.

## V2 promotion

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

### Should V2 become the default? (b71)

Resolved in b71 (V4-D21 part 3 / Step 3). After V4-D21 part 1
(below-chart parity) and part 2 (chain UI port) closed every
behavior gap, `LiveCaptureContainer.shouldUseV2` collapsed to
`return uiVersion != "v1"`. V2 is now the canonical live capture
view for every session shape; `@AppStorage("liveCaptureUIVersion")`
is an emergency rollback kill switch only. The first-launch picker
remains for compatibility but both choices route to V2 unless the
user explicitly picks V1. See ADR **V4-D21 part 3** in
`04_DECISIONS_AND_CONSTRAINTS.md` and the routing section in
`08_SUPERSET.md`.

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
