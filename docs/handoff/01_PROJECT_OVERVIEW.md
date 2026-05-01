# 01 — Project Overview

_Current shipping build: **v0.4.46 / build 73** (b73 cycle, branch `feat/ui-v4-2-claude`). For the rolling cycle snapshot see `02_CURRENT_STATE.md`._

## What VOLTRA Live is

A native iOS app that mirrors live workout telemetry from a Beyond Power
**VOLTRA** cable machine over BLE, logs sets to a local SwiftData store,
and overlays HealthKit data (heart rate, active calories) during sessions.

Originally framed as **read-only**. As of April 2026 the user has explicitly
approved **control writes** (weight, eccentric, chains, mode, and upcoming
LOAD/UNLOAD), gated through `VoltraWriter`. See
`05_BLE_AND_PROTOCOL.md#control-writes` for the policy.

## Identifiers

- iOS bundle ID: `com.voltralive.app`
- Test bundle ID: `com.voltralive.app.tests`
- Min iOS: 17.0
- Apple Team: `588XUZGNNS`
- App Store Connect App ID: `6763798738`
- iCloud Container: `iCloud.com.voltralive.app` (currently **disabled** — see `02_CURRENT_STATE.md`)
- GitHub user: `5frctqwvmn-ship-it`
- Repo: <https://github.com/5frctqwvmn-ship-it/voltra-live-ios>

## Hardware in scope

- 1 or 2 VOLTRA cable machines per session.
  - Single-device: existing flow, one peripheral.
  - Dual-device: new flow (build 30), Left + Right with Independent or Combined mode.
- iPhone running iOS 17+. **No Mac available to user** — all signing is CI.
- Apple Watch companion: deferred to v1.2.

## Constraints the user has been firm about

- Single-device flow must keep working with no regression as dual ships.
- Build number must be visible on every screen.
- Push notification when long-running task needs input.
- "Repeat what I asked" before executing (Karpathy).
- Sacred protocol files are off-limits without explicit approval.
- Secrets are referenced by NAME only, never values.
- User has no Mac → browser-only signing path is mandatory.

## Audience for this doc set

- Future LLM sessions (after compaction or new chat).
- Future-me reviewing months later.
- Anyone the user invites to contribute.
