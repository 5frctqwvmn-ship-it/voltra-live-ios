// VoltraLive/Coaching/Models/HistoricalSetMatch.swift
// RC-01 — result of a historical lookup for a given exercise.

import Foundation

struct HistoricalSetMatch: Equatable {
    let exerciseName: String
    let previousSessionDate: Date?
    let previousSessionID: UUID?
    /// The set at the SAME index as the last completed set today,
    /// from the most recent prior session. Used for delta calculation.
    let previousSameIndexSet: SetPerformanceSnapshot?
    /// The set at the NEXT index (the one about to be performed),
    /// from the most recent prior session. Used as the anchor weight.
    let previousNextIndexSet: SetPerformanceSnapshot?
    /// All prior sets for this exercise across all sessions (excluding today).
    let allPreviousSets: [SetPerformanceSnapshot]

    /// Highest actual weight ever completed for this exercise.
    var historicalMaxWeight: Double? {
        allPreviousSets.map(\.actualWeightLb).max()
    }

    init(
        exerciseName: String,
        previousSessionDate: Date? = nil,
        previousSessionID: UUID? = nil,
        previousSameIndexSet: SetPerformanceSnapshot? = nil,
        previousNextIndexSet: SetPerformanceSnapshot? = nil,
        allPreviousSets: [SetPerformanceSnapshot] = []
    ) {
        self.exerciseName = exerciseName
        self.previousSessionDate = previousSessionDate
        self.previousSessionID = previousSessionID
        self.previousSameIndexSet = previousSameIndexSet
        self.previousNextIndexSet = previousNextIndexSet
        self.allPreviousSets = allPreviousSets
    }
}
