# 02 — Current State

_Last updated: 2026-04-27 (after build 29 ship + drop-set/HR bugs reported)._

## Latest shipped build

**v0.4.7 build 29** — tag `v0.4.7-build29`, commit `54b33b3`, shipped today.

- Launches cleanly on user's device.
- Single-VOLTRA connect works.
- Heart rate **does** read once at session start (snapshot) — not yet streaming.
- Active calories **do not** appear at all.
- Drop-set logic regressed (compounds reductions instead of anchoring).
- Build 29 was a **crash-fix only** release. Dual-Voltra was deferred.

## How build 29 fixed the launch crash

Builds 27 and 28 crashed at launch with `_assertionFailure` in
`SwiftData.DefaultMigrationManager`. Root cause: the on-disk store from
build 27 carried CloudKit metadata. Even after dropping
`cloudKitDatabase: .automatic` (build 28), reopening the same store URL
still triggered an uncatchable Swift assertion in the migration manager.

Build 29's fix (commit `54b33b3`):

- Open SwiftData at a **new** store URL:
  `Application Support/voltra-live-v2.store`.
- Use the explicit `ModelConfiguration(name:schema:url:allowsSave:cloudKitDatabase:)`
  initializer to avoid overload edge cases.
- Pass `cloudKitDatabase: .none` for now.
- Fall back to in-memory store if the new URL also fails.

This sidesteps migration entirely by leaving the old store on disk and
opening a fresh one. Old logs are not yet imported — that is a future task
(see `10_OPEN_QUESTIONS.md`).

## Known bugs (must fix in build 30)

1. **Drop-set regression (reported, not yet reproduced in code).** User
   reports reductions compound off the **current** weight (`100 → 80 → 64`,
   i.e. −20% twice on rolling current) instead of anchoring to the original
   starting weight (`100 → 80 → 60 → 40`).
   - Investigation summary (build 30, day 1): static analysis of the v0.4.7
     code shows the production cascade goes through
     `LoggingStore.cascadeAnchoredDeviceWeight(anchor:tier:stepIndex:multiplier:)`,
     which is mathematically anchor-correct. The non-anchored helper
     `cascadeNextWeight(from:tier:)` would compound, but it has **no live
     callers** — only `cascadeNextDeviceWeight` and `dropStepLb`, both also
     unreferenced in production. `defaultDropPercent` on `Exercise` is
     declared but never read.
   - The `100 → 80 → 64` ladder is the canonical artifact of `currentLb × 0.8`
     compounded twice. The only function in the repo that produces it is
     `cascadeNextWeight(from: 100, tier: 4)` followed by
     `cascadeNextWeight(from: 80, tier: 4)`. `bumpCascadeTier` caps tier at
     3, so this path should be unreachable in shipping code.
   - Hypotheses still open: (a) user is reading the active-tile **preview**
     which re-anchors at the post-drop current, making it look like
     compounding; (b) build 25/early binary still installed; (c) a code path
     not yet found. Build 30 day 2 should ask the user for a precise
     reproduction (tap sequence, screen-recorded tile values, build number
     visible on screen at the time).
   - Regression tests added in `VoltraLiveTests/DropSetCascadeTests.swift`
     pin the anchor-correct behavior at all tiers so any future change
     cannot silently regress to compounding.
   - Suspect files for any further fix (in priority order):
     1. `VoltraLive/Logging/Persistence/LoggingStore.swift` cascade math.
     2. `VoltraLive/Logging/Views/LiveCaptureView.swift` `dropSetTileActive`
        preview (re-anchors at `pendingPlannedWeightLb` after each drop).
     3. `VoltraLive/Logging/Model/LoggingModels.swift` — `defaultDropPercent`
        is dead and should be removed (separate cleanup commit).
2. **HR is one-shot snapshot.** Heart rate populates once at session start
   then stops updating. Should stream continuously.
   - Suspect file: `VoltraLive/Health/HealthKitStore.swift`.
   - Fix: `HKAnchoredObjectQuery` (or observer query) for continuous reads.
3. **Active calories never arrive.** Same store, same session, kcal stays empty.
   - Likely the same query never fires, or the wrong type is queried.
4. **No live-data indicator.** User wants a pulsing green dot on the HR
   and kcal tiles when fresh data arrived in the last ~3 seconds; goes
   solid grey when data goes stale. New view: `PulseDot`.

## Active design specs to preserve

- Dual-Voltra: see `07_DUAL_VOLTRA.md`.
- Superset: see `08_SUPERSET.md` (deferred to build 31).
- Workout-creation Group dropdown (existing tags + add new): part of build 30.

## Repository facts

- Canonical local path: `/tmp/voltra-live-ios`
- Default branch: `main`
- HEAD at last summarization: `54b33b3`
- Working tree: clean
- CI runner: `macos-26`, Xcode `26.2`, iPhoneOS `26.2.sdk`
- Bot identity for commits:
  `git -c user.name="VOLTRA Live Bot" -c user.email="bot@voltralive.app"`

## Stashed but not committed

`.dual-voltra-wip/` (in `.gitignore`) holds 4 build-30 work-in-progress files:

- `VoltraControlFrames+LoadUnload.swift`
- `VoltraDiscoveryScanner.swift`
- `MultiDeviceManager.swift`
- `DualMode.swift`

These are the seed for the dual-Voltra implementation in build 30. Restore
into `VoltraLive/` when starting that task. Do not commit them as-is — they
predate the build-29 crash fix and may need updating.

## Tags and recent commits

Recent commits on `main` (newest first):

- `54b33b3` — fix(launch): open SwiftData at fresh store URL to bypass migration assertion (build 29)
- `2a3d7ef` — fix(launch): drop CloudKit from ModelContainer (build 28, INSUFFICIENT)
- `e437c52` — ci(release): cache DerivedData + remove entitlement-dump diagnostic
- `0ae2226` — chore(version): bump to 0.4.6 build 27
- `1b204af` — fix(demo): inject DemoController AFTER demoModeOverlay modifier
- `da24c58` — fix(version): CFBundleShortVersionString must be 3 components max

Tags:

- `v0.4.7-build29` — shipped, working
- `v0.4.6-build28` — shipped, crashed at launch
- `v0.4.6-build27` — shipped, crashed at launch
- `v0.4.6-build26` — rejected by `altool`
- `v0.4.6.2` — rejected (4-component version, violates Apple's ≤3 rule)

## Apple's version-component rule

`CFBundleShortVersionString` must be **≤ 3 components** (e.g. `0.4.7`,
not `0.4.7.1`). Apple rejects 4-component versions. Use
`CFBundleVersion` (build number) for finer granularity instead.

## Three places to bump on every release

1. `VoltraLive/Info.plist` → `CFBundleShortVersionString` and `CFBundleVersion`
2. `project.yml` settings block (lines ~16–17): `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`
3. `project.yml` `info.properties` block (lines ~92–93): `CFBundleShortVersionString` and `CFBundleVersion`

All three must agree or the build will fail signing or be rejected by altool.
