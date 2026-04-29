# 09 — Release and Signing

## The user has no Mac

All signing **must** work in the browser via GitHub Actions. There is no
local Xcode fallback. Do not introduce steps that assume a Mac.

## ONE place to bump on every release (post-b60 macro fix)

As of commit `52c2a14` (b60), `project.yml` `info.properties` uses xcodebuild
macros instead of hardcoded literals:

```yaml
info:
  properties:
    CFBundleShortVersionString: "$(MARKETING_VERSION)"
    CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
```

xcodebuild expands these at archive time from the target's build settings. So
there is now exactly **one** place to edit on every release:

- `project.yml` target settings block (`targets.VoltraLive.settings.base`, lines 64–65)
  - `MARKETING_VERSION`
  - `CURRENT_PROJECT_VERSION`

**Bump procedure:**

1. Edit `project.yml` lines 64–65 only.
2. (Optional, cosmetic) Sync `VoltraLive/Info.plist` literals so `git diff` is
   honest when the file is read outside CI. xcodegen regenerates this file
   from the macros above on every CI run, so it does not affect what ships.
3. Commit, push, dry-run, ship.

`CFBundleShortVersionString` must be **≤ 3 components**. Apple rejects 4-component versions. Use the build number for finer granularity.

## DO NOT re-add hardcoded version literals to `info.properties`

Before b60, `project.yml` `info.properties` contained hardcoded literals
(`CFBundleShortVersionString: "0.4.37"`, `CFBundleVersion: "59"`). xcodegen
regenerates `VoltraLive/Info.plist` from `info.properties` at the start of
every CI run (look for `⚙️ Generating plists...` in the workflow log,
"Generate Xcode project" step), silently overwriting any bump made only at
the target build-settings level. This caused **three consecutive altool
rejections** at b60/b61/b65: every IPA literally contained `CFBundleVersion=59`
even though the target build setting said 65, because xcodegen wrote 59 into
the Info.plist before xcodebuild archived. The macros eliminate the trap by
deferring substitution to archive time so there is only one source of truth.

The earlier b55-fix in this doc tried to solve the same class of bug by
requiring three places to be kept in sync via a checklist. That rule is now
obsolete and should not be reintroduced — it is fragile (any agent who edits
one and forgets the other ships a wrong build) and the macro pattern
removes the need entirely.

## If you see this altool error

```
status 409
code ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE
pointer /data/attributes/cfBundleVersion
previousBundleVersion: <N-1>
NSUnderlyingError -19241 / -19232
```

with a 3–5 second altool wall-clock time (vs 20s–2min for a real upload),
this is **pre-flight metadata rejection**, not a network or auth failure.
Apple is comparing the IPA's actual `CFBundleVersion` against the highest
build it has on file and rejecting because they match. Diagnostic flow:

1. Download the dry-run IPA artifact:
   `gh api -H "Accept: application/vnd.github.raw" repos/<owner>/<repo>/actions/artifacts/<id>/zip > ipa.zip`
   (`gh run download` 401s on the Azure-blob redirect; `gh api` works.)
2. Unzip and read the embedded plist with Python:
   ```
   import plistlib
   with open("Payload/VOLTRA Live.app/Info.plist", "rb") as f:
       print(plistlib.load(f)["CFBundleVersion"])
   ```
3. If the printed value is the previous build (not the bump), `info.properties`
   has been re-corrupted with hardcoded literals — restore the macro pattern
   in the section above. Do **not** bump the build number again; the bump is
   not the problem.


## Mandatory altool / TestFlight ship-verification

**CI green is necessary but not sufficient.** Xcode 26's `xcrun altool` upload pipeline (which internally uses `avtool` / `ContentDelivery.Uploader`) will exit 0 even when Apple rejects the upload — see `fastlane/fastlane#29743`. The `release.yml` workflow now enforces three independent checks inside the upload step (lines 679–732). If any of them fails, the workflow turns red and the build is **not** considered shipped:

1. **Failure-marker grep.** Matches both legacy and modern altool error patterns: `UPLOAD FAILED|Validation failed|ERROR ITMS-|Failed to upload package|ERROR: \[ContentDelivery|ERROR: \[altool|\(-[0-9]+\)`.
2. **Wall-clock duration sanity check.** Real IPA uploads to ASC take 20s–2min. The step requires `≥ 10s`. A 4-second altool exit means the request never reached Apple (this is the b55 silent-fail signature).
3. **Positive success-marker required.** The log must contain one of: `UPLOAD COMPLETED SUCCESSFULLY`, `No errors uploading`, `package was successfully uploaded`, `successfully uploaded`. Absence ⇒ fail.

