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
