// VoltraLive/Coaching/Models/ExerciseSessionCursor.swift
// RC-01 — cursor describing where the user is right now within
// today's exercise session.

import Foundation

struct ExerciseSessionCursor: Equatable {
    let exerciseName: String
    let currentWorkoutSessionID: UUID
    /// All sets completed today for this exercise, in order.
    let completedSetsToday: [SetPerformanceSnapshot]

    /// 0-based index of the last completed set. -1 if none completed yet.
    var lastCompletedSetIndex: Int { completedSetsToday.last?.setIndex ?? -1 }
    /// 0-based index of the NEXT set to be performed.
    var nextSetIndex: Int { lastCompletedSetIndex + 1 }
    var lastCompletedSet: SetPerformanceSnapshot? { completedSetsToday.last }
}
