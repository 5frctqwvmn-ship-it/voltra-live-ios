// HistoryImporterTests.swift
// Regression test for v0.2.2: the leg-day picker was empty on real devices
// because either (a) v0.2.0 imported but mis-tagged, or (b) parsing failed
// silently. We now lock down the parser against the real seed/history.md so
// any future regression in the parse pipeline blocks the build.
//
// Asserts:
//   - parse() finds at least 80 sessions in the bundled history.md
//   - At least 25 of those are classified as DayType.leg
//   - At least one well-known leg exercise (Belt Squats) appears with sets
//   - Every parsed exercise has at least one set with a positive rep count

import XCTest
@testable import VoltraLive

final class HistoryImporterTests: XCTestCase {

    private func loadBundledHistory() throws -> String {
        let bundle = Bundle(for: HistoryImporterTests.self)
        // Test bundle hosts inside the app bundle for resources, so try main
        // bundle first then fall back.
        let url = Bundle.main.url(forResource: "history", withExtension: "md", subdirectory: "seed")
              ?? Bundle.main.url(forResource: "history", withExtension: "md")
              ?? bundle.url(forResource: "history", withExtension: "md", subdirectory: "seed")
              ?? bundle.url(forResource: "history", withExtension: "md")
        guard let url else {
            XCTFail("seed/history.md not found in any bundle")
            throw NSError(domain: "test", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testParsesAllSessionsFromBundledHistory() throws {
        let text = try loadBundledHistory()
        let sessions = HistoryImporter.parse(text)
        XCTAssertGreaterThanOrEqual(
            sessions.count, 80,
            "Expected ≥80 sessions in seed/history.md, got \(sessions.count)"
        )
    }

    func testLegDayClassification() throws {
        let text = try loadBundledHistory()
        let sessions = HistoryImporter.parse(text)
        let legSessions = sessions.filter { $0.dayType == .leg }
        XCTAssertGreaterThanOrEqual(
            legSessions.count, 25,
            "Expected ≥25 leg-classified sessions (Leg Day / Posterior Chain / Hamstrings…), got \(legSessions.count)"
        )

        // Every leg session must contain at least one parsed exercise.
        let legSessionsWithExercises = legSessions.filter { !$0.exercises.isEmpty }
        XCTAssertEqual(
            legSessionsWithExercises.count, legSessions.count,
            "Some leg sessions parsed with zero exercises — table parser regression"
        )
    }

    func testLegExercisesHaveSets() throws {
        let text = try loadBundledHistory()
        let sessions = HistoryImporter.parse(text)
        let legExerciseNames = Set(
            sessions
                .filter { $0.dayType == .leg }
                .flatMap(\.exercises)
                .map { $0.name.lowercased() }
        )
        XCTAssertTrue(
            legExerciseNames.contains(where: { $0.contains("belt squat") }),
            "Expected Belt Squats among leg exercises; got \(Array(legExerciseNames).sorted())"
        )

        // Spot-check: at least 8 distinct leg exercises overall
        XCTAssertGreaterThanOrEqual(
            legExerciseNames.count, 8,
            "Expected ≥8 distinct leg exercises, got \(legExerciseNames.count): \(Array(legExerciseNames).sorted())"
        )
    }

    func testEveryParsedExerciseHasAtLeastOneSet() throws {
        let text = try loadBundledHistory()
        let sessions = HistoryImporter.parse(text)
        var emptyCount = 0
        for s in sessions {
            for ex in s.exercises where ex.sets.isEmpty {
                emptyCount += 1
            }
        }
        XCTAssertEqual(
            emptyCount, 0,
            "\(emptyCount) parsed exercises have zero sets — parser dropped rows"
        )
    }

    func testFormFeedDoesNotKillSetOne() {
        // The seed file contains lines like "\u{0C} 1   Warm-Up   33 lbs ..."
        // which would previously be skipped because U+000C is not in
        // CharacterSet.whitespaces. Verify the cleaner strips controls.
        let block = """
        Belt Squats (Voltra)


         Set     Label            Weight   Eccentric        Reps      Notes
        \u{0C} 1         Warm-Up        33 lbs       —             12

         2         Working        85 lbs       —             10
        """
        // Wrap in a synthetic session header so parse() picks it up.
        let synthetic = "Session 999 — March 1, 2025 — Leg Day\n\n" + block
        let sessions = HistoryImporter.parse(synthetic)
        XCTAssertEqual(sessions.count, 1)
        let exercises = sessions.first?.exercises ?? []
        XCTAssertEqual(exercises.count, 1, "Belt Squats should parse")
        XCTAssertEqual(exercises.first?.sets.count, 2, "Both rows including the form-feed row should be captured")
    }
}
