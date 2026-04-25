# AGENTS.md

> **Purpose:** Fast-path context for any LLM agent (or future session) working on this repo.
> Read this file **before** modifying anything. It encodes the constraints, sacred files, and
> success criteria that make this project work on real hardware.
>
> Style guide: [Karpathy Guidelines](https://pyshine.com/Andrej-Karpathy-Skills-LLM-Coding-Guidelines/) —
> Think Before Coding · Simplicity First · Surgical Changes · Goal-Driven Execution.

---

## What this is

VOLTRA Live is a **read-only** native iOS + watchOS app that mirrors live workout telemetry
from a Beyond Power VOLTRA cable machine over BLE. It does **not** issue any control writes
(no load, no unload, no mode change). Telemetry only.

- iOS bundle ID: `com.voltralive.app` (PRODUCT_NAME: "VOLTRA Live" → `VOLTRA Live.app`)
- Watch bundle ID: `com.voltralive.app.watchkitapp` (PRODUCT_NAME: "VOLTRA Live Watch" → `VOLTRA Live Watch.app`)
- Test bundle ID: `com.voltralive.app.tests` (PRODUCT_NAME: "VoltraLiveTests")
- The two app PRODUCT_NAMEs MUST be distinct — if both produce `VOLTRA Live.app`, Xcode fails with `Multiple commands produce 'VOLTRA Live.app'`.
- Min iOS: 17.0 · Min watchOS: 10.0
- Connected GitHub user: `5frctqwvmn-ship-it`
- Repo: <https://github.com/5frctqwvmn-ship-it/voltra-live-ios>

## The hard constraint (do not violate)

**READ-ONLY.** Never add code that writes anything except the 9 BOOTSTRAP_WRITES already
present. The bootstrap writes are read-only handshake captures from the official iPad app —
they are the *only* outbound traffic permitted. No load adjustments. No mode changes.
No pairing writes. Nothing.

If a feature request would require a control write, **stop and surface the assumption** before
coding. The user has been clear: this app must never modify the device's state.

## Sacred files (do not modify without explicit user approval)

| Path | Why sacred |
|---|---|
| `VoltraLive/Protocol/VoltraProtocol.swift` | Wire-format constants verified on hardware 2026-04-15. Mutating any byte breaks connection. |
| `VoltraLive/Protocol/TelemetryExtractor.swift` | 0xAA decode logic. Mutating offsets makes the FORCE/REPS/PHASE tiles silently wrong. |
| `VoltraLive/Protocol/PacketParser.swift` | Frame parser, mirrors JS reference. |
| `VoltraLive/Protocol/FrameAssembler.swift` | Stream defragmenter. |
| `.github/workflows/build.yml` | Working unsigned IPA build. 4 fixes needed to get it green originally — do not regress. *(Exception: 2026-04-25 surgical edit to pin iOS app name after Watch target added — `'VOLTRA Live.app'` instead of `'*.app'`.)* |

If you must modify a sacred file:
1. State the assumption that the change is necessary.
2. Add or update a test in `VoltraLiveTests/ProtocolGoldenTests.swift` that pins the new expected behavior.
3. Run `xcodebuild test -scheme VoltraLive` locally before pushing.

## Source of truth

Reverse-engineered protocol reference (Apache-licensed):
<https://github.com/dylanmaniatakes/Beyond-Power-Voltra-Android>

Key wire facts:

- Service UUID: `e4dada34-0867-8783-9f70-2ca29216c7e4`
- 9 (not 10) BOOTSTRAP_WRITES
- 0xAA telemetry layout: phase @ offset 2 · setCount @ 3 · repCount uint16-**BE** @ 4–5 · forceTenthsLb uint16-**LE** @ 11
- Set-complete heuristic: `phase == .idle AND force < 5 AND reps > 0 AND idle ≥ 4000ms`

## Project layout

```
voltra-ios/
├── VoltraLive/                   # iOS app (SwiftUI)
│   ├── Protocol/                 # SACRED — wire format
│   ├── Bridge/                   # PhoneWatchBridge (5Hz force throttle, 1Hz rest tick)
│   ├── Views/
│   ├── Assets.xcassets/          # App icon (3 nested teal triangles, #00d4aa on #0a0e0c)
│   └── Info.plist
├── VoltraWatch/                  # watchOS companion (paired, NOT standalone)
│   ├── WatchSessionDelegate.swift
│   ├── WatchTelemetryStore.swift
│   ├── Views/
│   └── Assets.xcassets/
├── VoltraLiveTests/              # Protocol golden-fixture tests
│   └── ProtocolGoldenTests.swift # MUST stay green or release.yml fails
├── .github/workflows/
│   ├── build.yml                 # Unsigned dev IPA on every push
│   └── release.yml               # Tag-triggered TestFlight + dry-run dispatch
├── project.yml                   # XcodeGen — single source of truth for Xcode config
├── VALIDATION.md                 # First-TestFlight-run checklist (run on real hardware)
└── AGENTS.md                     # this file
```

## CI architecture

| Trigger | Workflow | What runs |
|---|---|---|
| Every push | `build.yml` | Unsigned dev IPA, attached to "latest" release |
| `workflow_dispatch` (dry_run=true, default) | `release.yml` | Tests + signed archive + IPA artifact. **Skips upload.** Use this to validate signing config without burning a TestFlight build number. |
| `workflow_dispatch` (dry_run=false) | `release.yml` | Tests + signed archive + TestFlight upload (manual override). |
| Tag `v*.*.*` | `release.yml` | Tests + signed archive + TestFlight upload + GitHub release. |

## Required GitHub secrets (for release.yml)

User must add these once Apple Developer enrollment is approved:

| Secret | Source |
|---|---|
| `APPLE_TEAM_ID` | <https://developer.apple.com/account> → Membership Details (10-char alphanumeric) |
| `APPLE_API_KEY_ID` | App Store Connect → Users and Access → Integrations → Team Keys (10-char) |
| `APPLE_API_ISSUER_ID` | Same page, top of Team Keys section (UUID) |
| `APPLE_API_PRIVATE_KEY` | The `.p8` file contents — entire file including `-----BEGIN PRIVATE KEY-----` lines |
| `KEYCHAIN_PASSWORD` | Any random string — only used inside the macOS-15 runner |

API key role: **App Manager**.

## Workflow rules for agents (Karpathy-style)

1. **Surface assumptions before coding.** If the request is ambiguous, list 2–3 interpretations and ask.
2. **Surgical changes only.** Do not reformat, do not "improve" adjacent code, do not add type hints to code you didn't touch.
3. **No drive-by refactors.** Even if you see something you'd write differently, leave it alone unless the user asks.
4. **Declarative > imperative.** Don't fix bugs blind — write a failing test first, then make it pass.
5. **Boundary set.** `Protocol/` is sacred (see above). The 9 BOOTSTRAP_WRITES are byte-identical to the iPad capture.
6. **Single commit per feature.** Group related file changes; don't sprinkle.
7. **Honor the unsigned build path.** `CODE_SIGNING_REQUIRED: NO` is intentional — it lets `build.yml` produce dev IPAs without a Team ID. Don't remove these settings.
8. **`WatchTelemetryMessage` is duplicated** between `VoltraLive/Bridge/PhoneWatchBridge.swift` and `VoltraWatch/WatchTelemetryStore.swift` (no shared framework). They MUST stay in sync. The enum cases use identical raw `String` values for JSON round-tripping.

## Known caveats / future migrations

- **`altool` is being deprecated** by Apple. Still works in Xcode 16; migrate to `xcrun notarytool` before Apple removes support.
- **`WatchTelemetryMessage` duplication** — see rule 8 above. If/when we add a shared Swift package, collapse these.
- **Web prototype is abandoned** — `voltra-live/` (sibling dir) exists but is no longer the path forward. Native is canonical.

## How to know your changes are good

1. `xcodegen generate` succeeds with no errors.
2. `xcodebuild test -scheme VoltraLive -destination 'platform=iOS Simulator,name=iPhone 15'` passes.
3. CI `build.yml` stays green on push.
4. CI `release.yml` dry-run produces an IPA artifact.
5. The 4 assertions in `VALIDATION.md` still hold when the user runs against real hardware.

If any of these regress, **revert** rather than try to fix forward. The protocol layer is more
important than any feature.
