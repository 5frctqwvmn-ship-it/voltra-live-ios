// RecentCustomLabelsTests.swift
// v0.4.8 / build 30 — inline custom-day flow.
//
// What this pins:
//   1. `recentCustomLabels()` returns [] when no modelContext is set.
//      LoggingHomeView reads this on every render of the inline custom
//      card — a crash here would brick the home screen for previews and
//      for the brief startup window before the modelContext wires in.
//   2. With a populated context, the helper:
//        • returns distinct labels (no duplicates)
//        • orders most-recent-first (by session.startedAt desc)
//        • trims whitespace and skips empty labels
//        • respects the `limit` parameter
//        • ignores sessions whose customLabel is nil (non-custom days)
//
// These properties are the contract LoggingHomeView's inline expander
// relies on — a regression here would either retype-stuff the chip row
// or surface stale labels at the top.

import XCTest
import SwiftData
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

    // MARK: - Algorithm coverage (in-memory SwiftData)

    /// Set up an in-memory ModelContainer matching the production schema
    /// (PastSession + PastSet + LoggingSchema.models) so we can insert
    /// WorkoutSession rows and query them through LoggingStore.
    private func makeStoreWithContext() throws -> LoggingStore {
        var allModels: [any PersistentModel.Type] = [PastSession.self, PastSet.self]
        allModels.append(contentsOf: LoggingSchema.models)
        let schema = Schema(allModels)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let store = LoggingStore.makeForTesting()
        store.modelContext = container.mainContext
        return store
    }

    /// Empty store → empty result.
    func testRecentCustomLabels_EmptyStore_ReturnsEmpty() throws {
        let store = try makeStoreWithContext()
        XCTAssertEqual(store.recentCustomLabels(), [])
    }

    /// Sessions without a customLabel (the leg/back/chest/arm presets)
    /// must NOT appear in the recent-customs list.
    func testRecentCustomLabels_IgnoresPresetSessions() throws {
        let store = try makeStoreWithContext()
        let ctx = store.modelContext!
        ctx.insert(WorkoutSession(startedAt: .init(timeIntervalSince1970: 1000),
                                  dayType: .leg, customLabel: nil))
        ctx.insert(WorkoutSession(startedAt: .init(timeIntervalSince1970: 2000),
                                  dayType: .chest, customLabel: nil))
        try ctx.save()
        XCTAssertEqual(store.recentCustomLabels(), [],
                       "preset days have no customLabel and must be skipped")
    }

    /// Distinct: a label used 3 times appears exactly once. Order: by the
    /// MOST RECENT use of that label.
    func testRecentCustomLabels_Distinct_OrderedByMostRecent() throws {
        let store = try makeStoreWithContext()
        let ctx = store.modelContext!
        // "Push" used at t=1000 and t=3000 → most recent use is t=3000.
        // "Mobility" used at t=2000.
        // "Pull" used at t=4000 (newest).
        ctx.insert(WorkoutSession(startedAt: .init(timeIntervalSince1970: 1000),
                                  dayType: .custom, customLabel: "Push"))
        ctx.insert(WorkoutSession(startedAt: .init(timeIntervalSince1970: 2000),
                                  dayType: .custom, customLabel: "Mobility"))
        ctx.insert(WorkoutSession(startedAt: .init(timeIntervalSince1970: 3000),
                                  dayType: .custom, customLabel: "Push"))
        ctx.insert(WorkoutSession(startedAt: .init(timeIntervalSince1970: 4000),
                                  dayType: .custom, customLabel: "Pull"))
        try ctx.save()

        let labels = store.recentCustomLabels()
        XCTAssertEqual(labels, ["Pull", "Push", "Mobility"],
                       "distinct + ordered by latest use of each label")
    }

    /// Whitespace is trimmed; empty / whitespace-only labels are skipped.
    /// This guards against accidental empty strings sneaking in from a
    /// future caller that doesn't trim before insert.
    func testRecentCustomLabels_TrimsWhitespace_SkipsEmpty() throws {
        let store = try makeStoreWithContext()
        let ctx = store.modelContext!
        ctx.insert(WorkoutSession(startedAt: .init(timeIntervalSince1970: 1000),
                                  dayType: .custom, customLabel: "   "))
        ctx.insert(WorkoutSession(startedAt: .init(timeIntervalSince1970: 2000),
                                  dayType: .custom, customLabel: ""))
        ctx.insert(WorkoutSession(startedAt: .init(timeIntervalSince1970: 3000),
                                  dayType: .custom, customLabel: "  Push  "))
        try ctx.save()

        let labels = store.recentCustomLabels()
        XCTAssertEqual(labels, ["Push"],
                       "whitespace trimmed; empty / whitespace-only skipped")
    }

    /// `limit` parameter caps the result count even when more distinct
    /// labels exist. Default is 6; explicit smaller limit returns fewer.
    func testRecentCustomLabels_RespectsLimit() throws {
        let store = try makeStoreWithContext()
        let ctx = store.modelContext!
        for (i, label) in ["A", "B", "C", "D", "E", "F", "G", "H"].enumerated() {
            ctx.insert(WorkoutSession(
                startedAt: .init(timeIntervalSince1970: TimeInterval(1000 * (i + 1))),
                dayType: .custom,
                customLabel: label))
        }
        try ctx.save()

        XCTAssertEqual(store.recentCustomLabels(limit: 3), ["H", "G", "F"])
        XCTAssertEqual(store.recentCustomLabels(limit: 6).count, 6)
        XCTAssertEqual(store.recentCustomLabels(limit: 100).count, 8)
    }
}
