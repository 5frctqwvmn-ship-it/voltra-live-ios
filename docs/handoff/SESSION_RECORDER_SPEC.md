# Session Recorder Spec (B74-F11)

> Status: SPEC ONLY. No Swift implementation in this commit. Scope-locked
> docs PR. Implementation lands in a separate PR per the agent-roles
> contract.
>
> Cross-refs: `B74_BUG_QUEUE.md` (status row + entry),
> `04_DECISIONS_AND_CONSTRAINTS.md` ADR V4-D25 (architecture rationale),
> `07_FILE_MAP.md` (file placeholders), `docs/WORK_LOG.md` (open entry).

## Purpose

Local-only AI-readable session recorder for debugging. No server. No PII
by default.

## Activation

Hidden until the user **triple-taps the build-badge chip**. Persisted in
UserDefaults as `VOLTRARecorderUnlocked`. When unlocked, a **24×24 pt
dot** appears at the bottom-trailing safe area on every screen via **one
root-level overlay** — never per-screen.

## Toggle

- **Tap** = start / stop recording.
- **Red 1 Hz pulse** while armed via `TimelineView(.animation)`.
- **Faint `textFaint` dot** while idle.
- **Long-press** = open `SessionRecorderViewer` sheet.
- **Accessibility:** `"Session recorder on/off. Double tap to toggle. Long press to view."`

## Service

`SessionRecorder` is **one** `ObservableObject` single shared recorder.
It is injected at the app root via `.environmentObject`. It owns:

- `isRecording`
- `sessionId`
- `start` / `end` `Date`
- 10,000-event FIFO ring buffer
- `ActionScope` task-local `actionId`

### Persistence

- Thread-safe buffer via serial queue or `actor`.
- On app background / kill, persist current session JSON to
  `Application Support/SessionRecorder/last_session.json`.
- Load last session on init.
- **No** other disk writes.
- **No** network. Ever.

## Event Schema

`RecorderEvent: Codable, Identifiable`

- `id: UUID`
- `sessionId: UUID`
- `actionId: UUID?` (nil for ambient events)
- `timestamp: Date`
- `monotonic: UInt64` using `DispatchTime.now().uptimeNanoseconds`
- `category`: `ui | nav | state | async | ble | guard | lifecycle | recorder`
- `name: String` — dotted event name, e.g. `"ble.write.tx"`
- `screen: String?`
- `metadata: [String: Value]` where `Value = string | int | double | bool | hex`
- `error: ErrorRecord?` with `domain`, `code`, `message`, `isUserVisible`
- `ble: BLESubrecord?` with `kind`, `peripheralId`, `side`, `characteristic`,
  `hex`, `length`, `rssi`

`BLESubrecord.kind`:

`discovery`, `connect`, `disconnect`, `writeTx`, `writeAck`, `notifyRx`,
`readRx`, `error`.

## Name Grammar

```
ui.tap, ui.toggle, ui.gesture
nav.push, nav.pop, nav.tabChange, nav.sheetPresent, nav.sheetDismiss,
   nav.screenAppear, nav.screenDisappear
state.modeChange, state.flagChange, state.validation
async.taskStart, async.taskEnd, async.taskError
ble.discovery, ble.connect, ble.disconnect, ble.write.tx, ble.write.ack,
   ble.notify.rx, ble.read.rx, ble.error
guard.trip
lifecycle.sessionStart, lifecycle.sessionEnd, lifecycle.appBackground,
   lifecycle.appForeground
recorder.armed, recorder.disarmed, recorder.exported
```

## ActionScope

Task-local `UUID`. User-initiated UI actions mint a new `actionId` and
run downstream work inside the scope. All events emitted inside the
scope auto-inherit `actionId` without manual threading.

## Redaction

`RecorderRedactor` runs on every metadata write.

- BLE peripheral name → UUID.
- Exercise name, custom day name, user-entered free text → `"<redacted:len=N>"`.
- Hex, numeric values, screen names, and dotted event names pass through raw.
- Caller may opt in to raw only with explicit `unsafeRaw` API.

## Export

`RecorderExporter` produces two outputs:

1. **`.txt` AI-readable report** with header (app version, build,
   `sessionId`, start / end, timezone, event count), timeline grouped by
   `actionId` showing cause → effect chains, errors / guards subsection,
   and BLE transcript.
2. **`.json` full structured export:**
   `{ schemaVersion, appVersion, build, session, events }`.

Share via `ShareLink` with **both `.txt` and `.json`** attachments in
one share action.

## UI Mount

Single overlay in `VoltraLiveApp` root via
`.overlay(alignment: .bottomTrailing) { SessionRecorderToggle() }`.

**No per-screen buttons.**

Screens tag themselves via `.recorderScreen("ScreenName")` wrapping
`.onAppear` / `.onDisappear`.

## Instrumentation Scope

- **UI:** major taps, toggles, modal present / dismiss.
- **Nav:** push / pop / tab / sheet + screen appear / disappear via
  `.recorderScreen`.
- **State:** demo flag, mode transitions, validation decisions.
- **Async:** `taskStart` / `taskEnd` / `taskError` on long-running flows.
- **BLE:** central chokepoints in `MultiDeviceManager`,
  `MultiDeviceManager+V42`, `DualMode`, `PairingCoordinator`, and
  write / notify handlers.
- **HealthKit:** read-only logging of auth state, session start / end,
  sample arrivals, `HKSource.name`, and `HKSource.bundleIdentifier`.
- **Guards:** sweep `guard … else { return }` on user-visible paths;
  replace with `rec.guardTrip(name:, reason:, state:)` then return.

## Hard Stops

- No `Info.plist` changes.
- No `project.yml` changes.
- No entitlements changes.
- No release-workflow changes.
- No BLE runtime behavior changes.
- No `WatchConnectivity` runtime behavior changes.
- No server calls.
- No analytics.
- No external logging.
- No per-screen toggle buttons.
- No new silent guards.

## Verification Contract

**Mechanically verified:**

- Swift compile.
- Unit tests for `RecorderBuffer` wrap / thread-safety.
- Unit tests for `RecorderRedactor` PII rules.
- Unit tests for `RecorderExporter` text + JSON round-trip.
- Unit tests for `ActionScope` propagation.

**TestFlight QA** must append to `docs/handoff/QA_LOG.md` with
**Working / Not / Other** for each pass:

A. **Ubiquity:** toggle appears on Home, all day tiles, Live view, and
   a sheet.
B. **Lifecycle:** tap on / off produces red pulse; session survives
   app kill.
C. **Semantic log:** 3 taps + 1 modal + 1 navigation event produce a
   readable timeline with screen names.
D. **Correlation:** Connect L produces one `actionId` chain through
   validate → `ble.write.tx` → `write.ack` → `notify.rx` → state
   update.
E. **Loud guards:** blocked action produces `guard.trip` with reason
   and state.
F. **Share:** `.txt` and `.json` both attach and are non-empty.
G. **HealthKit:** with recorder on + live workout, HR sample source
   and `lastHRSampleAt` are logged truthfully.

## Definition of Done

Session Recorder is **not done** until:

- Spec PR merged.
- Implementation PR merged.
- One TestFlight build shipped with feature label `"Session Recorder"`.
- `QA_LOG.md` contains Working / Not / Other for passes A–G.
- Any **Not** result is filed in `docs/handoff/06_KNOWN_ISSUES.md` or
  fixed in a follow-up PR.
