# VOLTRA Live — iOS Native App

Real-time workout telemetry for VOLTRA BLE devices. Native SwiftUI app for iPhone and iPad. iPad landscape (rack-mounted) is the primary use case.

## Features

- **Live force chart** — 30-second rolling window, phase-colored line segments
- **4 big tiles** — REPS, PHASE, FORCE, REST — readable from 8 feet
- **Set-complete detection** — auto-detects set end after 4s of idle
- **Rest timer** — auto-starts on set end, stops on next rep
- **Session history** — persisted via SwiftData, last 50 sessions retained
- **Compare strip** — current session vs last session rep delta
- **Read-only BLE** — only the 10 handshake writes; no control commands
- **Apple Watch companion** — live rep/phase/force mirrored to Watch via WatchConnectivity

## Requirements

- iPhone or iPad running iOS 17+
- VOLTRA BLE device
- Apple Watch (Series 4+, watchOS 10+) — optional, for wrist telemetry

## Installing via AltStore (sideload)

1. Download the latest `VoltraLive-unsigned.ipa` from the [GitHub Actions artifacts](../../actions).
2. Install [AltStore](https://altstore.io) on your Mac/PC and on your device.
3. Connect your device via USB to the Mac/PC running AltStore.
4. Open AltStore on your device → **My Apps** → **+** → select `VoltraLive.ipa`.
5. Sign in with your free Apple ID when prompted.
6. App will appear on your home screen.

### AltStore refresh cadence

Free Apple IDs sign apps for 7 days. AltStore can auto-refresh when your device and Mac/PC are on the same Wi-Fi.

- Keep **AltServer** running on your Mac/PC.
- Enable **Background App Refresh** for AltStore on your device.
- AltStore will refresh automatically every few days in the background.

Alternatively, use [SideStore](https://sidestore.io) for fully on-device signing that doesn't require a Mac/PC to stay running.

## TestFlight Setup

Once your Apple Developer Program enrollment is approved (~24 hours), follow these steps to enable signed TestFlight builds via CI.

### Step 1 — Get your Team ID

1. Sign in at [developer.apple.com/account](https://developer.apple.com/account).
2. Go to **Membership Details**.
3. Copy your **Team ID** (10-character alphanumeric string, e.g., `A1B2C3D4E5`).

### Step 2 — Create an App Store Connect API key

1. Open [App Store Connect](https://appstoreconnect.apple.com) → **Users and Access** → **Integrations** tab → **Team Keys**.
2. Click **+** to create a new key.
3. **Name**: `GitHub Actions CI`
4. **Access**: `App Manager` (sufficient for TestFlight uploads — no need for Admin).
5. Click **Generate**.
6. **Download the `.p8` file immediately** — Apple only shows it once. Store it securely.
7. Note the **Key ID** (10 characters, shown in the table) and **Issuer ID** (UUID, shown at the top of the page).

### Step 3 — Reserve the bundle ID

1. In App Store Connect → **Apps** → **+** → **New App**.
2. Platform: iOS.
3. Bundle ID: `com.voltralive.app` (must match exactly).
4. Complete the form. You don't need to submit anything yet — just reserving the ID allows CI to auto-create provisioning profiles.

### Step 4 — Add GitHub secrets

In your GitHub repo: **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.

Add these 5 secrets:

| Secret name | Value |
|---|---|
| `APPLE_TEAM_ID` | 10-char Team ID from Step 1 |
| `APPLE_API_KEY_ID` | 10-char Key ID from Step 2 |
| `APPLE_API_ISSUER_ID` | UUID Issuer ID from Step 2 |
| `APPLE_API_PRIVATE_KEY` | Full contents of the `.p8` file (including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines) |
| `KEYCHAIN_PASSWORD` | Any random string — used to protect the temporary CI keychain (e.g., generate with `openssl rand -hex 16`) |

### Step 5 — Trigger a release build

Tag a release and push:

```bash
git tag v0.1.0
git push --tags
```

The `.github/workflows/release.yml` workflow triggers automatically on `v*` tags. It will:

1. Generate the Xcode project (with your Team ID injected).
2. Install the ASC API key so xcodebuild can auto-provision.
3. Archive and sign the app (certificate + provisioning profile created automatically).
4. Export and upload the signed IPA to TestFlight.
5. Attach the signed IPA to the GitHub release for the tag.

### Step 6 — Find the build in TestFlight

Apple processes uploaded builds in 5–15 minutes. Once processed:

1. Open **TestFlight** on your iPhone.
2. The `VOLTRA Live` build appears under **Apps**.
3. Tap **Install** to sideload it directly — no AltStore, no weekly refresh.

---

## Building from source (CI)

GitHub Actions builds an unsigned IPA automatically on every push to `main`.

### Local build (macOS with Xcode 15+)

```bash
brew install xcodegen
xcodegen generate
xcodebuild \
  -project VoltraLive.xcodeproj \
  -scheme VoltraLive \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

# Package IPA
mkdir -p Payload
cp -r build/Build/Products/Release-iphoneos/VoltraLive.app Payload/
zip -qry VoltraLive.ipa Payload
rm -rf Payload
```

## Project structure

```
VoltraLive/
├── Protocol/
│   ├── VoltraProtocol.swift       UUIDs, BOOTSTRAP_WRITES, constants
│   ├── FrameAssembler.swift       BLE fragmentation reassembly
│   ├── PacketParser.swift         Packet header decoder
│   └── TelemetryExtractor.swift   Rep/force/battery telemetry decoder
├── BLE/
│   └── VoltraBLEManager.swift     CoreBluetooth scan/connect/notify
├── Session/
│   ├── Models.swift               SwiftData PastSession/PastSet models
│   └── SessionStore.swift         Set-complete heuristic, rest timer
├── Bridge/
│   └── PhoneWatchBridge.swift     WatchConnectivity — pushes telemetry to Watch
└── Views/
    ├── ContentView.swift           Root: connect vs dashboard
    ├── ConnectView.swift           Bluetooth connect screen
    ├── DashboardView.swift         Live workout tiles + chart
    ├── TileView.swift              Reusable big-number tile
    ├── PhaseTileView.swift         Phase-animated tile
    ├── ForceChartView.swift        Swift Charts force chart
    ├── CompareStripView.swift      Set vs last session comparison
    ├── HistoryDrawerView.swift     Session history sheet
    └── VoltraTheme.swift           Colors, fonts (from styles.css)

VoltraWatch/                        Apple Watch companion
├── VoltraWatchApp.swift            @main entry, WCSession activation
├── WatchTelemetryStore.swift       ObservableObject for live Watch state
├── WatchSessionDelegate.swift      WCSessionDelegate — receives + decodes messages
├── ContentView.swift               Root: connected or waiting
├── Info.plist                      WKApplication: true, WKCompanionAppBundleIdentifier
└── Views/
    ├── ConnectedView.swift         Live dashboard: reps, phase, force, rest
    ├── WaitingForPhoneView.swift   "Open VOLTRA Live on your iPhone"
    └── PhaseIndicator.swift        Colored dot + phase label
```

## Protocol notes

- Service UUID: `e4dada34-0867-8783-9f70-2ca29216c7e4`
- 10 bootstrap write frames sent to TRANSPORT characteristic on connect
- Three notification characteristics subscribed (CMD, NOTIFY, TRANSPORT)
- Frame magic: `0x55`; extended types `0x09`/`0x05` add 256 to declared length
- All parsing logic ported verbatim from `voltra-protocol.js`

## Watch architecture

The Watch is a **phone-paired companion** — the iPhone handles all BLE communication, the Watch just renders what the phone sends. This is intentional:

- Phone BLE is always active during a set (phone is on the rack or nearby)
- VOLTRA only allows one BLE central per session
- Watch BLE has tight power constraints and is less reliable for this use case
- If the phone goes out of range, the Watch shows a clear "Phone Disconnected" screen

Data flows via `WatchConnectivity.transferUserInfo` (queued, reliable delivery even when Watch display is off), with a `sendMessage` fast path when the Watch is awake and reachable.

## License

Apache 2.0 — protocol reverse engineering credit: [dylanmaniatakes/Beyond-Power-Voltra-Android](https://github.com/dylanmaniatakes/Beyond-Power-Voltra-Android)
