// VoltraLive/Coaching/Services/CoachingEngine.swift
// SC-01 — rule-based, explainable weight recommendation engine.
//
// Guarantees:
//   - No BLE writes. No automatic weight changes. No hidden AI.
//   - Every recommendation has a reasonLine.
//   - Aggressive option only when strictly > recommended AND gate allows.
//   - All output weights rounded to CoachingConstants.weightIncrementLb.
//   - Guardrails list every cap/suppression that fired.

import Foundation

struct CoachingEngine {
    func recommend(
        cursor: ExerciseSessionCursor,
        history: HistoricalSetMatch
    ) -> CoachingRecommendation {
        var guardrails: [String] = []

        let nextSet      = cursor.nextSetIndex
        let nextSetLabel = setLabel(for: nextSet)
        let headline     = "Next: \(cursor.exerciseName) \(nextSetLabel)"

        let anchor       = history.previousNextIndexSet?.actualWeightLb
        let priorSameIdx = history.previousSameIndexSet?.actualWeightLb

        // MARK: Rule 0 — no history at all
        if history.previousSameIndexSet == nil && history.previousNextIndexSet == nil {
            let currentWeight = cursor.lastCompletedSet?.actualWeightLb ?? 0
            let safe = roundWeight(currentWeight)
            guardrails.append("no_history_repeat_current")
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
                guardrailsApplied: guardrails
            )
        }

        // MARK: Rule 1 — no sets today yet
        if cursor.completedSetsToday.isEmpty {
            let anchorWeight = anchor ?? priorSameIdx ?? 0
            let rec = roundWeight(anchorWeight)
            guardrails.append("start_at_anchor")
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
                guardrailsApplied: guardrails
            )
        }

        // Rules 2+ require at least one completed set today.
        guard let lastSet = cursor.lastCompletedSet else {
            assertionFailure("lastCompletedSet must be non-nil past rules 0 and 1")
            return buildSafeFallback(cursor: cursor, headline: headline, nextSet: nextSet)
        }

        // MARK: Fatigue gate
        let forceDO       = lastSet.forceDropoffPct
        let powerDO       = lastSet.powerDropoffPct
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

        // MARK: Rule 2 — red gate
        if gate == .red {
            guardrails.append("red_gate_no_increase")
            return CoachingRecommendation(
                exerciseName: cursor.exerciseName,
                nextSetIndex: nextSet,
                anchorWeightLb: anchor,
                recommendedWeightLb: roundWeight(currentWeight),
                aggressiveWeightLb: nil,
                safeWeightLb: roundWeight(max(currentWeight * 0.9, 0)),
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

        // MARK: Rule 3 — yellow gate
        if gate == .yellow {
            guardrails.append("yellow_gate_cap_5pct")
            let candidate = min(anchor ?? currentWeight, currentWeight * 1.05)
            return CoachingRecommendation(
                exerciseName: cursor.exerciseName,
                nextSetIndex: nextSet,
                anchorWeightLb: anchor,
                recommendedWeightLb: roundWeight(candidate),
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

        // MARK: Rules 4+ — green / unknown gate
        let baseAnchor = anchor ?? currentWeight
        var recommended = baseAnchor
        var aggressive: Double? = nil

        if let d = deltaPct, d > 15 {
            // Significant performance jump — offer aggressive
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
            // Modest performance improvement — conservative bump
            recommended = baseAnchor * (1.0 + CoachingConstants.conservativeBumpPct / 100.0)
            guardrails.append("conservative_bump_5pct")
            if FeatureFlags.aggressiveRecommendationsEnabled {
                let agg = baseAnchor * (1.0 + CoachingConstants.conservativeBumpPct * 2.0 / 100.0)
                if agg > recommended { aggressive = agg }
            }
        } else {
            recommended = baseAnchor
            guardrails.append("match_anchor")
        }

        // Session cap: never exceed +25% over today's best
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

        // Historical cap: never exceed +15% over all-time max
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

        // Suppress aggressive when gate is unknown or drop > 15
        if gate == .unknown {
            aggressive = nil
            guardrails.append("unknown_gate_suppress_aggressive")
        }
        if dropoffSignal > 15 {
            aggressive = nil
            guardrails.append("dropoff_over_15_suppress_aggressive")
        }

        let recRounded = roundWeight(recommended)
        let aggRounded = aggressive.map { roundWeight($0) }
        let showAggressive = FeatureFlags.aggressiveRecommendationsEnabled
            && (aggRounded ?? 0) > recRounded

        let reason: String = {
            if let d = deltaPct, d > 15 {
                return "Today's set was \(Int(d.rounded()))% over last time. You can push."
            }
            if let d = deltaPct, d > 0 {
                return "Solid set. Small bump on top of last time's \(nextSetLabel)."
            }
            if anchor != nil { return "Match last time's \(nextSetLabel)." }
            return "No prior \(nextSetLabel) — repeat current weight."
        }()

        let confidence: RecommendationConfidence = {
            switch gate {
            case .green:   return .high
            case .yellow:  return .medium
            case .red:     return .medium
            case .unknown: return .low
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

    // MARK: - Helpers
    private func roundWeight(_ w: Double) -> Double {
        let inc = CoachingConstants.weightIncrementLb
        guard inc > 0 else { return w }
        return (w / inc).rounded() * inc
    }

    private func intLb(_ w: Double) -> String { "\(Int(w.rounded()))" }

    private func setLabel(for index: Int) -> String { "Set \(index + 1)" }

    private func historyLine(for label: String, anchor: Double?) -> String {
        if let a = anchor { return "Last time, \(label) was \(intLb(a)) lb" }
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
