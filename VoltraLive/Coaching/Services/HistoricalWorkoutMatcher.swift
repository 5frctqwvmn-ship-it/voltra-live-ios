// VoltraLive/Coaching/Services/HistoricalWorkoutMatcher.swift
// RC-01 — looks up prior sessions for the same exercise and returns
// the most recent session's same-index and next-index sets.
// Groups by workoutSessionID (not calendar day) per fix #4.

import Foundation

protocol HistoricalWorkoutMatching {
    func mostRecentMatch(
        for exerciseName: String,
        excluding sessionID: UUID,
        nextSetIndex: Int,
        lastCompletedSetIndex: Int?
    ) -> HistoricalSetMatch
}

struct DefaultHistoricalWorkoutMatcher: HistoricalWorkoutMatching {
    private let allSnapshots: () -> [SetPerformanceSnapshot]

    init(allSnapshots: @escaping () -> [SetPerformanceSnapshot]) {
        self.allSnapshots = allSnapshots
    }

    func mostRecentMatch(
        for exerciseName: String,
        excluding sessionID: UUID,
        nextSetIndex: Int,
        lastCompletedSetIndex: Int?
    ) -> HistoricalSetMatch {
        let target = exerciseName.lowercased()
        let pool = allSnapshots()
            .filter { $0.exerciseName.lowercased() == target }
            .filter { $0.workoutSessionID != sessionID }

        guard let mostRecent = pool.max(by: { $0.workoutDate < $1.workoutDate }) else {
            return HistoricalSetMatch(exerciseName: exerciseName)
        }

        let recentSessionSets = pool
            .filter { $0.workoutSessionID == mostRecent.workoutSessionID }
            .sorted { $0.setIndex < $1.setIndex }

        let sameIndex = lastCompletedSetIndex.flatMap { idx in
            recentSessionSets.first { $0.setIndex == idx }
        }

        let nextIndex = recentSessionSets.first { $0.setIndex == nextSetIndex }

        return HistoricalSetMatch(
            exerciseName: exerciseName,
            previousSessionDate: mostRecent.workoutDate,
            previousSessionID: mostRecent.workoutSessionID,
            previousSameIndexSet: sameIndex,
            previousNextIndexSet: nextIndex,
            allPreviousSets: pool
        )
    }
}
