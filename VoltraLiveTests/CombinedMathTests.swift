// CombinedMathTests.swift
// v0.4.8 / build 30 — pin Combined-mode dual-Voltra splits and aggregates.
//
// Why these tests matter:
//   In Combined mode the user enters TOTAL weight; we split it across two
//   Voltras so the sum stays exact. The user-stated rule is "Left rounds up
//   when TOTAL is odd, so the sum stays exact." A regression that swaps the
//   rounding side would be silent — the cable would still load, the user
//   would just feel an extra pound on the wrong side. These tests pin the
//   convention so any future refactor preserves it.
//
// Telemetry aggregates (sum / sum / sum / avg) are also pinned because the
// Combined panel reads them. A swap of "average force" vs "sum force" would
// halve the user's force readout and the user might not notice immediately.

import XCTest
@testable import VoltraLive

final class CombinedMathTests: XCTestCase {

    // MARK: - splitWeight

    /// Even totals split exactly.
    func testSplitWeight_Even() {
        let s = CombinedMath.splitWeight(total: 100)
        XCTAssertEqual(s.left, 50)
        XCTAssertEqual(s.right, 50)
        XCTAssertEqual(s.left + s.right, 100, "sum must equal total")
    }

    /// Odd totals: Left rounds up. Pinned per user's stated convention.
    func testSplitWeight_OddRoundsLeftUp() {
        let s = CombinedMath.splitWeight(total: 101)
        XCTAssertEqual(s.left, 51, "Left must round UP on odd totals")
        XCTAssertEqual(s.right, 50)
        XCTAssertEqual(s.left + s.right, 101, "sum must remain exact")
    }

    /// Zero total — both sides go to zero (used when the user clears weight).
    func testSplitWeight_Zero() {
        let s = CombinedMath.splitWeight(total: 0)
        XCTAssertEqual(s.left, 0)
        XCTAssertEqual(s.right, 0)
    }

    /// Negative input is clamped to zero on both sides. The user shouldn't
    /// be able to enter negative weight, but the math must not produce a
    /// negative-on-one-side / positive-on-the-other split if they do.
    func testSplitWeight_NegativeClampsToZero() {
        let s = CombinedMath.splitWeight(total: -10)
        XCTAssertEqual(s.left, 0)
        XCTAssertEqual(s.right, 0)
    }

    /// One-pound total: edge case — Left gets the lone pound, Right gets 0.
    /// Documents the behavior at the smallest meaningful odd input.
    func testSplitWeight_One() {
        let s = CombinedMath.splitWeight(total: 1)
        XCTAssertEqual(s.left, 1, "Left rounds up — gets the lone pound")
        XCTAssertEqual(s.right, 0)
    }

    // MARK: - aggregates

    /// Reps sum across both sides.
    func testCombineRepCount_Sum() {
        XCTAssertEqual(CombinedMath.combineRepCount(left: 5, right: 7), 12)
    }

    /// Force sums across both sides; missing side falls back to zero so
    /// the user still sees a reading from the connected device.
    func testCombineForceLb_BothPresent_Sum() {
        XCTAssertEqual(CombinedMath.combineForceLb(left: 100.0, right: 80.0), 180.0)
    }

    func testCombineForceLb_OneMissing_FallsBackToPresent() {
        XCTAssertEqual(CombinedMath.combineForceLb(left: 100.0, right: nil), 100.0)
        XCTAssertEqual(CombinedMath.combineForceLb(left: nil, right: 80.0), 80.0)
    }

    func testCombineForceLb_BothMissing_Zero() {
        XCTAssertEqual(CombinedMath.combineForceLb(left: nil, right: nil), 0.0)
    }

    /// Peak power: both nil → nil; one present → that one; both → sum.
    func testCombinePeakPower_NilHandling() {
        XCTAssertNil(CombinedMath.combinePeakPower(left: nil, right: nil))
        XCTAssertEqual(CombinedMath.combinePeakPower(left: 200, right: nil), 200)
        XCTAssertEqual(CombinedMath.combinePeakPower(left: nil, right: 150), 150)
        XCTAssertEqual(CombinedMath.combinePeakPower(left: 200, right: 150), 350)
    }

    /// averageOptional must average present values and ignore nils.
    /// One-side-only returns the present side; both-nil returns nil.
    func testAverageOptional_AllCases() {
        XCTAssertNil(CombinedMath.averageOptional(nil, nil))
        XCTAssertEqual(CombinedMath.averageOptional(10.0, nil), 10.0)
        XCTAssertEqual(CombinedMath.averageOptional(nil, 20.0), 20.0)
        XCTAssertEqual(CombinedMath.averageOptional(10.0, 20.0), 15.0)
    }
}

// MARK: - DualMode + DeviceSlot

final class DualModeTests: XCTestCase {
    /// Pin the user-facing labels — they appear in the segmented control
    /// header and in history rows. A typo refactor would surface here.
    func testDualMode_Labels() {
        XCTAssertEqual(DualMode.independent.label, "Independent")
        XCTAssertEqual(DualMode.combined.label,    "Combined")
    }

    func testDeviceSlot_Labels() {
        XCTAssertEqual(DeviceSlot.left.label,  "Left")
        XCTAssertEqual(DeviceSlot.right.label, "Right")
    }

    /// `.other` flips left ↔ right. Used by the Combined-mode disconnect
    /// watchdog to find the survivor of a drop.
    func testDeviceSlot_Other() {
        XCTAssertEqual(DeviceSlot.left.other,  .right)
        XCTAssertEqual(DeviceSlot.right.other, .left)
    }
}
