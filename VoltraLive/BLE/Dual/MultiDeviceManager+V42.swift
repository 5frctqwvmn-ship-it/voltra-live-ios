// b66 V4.2: per-exercise assignment override + pair-scan request.
//
// Sacred-files note: this is an EXTENSION on `MultiDeviceManager`. The
// canonical class file (`MultiDeviceManager.swift`) is NOT modified — the
// session rule is reskin-not-rewrite, and adding new published state
// directly on the canonical class is a behavior change. Here we add ONLY:
//
//   1. A per-exercise override dict (`exerciseAssignmentOverride`) used by
//      the V4.2 ASSIGN TO VOLTRA panel when it is mounted on the EXERCISE
//      screen (mirror rule 1A locked via MC: day screen sets the default
//      `mdm.workoutMode`; exercise screen overrides per-exercise).
//
//   2. A `requestPairScan(for:)` API used by the panel when the user taps
//      a greyed-out L or R pill — the panel kicks the discovery scanner
//      to surface a pair sheet for the requested slot. The actual scanner
//      wiring is done in the host that owns the discovery scanner; this
//      extension exposes a Combine `PassthroughSubject` so any host can
//      subscribe without dragging the scanner into the MDM API.
//
// Storage trick: Swift extensions cannot add stored properties. We use a
// static dict keyed by `ObjectIdentifier(self)` to side-store the dict.
// This is fine because:
//   • The app has one MDM instance per session.
//   • The dict is cleared explicitly via `clearExerciseOverrides()` at
//     workout-end, so the side store never grows unbounded.
//   • We do NOT participate in `@Published` here — the override dict is
//     read on demand by the panel's `currentMode(exerciseName:mdm:)`
//     helper, which combines it with `mdm.workoutMode` (which IS
//     @Published) at SwiftUI render time. So changing the override
//     triggers a recompute through the helper's normal Equatable check.
//
// IF this side-store approach ever proves insufficient (e.g. SwiftUI
// fails to recompute when the override changes because there is no
// upstream `@Published`), the next agent should fold the dict into the
// canonical MDM as a real `@Published var` — at that point it has been
// validated as a real V4.2 product feature, not a head-to-head
// experiment, and the reskin-not-rewrite rule no longer applies.

import Foundation
import Combine

// b66 hotfix: under Xcode 26 / Swift 6 strict concurrency, members on an
// extension of a `@MainActor` class are NOT automatically main-actor-isolated.
// The computed property below touches `self.workoutMode` (which IS @MainActor
// on `MultiDeviceManager`), so we must explicitly annotate the extension
// members. Marking the whole extension `@MainActor` is the cleanest path:
// every member touches main-actor state, and SwiftUI views that read these
// helpers are themselves main-actor-bound at body-eval time.
@MainActor
extension MultiDeviceManager {
    // MARK: - Per-exercise assignment override (mirror rule 1A)

    /// Side-store for the per-exercise override dict. Keyed by
    /// `ObjectIdentifier(mdm)` so multiple MDM instances (e.g. preview)
    /// stay isolated. Main-actor-isolated like the rest of MDM state
    /// so the get/set path stays on a single concurrency domain.
    private static var _exerciseOverrideStore: [ObjectIdentifier: [String: WorkoutMode]] = [:]

    /// b66: read/write per-exercise mode override. Empty/nil means
    /// "fall back to `workoutMode`". Keyed by exercise NAME (the same
    /// string the logging engine writes into `LoggedSet.exerciseName`)
    /// so the override survives ExerciseDetail re-renders.
    var exerciseAssignmentOverride: [String: WorkoutMode] {
        get {
            Self._exerciseOverrideStore[ObjectIdentifier(self)] ?? [:]
        }
        set {
            Self._exerciseOverrideStore[ObjectIdentifier(self)] = newValue
            // Nudge the existing @Published `workoutMode` so SwiftUI views
            // observing the MDM recompute. Setting it to its current value
            // is safe — `WorkoutMode` is Equatable, so SwiftUI will only
            // rerun bodies that actually depend on the override (via the
            // currentMode helper). This is a deliberate nudge, not a state
            // change.
            let m = self.workoutMode
            self.workoutMode = m
        }
    }

    /// Clear all per-exercise overrides. Called by the host at workout
    /// end so a stale override from one workout does not leak into the
    /// next.
    func clearExerciseOverrides() {
        Self._exerciseOverrideStore[ObjectIdentifier(self)] = nil
    }

    // MARK: - Pair-scan request (greyed pill tap)

    /// b66: subscribe to be notified when the V4.2 panel wants to surface
    /// a pair-scan sheet for a specific slot. Hosts that own the discovery
    /// scanner subscribe in `.onAppear` and present their pair sheet in
    /// response. Stub-style: this extension does NOT itself trigger the
    /// scan because the scanner lives outside the MDM.
    nonisolated static let scanRequestedSubject = PassthroughSubject<DeviceSlot, Never>()

    /// b66: panel calls this when the user taps a greyed L or R pill.
    /// Emits a request-event on `scanRequestedSubject`; the host that
    /// owns the discovery scanner should be subscribed and surface a
    /// pair sheet for the requested slot.
    func requestPairScan(for slot: DeviceSlot) {
        Self.scanRequestedSubject.send(slot)
    }
}
