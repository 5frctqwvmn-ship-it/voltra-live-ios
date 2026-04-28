# Model Council Prompt — HealthKit prompt-on-fresh-install bug

Copy everything below the `---` line into Perplexity model council. The
prompt is self-contained: facts, hypotheses already ruled out, and the
exact response format requested.

---

# VOLTRA Live iOS — HealthKit permission prompt never appears on fresh install

I'm shipping an iOS app via TestFlight using a GitHub Actions browser-only
pipeline (no Mac). On a fresh install of build 47/48, two things are wrong:

1. The system HealthKit permission sheet **never appears** on first launch.
2. The app's row never appears under **iOS Settings → Health → Data Access & Devices**.

But heart rate and active-energy samples DO flow into the app *if* HealthKit
authorization was granted on a previous install of the same bundle ID. So
the entitlement is partially working — the OS just isn't recognizing the
app as HK-capable on first install.

Please diagnose this and recommend the highest-confidence next action.
Format your response per the "How to respond" section at the bottom.

---

## Confirmed facts

### App identity

- Bundle ID: `com.voltralive.app`
- Apple Team: `588XUZGNNS`
- App ID record `6763798738`
- App Store provisioning profile UUID: `b3c606c2-0636-4727-a4a6-2d0b0ee81eb2`
- Distribution path: TestFlight via `altool` from GitHub Actions
- Deployment target: iOS 17.0
- Xcode: 26.2 on macos-26 runner
- Signing style: **manual** (ExportOptions.plist `signingStyle=manual`)
- The user has no Mac — all signing is browser/CI only.

### Entitlements file (`VoltraLive/VoltraLive.entitlements`)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudDocuments</string>
        <string>CloudKit</string>
    </array>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.com.voltralive.app</string>
    </array>
    <key>com.apple.developer.ubiquity-container-identifiers</key>
    <array>
        <string>iCloud.com.voltralive.app</string>
    </array>
    <key>com.apple.developer.ubiquity-kvstore-identifier</key>
    <string>$(TeamIdentifierPrefix)com.voltralive.app</string>
    <key>com.apple.developer.healthkit</key>
    <true/>
</dict>
</plist>
```

Notable: there is NO `com.apple.developer.healthkit.access` key (it was
intentionally removed in build 46 because it's only for clinical-records
read access, and an empty array value broke things). Standard HKQuantity
types like heart rate and active energy do not require it.

### Info.plist HK-relevant strings (present)

```
NSHealthShareUsageDescription = "VOLTRA Live reads heart rate and active energy from your Apple Watch workout so you can see live BPM and calories during a session."
NSHealthUpdateUsageDescription = "VOLTRA Live does not write to Health — this entry is required by the platform."
```

`UIBackgroundModes` is NOT set. There is no `processing` or background
fetch background mode declared. There is no `HKWorkoutSession` (this is an
iPhone app, not a watchOS app — HK samples come from the user's paired
Apple Watch via the iPhone HealthKit shared store).

### CI verifies HK is in the SIGNED entitlements

The release workflow has a hard-fail step that runs after `xcodebuild
-exportArchive`:

```bash
codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | tee /tmp/embedded.entitlements
grep -q "com.apple.developer.healthkit" /tmp/embedded.entitlements || MISSING+=("healthkit")
# fails build if missing
```

This step **passes green on every shipped build, including b47 and b48.**
So the embedded entitlements blob in the signed binary that ships to
TestFlight does contain `com.apple.developer.healthkit`. The provisioning
profile DOES grant it. (The profile is fetched by the App Store Connect
REST API at CI time and was generated against the App ID which has the
HealthKit capability checked.)

### App-side code (HealthKitStore.swift)

- Singleton `HealthKitStore` is created at app launch and injected as an
  `@EnvironmentObject`.
- `VoltraLiveApp.swift` calls `healthStore.requestAuthIfNeeded()` from the
  root `WindowGroup`'s `.onAppear` — i.e. as soon as the home screen
  renders on first launch.
- `requestAuthIfNeeded()` checks `HKHealthStore.isHealthDataAvailable()`,
  then calls:
  ```swift
  store.requestAuthorization(toShare: nil, read: readSet) { ok, _ in ... }
  ```
  with `readSet = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]`.
- All call sites are guarded `#if canImport(HealthKit)`.
- The implementation is correct against Apple's docs: read-only auth
  request with usage description strings present. This is the same code
  that worked in earlier installs (HK once authorized).

### Symptom on fresh install of b47/b48

User installs from TestFlight, deletes any prior version first or installs
on a device that has never seen the app:

1. Open app → no HK permission sheet.
2. Settings.app → Health → Data Access & Devices → **VOLTRA Live is not listed.**
3. Settings.app → Privacy & Security → Health → **VOLTRA Live is not listed.**
4. Settings.app → VOLTRA Live → there is no Health row in the per-app settings.
5. HR / kcal tiles in the live workout screen show em-dash (no data) for
   the entire session.

