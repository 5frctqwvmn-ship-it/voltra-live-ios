# 06 — HealthKit

## Status (b49)

**Working.** First-launch authorization prompt now appears, VOLTRA Live
shows up under iOS Settings → Health → Data Access & Devices, and HR /
active-energy reads stream during workouts.

## What was broken before b49

Through b48, the auth prompt never appeared on a fresh install. The IPA
contained the right entitlement (CI verified
`com.apple.developer.healthkit` in the embedded provisioning profile),
the Info.plist had the two required usage strings, and the app called
`HKHealthStore.requestAuthorization` from
`VoltraLiveApp.onAppear` — yet iOS silently ignored every request, no
prompt, no error, no row in Settings.

## Root cause

iOS 17+ tightened HealthKit entitlement parsing. The signed provisioning
profile shipped **all three** HealthKit entitlement keys
(`com.apple.developer.healthkit`,
`com.apple.developer.healthkit.access`,
`com.apple.developer.healthkit.background-delivery`), but the app's
`VoltraLive.entitlements` file declared only the first.

When the embedded profile and the app entitlements don't agree on the
HealthKit key set, iOS marks the HealthKit registration as malformed
and drops it on the floor — with no diagnostic surfaced to the app or
the user. The framework call returns success, but no prompt is shown
and no entry is written under Settings.

## Fix (b49)

`VoltraLive/VoltraLive.entitlements` now declares all three keys to
match the profile:

```xml
<key>com.apple.developer.healthkit</key>
<true/>
<key>com.apple.developer.healthkit.access</key>
<array/>
<key>com.apple.developer.healthkit.background-delivery</key>
<true/>
```

`.access` is intentionally an empty array — we don't request any of the
three "clinical-records" specializations. `.background-delivery` is set
to `true` because we observe HR via `HKObserverQuery` while the screen
may be off; without this key the OS may suspend the observer.

## CI guard

The release workflow's "verify-entitlements" step now uses `plistlib` to
parse the embedded entitlements (instead of regex on raw XML) and
asserts exact-key presence:

- `com.apple.developer.healthkit == true`
- `com.apple.developer.healthkit.access == []`
- `com.apple.developer.healthkit.background-delivery == true`

If any of those drift in a future build, the dry-run/release fails
before signing — preventing a regression where the entitlements file
silently disagrees with the profile again.

## Code paths

- `VoltraLiveApp.swift` — `requestAuthorizationOnce()` called from
  `WindowGroup.onAppear`; gated by `UserDefaults` so we don't spam the
  user across launches.
- `Health/HealthKitClient.swift` — `HKObserverQuery` for HR,
  `HKAnchoredObjectQuery` for active energy. Both attached on session
  start, detached on session end.
- Display surfaces: live HR + kcal pills in `LiveCaptureView` header.

## What we don't write to HealthKit

We are read-only for now. Writing a `HKWorkout` on session end is on
the roadmap (see `03_ROADMAP.md`); when that lands, add
`com.apple.developer.healthkit.access` entries for `HKWorkoutType` and
the share-permission usage string to Info.plist.

## Smoke test (after each release)

1. Fresh install on a device that has never seen this build.
2. First launch → expect HealthKit prompt before the home screen appears.
3. Approve → open Settings → Health → Data Access & Devices → confirm
   "VOLTRA Live" row exists.
4. Start any workout → confirm HR pill updates within ~5 s of putting
   the device on a wrist that's reporting HR.
5. End session → kcal pill non-zero (Active Energy summed for the
   session window).
