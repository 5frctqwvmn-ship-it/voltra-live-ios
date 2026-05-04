// VoltraLive/Coaching/Models/CoachingRecommendation.swift
// RC-01 — output of CoachingEngine.recommend(cursor:history:).
// All fields are display-ready strings or typed values.
// Nothing in this type performs BLE writes.

import Foundation

enum FatigueGate: String, Codable {
    case green    // drop-off < 15%
    case yellow   // 15% <= drop-off < 30%
    case red      // drop-off >= 30%
    case unknown  // per-rep data unavailable
}

enum RecommendationConfidence: String, Codable {
    case low
    case medium
    case high
}

struct CoachingRecommendation: Codable, Equatable {
    let exerciseName: String
    /// 0-based index of the set this recommendation is for.
    let nextSetIndex: Int

    /// Weight from last session's corresponding set (the "anchor").
    let anchorWeightLb: Double?
    /// Primary recommended weight. Always rounded to weightIncrementLb.
    let recommendedWeightLb: Double
    /// Aggressive option, present only when shouldShowAggressiveOption is true.
    let aggressiveWeightLb: Double?
    /// "Safe" option — repeat current weight. Hidden when <= 0.
    let safeWeightLb: Double

    // MARK: - Display strings
    let headline: String
    let historyLine: String
    let deltaLine: String?
    let reasonLine: String
    let fatigueLine: String?

    // MARK: - State
    let fatigueGate: FatigueGate
    let confidence: RecommendationConfidence
    let shouldShowAggressiveOption: Bool

    /// Ordered list of guardrails that were applied, for debug export.
    let guardrailsApplied: [String]
}
