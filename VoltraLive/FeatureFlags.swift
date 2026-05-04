// VoltraLive/FeatureFlags.swift
// RC-01 feature flags — all off by default in production.
// Set individual flags to true for TestFlight betas.
// No flag change requires a new binary — adjust and rebuild.

enum FeatureFlags {
    /// Shows the rest-state Coaching Card panel in LiveCapture.
    /// Off by default — ship dark until A1 hardware retest passes for KI-20.
    static var coachingCardEnabled: Bool = false

    /// Enables Smart Coach weight recommendations inside the Coaching Card.
    /// Ignored when coachingCardEnabled is false.
    static var smartCoachEnabled: Bool = false

    /// Enables the "Push X lb" aggressive option when the coaching engine
    /// calculates a safe aggressive alternative. Requires smartCoachEnabled.
    static var aggressiveRecommendationsEnabled: Bool = false

    /// When true, prevents starting a set if HR is above recovery threshold.
    /// Currently log-only — do not enable hard lock until threshold is tuned.
    static var hrRecoveryHardLockEnabled: Bool = false

    /// Appends coaching recommendation inputs/outputs to the session recorder
    /// debug JSON export. Requires telemetry debug export to be unlocked.
    static var telemetryDebugExportEnabled: Bool = false
}
