# B70 — Ambiguity adjudication request for Opus

You are being asked to adjudicate every discrepancy between (a) the b70
implementation prompt issued by a previous reviewer, (b) the b70 handoff
README I (Claude Sonnet 4.6) authored as the source-of-truth context for that
reviewer, and (c) what the actual repo at HEAD `0312a90` (branch
`feat/ui-v4-2-claude`) contains.

The reviewer's b70 prompt was generated against my README. **My README contained
factual errors about the repo.** Therefore the b70 prompt may be partly
miscalibrated. Before I write a single line of b70 code, the user wants you to
adjudicate, item by item, whether each ambiguity is (i) a no-op, (ii) a
prompt-amendment, or (iii) a code change relative to what the prompt said.

The user's hard rule is: **do not guess, do not infer, do not invent**. Every
load-bearing fact below is cited with a file path and line number from HEAD
`0312a90`. Where my own prior README contradicts the repo, both are quoted.

---

## Repo state

- Branch: `feat/ui-v4-2-claude`
- HEAD: `0312a90` (pre-edit scratchpad committed, no b70 code yet)
- Last shipped: v0.4.42 / build 69 (TestFlight, but the user reports b69's
  Demo Mode "didn't include the simulation tho")
- Target: v0.4.43 / build 70

## What b69 actually does today (verified, not assumed)

The b68/b69 fix IS in the code at HEAD. Both V1 (`LiveCaptureView.swift`)
and V2 (`LiveCaptureViewV2.swift`) contain a private
`autoEngageDemoIfNeeded()` that reads `DemoTelemetryBridge.shared.handler` and
calls `demo.enter(source: .prePair, onTelemetry: handler)` when
`!anyDeviceConnected && !demo.isActive`. Verbatim from `LiveCaptureViewV2.swift:1487-1495`:

```swift
private func autoEngageDemoIfNeeded() {
    guard !anyDeviceConnected, !demo.isActive else { return }
    guard let handler = DemoTelemetryBridge.shared.handler else { return }
    demo.note(.buttonTap(
        label: "Auto-engage (no device, weight tapped)",
        screen: "LiveCaptureViewV2"
    ))
    demo.enter(source: .prePair, onTelemetry: handler)
}
```

V1 has an identical helper at `LiveCaptureView.swift:994-1004`.

**`anyDeviceConnected` is computed at `LiveCaptureViewV2.swift:1478-1482`:**

```swift
private var anyDeviceConnected: Bool {
    ble.connectionState.isConnected
        || mdm.left.connectionState.isConnected
        || mdm.right.connectionState.isConnected
}
```

**Trigger sites:**
- V1: `sendLoad()` calls `autoEngageDemoIfNeeded()` first (per commit
  `b0f67ac`).
- V2: `toggleHardwareLoad()` calls it at line 1462.

So the fix is in. The reported failure mode "Demo Mode didn't include the
simulation" implies one of: (1) `handler` is nil at call time, (2)
`demo.isActive` is already true so `enter()` early-returns and the synthetic
generator was never started, (3) some other path I haven't seen. This frames
the b70 hypotheses below.

---

## Discrepancies between the b70 prompt and the repo

### D1. Path typo: `LoggingViews/` vs `Logging/Views/`

**B70 prompt says:** modify `VoltraLive/LoggingViews/DebugView.swift` and
`VoltraLive/LoggingViews/LoggingHomeView.swift`.

**Repo at HEAD:** the directory is `VoltraLive/Logging/Views/` (with the
slash). `glob VoltraLive/LoggingViews/*.swift` returns 0 files. `glob
VoltraLive/Logging/Views/*.swift` returns 13 files.

**Adjudication needed:** confirm the b70 prompt's intended targets are the
files at `VoltraLive/Logging/Views/DebugView.swift` (356 lines) and
`VoltraLive/Logging/Views/LoggingHomeView.swift` (555 lines). If yes, no other
change — just use the correct paths.

---

### D2. **CRITICAL: my README falsely claimed "no Demo Toggle exists"**

