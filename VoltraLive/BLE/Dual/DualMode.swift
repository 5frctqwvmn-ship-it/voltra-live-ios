// DualMode.swift
//
// v0.4.7 build 29: shared types for dual-Voltra operation.
//
// Three things live here, all small:
//
//   1) DualMode \u2014 enum the user toggles in the dual capture screen.
//   2) DeviceSlot \u2014 which physical Voltra (.left / .right) a control or
//      log entry pertains to. Used everywhere a Voltra-bound identity is
//      needed.
//   3) CombinedMath \u2014 helpers that translate user-facing TOTAL values into
//      per-device values for Combined mode, and aggregate per-device telemetry
//      back into a single virtual-twin telemetry.
//
// Why these are in one file:
//   They're tightly coupled (Combined math reads DeviceSlot, both modes use
//   DualMode), small (<150 lines together), and live in the BLE layer because
//   they describe how we drive the BLE writers \u2014 not UI semantics.

import Foundation

// MARK: - DualMode

/// The capture-screen mode the user has selected.
///
/// `.independent` \u2014 the two Voltras are driven separately. Each side has its
///                   own mode/weights/exercise selection and logs to history
///                   independently. Default on dual-connect.
///
/// `.combined`    \u2014 the two Voltras are driven as a virtual twin for ONE
///                   exercise. User sets total weight; we split. Telemetry
///                   surfaces as combined sums/averages.
enum DualMode: String, CaseIterable, Equatable {
    case independent
    case combined

    var label: String {
        switch self {
        case .independent: return "Independent"
        case .combined:    return "Combined"
        }
    }
}

// MARK: - WorkoutMode (b42)

/// Build 42: pre-workout choice when both Voltras are paired. The user told
/// us they want both Voltras pairable but each engaged separately by
/// default \u2014 "having them dual mode by default is not by intent". This
/// mode is selected on a sheet that appears between tapping a day-tile and
/// startSession, and stays in effect for the duration of the workout.
///
///   .singleLeft  / .singleRight \u2014 only one Voltra produces telemetry; the
///                                  other stays paired but idle.
///   .independent                 \u2014 both Voltras are tracked side-by-side,
///                                  reps/force not summed.
///   .combined                    \u2014 virtual-twin: weights split, telemetry
///                                  summed (the legacy DualMode .combined).
enum WorkoutMode: String, CaseIterable, Equatable {
    case singleLeft
    case singleRight
    case independent
    case combined
    /// b48 (v0.4.26): Superset chain. Both Voltras are paired but each is
    /// loaded with a DIFFERENT exercise (e.g. left = bench press, right =
    /// bent-over row). The user alternates A \u2192 B \u2192 A \u2192 B; each
    /// Voltra logs its own sets, but the chain is tracked as a tied A/B
    /// superset rather than two parallel independent sets. Only surfaced
    /// in the picker when both Voltras are paired.
    case superset

    var label: String {
        switch self {
        case .singleLeft:  return "Left only"
        case .singleRight: return "Right only"
        case .independent: return "Independent"
        case .combined:    return "Combined"
        case .superset:    return "Superset"
        }
    }

    var subtitle: String {
        switch self {
        case .singleLeft:  return "Use just the Left Voltra. Right stays paired but idle."
        case .singleRight: return "Use just the Right Voltra. Left stays paired but idle."
        case .independent: return "Track both Voltras side-by-side. Reps and force are not summed."
        case .combined:    return "Treat both Voltras as one. Set total weight; force and reps are summed."
        case .superset:    return "Two exercises, one chain. Set A on Left, B on Right \u{2014} alternate sets back-to-back."
        }
    }

    var icon: String {
        switch self {
        case .singleLeft:  return "l.circle.fill"
        case .singleRight: return "r.circle.fill"
        case .independent: return "square.split.2x1"
        case .combined:    return "link"
        case .superset:    return "arrow.left.arrow.right"
        }
    }

    /// b47: combined-mode parity rule \u2014 weights split per CombinedMath
    /// across two Voltras, so the total must be EVEN to split evenly.
    /// Resistance nudgers, drop-set step, and mode-switch rounding all
    /// consult this to enforce the constraint. Independent / single /
    /// superset do NOT have this constraint (each side is independent).
    var requiresEvenWeight: Bool {
        switch self {
        case .combined: return true
        default:        return false
        }
    }
}

// MARK: - DeviceSlot