But on a device where HK was authorized for an *older build* of the same
bundle ID before, b47/b48 still receive HR/kcal samples fine, no prompt
needed (which is expected — auth is sticky per bundle ID + sample type).

### What I've already ruled out

- **Missing usage strings** → both present and correct, see above.
- **Missing `com.apple.developer.healthkit` entitlement in source file** → present (`<true/>`).
- **Profile doesn't grant HealthKit** → CI hard-fail step proves the
  entitlement is in the signed IPA blob, build is green.
- **App didn't actually call requestAuthorization** → it does, from
  `WindowGroup.onAppear` at app launch (and again on session start).
- **Simulator** → user is on real hardware. Simulator HK is not relevant.
- **`HKHealthStore.isHealthDataAvailable()` returning false** → the user
  has an Apple Watch paired and HR/kcal flow on prior-authorized installs,
  so the device is HK-capable.
- **Bundle ID mismatch** → app installs and runs fine; iCloud, BLE, etc.
  all work; only HK prompt is missing.

## Hypotheses I want the council to evaluate

1. **Provisioning profile injects a stale or extra HealthKit-related key**
   that confuses iOS — e.g. an empty `com.apple.developer.healthkit.access`
   array gets added by the profile even though the local entitlements file
   omits it. The CI verify step only `grep -q "com.apple.developer.healthkit"`
   which would match `.healthkit` AND `.healthkit.access` strings. This
   could be hiding a profile-side bug.

2. **App ID record on Apple Developer portal needs a "Configure"
   sub-step for HealthKit** that wasn't done. Just checking the HealthKit
   capability box may not be enough — some capabilities have a follow-on
   Configure pane (e.g. for "Clinical Health Records" access).

3. **The provisioning profile was generated programmatically via the ASC
   REST API before HealthKit was enabled on the App ID**, and even though
   the app ID now has HK, the profile was minted with an older entitlement
   set. Profiles are immutable — they don't auto-update when the App ID
   changes. The current profile may have been generated months ago.

4. **iOS 17.0+ requires an explicit `NSHealthRequiredReadAuthorizationTypeIdentifiers`
   key in Info.plist** to surface the app under Settings → Health, and our
   Info.plist doesn't have it. (I'm not certain this key exists — please
   verify.)

5. **The signed entitlements blob has the entitlement but the embedded
   `.mobileprovision` inside the .app bundle is for a different App ID or
   has been corrupted**, so iOS rejects the HK declaration silently while
   accepting the codesign. Sometimes manifests as "app appears installed
   but capabilities are missing in OS-level UI."

6. **TestFlight builds have a known quirk** where capability registration
   lags the first launch — user needs to launch, force-quit, relaunch
   before iOS surfaces the app under Health settings.

7. **The user's device has stale HK denial cached** for this bundle ID
   from a prior install where they tapped "Don't Allow." Once denied, iOS
   does NOT re-prompt. This would explain prompt-missing AND no row in
   Settings → Health if iOS treats persistent denial as "app uninstalled
   the capability." Resetting via Settings → General → Transfer or Reset
   iPhone → Reset Location & Privacy is the only way to re-trigger.

## What I want from you

I want to ship build 49 with the highest-confidence fix or diagnostic
step. The user is browser-only, so any "open the Apple Developer portal
and click X" instruction must be precise and verifiable from a phone.

## How to respond

Please structure your response exactly like this:

### 1. Most likely root cause

One paragraph. Pick the single most likely cause from my hypotheses, or
propose a different one. Cite Apple documentation URLs where applicable.

### 2. Verification step (do this first)

A short, safe diagnostic the user or I can run RIGHT NOW that confirms or
disconfirms the hypothesis without shipping a new build. Examples: "decode
the .mobileprovision and look for X key"; "run `codesign -d --entitlements
:- VoltraLive.app` on the latest IPA and grep for Y"; "ask the user to
confirm if they ever tapped Don't Allow on a prior install."

### 3. Fix recommendation

Concrete steps for build 49. Prefer code or CI changes over manual portal
steps when possible (we automate everything we can). If a portal step is
unavoidable, give exact navigation: "developer.apple.com → Identifiers →
com.voltralive.app → Capabilities → ..."

### 4. Confidence level

Low / Medium / High, with one-sentence reasoning.

### 5. If you're wrong, the next thing to try

One backup hypothesis with a different test, so I'm not stuck if your
primary recommendation doesn't work.

### 6. Citations

Apple docs links, Stack Overflow threads, or Apple Developer Forum
discussions you're drawing from. URLs only — I'll verify them.

Keep the whole response under ~800 words. No filler. The user is going
to paste your answer back to me verbatim and I'll act on it.