**My b70 README said (line 94 of the bundle README):**
> "There is no `Toggle` for Demo Mode anywhere in the codebase. Demo Mode is
> entered via two `DemoModeButton` instances..."

**Repo at HEAD says different.** `VoltraLive/Logging/Views/DebugView.swift:86-111`
contains:

```swift
section("DEMO MODE") {
    HStack {
        Text(demo.isActive ? "Demo Mode is active" : "Demo Mode is off")
            .font(.system(size: 14))
            .foregroundColor(VoltraColor.text)
        Spacer()
        Toggle("", isOn: Binding(
            get: { demo.isActive },
            set: { newVal in
                if newVal {
                    guard let handler = DemoTelemetryBridge.shared.handler else { return }
                    demo.note(.buttonTap(label: "Demo toggle ON", screen: "Debug"))
                    demo.enter(source: .settingsRestore, onTelemetry: handler)
                } else {
                    demo.note(.buttonTap(label: "Demo toggle OFF", screen: "Debug"))
                    _ = demo.exit()
                }
            }
        ))
        .labelsHidden()
        .tint(VoltraColor.accent)
    }
    Text("While active, no logs, sets, or settings are written to disk. ...")
}
```

So a Toggle DOES exist. It uses `source: .settingsRestore`. This is consistent
with the reviewer's diagnosis that `.settingsRestore` never starts the
synthetic generator (per `DemoController.enter` at lines 105-149, only the
`source == .prePair` branch creates a `SyntheticTelemetryGenerator`).

**B70 prompt says:** "in DebugView, inject ble + mdm env objects, replace the
demo toggle binding to pick source by connection."

**Adjudication needed:** the prompt's intent matches the existing toggle
exactly — the change is *rebind the existing toggle's `set:` closure*, not
*add a new toggle*. Confirm we should rebind in place. The new `set:` should
choose `.prePair` (no device) or `.postPair` (device connected) instead of
`.settingsRestore`. This means `.settingsRestore` will become unreferenced in
the codebase (currently it has zero call sites that ever start a synthetic
stream — the toggle is its only caller). Should we DELETE the
`.settingsRestore` enum case from `DemoController.swift:35-45`, or leave it as
dead code for future use?

---

### D3. `DemoController` exposes `entrySource`, not `source`

**B70 prompt's pseudocode for the self-heal branch in `enter()`:**
```
if isActive && source == .prePair && synthetic == nil {
    startSynthetic(onTelemetry: onTelemetry)
}
```

**Repo at HEAD:** the published property is `entrySource`, not `source`. From
`DemoController.swift:62`:

```swift
@Published private(set) var entrySource: DemoEntrySource? = nil
```

The parameter to `enter()` is named `source` (line 105:
`func enter(source: DemoEntrySource, onTelemetry: ...)`). So inside `enter()`,
`source` is the local parameter. But for the self-heal branch the controller
needs to compare against the *currently-active* entry source, which is
`entrySource` (the published property). Otherwise we'd be comparing a fresh
incoming param against itself.

**Adjudication needed:** confirm the self-heal condition should be:

```swift
if isActive && entrySource == .prePair && synthetic == nil {
    startSynthetic(onTelemetry: onTelemetry)
    return
}
```

Placed BEFORE the existing `guard !isActive else { return }` at line 106.

Also note: `entrySource` is `private(set)`, which is fine for read access from
inside the controller. No visibility change needed.

---

### D4. Persistence: `demoMode.toggleOn` is genuinely dead on launch (verified)

**B70 prompt says:** add a launch `.onAppear` in `VoltraLiveApp.swift` that
reads `demo.settingsToggleOn` and re-enters if true.

**Repo at HEAD:**
- `DemoController.toggleKey = "demoMode.toggleOn"` is at line 73.
- `enter()` writes `true` at line 146; `exit()` writes `false` at line 179.
- `settingsToggleOn` getter is at lines 76-79.
- **`grep "settingsToggleOn" VoltraLive/**/*.swift` returns ONLY the getter
  declaration** — there are zero other call sites in any Swift file. No
  `.onAppear` reads it.
