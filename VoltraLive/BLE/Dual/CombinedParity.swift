// CombinedParity.swift
//
// b47 (v0.4.25): Combined-mode even-weight enforcement.
//
// Why this exists: in Combined mode the total weight is split per
// CombinedMath.splitWeight (left rounds up and right rounds down for odd
// totals. So if the user enters 35 lb total, left gets 18 and right gets 17:
// the cables feel different on each side, which the user described as
// "different weights on each Voltra, will feel off." Per user direction:
// "when the Voltras are combined, you're only allowed to have even
// numbers, so it can split evenly."
//
// Scope: this helper centralizes the parity rule so all the call sites
// (resistance nudgers, drop-set step, mode-switch rounding, anywhere a
// weight is set in Combined mode) share one implementation.
//
// Independent / single-side / superset modes do NOT enforce parity; each
// side stands alone, so odd weights are fine.

import Foundation

enum CombinedParity {

    /// b47 step increments. Combined uses even steps so totals stay even.
    /// Independent / single / superset use the legacy 1/5 lb steps.
    static func smallStepLb(for mode: WorkoutMode) -> Int {
        return mode.requiresEvenWeight ? 2 : 1
    }
    static func largeStepLb(for mode: WorkoutMode) -> Int {
        return mode.requiresEvenWeight ? 6 : 5
    }

    /// Round-DOWN to the nearest even pound. Per user choice (b47 Q1 = A):
    /// when entering combined from a non-even weight (e.g. switched from
    /// independent at 35 lb), prefer 34 over 36 -- never adds weight the
    /// user didn't ask for. Negative inputs clamp to zero.
    static func roundDownToEven(_ lb: Int) -> Int {
        let clamped = max(0, lb)
        return clamped - (clamped % 2)
    }

    /// Same rule applied to a Double on the device coordinate (which uses
    /// 2.5 lb resolution for non-combined). For combined we want exact even
    /// pounds, so floor to the nearest even integer.
    static func roundDownToEven(_ lb: Double) -> Double {
        return Double(roundDownToEven(Int(lb.rounded(.down))))
    }

    /// Drop-set step magnitude in Combined mode. Per user choice (b47 Q2 = A):
    /// -6 lb per drop, matching the +6 nudger for symmetry. The cascade
    /// math floors to the nearest even pound after each step so totals
    /// stay even all the way to BOTTOM.
    static let combinedDropStepLb: Double = 6.0

    /// Apply the parity rule to a candidate weight given the current mode.
    /// In Combined: floor to nearest even. Otherwise: pass through.
    static func enforce(_ lb: Int, mode: WorkoutMode) -> Int {
        return mode.requiresEvenWeight ? roundDownToEven(lb) : lb
    }
    static func enforce(_ lb: Double, mode: WorkoutMode) -> Double {
        return mode.requiresEvenWeight ? roundDownToEven(lb) : lb
    }
}
