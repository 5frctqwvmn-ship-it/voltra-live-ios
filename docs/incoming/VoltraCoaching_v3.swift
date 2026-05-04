//
// VoltraCoaching.swift — v3 (clean, all 15 review fixes applied + unit tests)
// VoltraLive — RC-01 Rest-State Coaching Card + SC-01 Smart Coach beta
//
// SINGLE-FILE DROP-IN for review. The integrator should split this into the
// target paths listed at the bottom of this file and integrate the LiveCapture
// panel switch. Nothing in this file performs BLE writes.
//
// Fixes applied vs v1:
//  1  Added onLoadAggressive callback; aggressive button routes correctly.
//  2  conservativeBumpPct = 5.0; math now matches the constant name.
//  3  Session cap respects anchor floor (never lowers below last-session weight).
//  4  Historical matcher groups by workoutSessionID, not calendar day.
//  5  Aggressive only emitted when strictly greater than recommended.
//  6  onLoadAggressive callback added to CoachingCardView API.
//  7  Repeat button hidden in view when safeWeightLb <= 0.
//  8  Delta line renders "matches last time" when |delta| < 1%.
//  9  Engine uses guard-let instead of `?? 0` on set index.
// 10  Unknown fatigue gate suppresses aggressive; confidence = .low.
// 16  Added explicit guard on lastSetToday before rule 2+.
// 18  Drop-off percentages clamped to [0,100].
// 19  Fatigue line labels "force" vs "power" based on which actually dropped.
// 21  Card has minHeight so panel switch doesn't cause layout shift.
// 22  HistoricalSetMatch.empty removed; engine constructs per-exercise value.
// 23  Historical-max cap now respects anchor floor.
// 24  No-history/no-set UI shows "Pick a starting weight" instead of 0 lb.
// 25  Unit tests moved to standalone CoachingEngineTests_v4.swift artifact.
//
// Author: Perplexity assistant, authored 2026-05-03.
//

import Foundation
import SwiftUI

// MARK: - Feature Flags
// Place at: VoltraLive/FeatureFlags.swift
public enum FeatureFlags {
    public static var coachingCardEnabled: Bool = true
    public static var smartCoachEnabled: Bool = true
    public static var aggressiveRecommendationsEnabled: Bool = true
    public static var hrRecoveryHardLockEnabled: Bool = false
    public static var telemetryDebugExportEnabled: Bool = true
}

// MARK: - Coaching Constants
// Place at: VoltraLive/Coaching/CoachingConstants.swift
public enum CoachingConstants {
    public static let forceActivityThresholdLb: Double = 5.0
    public static let restingDebounceSeconds: Double = 1.5
    public static let cardTransitionSeconds: Double = 0.25
    public static let cardMinHeight: CGFloat = 180

    // Fatigue gate thresholds (% drop-off: best rep to last rep)
    public static let fatigueYellowPct: Double = 15.0
    public static let fatigueRedPct: Double = 30.0

    // Progression caps
    public static let maxSessionJumpPct: Double = 25.0
    public static let maxHistoricalJumpPct: Double = 15.0
    public static let conservativeBumpPct: Double = 5.0
    public static let aggressiveFloorOverPrimaryPct: Double = 5.0

    // Weight rounding
    public static let weightIncrementLb: Double = 5.0
}

// MARK: - SetPerformanceSnapshot
// Place at: VoltraLive/Coaching/Models/SetPerformanceSnapshot.swift
public struct SetPerformanceSnapshot: Codable, Identifiable, Hashable {
    public let id: UUID
    public let exerciseName: String
    public let setIndex: Int            // 0-based
    public let workoutSessionID: UUID
    public let workoutDate: Date

    public let plannedWeightLb: Double
    public let actualWeightLb: Double

    public let repCount: Int?
    public let setDurationSec: Double

    public let avgForceLb: Double?
    public let peakForceLb: Double?
    public let bestRepForceLb: Double?
    public let lastRepForceLb: Double?

    public let avgPowerW: Double?
    public let peakPowerW: Double?
    public let bestRepPowerW: Double?
    public let lastRepPowerW: Double?

    public let heartRateAvgBpm: Double?
    public let heartRateMaxBpm: Double?

