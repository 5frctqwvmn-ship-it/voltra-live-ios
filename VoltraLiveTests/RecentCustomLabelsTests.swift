// RecentCustomLabelsTests.swift
// v0.4.8 / build 30 — inline custom-day flow.
//
// What this pins:
//   1. `recentCustomLabels()` returns [] when no modelContext is set.
//      LoggingHomeView reads this on every render of the inline custom
//      card — a crash here would brick the home screen for previews and
//      for the brief startup window before the modelContext wires in.
//   2. The pure `distinctRecentCustomLabels(from:limit:)` helper:
//        • returns distinct labels (no duplicates)
//        • preserves most-recent-first input order
//        • trims whitespace and skips empty labels
//        • respects the `limit` parameter
//        • ignores nil entries (preset days have no customLabel)
//
// We test the pure helper directly instead of standing up an in-memory
// SwiftData ModelContainer. The hosted xctest target's ModelContainer
// init hangs on the simulator (~30s+), trips the test watchdog, and
// looks like a crash. The DB-backed `recentCustomLabels()` is a thin
// wrapper that fetches sessions ordered by startedAt desc and forwards
// the labels to this helper, so testing the helper covers the contract
// LoggingHomeView relies on.

import XCTest
@testable import VoltraLive

@MainActor
final class RecentCustomLabelsTests: XCTestCase {

    // MARK: - No-context safety

    /// Without a modelContext, the helper short-circuits at the
    /// `guard let ctx` and returns []. SetLogView and LoggingHomeView
    /// both rely on this safe fallthrough during previews and during
    /// the brief startup window before VoltraLiveApp.onAppear wires
    /// the context in.
    func testRecentCustomLabels_NoModelContext_ReturnsEmpty() {
        let store = LoggingStore.makeForTesting()
        XCTAssertNil(store.modelContext, "factory leaves modelContext nil")
        XCTAssertEqual(store.recentCustomLabels(), [],
                       "no context must return [] not crash")
    }

    // MARK: - Pure helper coverage

    /// Empty input → empty result.
    func testDistinctRecentCustomLabels_Empty() {
        XCTAssertEqual(
            LoggingStore.distinctRecentCustomLabels(from: []),
            []
        )
    }

    /// Nil entries (preset days have no customLabel) are skipped.
    func testDistinctRecentCustomLabels_IgnoresNil() {
        XCTAssertEqual(
            LoggingStore.distinctRecentCustomLabels(from: [nil, nil, nil]),
            []
        )
    }

    /// Distinct: a label used 3 times appears exactly once. Order:
    /// preserves the input (most-recent-first) order of FIRST seen.
    func testDistinctRecentCustomLabels_Distinct_OrderedByMostRecent() {
        // Newest-first input as `recentCustomLabels()` would produce:
        //   t=4000 "Pull"  (newest)
        //   t=3000 "Push"
        //   t=2000 "Mobility"
        //   t=1000 "Push"  (older — should be deduped)
        let input: [String?] = ["Pull", "Push", "Mobility", "Push"]
        XCTAssertEqual(
            LoggingStore.distinctRecentCustomLabels(from: input),
            ["Pull", "Push", "Mobility"]
        )
    }

    /// Whitespace is trimmed; empty / whitespace-only labels are skipped.
    func testDistinctRecentCustomLabels_TrimsWhitespace_SkipsEmpty() {
        let input: [String?] = ["  Push  ", "", "   ", "Pull"]
        XCTAssertEqual(
            LoggingStore.distinctRecentCustomLabels(from: input),
            ["Push", "Pull"]
        )
    }

    /// `limit` parameter caps the result count even when more distinct
    /// labels exist. Default is 6; explicit smaller limit returns fewer.
    func testDistinctRecentCustomLabels_RespectsLimit() {
        let input: [String?] = ["H", "G", "F", "E", "D", "C", "B", "A"]
        XCTAssertEqual(
            LoggingStore.distinctRecentCustomLabels(from: input, limit: 3),
            ["H", "G", "F"]
        )
        XCTAssertEqual(
            LoggingStore.distinctRecentCustomLabels(from: input, limit: 6).count,
            6
        )
        XCTAssertEqual(
            LoggingStore.distinctRecentCustomLabels(from: input, limit: 100).count,
            8
        )
    }

    /// Trim+dedupe interaction: "Push" and " Push " collapse to one entry.
    func testDistinctRecentCustomLabels_TrimDedupeInteraction() {
        let input: [String?] = ["Push", "  Push  ", "Pull"]
        XCTAssertEqual(
            LoggingStore.distinctRecentCustomLabels(from: input),
            ["Push", "Pull"]
        )
    }
}
