// VoltraLive/FeatureFlags.swift
// RC-01 feature flags — all off by default in production.
// Smart Coach is unlocked via hidden 4-tap on the version badge.

import Foundation

enum FeatureFlags {

    // MARK: - Hidden Smart Coach unlock

    /// UserDefaults key written by the 4-tap gesture on BuildBadgeChip.
    /// Persists across app launches.
    static let smartCoachUnlockUserDefaultsKey = "VOLTRASmartCoachUnlocked"

    private static var smartCoachUnlocked: Bool {
        UserDefaults.standard.bool(forKey: smartCoachUnlockUserDefaultsKey)
    }

    // MARK: - Coaching flags (driven by UserDefaults unlock)

    /// Shows the rest-state Coaching Card panel in LiveCapture.
    /// OFF by default; enabled by the hidden version-badge 4-tap.
    static var coachingCardEnabled: Bool { smartCoachUnlocked }

    /// Enables Smart Coach weight recommendations inside the Coaching Card.
    /// Ignored when coachingCardEnabled is false.
    static var smartCoachEnabled: Bool { smartCoachUnlocked }

    // MARK: - Other flags (static defaults)

    /// Enables the "Push X lb" aggressive option. Keep dark unless explicitly
    /// enabled in a later task.
    static var aggressiveRecommendationsEnabled: Bool = false

    /// When true, prevents starting a set if HR is above recovery threshold.
    /// Currently log-only — do not enable hard lock until threshold is tuned.
    static var hrRecoveryHardLockEnabled: Bool = false

    /// Appends coaching recommendation inputs/outputs to the session recorder
    /// debug JSON export. Requires telemetry debug export to be unlocked.
    static var telemetryDebugExportEnabled: Bool = false
}
