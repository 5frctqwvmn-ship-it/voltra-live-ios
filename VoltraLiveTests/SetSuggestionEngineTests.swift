// SetSuggestionEngineTests.swift
// Tests the v0.2.1 smart-start logic. The engine is pure Foundation so these
// tests don't need a SwiftData container — they construct LoggedSet stubs by
// hand. The model `init` accepts plain values so this stays simple.

import XCTest
@testable import VoltraLive

final class SetSuggestionEngineTests: XCTestCase {

    // MARK: - Helpers

    private func mkSet(order: Int, weight: Double, reps: Int = 10) -> LoggedSet {
        LoggedSet(orderIndex: order, weightLb: weight, reps: reps)
    }

    // MARK: - Set 1

    func testSet1_NoHistory_FreeEntry() {
        let s = SetSuggestionEngine.suggestion(
            forSetIndex: 1,
            currentInstanceSets: [],
            previousSeries: []
        )
        XCTAssertTrue(s.isFreeEntry)
        XCTAssertNil(s.anchorLb)
        XCTAssertEqual(s.options, [])
    }

    func testSet1_WithHistory_AnchorsToFirstSetLastSession() {
        let prev = [mkSet(order: 1, weight: 30), mkSet(order: 2, weight: 35), mkSet(order: 3, weight: 40)]
        let s = SetSuggestionEngine.suggestion(
            forSetIndex: 1,
            currentInstanceSets: [],
            previousSeries: prev
        )
        XCTAssertEqual(s.anchorLb, 30)
        XCTAssertEqual(s.options, [25, 30, 35])
        XCTAssertEqual(s.offsets, [-5, 0, 5])
        XCTAssertEqual(s.sameIndex, 1)
    }

    // MARK: - Set 2+ delta projection

    func testSet2_ProjectsDeltaFromHistory_OntoCurrent() {
        // Last week: 30 -> 35 (+5 jump into set 2).
        // Today: user actually started at 25 (e.g. felt heavy).
        // Expected anchor: 25 + 5 = 30. Toggle: 25 / 30 / 35.
        let prev = [mkSet(order: 1, weight: 30), mkSet(order: 2, weight: 35)]
        let curr = [mkSet(order: 1, weight: 25)]
        let s = SetSuggestionEngine.suggestion(
            forSetIndex: 2,
            currentInstanceSets: curr,
            previousSeries: prev
        )
        XCTAssertEqual(s.anchorLb, 30)
        XCTAssertEqual(s.options, [25, 30, 35])
    }

    func testSet2_NegativeDelta_FromHistory() {
        // Last week: 40 -> 35 (drop set, -5). Today started at 50. Anchor: 45.
        let prev = [mkSet(order: 1, weight: 40), mkSet(order: 2, weight: 35)]
        let curr = [mkSet(order: 1, weight: 50)]
        let s = SetSuggestionEngine.suggestion(
            forSetIndex: 2,
            currentInstanceSets: curr,
            previousSeries: prev
        )
        XCTAssertEqual(s.anchorLb, 45)
        XCTAssertEqual(s.options, [40, 45, 50])
    }

    func testSet3_UsesDeltaBetweenSet2AndSet3() {
        // Last week: 30 -> 35 -> 45 (delta into set 3 = +10). Today: 25 -> 30.
        // Expected anchor: 30 + 10 = 40. Toggle: 35 / 40 / 45.
        let prev = [mkSet(order: 1, weight: 30), mkSet(order: 2, weight: 35), mkSet(order: 3, weight: 45)]
        let curr = [mkSet(order: 1, weight: 25), mkSet(order: 2, weight: 30)]
        let s = SetSuggestionEngine.suggestion(
            forSetIndex: 3,
            currentInstanceSets: curr,
            previousSeries: prev
        )
        XCTAssertEqual(s.anchorLb, 40)
        XCTAssertEqual(s.options, [35, 40, 45])
    }

    func testSet3_DeltaSnapsToFive() {
        // Pretend last week's delta into set 3 was +7 (oddball). Should snap to +5.
        let prev = [mkSet(order: 1, weight: 30), mkSet(order: 2, weight: 30), mkSet(order: 3, weight: 37)]
        let curr = [mkSet(order: 1, weight: 30), mkSet(order: 2, weight: 30)]
        let s = SetSuggestionEngine.suggestion(
            forSetIndex: 3,
            currentInstanceSets: curr,
            previousSeries: prev
        )
        // Delta 7 snaps to 5. Anchor = 30 + 5 = 35.
        XCTAssertEqual(s.anchorLb, 35)
    }

    // MARK: - Edge cases

    func testSet2_PreviousShorter_RepeatsCurrent() {
        // History only has 1 set, but user is on set 2 today.
        let prev = [mkSet(order: 1, weight: 30)]
        let curr = [mkSet(order: 1, weight: 30)]
        let s = SetSuggestionEngine.suggestion(
            forSetIndex: 2,
            currentInstanceSets: curr,
            previousSeries: prev
        )
        XCTAssertEqual(s.anchorLb, 30)
        if case .repeatCurrent = s.source { /* ok */ } else {
            XCTFail("Expected repeatCurrent, got \(s.source)")
        }
    }

    func testSet2_NoCurrentSetsYet_FallsBackToPreviousSlot() {
        // User somehow on set 2 with no current sets logged. Use prev set 2.
        let prev = [mkSet(order: 1, weight: 30), mkSet(order: 2, weight: 35)]
        let s = SetSuggestionEngine.suggestion(
            forSetIndex: 2,
            currentInstanceSets: [],
            previousSeries: prev
        )
        XCTAssertEqual(s.anchorLb, 35)
    }

    func testNegativeAnchor_Clamps_ToZero() {
        // Pathological: last current 5, history delta -10 -> -5. Should clamp to 0.
        let prev = [mkSet(order: 1, weight: 20), mkSet(order: 2, weight: 10)]
        let curr = [mkSet(order: 1, weight: 5)]
        let s = SetSuggestionEngine.suggestion(
            forSetIndex: 2,
            currentInstanceSets: curr,
            previousSeries: prev
        )
        XCTAssertEqual(s.anchorLb, 0)
        // Options filter out negatives, so [-5, 0, 5] over 0 -> [0, 5].
        XCTAssertEqual(s.options, [0, 5])
    }

    // MARK: - Captions sanity

    func testCaption_PreviousFirstSet() {
        let s = SetSuggestion(source: .previousFirstSet(lb: 30), anchorLb: 30, offsets: [-5, 0, 5])
        XCTAssertTrue(s.caption.contains("30"))
        XCTAssertTrue(s.caption.contains("started"))
    }

    func testCaption_ProjectedDelta_Positive() {
        let s = SetSuggestion(
            source: .projectedDelta(lastCurrentLb: 25, deltaFromHistory: 5),
            anchorLb: 30, offsets: [-5, 0, 5])
        XCTAssertTrue(s.caption.contains("+5"))
    }

    func testCaption_FreeEntry() {
        let s = SetSuggestion(source: .freeEntry, anchorLb: nil, offsets: [])
        XCTAssertTrue(s.caption.lowercased().contains("first time"))
    }
}