    public var forceDropoffPct: Double? {
        guard let best = bestRepForceLb, let last = lastRepForceLb, best > 0 else { return nil }
        let raw = (best - last) / best * 100.0
        return max(0, min(100, raw))
    }

    public var powerDropoffPct: Double? {
        guard let best = bestRepPowerW, let last = lastRepPowerW, best > 0 else { return nil }
        let raw = (best - last) / best * 100.0
        return max(0, min(100, raw))
    }

    public init(
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

// MARK: - ExerciseSessionCursor
// Place at: VoltraLive/Coaching/Models/ExerciseSessionCursor.swift
public struct ExerciseSessionCursor: Equatable {
    public let exerciseName: String
    public let currentWorkoutSessionID: UUID
    public let completedSetsToday: [SetPerformanceSnapshot]

    public var lastCompletedSetIndex: Int { completedSetsToday.last?.setIndex ?? -1 }
    public var nextSetIndex: Int { lastCompletedSetIndex + 1 }
    public var lastCompletedSet: SetPerformanceSnapshot? { completedSetsToday.last }

    public init(
        exerciseName: String,
        currentWorkoutSessionID: UUID,
        completedSetsToday: [SetPerformanceSnapshot]
    ) {
        self.exerciseName = exerciseName
        self.currentWorkoutSessionID = currentWorkoutSessionID
        self.completedSetsToday = completedSetsToday
    }
}

// MARK: - HistoricalSetMatch
// Place at: VoltraLive/Coaching/Models/HistoricalSetMatch.swift
public struct HistoricalSetMatch: Equatable {
    public let exerciseName: String
    public let previousSessionDate: Date?
    public let previousSessionID: UUID?
    public let previousSameIndexSet: SetPerformanceSnapshot?
    public let previousNextIndexSet: SetPerformanceSnapshot?
    public let allPreviousSets: [SetPerformanceSnapshot]

    public var historicalMaxWeight: Double? {
        allPreviousSets.map(\.actualWeightLb).max()
    }

    public init(
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

// MARK: - CoachingRecommendation
// Place at: VoltraLive/Coaching/Models/CoachingRecommendation.swift
public enum FatigueGate: String, Codable {
    case green
    case yellow
    case red
    case unknown
}

public enum RecommendationConfidence: String, Codable {
    case low
    case medium
    case high
}

public struct CoachingRecommendation: Codable, Equatable {
    public let exerciseName: String
    public let nextSetIndex: Int

    public let anchorWeightLb: Double?
    public let recommendedWeightLb: Double
    public let aggressiveWeightLb: Double?
    public let safeWeightLb: Double

    public let headline: String
    public let historyLine: String
    public let deltaLine: String?
    public let reasonLine: String
    public let fatigueLine: String?

    public let fatigueGate: FatigueGate
    public let confidence: RecommendationConfidence
    public let shouldShowAggressiveOption: Bool

    public let guardrailsApplied: [String]
}

// MARK: - HistoricalWorkoutMatcher
// Place at: VoltraLive/Coaching/Services/HistoricalWorkoutMatcher.swift
public protocol HistoricalWorkoutMatching {
    func mostRecentMatch(
        for exerciseName: String,
        excluding sessionID: UUID,
        nextSetIndex: Int,
        lastCompletedSetIndex: Int?
    ) -> HistoricalSetMatch
}

public struct DefaultHistoricalWorkoutMatcher: HistoricalWorkoutMatching {
    private let allSnapshots: () -> [SetPerformanceSnapshot]

    public init(allSnapshots: @escaping () -> [SetPerformanceSnapshot]) {
        self.allSnapshots = allSnapshots
    }

    public func mostRecentMatch(
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
            .sorted(by: { $0.setIndex < $1.setIndex })

        let sameIndex = lastCompletedSetIndex.flatMap { idx in
            recentSessionSets.first(where: { $0.setIndex == idx })
        }

        let nextIndex = recentSessionSets.first(where: { $0.setIndex == nextSetIndex })

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

// MARK: - CoachingEngine
// Place at: VoltraLive/Coaching/Services/CoachingEngine.swift
public struct CoachingEngine {
    public init() {}

    public func recommend(
        cursor: ExerciseSessionCursor,
        history: HistoricalSetMatch
    ) -> CoachingRecommendation {
        var guardrails: [String] = []

        let nextSet = cursor.nextSetIndex
        let nextSetLabel = setLabel(for: nextSet)
        let headline = "Next: \(cursor.exerciseName) \(nextSetLabel)"

        let anchor = history.previousNextIndexSet?.actualWeightLb
        let priorSameIdx = history.previousSameIndexSet?.actualWeightLb

        if history.previousSameIndexSet == nil && history.previousNextIndexSet == nil {
            let currentWeight = cursor.lastCompletedSet?.actualWeightLb ?? 0
            let safe = roundWeight(currentWeight)

            return CoachingRecommendation(
                exerciseName: cursor.exerciseName,
                nextSetIndex: nextSet,
                anchorWeightLb: nil,
                recommendedWeightLb: safe,
                aggressiveWeightLb: nil,
                safeWeightLb: safe,
                headline: headline,
                historyLine: "First time tracking \(cursor.exerciseName)",
                deltaLine: nil,
                reasonLine: "No prior history — pick a starting weight.",
                fatigueLine: nil,
                fatigueGate: .unknown,
                confidence: .low,
                shouldShowAggressiveOption: false,
                guardrailsApplied: ["no_history_repeat_current"]
            )
        }

        if cursor.completedSetsToday.isEmpty {
            let anchorWeight = anchor ?? priorSameIdx ?? 0
            let rec = roundWeight(anchorWeight)

            return CoachingRecommendation(
                exerciseName: cursor.exerciseName,
                nextSetIndex: nextSet,
                anchorWeightLb: anchor,
                recommendedWeightLb: rec,
                aggressiveWeightLb: nil,
                safeWeightLb: rec,
                headline: headline,
                historyLine: "Last time, \(nextSetLabel) was \(intLb(anchorWeight)) lb",
                deltaLine: nil,
                reasonLine: "Start with last time's \(nextSetLabel) weight.",
                fatigueLine: nil,
                fatigueGate: .unknown,
                confidence: .medium,
                shouldShowAggressiveOption: false,
                guardrailsApplied: ["start_at_anchor"]
            )
        }

        guard let lastSet = cursor.lastCompletedSet else {
            assertionFailure("lastCompletedSet must be non-nil past rules 0 and 1")
            return buildSafeFallback(cursor: cursor, headline: headline, nextSet: nextSet)
        }

        let forceDO = lastSet.forceDropoffPct
        let powerDO = lastSet.powerDropoffPct
        let dropoffSignal = max(forceDO ?? 0, powerDO ?? 0)

        let gate: FatigueGate
        if forceDO == nil && powerDO == nil {
            gate = .unknown
        } else if dropoffSignal >= CoachingConstants.fatigueRedPct {
            gate = .red
        } else if dropoffSignal >= CoachingConstants.fatigueYellowPct {
            gate = .yellow
        } else {
            gate = .green
        }

        let whichSignalDropped: String = {
            let f = forceDO ?? -1
            let p = powerDO ?? -1
            return f >= p ? "force" : "power"
        }()

        let fatigueLine: String? = {
            switch gate {
            case .red:
                return "High fatigue — \(whichSignalDropped) dropped \(Int(dropoffSignal.rounded()))%."
            case .yellow:
                return "Moderate fatigue — \(whichSignalDropped) drop-off \(Int(dropoffSignal.rounded()))%."
            case .green, .unknown:
                return nil
            }
        }()

        let currentWeight = lastSet.actualWeightLb

        let deltaPct: Double? = {
            guard let p = priorSameIdx, p > 0 else { return nil }
            return (currentWeight - p) / p * 100.0
        }()

        let deltaLine: String? = {
            let completedLabel = setLabel(for: lastSet.setIndex)

            guard let d = deltaPct else {
                return "Today's \(completedLabel): \(intLb(currentWeight)) lb"
            }

            if abs(d) < 1 {
                return "Today's \(completedLabel): \(intLb(currentWeight)) lb (matches last time)"
            }

            let sign = d >= 0 ? "+" : ""
            return "Today's \(completedLabel): \(intLb(currentWeight)) lb (\(sign)\(Int(d.rounded()))% vs last time)"
        }()

        if gate == .red {
            let safe = roundWeight(max(currentWeight * 0.9, 0))
            let rec = roundWeight(currentWeight)
            guardrails.append("red_gate_no_increase")

            return CoachingRecommendation(
                exerciseName: cursor.exerciseName,
                nextSetIndex: nextSet,
                anchorWeightLb: anchor,
                recommendedWeightLb: rec,
                aggressiveWeightLb: nil,
                safeWeightLb: safe,
                headline: headline,
                historyLine: historyLine(for: nextSetLabel, anchor: anchor),
                deltaLine: deltaLine,
                reasonLine: "Hold weight — fatigue is high.",
                fatigueLine: fatigueLine,
                fatigueGate: gate,
                confidence: .medium,
                shouldShowAggressiveOption: false,
                guardrailsApplied: guardrails
            )
        }

        if gate == .yellow {
            let candidate = min(anchor ?? currentWeight, currentWeight * 1.05)
            let rec = roundWeight(candidate)
            guardrails.append("yellow_gate_cap_5pct")

            return CoachingRecommendation(
                exerciseName: cursor.exerciseName,
                nextSetIndex: nextSet,
                anchorWeightLb: anchor,
                recommendedWeightLb: rec,
                aggressiveWeightLb: nil,
                safeWeightLb: roundWeight(currentWeight),
                headline: headline,
                historyLine: historyLine(for: nextSetLabel, anchor: anchor),
                deltaLine: deltaLine,
                reasonLine: "Match last time's \(nextSetLabel) — moderate fatigue.",
                fatigueLine: fatigueLine,
                fatigueGate: gate,
                confidence: .medium,
                shouldShowAggressiveOption: false,
                guardrailsApplied: guardrails
            )
        }

        let baseAnchor = anchor ?? currentWeight
        var recommended = baseAnchor
        var aggressive: Double? = nil

        if let d = deltaPct, d > 15 {
            let scaled = currentWeight * (1.0 + d / 100.0)
            recommended = baseAnchor

            if scaled > recommended {
                aggressive = max(
                    scaled,
                    recommended * (1.0 + CoachingConstants.aggressiveFloorOverPrimaryPct / 100.0)
                )
                guardrails.append("delta_over_15_offered_aggressive")
            }
        } else if let d = deltaPct, d > 0 {
            recommended = baseAnchor * (1.0 + CoachingConstants.conservativeBumpPct / 100.0)
            guardrails.append("conservative_bump_5pct")

            if FeatureFlags.aggressiveRecommendationsEnabled {
                let agg = baseAnchor * (1.0 + CoachingConstants.conservativeBumpPct * 2.0 / 100.0)
                if agg > recommended {
                    aggressive = agg
                }
            }
        } else {
            recommended = baseAnchor
            guardrails.append("match_anchor")
        }

        let sessionMax = cursor.completedSetsToday.map(\.actualWeightLb).max() ?? currentWeight
        let sessionCap = sessionMax * (1.0 + CoachingConstants.maxSessionJumpPct / 100.0)

        if recommended > sessionCap && recommended > baseAnchor {
            recommended = max(sessionCap, baseAnchor)
            guardrails.append("capped_session_max_25pct")
        }

        if let a = aggressive, a > sessionCap && a > baseAnchor {
            aggressive = max(sessionCap, baseAnchor)
            guardrails.append("capped_aggressive_session_max_25pct")
        }

        if let histMax = history.historicalMaxWeight {
            let histCap = histMax * (1.0 + CoachingConstants.maxHistoricalJumpPct / 100.0)

            if recommended > histCap && recommended > baseAnchor {
                recommended = max(histCap, baseAnchor)
                guardrails.append("capped_historical_max_15pct")
            }

            if let a = aggressive, a > histCap && a > baseAnchor {
                aggressive = max(histCap, baseAnchor)
                guardrails.append("capped_aggressive_historical_max_15pct")
            }
        }

        if gate == .unknown {
            aggressive = nil
            guardrails.append("unknown_gate_suppress_aggressive")
        }

        if dropoffSignal > 15 {
            aggressive = nil
            guardrails.append("dropoff_over_15_suppress_aggressive")
        }

        let recRounded = roundWeight(recommended)
        let aggRounded: Double? = aggressive.map { roundWeight($0) }

        let showAggressive = FeatureFlags.aggressiveRecommendationsEnabled
            && (aggRounded ?? 0) > recRounded

        let reason: String = {
            if let d = deltaPct, d > 15 {
                return "Today's set was \(Int(d.rounded()))% over last time. You can push."
            }

            if let d = deltaPct, d > 0 {
                return "Solid set. Small bump on top of last time's \(nextSetLabel)."
            }

            if anchor != nil {
                return "Match last time's \(nextSetLabel)."
            }

            return "No prior \(nextSetLabel) — repeat current weight."
        }()

        let confidence: RecommendationConfidence = {
            switch gate {
            case .green:
                return .high
            case .yellow:
                return .medium
            case .red:
                return .medium
            case .unknown:
                return .low
            }
        }()

        return CoachingRecommendation(
            exerciseName: cursor.exerciseName,
            nextSetIndex: nextSet,
            anchorWeightLb: anchor,
            recommendedWeightLb: recRounded,
            aggressiveWeightLb: showAggressive ? aggRounded : nil,
            safeWeightLb: roundWeight(currentWeight),
            headline: headline,
            historyLine: historyLine(for: nextSetLabel, anchor: anchor),
            deltaLine: deltaLine,
            reasonLine: reason,
            fatigueLine: fatigueLine,
            fatigueGate: gate,
            confidence: confidence,
            shouldShowAggressiveOption: showAggressive,
            guardrailsApplied: guardrails
        )
    }

    private func roundWeight(_ w: Double) -> Double {
        let inc = CoachingConstants.weightIncrementLb
        guard inc > 0 else { return w }
        return (w / inc).rounded() * inc
    }

    private func intLb(_ w: Double) -> String {
        "\(Int(w.rounded()))"
    }

    private func setLabel(for index: Int) -> String {
        "Set \(index + 1)"
    }

    private func historyLine(for label: String, anchor: Double?) -> String {
        if let a = anchor {
            return "Last time, \(label) was \(intLb(a)) lb"
        }

        return "No prior \(label) on record"
    }

    private func buildSafeFallback(
        cursor: ExerciseSessionCursor,
        headline: String,
        nextSet: Int
    ) -> CoachingRecommendation {
        CoachingRecommendation(
            exerciseName: cursor.exerciseName,
            nextSetIndex: nextSet,
            anchorWeightLb: nil,
            recommendedWeightLb: 0,
            aggressiveWeightLb: nil,
            safeWeightLb: 0,
            headline: headline,
            historyLine: "No data available",
            deltaLine: nil,
            reasonLine: "Fallback — set a starting weight manually.",
            fatigueLine: nil,
            fatigueGate: .unknown,
            confidence: .low,
            shouldShowAggressiveOption: false,
            guardrailsApplied: ["fallback_safe"]
        )
    }
}

// MARK: - CoachingCardView
// Place at: VoltraLive/Coaching/Views/CoachingCardView.swift
public struct CoachingCardView: View {
    public let recommendation: CoachingRecommendation
    public let onLoadRecommended: () -> Void
    public let onLoadAggressive: () -> Void
    public let onLoadAnchor: () -> Void
    public let onRepeatCurrent: () -> Void

    public init(
        recommendation: CoachingRecommendation,
        onLoadRecommended: @escaping () -> Void,
        onLoadAggressive: @escaping () -> Void,
        onLoadAnchor: @escaping () -> Void,
        onRepeatCurrent: @escaping () -> Void
    ) {
        self.recommendation = recommendation
        self.onLoadRecommended = onLoadRecommended
        self.onLoadAggressive = onLoadAggressive
        self.onLoadAnchor = onLoadAnchor
        self.onRepeatCurrent = onRepeatCurrent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(recommendation.headline)
                    .font(.headline)

                Spacer()

                FatigueIndicatorView(gate: recommendation.fatigueGate)
            }

            Text(recommendation.historyLine)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if let delta = recommendation.deltaLine {
                Text(delta)
                    .font(.subheadline)
            }

            if let fatigue = recommendation.fatigueLine {
                Text(fatigue)
                    .font(.footnote)
                    .foregroundColor(.orange)
            }

            if recommendation.recommendedWeightLb > 0 {
                Text("Recommended: \(formatWeight(recommendation.recommendedWeightLb)) lb")
                    .font(.title3.bold())
                    .padding(.top, 4)
            } else {
                Text("Pick a starting weight")
                    .font(.title3.bold())
                    .padding(.top, 4)
            }

            Text(recommendation.reasonLine)
                .font(.footnote)
                .foregroundColor(.secondary)

            CoachingCardButtonRow(
                recommendation: recommendation,
                onLoadRecommended: onLoadRecommended,
                onLoadAggressive: onLoadAggressive,
                onLoadAnchor: onLoadAnchor,
                onRepeatCurrent: onRepeatCurrent
            )
            .padding(.top, 6)
        }
        .padding(12)
        .frame(
            maxWidth: .infinity,
            minHeight: CoachingConstants.cardMinHeight,
            alignment: .topLeading
        )
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(12)
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(w))"
            : String(format: "%.1f", w)
    }
}

// MARK: - CoachingCardButtonRow
// Place at: VoltraLive/Coaching/Views/CoachingCardButtonRow.swift
public struct CoachingCardButtonRow: View {
    public let recommendation: CoachingRecommendation
    public let onLoadRecommended: () -> Void
    public let onLoadAggressive: () -> Void
    public let onLoadAnchor: () -> Void
    public let onRepeatCurrent: () -> Void

    public var body: some View {
        HStack(spacing: 8) {
            Button(action: onLoadRecommended) {
                Text("Load \(format(recommendation.recommendedWeightLb)) lb")
                    .font(.callout.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(8)
            }
            .accessibilityLabel(
                "Load recommended weight \(format(recommendation.recommendedWeightLb)) pounds"
            )

            if recommendation.shouldShowAggressiveOption,
               let agg = recommendation.aggressiveWeightLb {
                Button(action: onLoadAggressive) {
                    Text("Push \(format(agg)) lb")
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(8)
                }
                .accessibilityLabel("Aggressive push weight \(format(agg)) pounds")
            } else if let anchor = recommendation.anchorWeightLb,
                      Int(anchor.rounded()) != Int(recommendation.recommendedWeightLb.rounded()) {
                Button(action: onLoadAnchor) {
                    Text("Last \(format(anchor)) lb")
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(8)
                }
                .accessibilityLabel("Load last session weight \(format(anchor)) pounds")
            }

            if recommendation.safeWeightLb > 0 {
                Button(action: onRepeatCurrent) {
                    Text("Repeat \(format(recommendation.safeWeightLb)) lb")
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(8)
                }
                .accessibilityLabel(
                    "Repeat current weight \(format(recommendation.safeWeightLb)) pounds"
                )
            }
        }
    }

    private func format(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(w))"
            : String(format: "%.1f", w)
    }
}

// MARK: - FatigueIndicatorView
// Place at: VoltraLive/Coaching/Views/FatigueIndicatorView.swift
public struct FatigueIndicatorView: View {
    public let gate: FatigueGate

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .accessibilityLabel(label)
    }

    private var color: Color {
        switch gate {
        case .green:
            return .green
        case .yellow:
            return .yellow
        case .red:
            return .red
        case .unknown:
            return .gray
        }
    }

    private var label: String {
        switch gate {
        case .green:
            return "Low fatigue"
        case .yellow:
            return "Moderate fatigue"
        case .red:
            return "High fatigue"
        case .unknown:
            return "Fatigue unknown"
        }
    }
}

/*
TARGET FILE PLACEMENTS
======================
- VoltraLive/FeatureFlags.swift
- VoltraLive/Coaching/CoachingConstants.swift
- VoltraLive/Coaching/Models/SetPerformanceSnapshot.swift
- VoltraLive/Coaching/Models/ExerciseSessionCursor.swift
- VoltraLive/Coaching/Models/HistoricalSetMatch.swift
- VoltraLive/Coaching/Models/CoachingRecommendation.swift
- VoltraLive/Coaching/Services/HistoricalWorkoutMatcher.swift
- VoltraLive/Coaching/Services/CoachingEngine.swift
- VoltraLive/Coaching/Services/SetSnapshotBuilder.swift  ← NEW (not in staging file)
- VoltraLive/Coaching/Views/CoachingCardView.swift
- VoltraLive/Coaching/Views/CoachingCardButtonRow.swift
- VoltraLive/Coaching/Views/FatigueIndicatorView.swift
- (Edit) VoltraLive/Logging/Views/LiveCaptureViewV2.swift
- (New) docs/specs/RC-01_COACHING_CARD.md
*/
