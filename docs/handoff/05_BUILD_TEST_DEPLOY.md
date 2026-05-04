# 05 — Build, Test, Deploy

_Last updated: 2026-05-04_

## Environment facts

- **User OS:** Windows. No Mac, no Xcode, no `xcodebuild` available locally.
- **Local compile gate:** UNAVAILABLE. `xcodebuild` is not installed.
- **Authoritative compile gate:** GitHub Actions workflow
  **"Build VoltraLive IPA"** (`build.yml`). Every commit must pass this
  before TestFlight ship.

## Authoritative CI path

```
1. git push origin feat/ui-v4-2-claude
2. gh workflow run "Build VoltraLive IPA" --ref feat/ui-v4-2-claude
3. gh run watch <run-id>   → must be green
4. Only if step 3 is green:
   gh workflow run "Release to TestFlight" --ref feat/ui-v4-2-claude
5. gh run watch <run-id>   → 5-gate altool verify
```

**Never ship TestFlight if the build workflow fails.** Fix the failure first.

## Version bump requirement

Every TestFlight ship requires bumping 6 lines before step 4:
- `project.yml` lines ~64-65 (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`)
- `project.yml` lines ~92-93 (`CFBundleShortVersionString`, `CFBundleVersion`)
- `VoltraLive/Info.plist` (`CFBundleShortVersionString`, `CFBundleVersion`)

See `09_RELEASE_AND_SIGNING.md` for full detail.

## CI runner

- Workflow: `build.yml` (unsigned IPA), `release.yml` (signed + TestFlight)
- Runner: `macos-26` / Xcode `26.2` / iPhoneOS SDK `26.2`

## Sacred files — never modify

- `VoltraLive/Protocol/VoltraProtocol.swift`
- `VoltraLive/BLE/TelemetryExtractor.swift`
- `VoltraLive/BLE/PacketParser.swift`
- `VoltraLive/BLE/FrameAssembler.swift`
- `.github/workflows/build.yml`
- `.github/workflows/release.yml`
- `VoltraLive/BLE/VoltraWriter.swift` (semi-sacred — see AGENTS.md)
- `VoltraLive/BLE/WriterRouter.swift` (semi-sacred)

## 5-gate altool verification (post TestFlight ship)

After `release.yml` completes with `conclusion: success`:
1. No failure-marker strings in job log.
2. Wall-clock duration > 10 s (actual upload takes minutes).
3. Positive marker: `No errors uploading archive at 'build/export/VoltraLive.ipa'`.
4. No `ERROR:` lines in altool output section.
5. Delivery UUID present in log.

## Standing permission (docs conflict on push)

If `git push` is rejected because remote is ahead:
- `git fetch` + inspect divergence read-only.
- If ONLY `docs/WORK_LOG.md`, `docs/handoff/*.md`, or `AGENTS.md` conflict:
  keep both sides (chronological order), run `git diff --check`, stage,
  `git rebase --continue`, push normally.
- **STOP if any `.swift`, test, build, CI, project, workflow, or secret
  file conflicts.**
