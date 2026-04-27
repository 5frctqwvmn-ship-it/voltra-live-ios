// DropSetCascadeTests.swift
// Pins the user-stated invariant that drop-set reductions ALWAYS anchor to
// the original starting weight and NEVER compound off the most recently
// dropped value.
//
// Reported regression (build 29):
//   Starting 100 lb at "20% per drop" should give 100 → 80 → 60 → 40.
//   Build 29 produced 100 → 80 → 64 (compounded: 100 × 0.8 × 0.8).
//
// This file exercises BOTH:
//   1. The pure helper `cascadeAnchoredDeviceWeight` (math-only).
//   2. A live `LoggingStore.startDropSet` simulation that drives the
//      cascade and asserts on `dropChainPlannedLb`.
//
// If any of these tests start failing later, do NOT relax the assertion —
// re-anchor the implementation instead.

import XCTest
@testable import VoltraLive

@MainActor
final class DropSetCascadeTests: XCTestCase {

    // MARK: - Pure cascade math (anchor-relative)

    /// Tier 1 = 5 lb / 5%. Anchored to 100, steps 1..3 must give the same
    /// arithmetic ladder regardless of how many times the function is
    /// called or in what order.
    func testCascadeAnchored_Tier1_FromHundred() {
        let a = 100.0
        XCTAssertEqual(LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: a, tier: 1, stepIndex: 1, multiplier: 1.0), 95.0)
        XCTAssertEqual(LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: a, tier: 1, stepIndex: 2, multiplier: 1.0), 90.0)
        XCTAssertEqual(LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: a, tier: 1, stepIndex: 3, multiplier: 1.0), 85.0)
        XCTAssertEqual(LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: a, tier: 1, stepIndex: 4, multiplier: 1.0), 80.0)
    }

    /// Tier 2 = 10 lb / 10%. From 100, must give 90/80/70/60.
    func testCascadeAnchored_Tier2_FromHundred() {
        let a = 100.0
        XCTAssertEqual(LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: a, tier: 2, stepIndex: 1, multiplier: 1.0), 90.0)
        XCTAssertEqual(LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: a, tier: 2, stepIndex: 2, multiplier: 1.0), 80.0)
        XCTAssertEqual(LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: a, tier: 2, stepIndex: 3, multiplier: 1.0), 70.0)
        XCTAssertEqual(LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: a, tier: 2, stepIndex: 4, multiplier: 1.0), 60.0)
    }

    /// Tier 3 = 15 lb / 15%. From 100, must give 85/70/55/40.
    func testCascadeAnchored_Tier3_FromHundred() {
        let a = 100.0
        XCTAssertEqual(LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: a, tier: 3, stepIndex: 1, multiplier: 1.0), 85.0)
        XCTAssertEqual(LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: a, tier: 3, stepIndex: 2, multiplier: 1.0), 70.0)
        XCTAssertEqual(LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: a, tier: 3, stepIndex: 3, multiplier: 1.0), 55.0)
        XCTAssertEqual(LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: a, tier: 3, stepIndex: 4, multiplier: 1.0), 40.0)
    }

    /// Pulley mode (multiplier 2.0): math runs on EFFECTIVE load, then maps
    /// back to device. Anchor 50 (device) → effective 100. Tier 2 step 1
    /// effective = 100 - 10 = 90 → device = 45.
    func testCascadeAnchored_PulleyMode_AnchorsOnEffective() {
        let dev = 50.0
        let s1 = LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: dev, tier: 2, stepIndex: 1, multiplier: 2.0)
        let s2 = LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: dev, tier: 2, stepIndex: 2, multiplier: 2.0)
        XCTAssertEqual(s1, 45.0, "device step 1 under 2× pulley")
        XCTAssertEqual(s2, 40.0, "device step 2 under 2× pulley — must NOT compound off 45")
    }

    /// Calling step 3 directly must equal calling step 1 then step 2 then
    /// step 3 in sequence — the function is path-independent.
    func testCascadeAnchored_PathIndependence() {
        let a = 200.0
        let direct = LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: a, tier: 1, stepIndex: 3, multiplier: 1.0)
        // Walking step-by-step but each call still anchors to `a`.
        let s1 = LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: a, tier: 1, stepIndex: 1, multiplier: 1.0)
        let s2 = LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: a, tier: 1, stepIndex: 2, multiplier: 1.0)
        let s3 = LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: a, tier: 1, stepIndex: 3, multiplier: 1.0)
        XCTAssertEqual(direct, s3)
        XCTAssertGreaterThan(s1, s2)
        XCTAssertGreaterThan(s2, s3)
    }

    // MARK: - Live cascade simulation

    /// Drive a real `LoggingStore` cascade and assert the planned-weight
    /// chain it builds matches the anchor-relative ladder. This catches
    /// regressions where the math helper stays correct but the state
    /// machine starts feeding it the wrong anchor (e.g. the just-dropped
    /// weight instead of the original starting weight).
    func testLiveCascade_Tier1_BuildsAnchoredLadder() {
        let store = LoggingStore.makeForTesting()
        var pushedWeights: [Double] = []
        store.startDropSet(startingLb: 100.0) { lb in
            pushedWeights.append(lb)
        }
        // After startDropSet the immediate drop #2 has fired (tier 1 step 1 → 95).
        // Drive 3 more recurring fires to reach drops #3, #4, #5.
        store.testFireCascadeStep()
        store.testFireCascadeStep()
        store.testFireCascadeStep()

        // dropChainPlannedLb starts with [startingLb] and appends each fired
        // step's weight. Expect 100 (drop #1, the starting weight) followed
        // by anchor-relative drops at tier 1.
        XCTAssertEqual(store.dropChainPlannedLb, [100.0, 95.0, 90.0, 85.0, 80.0],
                       "cascade ladder must be anchor-relative, not compounding")
        XCTAssertEqual(pushedWeights, [95.0, 90.0, 85.0, 80.0],
                       "device pushes must follow the anchored ladder")
    }

    /// User-reported scenario: starting at 100, tier-bumped twice (so each
    /// tap fires at the new tier). The chain must follow the anchored
    /// progression — NEVER 100 → 80 → 64 (which is 20% compounded).
    func testLiveCascade_BumpedTier_DoesNotCompound() {
        let store = LoggingStore.makeForTesting()
        store.startDropSet(startingLb: 100.0) { _ in }
        // After start: tier 1, drop #2 fired = 95. cascadeStepIndex = 1.
        // First bump → tier 2, fires drop #3 anchored at step 2 → 100 - max(10, 100*0.10*2) = 80.
        store.bumpCascadeTier()
        // Second bump → tier 3, fires drop #4 anchored at step 3 → 100 - max(15, 100*0.15*3) = 55.
        store.bumpCascadeTier()

        XCTAssertEqual(store.dropChainPlannedLb, [100.0, 95.0, 80.0, 55.0],
                       "tier-bump fires must remain anchor-relative; compounding would yield ...80, 64...")
        // Specifically: assert the compounding artifact never appears.
        XCTAssertFalse(store.dropChainPlannedLb.contains(64.0),
                       "64 lb is the canonical compounding artifact (100 × 0.8 × 0.8) and must never appear")
    }

    /// The 20%-per-drop ladder the user described in plain language
    /// (100 → 80 → 60 → 40) corresponds to a fixed step of 20 lb anchored
    /// to 100. The current cascade caps at tier 3 (15%/15 lb), so the
    /// cleanest way to reproduce the user's expected ladder is to run
    /// `cascadeAnchoredDeviceWeight` directly with a hypothetical tier 4
    /// (20%/20 lb). This test pins what that ladder would look like and
    /// will guide the build-30 UX (do we expose tier 4? do we offer a
    /// dedicated "20% drop" mode?).
    func testCascadeAnchored_HypotheticalTier4_MatchesUserLadder() {
        let a = 100.0
        XCTAssertEqual(LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: a, tier: 4, stepIndex: 1, multiplier: 1.0), 80.0)
        XCTAssertEqual(LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: a, tier: 4, stepIndex: 2, multiplier: 1.0), 60.0)
        XCTAssertEqual(LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: a, tier: 4, stepIndex: 3, multiplier: 1.0), 40.0)
        XCTAssertEqual(LoggingStore.cascadeAnchoredDeviceWeight(anchorDeviceLb: a, tier: 4, stepIndex: 4, multiplier: 1.0), 20.0)
    }
}