After the workflow turns green, the agent must additionally:

4. Pull the raw job log via `gh api -H "Accept: application/vnd.github.raw" repos/<owner>/<repo>/actions/jobs/<job_id>/logs`.
5. Confirm ≥1 positive success marker AND zero `ERROR:` / `Failed to upload package` / `(-NNNNN)` lines.

Only after (1)–(5) all hold should the agent report “shipped” to the user. b55 first-ship reported “shipped” on the strength of CI's green checkmark alone; the build was not on TestFlight; the user caught it. Don't repeat that.

## Build-number visibility

Every screen must show the current build number. This is a hard
requirement from the user — it makes "which build did you see this on?"
a non-question. Don't ship a screen without it.

## Tag and ship

- Tag format: `v<MARKETING_VERSION>-build<CURRENT_PROJECT_VERSION>`,
  e.g. `v0.4.7-build29`.
- Push the tag to trigger `release.yml`.
- The release workflow runs tests, signs, archives, uploads to TestFlight,
  and creates a GitHub release.

## CI architecture

| Trigger | Workflow | What runs |
|---|---|---|
| Every push | `build.yml` | Unsigned dev IPA, attached to "latest" release. |
| `workflow_dispatch` (`dry_run=true`) | `release.yml` | Tests + signed archive + IPA artifact. **No upload.** Use to validate signing without burning a build number. |
| `workflow_dispatch` (`dry_run=false`) | `release.yml` | Tests + signed archive + TestFlight upload (manual override). |
| Tag `v*.*.*` | `release.yml` | Tests + signed archive + TestFlight upload + GitHub release. |

`build.yml` is sacred (see `AGENTS.md`). One documented exception was
the 2026-04-25 surgical edit pinning the iOS app name (`'VOLTRA Live.app'`
instead of `'*.app'`) after a Watch target was briefly added.

## CI runner

- `macos-26`
- Xcode `26.2`
- iPhoneOS SDK `26.2`

## Bot identity for commits

```
git -c user.name="VOLTRA Live Bot" -c user.email="bot@voltralive.app" commit ...
```

Do not commit as the user.

## Signing identifiers

- Apple Team ID: `588XUZGNNS`
- App Store Connect App ID: `6763798738`
- Bundle ID: `com.voltralive.app`
- Cert ID: `6P8K7WJ7GW`
- Provisioning profile UUID: `b3c606c2-0636-4727-a4a6-2d0b0ee81eb2`

## Required GitHub secrets — names only

**Never paste secret values into any file.** These are referenced by name
in `release.yml`:

| Secret name | Purpose |
|---|---|
| `APPLE_TEAM_ID` | 10-char Team ID. |
| `APPLE_API_KEY_ID` | App Store Connect API key ID. |
| `APPLE_API_ISSUER_ID` | App Store Connect issuer UUID. |
| `APPLE_API_PRIVATE_KEY` | `.p8` file contents (entire file). |
| `KEYCHAIN_PASSWORD` | Random string used inside the macOS runner. |

API key role: **App Manager**.

DemoTrace secrets (currently **not set** — DemoTrace endpoint is unused):

- `DEMO_TRACE_ENDPOINT`
- `DEMO_TRACE_SHARED_TOKEN`

## CloudKit

CloudKit is currently **disabled** at the SwiftData layer
(`cloudKitDatabase: .none` in `VoltraLiveApp.swift`). The container
`iCloud.com.voltralive.app` still exists in the Apple Developer console.

### Re-enablement procedure (do later, only after fresh store is stable)

1. <https://icloud.developer.apple.com/dashboard/>
2. Select container `iCloud.com.voltralive.app`.
3. Schema → **Development** → "Deploy Schema Changes…" → confirm to
   **Production**.
4. In code, change `ModelConfiguration` to `cloudKitDatabase: .automatic`.
5. Bump build number, ship.

Do **not** do this until the v2 store has been stable across at least a
couple of releases. Re-enabling too early risks reintroducing the
`DefaultMigrationManager` assertion that crashed builds 27 and 28.

## Useful commands

```
# List recent release runs
gh run list --repo 5frctqwvmn-ship-it/voltra-live-ios --workflow=release.yml --limit 3

# Dry-run signing (no build-number burn)
gh workflow run release.yml --repo 5frctqwvmn-ship-it/voltra-live-ios --ref main -f dry_run=true

# Real release: tag and push
git tag v0.4.X-buildY
git push origin v0.4.X-buildY
```

Always pass `api_credentials=["github"]` to `bash` for git operations.

## Apple deprecations on the radar

- `altool` is being deprecated. Migrate to `xcrun notarytool` before Apple
  removes support. Still works in Xcode 26.