- `VoltraLiveApp.swift:120-200` is the app's `.onAppear` block. It wires the
  telemetry handler (line 174) and other setup, but never calls
  `demo.settingsToggleOn` or `demo.enter(source: .settingsRestore, ...)`.

So the persistence is genuinely write-only at HEAD. The b70 prompt's
rehydration fix is correct in principle.

**Adjudication needed:** the b70 prompt's rehydration uses `.settingsRestore`
as the source. Per D2 above, `.settingsRestore` never starts the synthetic
generator. So the rehydration would re-enter demo but never see a synthetic
stream — same bug as the toggle. Two options:

- **Option A:** rehydrate with a connection-aware source — `.prePair` if no
  device connected at launch, `.postPair` otherwise. (Matches the toggle fix
  in D2.)
- **Option B:** keep `.settingsRestore` and FIX `enter()` so the
  `.settingsRestore` branch ALSO starts the synthetic generator when no
  device is connected. (Adds a second source that triggers synthetic.)

Which path does the b70 prompt actually intend? The prompt isn't explicit.

---

### D5. `LoggingHomeView` demo button hardcodes `.postPair` (b70 prompt is correct)

**B70 prompt says:** in `LoggingHomeView`, replace the hardcoded `.postPair` in
the demo button with a connection-aware source.

**Repo at HEAD (`Logging/Views/LoggingHomeView.swift:159-167`):**

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

`LoggingHomeView` already has `@EnvironmentObject var ble: VoltraBLEManager`
(line 15) and `@EnvironmentObject var mdm: MultiDeviceManager` (line 27). So
the helpers are available without env-object injection changes.

**Adjudication needed:** confirm the new logic should be: if any device
connected → `.postPair`; otherwise → `.prePair`. And confirm the user
actually still wants this button visible at all when no device is connected
— previously it only made sense post-pair (the `.postPair` path uses real
device telemetry). For pre-pair, the prePair branch starts synthetic
telemetry, which IS what the user wants for "Demo Mode without a device". So
yes, button stays visible regardless and source switches.

---

### D6. Sheet `.pageBadge` additions — confirm targets exist

**B70 prompt says:** add `.pageBadge(...)` to `UnifiedConnectSheet`,
`DemoEndSheet`, `NewExerciseSheet`, `LiveCaptureUIPickerSheet`.

**Adjudication needed:** I have not yet verified all four sheets exist as
named, and what their current `.pageBadge` state is. Before editing, please
confirm the canonical names in the repo. (I will glob and report back in the
follow-up; this is a flag that I need to verify them, not an immediate
discrepancy.)

---

### D7. Self-heal branch — when does `isActive` ever drift `true` while `synthetic` is `nil`?

**B70 prompt's premise:** "the persisted `demoMode.toggleOn` UserDefaults
key never gets read on launch, so `enter()` early-returns on
`guard !isActive` once the bit drifts true with no synthetic generator
alive."

**Repo at HEAD says:** `isActive` is `private(set) var isActive: Bool = false`
and is only mutated in `enter()` (set to `true` at line 148) and `exit()`
(set to `false` at line 175). On a fresh app launch, the controller is
re-instantiated, `isActive` initializes to `false` regardless of what the
UserDefaults bit says. So the persisted bit can be `true` while
`isActive` is `false` — that's the dead-persistence bug (D4) — but it does
NOT cause `isActive` to "drift true with no synthetic alive" on launch.

**Adjudication needed:** is the b70 self-heal branch defending against a real
case, or a phantom one? Possible real cases:

1. A bug elsewhere that calls `enter()` then nils out `synthetic` (none seen
   in code).
2. A future regression where someone adds a code path that flips `isActive`
   true via something other than `enter()`.
3. A race during `exit()` where `synthetic = nil` is set but `isActive`
   doesn't get flipped (line 161 sets `synthetic = nil`; line 175 sets
   `isActive = false`; both are `@MainActor` so no race — these run
   atomically on the main actor).

If none of these are real, the self-heal branch is dead defensive code. If
the user wants belt-and-suspenders we keep it; if not, we drop it from the
scope. Which is the call?

---

