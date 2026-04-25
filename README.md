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

## Requirements

- iPhone or iPad running iOS 17+
- VOLTRA BLE device

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
```

## Protocol notes

- Service UUID: `e4dada34-0867-8783-9f70-2ca29216c7e4`
- 10 bootstrap write frames sent to TRANSPORT characteristic on connect
- Three notification characteristics subscribed (CMD, NOTIFY, TRANSPORT)
- Frame magic: `0x55`; extended types `0x09`/`0x05` add 256 to declared length
- All parsing logic ported verbatim from `voltra-protocol.js`

## License

Apache 2.0 — protocol reverse engineering credit: [dylanmaniatakes/Beyond-Power-Voltra-Android](https://github.com/dylanmaniatakes/Beyond-Power-Voltra-Android)
