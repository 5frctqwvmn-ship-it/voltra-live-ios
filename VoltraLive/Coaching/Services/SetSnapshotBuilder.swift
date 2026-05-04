// VoltraLive/Coaching/Services/SetSnapshotBuilder.swift
// RC-01 — adapts SwiftData LoggedSet + ExerciseInstance into
// SetPerformanceSnapshot values for the coaching engine.
//
// Compatibility notes:
//   - LoggedSet has peakForceLb and avgForceLb only.
//   - bestRepForceLb / lastRepForceLb / power fields are nil until
//     per-rep telemetry lands. FatigueGate will be .unknown for all
//     sets produced by this builder. This is intentional and correct.
//   - setIndex is 0-based: LoggedSet.orderIndex is 1-based, so
//     builder subtracts 1.

import Foundation

enum SetSnapshotBuilder {
    /// Build a snapshot from a LoggedSet.
    /// Returns nil if the set's instance or session cannot be resolved.
    static func build(
        from loggedSet: LoggedSet
    ) -> SetPerformanceSnapshot? {
        guard
            let instance = loggedSet.instance,
            let exercise = instance.exercise,
            let session  = instance.session
        else { return nil }

        let exerciseName = exercise.name
        let sessionID    = session.id
        let sessionDate  = session.startedAt

        // orderIndex is 1-based in the model; convert to 0-based.
        let setIndex = max(0, loggedSet.orderIndex - 1)

        let duration: Double = {
            if let start = loggedSet.startedAt, let end = loggedSet.endedAt {
                return end.timeIntervalSince(start)
            }
            return 0
        }()

        return SetPerformanceSnapshot(
            id: loggedSet.id,
            exerciseName: exerciseName,
            setIndex: setIndex,
            workoutSessionID: sessionID,
            workoutDate: sessionDate,
            plannedWeightLb: loggedSet.weightLb,   // best proxy for planned
            actualWeightLb: loggedSet.weightLb,
            repCount: loggedSet.reps > 0 ? loggedSet.reps : nil,
            setDurationSec: duration,
            avgForceLb: loggedSet.avgForceLb,
            peakForceLb: loggedSet.peakForceLb > 0 ? loggedSet.peakForceLb : nil,
            // Per-rep force not yet captured in LoggedSet. Nil is correct.
            bestRepForceLb: nil,
            lastRepForceLb: nil,
            // Power not yet captured. Nil is correct.
            avgPowerW: nil,
            peakPowerW: nil,
            bestRepPowerW: nil,
            lastRepPowerW: nil,
            // HealthKit HR at set level not yet stored in LoggedSet.
            heartRateAvgBpm: nil,
            heartRateMaxBpm: nil
        )
    }

    /// Build snapshots for all sets in an ExerciseInstance,
    /// sorted by orderIndex ascending.
    static func buildAll(
        from instance: ExerciseInstance
    ) -> [SetPerformanceSnapshot] {
        (instance.sets ?? [])
            .sorted { $0.orderIndex < $1.orderIndex }
            .compactMap { build(from: $0) }
    }

    /// Build snapshots for all LoggedSets across multiple ExerciseInstances
    /// for a given exercise name. Used by HistoricalWorkoutMatcher.
    static func buildAll(
        exerciseName: String,
        from allInstances: [ExerciseInstance]
    ) -> [SetPerformanceSnapshot] {
        allInstances
            .filter { $0.exercise?.name.lowercased() == exerciseName.lowercased() }
            .flatMap { buildAll(from: $0) }
    }
}
