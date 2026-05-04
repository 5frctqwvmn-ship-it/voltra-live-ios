// LoggingStore.swift
// Owns the v0.2 active-session state machine on top of SessionStore (v0.1).
//
// Responsibilities:
//   1. Track the user-facing flow: pickedDayType → pickedExercise → activeInstance.
//   2. Observe SessionStore.completedSets and surface the most recent
//      auto-detected set to the SetLogView for confirmation.
//   3. Persist confirmed sets into SwiftData via the v0.2 logging schema.
//   4. Provide picker data: exercises sorted by recency for a given day type.
//   5. Generate markdown export for "End Session".
//
// It does NOT touch SessionStore's internals — only reads completedSets and
// calls clearAll/endSession when the user explicitly resets.

import Foundation
import SwiftData
import Combine

@MainActor
final class LoggingStore: ObservableObject {

    // MARK: - Published state

    @Published var activeSession: WorkoutSession? = nil
    @Published var activeInstance: ExerciseInstance? = nil
    /// The most recent completed set detected by SessionStore that hasn't
    /// been logged yet. Cleared on log() or skip().
    @Published var pendingTelemetrySet: CompletedSet? = nil
    /// Mirror of the running set count for the current instance — drives the
    /// "Set #" label in the UI.
    @Published var setNumberForCurrentInstance: Int = 1
    /// User-chosen starting weight from the smart-start toggle (or free entry)
    /// for the upcoming set. Read by SetLogView at prefill time and cleared
    /// after each set is logged.
    @Published var pendingPlannedWeightLb: Double? = nil

    // MARK: - v0.4.0: Upcoming-set context (drives auto-log on telemetry)
    //
    // These fields hold the user's CURRENTLY-CONFIGURED next-set plan, set
    // from ExerciseDetailView and live-edited inline on LiveCaptureView via
    // ±1/±5 nudges. When SessionStore reports a telemetry-detected set
    // boundary, autoLogTelemetrySet() snapshots these into a new LoggedSet
    // (with telemetry reps + peak force overlaid) and clears them only as
    // appropriate (added load PERSISTS across sets in the same instance;
    // weight/ecc/mode are reused too so the user sees a hot prefill until
    // they nudge it).
    @Published var upcomingMode: SetMode = .working
    @Published var upcomingEccLb: Double = 0
    @Published var upcomingTargetReps: Int = 0
    /// b51: Eccentric motor toggle. When false, eccentric is disabled at
    /// the device but `upcomingEccLb` is preserved so re-enabling restores
    /// the prior value. Tap the eccentric icon in the resistance tile to
    /// toggle. Default ON (legacy behavior).
    @Published var upcomingEccEnabled: Bool = true
    /// b51: Chains weight in lb (digital chains-mode overload, simulating
    /// chain links lifting off the floor). Persists across sets in the
    /// active instance like ecc.
    @Published var upcomingChainsLb: Double = 0
    /// b51: Chains motor toggle. Same semantics as `upcomingEccEnabled`.
    @Published var upcomingChainsEnabled: Bool = true
    /// b56: Inverse-chain weight in lb (digital reverse chain — chains hang
    /// at top, lighten through the ROM). M