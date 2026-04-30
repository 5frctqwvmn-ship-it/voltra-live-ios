# b70 Pre-edit scratchpad — open questions

Created at HEAD `afec8ac` before any code changes for b70.
Purpose: capture verified facts + ambiguities before touching files, so that
even if context is lost, the next agent can pick up cleanly.

## Verified facts (from repo at HEAD afec8ac)

### 1. Real source paths (architect's prompt has typos)

Architect wrote `VoltraLive/LoggingViews/...` (no slash). Real paths are:

- `VoltraLive/Logging/Views/DebugView.swift` (356 lines)
- `VoltraLive/Logging/Views/LoggingHomeView.swift` (555 lines)

Use the real paths. `LoggingViews/` does not exist.

### 2. DebugView ALREADY HAS a Demo Mode toggle (architect's prompt is wrong here)

`VoltraLive/Logging/Views/DebugView.swift:86-111` contains a `Toggle("", isOn:
Binding(...))` that calls `demo.enter(source: .settingsRestore, ...)` when
flipped on. It is NOT a NavigationLink — it IS a Toggle.

My own b70 handoff README (which I shipped to the architect) stated "There is
no Toggle for Demo Mode anywhere in the codebase." **That statement was wrong.**
The architect's b70 prompt is partly built on this false premise.

What this changes about the b70 plan:

- The architect's "File 3" task says "replace Demo toggle binding to pick
  source by connection" — that is still the right intent, but the toggle
  ALREADY EXISTS and currently uses `.settingsRestore`. The change is to swap
  `.settingsRestore` → `.prePair` (no device) or `.postPair` (device connected),
  not to add a new toggle.
- The bug the architect identified (`.settingsRestore` never starts synthetic)
  IS real, because that's what the toggle uses today.

### 3. LoggingHomeView demo button hardcodes `.postPair` (architect was right)

`VoltraLive/Logging/Views/LoggingHomeView.swift:159-167`:

```swift
if !demo.isActive {
    HStack {
        Spacer()
        DemoModeButton(source: .postPair) {
            guard let handler = DemoTelemetryBridge.shared.handler else { return }
            demo.note(.buttonTap(label: "Demo Mode (post-pair)", screen: "LoggingHome"))
            demo.enter(source: .postPair, onTelemetry: handler)
        }
        Spacer()
    }
    .padding(.horizontal, 18)
}
```

This is unconditionally `.postPair` regardless of pairing state. Confirmed.

### 4. DemoController structure (architect's pseudocode references wrong field)

The controller exposes `entrySource: DemoEntrySource?`. There is NO field named
`source`. Architect's pseudocode `if isActive && source == .prePair && synthetic == nil`
must be `if isActive && entrySource == .prePair && synthetic == nil`.

`enter()` signature at line 105:
```swift
func enter(source: DemoEntrySource, onTelemetry: @escaping (Telemetry) -> Void)
```
The parameter name is `source`. The published property is `entrySource`.

### 5. `enter()` early-return is a real concern (architect was right)

Line 106: `guard !isActive else { return }`

If `isActive` is somehow `true` but `synthetic` is `nil`, calling `enter()`
again is a no-op. Architect's self-heal branch (start synthetic if active +
prePair + nil generator) is defensible.

But: how does `isActive` ever drift `true` while `synthetic` is `nil`? Only via
a bug in the controller itself (none seen) or a race during shutdown. The more
likely cause of the user's failure is path #6 below.

### 6. Persistence (architect's "dead UserDefaults" claim is correct)

`UserDefaults.standard.set(true, forKey: "demoMode.toggleOn")` is written by
`enter()` (line 146) and `exit()` (line 179). `settingsToggleOn` getter exists
at line 76 but **no caller invokes it on launch**. There is no `.onAppear` in
`VoltraLiveApp.swift` that rehydrates from this bit.

Result: across launches, the persisted bit can read `true` while
`DemoController.isActive` is `false`. No banner, no synthetic stream.

The fix proposed (rehydration call on launch) is correct.

## Open questions for user

I have enough verified state to proceed BUT the architect's prompt contains at
least one false premise (Q2 above, my own fault — I told the architect there
was no Toggle, when there is). Some of the proposed file changes need
adjustment. Per the user's hard rule "I have more bugs to report. Let's wait
until I say done to start trying to fix them", and per the architect's own
ambiguity rule, I need to confirm scope before editing.

Q1: Should I proceed with the b70 prompt as-written, treating the architect's
"add a Demo toggle to DebugView" instruction as "modify the EXISTING toggle in
DebugView to source-by-connection"? The intent is the same; only the
implementation changes from "add" to "rebind."

Q2: The architect lists 8 files plus 4 sheet additions for `.pageBadge`. Are
you done reporting bugs? Or should I hold all b70 implementation until you say
"done"?

Q3: Confirm version target: v0.4.43 / build 70?

## Plan-of-attack (only execute on user GO)

If user says "go," commit incrementally per architect's rules:

1. DemoController.swift — startSynthetic() helper extracted; self-heal branch
   added at top of enter() using `entrySource` (not `source`); persistence
   helpers consolidated.
2. VoltraLiveApp.swift — `.onAppear` rehydration that reads `demo.settingsToggleOn`
   and calls `demo.enter(source: <connection-aware>, onTelemetry: handler)` if
   the bit is true and `demo.isActive` is false.
3. DebugView.swift — replace EXISTING toggle binding's `set:` to choose
   `.prePair` (no device) vs `.postPair` (device connected). Inject
   `@EnvironmentObject ble: VoltraBLEManager` + `@EnvironmentObject mdm:
   MultiDeviceManager`. Update `#Preview`.
4. LoggingHomeView.swift — replace `.postPair` literal with the
   connection-aware source.
5. NEW VoltraLive/Views/DebugGridOverlay.swift — DebugGridMode enum
   (off/coarse/medium/fine) + `@AppStorage("debugGridMode")`.
6. NEW VoltraLive/Views/PageRegistry.swift — central numbering table.
7. PageBadgeOverlay.swift — render "<num> · <name>", mount
   `.debugGridOverlay()`.
8. BuildBadgeOverlay.swift — tap cycles DebugGridMode.
9. Add `.pageBadge(...)` to UnifiedConnectSheet, DemoEndSheet, NewExerciseSheet,
   LiveCaptureUIPickerSheet.
10. Bump version (project.yml + Info.plist) + docs (04, 06, 03, 07, WORK_LOG).
11. Push, run release.yml dry_run=false, 5-gate altool verify.
