# 09 — Release and Signing

## The user has no Mac

All signing **must** work in the browser via GitHub Actions. There is no
local Xcode fallback. Do not introduce steps that assume a Mac.

## Three places to bump on every release

`CFBundleShortVersionString` (marketing version) and `CFBundleVersion`
(build number) must agree across **three places** or the build will fail
signing or be rejected by `altool`:

1. `VoltraLive/Info.plist`
   - `CFBundleShortVersionString`
   - `CFBundleVersion`
2. `project.yml` settings block (top, around lines 16–17)
   - `MARKETING_VERSION`
   - `CURRENT_PROJECT_VERSION`
3. `project.yml` `info.properties` block (around lines 92–93)
   - `CFBundleShortVersionString`
   - `CFBundleVersion`

`CFBundleShortVersionString` must be **≤ 3 components**. Apple rejects
4-component versions. Use the build number for finer granularity.

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
