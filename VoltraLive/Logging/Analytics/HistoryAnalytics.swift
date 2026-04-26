// HistoryAnalytics.swift
// Pure functions over the v0.2 SwiftData logging schema. No side effects;
// callers fetch arrays once and pass them in. This keeps the engine testable
// and lets us reuse the same logic across the picker, the start screen, and
// future analytics views.
//
// Two main jobs in v0.2.1:
//  1. exercisesOrderedBySequence(...) — given a day type, list the exercises
//     the user actually performs on that day, ordered by how often they appear
//     FIRST / SECOND / THIRD in the session, weighted by recency. Falls back
//     to lastUsedAt for ties or sparse history.
//  2. previousSetSeries(...) — given an Exercise, return the sequence of
//     LoggedSet from the most recent prior session (excluding the active one).
//     This is what powers the smart-start toggle.

import Foundation

enum HistoryAnalytics {

    // MARK: - Sequence-based exercise ordering

    /// Score per exercise. Lower score = appears earlier in the user's typical
    /// sequence for this day type, weighted by how recently they did it.
    /// Returns the input exercises sorted ascending by score.
    ///
    /// Algorithm:
    ///   For each prior session matching this day type, look at its
    ///   ExerciseInstances ordered by orderIndex. Each occurrence contributes
    ///   `orderIndex × recencyWeight(session)` to that exercise's score. We
    ///   then average over total weight so an exercise done once at slot 1
    ///   beats an exercise done once at slot 5.
    ///
    /// Recency weight: half-life of ~30 days. Sessions older than ~6 months
    /// have negligible influence so a long-ago habit doesn't pin an exercise.
    static func exercisesOrderedBySequence(
        candidates: [Exercise],
        sessions: [WorkoutSession],
        dayType: DayType,
        now: Date = Date()
    ) -> [Exercise] {
        guard !candidates.isEmpty else { return [] }

        // Filter to sessions with completed instances on this day type.
        let relevant: [WorkoutSession] = sessions.filter { s in
            guard s.endedAt != nil || s.importedFromHistory else { return false }
            if dayType == .custom { return true }
            return s.dayType == dayType
        }

        // exerciseID -> (weighted slot sum, weight sum)
        var scoreNum: [UUID: Double] = [:]
        var scoreDen: [UUID: Double] = [:]
        // Tie-break: most recent appearance per exercise
        var lastSeen: [UUID: Date] = [:]

        for session in relevant {
            let w = recencyWeight(for: session.startedAt, now: now)
            let ordered = (session.instances ?? []).sorted { $0.orderIndex < $1.orderIndex }
            for inst in ordered {
                guard let ex = inst.exercise else { continue }
                // 1-indexed slot. Defensive default if orderIndex is 0/missing.
                let slot = max(inst.orderIndex, 1)
                scoreNum[ex.id, default: 0] += Double(slot) * w
                scoreDen[ex.id, default: 0] += w
                if (lastSeen[ex.id] ?? .distantPast) < session.startedAt {
                    lastSeen[ex.id] = session.startedAt
                }
            }
        }

        return candidates.sorted { a, b in
            let sa = avgScore(num: scoreNum[a.id], den: scoreDen[a.id])
            let sb = avgScore(num: scoreNum[b.id], den: scoreDen[b.id])
            if sa != sb { return sa < sb }
            // Tie-break by recency, then by name for stability.
            let ra = lastSeen[a.id] ?? a.lastUsedAt ?? .distantPast
            let rb = lastSeen[b.id] ?? b.lastUsedAt ?? .distantPast
            if ra != rb { return ra > rb }
            return a.name < b.name
        }
    }

    private static func avgScore(num: Double?, den: Double?) -> Double {
        guard let n = num, let d = den, d > 0 else { return .infinity }
        return n / d
    }

    /// Half-life ~30 days. Anything in the future returns 1.0.
    private static func recencyWeight(for date: Date, now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(date) / 86_400)
        // exp(-ln(2) * days / 30) so 30 days -> 0.5, 60 days -> 0.25
        return exp(-0.0231 * days)
    }

    // MARK: - Previous-set series

    /// All LoggedSets from the most recent prior session that included this
    /// exercise, in order. Excludes any active (un-ended) session and the
    /// session passed in as `excluding`. If no prior session is found,
    /// returns []. Imported-from-history sessions are included so the user's
    /// starting baseline comes from their master log.
    static func previousSetSeries(
        for exercise: Exercise,
        excluding activeSession: WorkoutSession?,
        now: Date = Date()
    ) -> [LoggedSet] {
        let instances = (exercise.instances ?? []).filter { inst in
            guard let session = inst.session else { return false }
            if let active = activeSession, session.id == active.id { return false }
            // A finished real session OR an imported one.
            return session.endedAt != nil || session.importedFromHistory
        }

        // Find the most-recent qualifying instance by its session start.
        let sortedInstances = instances.sorted { a, b in
            (a.session?.startedAt ?? .distantPast) > (b.session?.startedAt ?? .distantPast)
        }
        guard let latest = sortedInstances.first else { return [] }
        return (latest.sets ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Weight from a specific 1-indexed set in the previous series, or nil if
    /// the prior series was shorter.
    static func previousWeight(
        atSetIndex idx: Int,
        in series: [LoggedSet]
    ) -> Double? {
        guard idx >= 1, idx <= series.count else { return nil }
        let s = series[idx - 1]
        return s.weightLb > 0 ? s.weightLb : nil
    }

    /// Delta in lbs between previous-session set N and previous-session set N-1.
    /// Used to predict "what jump did the user typically take into this set".
    static func previousDelta(
        toSetIndex idx: Int,
        in series: [LoggedSet]
    ) -> Double? {
        guard idx >= 2, idx <= series.count else { return nil }
        let prev = series[idx - 2].weightLb
        let curr = series[idx - 1].weightLb
        guard prev > 0, curr > 0 else { return nil }
        return curr - prev
    }
}
