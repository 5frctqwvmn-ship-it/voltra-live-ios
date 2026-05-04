// VoltraLive/Coaching/Models/SetPerformanceSnapshot.swift
// RC-01 — immutable value type representing one completed set's
// performance data. Built from LoggedSet by SetSnapshotBuilder.
//
// NOTE on per-rep force fields:
//   LoggedSet (SwiftData) currently stores only peakForceLb + avgForceLb.
//   bestRepForceLb / lastRepForceLb are nil until per-rep telemetry lands
//   (planned for Telemetry v2 expansion). When nil, forceDropoffPct
//   returns nil and the fatigue gate resolves to .unknown.
//   SetSnapshotBuilder does NOT synthesize fake values from peakForceLb —
//   keeping these nil is correct and honest.

import Foundation

struct SetPerformanceSnapshot: Codable, Identifiable, Hashable {
    let id: UUID
    let exerciseName: String
    /// 0-based set index within its workout session for this exercise.
    let setIndex: Int
    let workoutSessionID: UUID
    let workoutDate: Date

    let plannedWeightLb: Double
    let actualWeightLb: Double

    let repCount: Int?
    let setDurationSec: Double

    // Force telemetry
    let avgForceLb: Double?
    let peakForceLb: Double?
    /// Nil until per-rep telemetry is available.
    let bestRepForceLb: Double?
    /// Nil until per-rep telemetry is available.
    let lastRepForceLb: Double?

    // Power telemetry (not yet captured by LoggedSet — reserved)
    let avgPowerW: Double?
    let peakPowerW: Double?
    let bestRepPowerW: Double?
    let lastRepPowerW: Double?

    // HealthKit
    let heartRateAvgBpm: Double?
    let heartRateMaxBpm: Double?

    // MARK: - Derived fatigue metrics
    /// Percent force drop-off from best rep to last rep. Nil when
    /// per-rep fields are unavailable.
    var forceDropoffPct: Double? {
        guard let best = bestRepForceLb, let last = lastRepForceLb, best > 0 else { return nil }
        return max(0, min(100, (best - last) / best * 100.0))
    }

    /// Percent power drop-off from best rep to last rep. Nil when
    /// per-rep fields are unavailable.
    var powerDropoffPct: Double? {
        guard let best = bestRepPowerW, let last = lastRepPowerW, best > 0 else { return nil }
        return max(0, min(100, (best - last) / best * 100.0))
    }

    init(
        id: UUID = UUID(),
        exerciseName: String,
        setIndex: Int,
        workoutSessionID: UUID,
        workoutDate: Date,
        plannedWeightLb: Double,
        actualWeightLb: Double,
        repCount: Int? = nil,
        setDurationSec: Double = 0,
        avgForceLb: Double? = nil,
        peakForceLb: Double? = nil,
        bestRepForceLb: Double? = nil,
        lastRepForceLb: Double? = nil,
        avgPowerW: Double? = nil,
        peakPowerW: Double? = nil,
        bestRepPowerW: Double? = nil,
        lastRepPowerW: Double? = nil,
        heartRateAvgBpm: Double? = nil,
        heartRateMaxBpm: Double? = nil
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.setIndex = setIndex
        self.workoutSessionID = workoutSessionID
        self.workoutDate = workoutDate
        self.plannedWeightLb = plannedWeightLb
        self.actualWeightLb = actualWeightLb
        self.repCount = repCount
        self.setDurationSec = setDurationSec
        self.avgForceLb = avgForceLb
        self.peakForceLb = peakForceLb
        self.bestRepForceLb = bestRepForceLb
        self.lastRepForceLb = lastRepForceLb
        self.avgPowerW = avgPowerW
        self.peakPowerW = peakPowerW
        self.bestRepPowerW = bestRepPowerW
        self.lastRepPowerW = lastRepPowerW
        self.heartRateAvgBpm = heartRateAvgBpm
        self.heartRateMaxBpm = heartRateMaxBpm
    }
}
