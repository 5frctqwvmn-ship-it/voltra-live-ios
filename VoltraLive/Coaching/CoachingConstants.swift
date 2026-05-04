// VoltraLive/Coaching/CoachingConstants.swift
// RC-01 / SC-01 — tunable constants for the coaching card and engine.
// Change only with hardware-validated test data.

import CoreGraphics   // CGFloat

enum CoachingConstants {
    // MARK: - UI timing
    /// Force reading below this threshold is treated as "device unloaded".
    static let forceActivityThresholdLb: Double = 5.0
    /// Seconds of continuous rest before the coaching card mounts.
    static let restingDebounceSeconds: Double = 1.5
    /// Card panel crossfade duration.
    static let cardTransitionSeconds: Double = 0.25
    /// Minimum card height — prevents layout shift on panel switch.
    static let cardMinHeight: CGFloat = 180

    // MARK: - Fatigue gates (% force/power drop-off, best rep → last rep)
    static let fatigueYellowPct: Double = 15.0
    static let fatigueRedPct:    Double = 30.0

    // MARK: - Progression caps
    /// Max % above today's best completed set weight.
    static let maxSessionJumpPct:         Double = 25.0
    /// Max % above historical max for this exercise.
    static let maxHistoricalJumpPct:      Double = 15.0
    /// Conservative bump when delta > 0 but <= 15%.
    static let conservativeBumpPct:       Double = 5.0
    /// Aggressive option must exceed primary by at least this %.
    static let aggressiveFloorOverPrimaryPct: Double = 5.0

    // MARK: - Weight rounding
    /// All recommended weights are rounded to the nearest increment.
    static let weightIncrementLb: Double = 5.0
}