/// Stable identity for a Voltra in the dual-Voltra session. Maps to a fixed
/// position on the user's rack ("left" / "right") rather than to a BLE
/// peripheral identifier so that the user model is consistent even if a
/// device disconnects + reconnects.
enum DeviceSlot: String, CaseIterable, Equatable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    /// User-facing label \u2014 capitalized, used in UI tiles and history rows.
    var label: String {
        switch self {
        case .left:  return "Left"
        case .right: return "Right"
        }
    }

    var other: DeviceSlot {
        switch self {
        case .left:  return .right
        case .right: return .left
        }
    }
}

// MARK: - DeviceSlotAssignment (b53)

/// b53: Per-exercise Voltra assignment. Distinct from `DeviceSlot` because
/// an exercise can target BOTH Voltras simultaneously (bilateral movement
/// where the user wants the same weight on each side, e.g. a barbell
/// substitute) in addition to a single side. Persisted on
/// `ExerciseInstance.assignedVoltraRaw` as the raw string.
///
/// Routing semantics in WriterRouter when both Voltras are paired:
///   - .left  → writes go to mdm.leftWriter only
///   - .right → writes go to mdm.rightWriter only
///   - .both  → writes broadcast to both writers (same target on each)
///
/// nil on the instance falls back to MDM-driven routing (legacy / chain-
/// derived, for sessions imported before b53).
enum DeviceSlotAssignment: String, CaseIterable, Equatable, Identifiable {
    case left
    case right
    case both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .left:  return "Left"
        case .right: return "Right"
        case .both:  return "Both"
        }
    }

    /// Convert from a single-slot pick. `.both` cannot be expressed as a
    /// `DeviceSlot` so we collapse to the active slot at routing time.
    init(slot: DeviceSlot) {
        switch slot {
        case .left:  self = .left
        case .right: self = .right
        }
    }

    /// Project to a single slot when needed (e.g. for the chain banner's
    /// active-side rendering). `.both` projects to `.left` by convention.
    var projectedSlot: DeviceSlot {
        switch self {
        case .left:  return .left
        case .right: return .right
        case .both:  return .left
        }
    }
}

// MARK: - Combined-mode math

/// Helpers for translating user-facing TOTAL values into per-device values in
/// Combined mode, and aggregating per-device telemetry back into a single
/// "virtual twin" reading.
///
/// Conventions used by the user (locked in earlier):
///   - Weight (base, eccentric, chains): user enters TOTAL \u2192 each device
///     gets TOTAL/2. Odd totals: round Left up, Right down so the sum stays
///     exact. ("100 lb total \u2192 50 / 50; 101 lb total \u2192 51 / 50.")
///   - Eccentric %, chains %, inverse, mode: same value mirrored to both
///     devices (no split).
///   - Telemetry: SUM repCount + power; AVG ROM + velocity. Phase = whichever
///     side leads (max of the two).
enum CombinedMath {

    /// Split a TOTAL pound value into per-device values. Left rounds up,
    /// Right rounds down, so left + right == total exactly even for odd input.
    /// Negative inputs are clamped to zero.
    static func splitWeight(total: Int) -> (left: Int, right: Int) {
        let t = max(0, total)
        let half = t / 2
        if t % 2 == 0 {
            return (left: half, right: half)
        } else {
            // Left gets the extra pound. Stable choice; documented above.
            return (left: half + 1, right: half)
        }
    }

    /// Aggregate two per-device repCount streams into the virtual-twin total.
    /// Combined-mode rule: SUM. (Both cables move together; each side counts
    /// its own reps. Sum reflects total reps across the system.)
    static func combineRepCount(left: Int, right: Int) -> Int {
        return left + right
    }

    /// Aggregate per-device peak power. Sum to give a "system power" reading.
    static func combinePeakPower(left: Int?, right: Int?) -> Int? {
        switch (left, right) {
        case (nil, nil): return nil
        case (let l?, nil): return l
        case (nil, let r?): return r
        case (let l?, let r?): return l + r
        }
    }

    /// Aggregate force readings. Combined-mode user-felt force is the sum of
    /// both cables (each cable is loaded with TOTAL/2 and the user lifts both
    /// at once). If a side is missing telemetry, fall back to the present one.
    static func combineForceLb(left: Double?, right: Double?) -> Double {
        return (left ?? 0) + (right ?? 0)
    }

    /// Average a value across the two sides, ignoring nils. Returns nil if
    /// neither side has a value.
    static func averageOptional(_ left: Double?, _ right: Double?) -> Double? {
        switch (left, right) {
        case (nil, nil): return nil
        case (let l?, nil): return l
        case (nil, let r?): return r
        case (let l?, let r?): return (l + r) / 2.0
        }
    }
}
