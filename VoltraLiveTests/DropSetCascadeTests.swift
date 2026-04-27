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
        let (store, session) = LoggingStore.makeForTestingWithSession()
        _ = session // retained for the duration of the test (weak ref on store)
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

    /// v0.4.8 (build 30) regression test for the user-reported bug shown in
    /// screenshots IMG_2241–2244. Each tap on the active drop-set tile was
    /// firing a drop AND bumping the tier, producing the ladder
    /// 100 → 95 (DROP 2, tier 1) → 80 (DROP 3, tier 2) → 55 (DROP 4, tier 3)
    /// across just three taps. After the fix, `bumpCascadeTier` is
    /// preview-only: it cycles 5%→10%→15% but does NOT fire a step. The
    /// 4s fuse remains the only path to commit a drop.
    ///
    /// Expected chain after start + 3 bumps: only the start's immediate
    /// fire of drop #2 at tier 1 is on the chain. Subsequent bumps add
    /// nothing.
    func testLiveCascade_BumpedTier_DoesNotFireDrop() {
        let (store, session) = LoggingStore.makeForTestingWithSession()
        _ = session
        var pushed: [Double] = []
        store.startDropSet(startingLb: 100.0) { lb in pushed.append(lb) }
        // startDropSet fires drop #2 immediately at tier 1: 100 → 95. This
        // is intentional ("the user wants the press of the button to feel
        // instant" — LoggingStore.startDropSet comment).
        XCTAssertEqual(store.dropChainPlannedLb, [100.0, 95.0],
                       "startDropSet fires drop #2 immediately at tier 1")
        XCTAssertEqual(pushed, [95.0],
                       "startDropSet's immediate fire pushes 95 to the device")

        // Three tier bumps: tier cycles 1→2→3→1. No further drops fire.
        store.bumpCascadeTier() // tier 2
        store.bumpCascadeTier() // tier 3
        store.bumpCascadeTier() // tier 1 (rolled)

        XCTAssertEqual(store.dropChainPlannedLb, [100.0, 95.0],
                       "tier bumps must NOT extend the drop chain past startDropSet's initial fire")
        XCTAssertEqual(pushed, [95.0],
                       "tier bumps must NOT push additional weights to the device")
        XCTAssertEqual(store.cascadeTier, 1, "three bumps cycles 1→2→3→1")
        // The canonical pre-fix ladder (...80, 55) must not appear.
        XCTAssertFalse(store.dropChainPlannedLb.contains(80.0),
                       "80 lb would only appear if bumpCascadeTier still fired (pre-build-30 bug)")
        XCTAssertFalse(store.dropChainPlannedLb.contains(55.0),
                       "55 lb would only appear if bumpCascadeTier still fired at tier 3 (pre-build-30 bug)")
    }

    /// When the 4s fuse fires (simulated via `testFireCascadeStep`), the
    /// drop committed must use whatever tier is current at fire time, and
    /// must remain anchor-relative — never compounding off prior drops.
    /// After bumping to tier 3, the fuse should fire 85, then 70 (= 100
    /// minus 15 × stepIndex), anchored to the original 100.
    func testLiveCascade_FuseFiresAtCurrentTier_AnchorRelative() {
        let (store, session) = LoggingStore.makeForTestingWithSession()
        _ = session
        store.startDropSet(startingLb: 100.0) { _ in }
        // Chain after start: [100, 95]. cascadeStepIndex = 1, tier = 1.
        store.bumpCascadeTier() // tier 2 (no fire)
        store.bumpCascadeTier() // tier 3 (no fire)
        store.testFireCascadeStep() // fuse: tier 3, step 2 → 100 - 15*2 = 70
        // Hmm — stepIndex went from 1→2, so the fired weight is anchored
        // at step 2 of tier 3: 100 - max(15, 100*0.15*2) = 100 - 30 = 70.

        XCTAssertEqual(store.dropChainPlannedLb.last, 70.0,
                       "fuse-fired drop at tier 3, step 2 must be 70 (anchor-relative)")
        XCTAssertFalse(store.dropChainPlannedLb.contains(64.0),
                       "64 lb (100 × 0.8 × 0.8) is the compounding artifact and must never appear")
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
