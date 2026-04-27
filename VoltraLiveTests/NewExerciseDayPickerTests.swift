// NewExerciseDayPickerTests.swift
// v0.4.8 / build 30 — pins the contract the new-exercise day-picker UI relies on.
//
// What this pins:
//   The day-type chosen in `NewExerciseSheet`'s dropdown is the value
//   passed to `LoggingStore.createNewExercise(dayType:)`, and that value
//   becomes the created `Exercise`'s `primaryDayType` AND a member of its
//   `dayTypeTags`. This is the contract the new dropdown depends on:
//   if the user picks a day from the menu and the resulting Exercise
//   doesn't reflect it, the feature is broken.
//
// Pure-model tests \u2014 no SwiftData container needed. The Exercise init
// path is exercised directly via `createNewExercise` against a
// model-context-less LoggingStore (it no-ops the insert and returns the
// Exercise object so we can read the stamped fields).

import XCTest
@testable import VoltraLive

@MainActor
final class NewExerciseDayPickerTests: XCTestCase {

    func testCreateNewExercise_StampPrimaryDayType_FromArgument() {
        let store = LoggingStore.makeForTesting()
        let ex = store.createNewExercise(name: "Belt Squat", equipment: "Voltra", dayType: .leg)
        XCTAssertEqual(ex.primaryDayType, .leg,
                       "primaryDayType must reflect the dayType argument from the picker.")
        XCTAssertTrue(ex.dayTypeTags.contains(.leg),
                      "dayTypeTags must contain the picked dayType so the picker filter shows the new exercise.")
    }

    func testCreateNewExercise_AllDayTypes_RoundTrip() {
        // Pin every selectable case in the dropdown so a future enum-case
        // addition or rename surfaces here. .custom is included because the
        // dropdown lists it and the picker filter has a special-case branch
        // for it.
        let store = LoggingStore.makeForTesting()
        for dt in DayType.allCases {
            let ex = store.createNewExercise(
                name: "Test \(dt.rawValue)",
                equipment: "Voltra",
                dayType: dt
            )
            XCTAssertEqual(ex.primaryDayType, dt, "round-trip failed for \(dt)")
            XCTAssertTrue(ex.dayTypeTags.contains(dt),
                          "dayTypeTags missing \(dt) after createNewExercise")
        }
    }

    func testCreateNewExercise_TrimsName() {
        // The dropdown change doesn't touch trimming, but pinning here
        // catches a regression if the implementation drifts. The visible
        // name in the picker must not have stray whitespace.
        let store = LoggingStore.makeForTesting()
        let ex = store.createNewExercise(
            name: "  Cable Fly  ",
            equipment: "  Voltra  ",
            dayType: .chest
        )
        XCTAssertEqual(ex.name, "Cable Fly")
        XCTAssertEqual(ex.equipment, "Voltra")
    }
}