### D8. Real root cause hypothesis — what actually broke b69?

Given everything above, here is the menu of failure modes consistent with the
user's report "Demo Mode engaged but didn't include the simulation":

**H1.** `DemoTelemetryBridge.shared.handler` was nil at the moment
`autoEngageDemoIfNeeded()` ran. The handler is set inside
`VoltraLiveApp.swift:174` on `.onAppear`, but the `.onAppear` is on the root
`ContentView` wrapping. If the user's first-launch flow hits the LIVE screen
before the root `.onAppear` fires (unlikely on a normal launch, but
plausible on state-restoration paths), the bridge handler is nil, the
`guard let handler` returns silently, and demo never enters. The user sees
nothing.

**H2.** `demo.isActive == true` at launch from a stale-state hand-back. If
the persisted `demoMode.toggleOn = true` is somehow read AND drives a state
where the controller treats itself as active (currently nothing does this,
but a forthcoming b70 change might), then `enter()` early-returns.

**H3.** The user tapped the DebugView toggle (which uses `.settingsRestore`)
which never starts the synthetic generator. Banner shows ("Demo Mode is
active"), but no telemetry → "didn't include the simulation". This is a
clean, fully-consistent explanation that matches user behavior.

**H4.** The synthetic generator started but nothing consumed its output. From
the bundle README: V1 chart reads `session.currentSet?.samples`, V1 tile
grid reads `ble.telemetry`. The bridge handler at
`VoltraLiveApp.swift:148-170` writes to BOTH. But if the user is on the
LiveCapture screen BEFORE `currentSet` exists (no set started yet), the
chart shows nothing. Synthetic frames flow into `bleManager.telemetry` via
`ingestRoutedTelemetry(telem)` at line 168 → tiles update → so SOME tiles
should still be ticking. If user reports "no simulation at all" (chart AND
tiles inert), this points back to H1.

**Adjudication needed:** which of H1, H2, H3, H4 should b70 actually target?
The prompt's 8 file changes lean toward H2/H3 mitigation. If H1 is real, we
need different fixes (e.g., move handler init earlier, or make
`SyntheticTelemetryGenerator` self-host the handler closure as a fallback).

---

## Open questions for Opus to resolve before any code is written

**Q1.** D1 path typo — confirm targets are `Logging/Views/`, not `LoggingViews/`. (I'm 99% sure but want it on record.)

**Q2.** D2 false-premise — confirm the DebugView Toggle exists, the b70 task
becomes "rebind existing toggle", and tell us whether to delete or retain the
`.settingsRestore` enum case.

**Q3.** D3 published-property naming — confirm the self-heal branch uses
`entrySource` for the comparison.

**Q4.** D4 rehydration source — Option A (connection-aware) or Option B
(make `.settingsRestore` start synthetic)?

**Q5.** D5 LoggingHomeView source rule — confirm "any device connected →
`.postPair`, else `.prePair`".

**Q6.** D6 sheet targets — please tell us the canonical sheet names so I can
locate them deterministically. Or instruct me to skip the sheet additions and
do them in a follow-up build.

**Q7.** D7 self-heal — is this defending a real case? If not, drop from
scope?

**Q8.** D8 root cause — which hypothesis does Opus believe is the actual b69
failure mode? The fix list should follow from this answer.

**Q9.** Build version — confirm v0.4.43 / build 70.

**Q10.** Anything else in the prompt that you (Opus) want to override given
the actual repo state. The prompt was generated against my flawed README; you
have direct repo access via this document.

---

## What I will do once Opus answers

For each Q above I will write the code change verbatim per Opus's
instruction, commit incrementally per the architect's discipline rule, push
to `feat/ui-v4-2-claude`, then run the 5-gate altool ship for v0.4.43/build
70. No edits will happen until Opus answers all of Q1–Q10.

This document is committed at HEAD `0312a90` →
`docs/handoff/_tmp/b70_OPUS_AMBIGUITY_PROMPT.md`. Opus is welcome to reference
specific file paths and line numbers from the canonical source zip at
`docs/handoff/_tmp/voltra-live-source-b70.zip` (already shipped).
