// WorkoutGroupTests.swift
// v0.4.8 / build 30 — Group-dropdown round-trip pinning.
//
// What this pins (the four cases requested in the kickoff):
//   1. Default new session has no group (`group == nil`, `groupLabel == nil`).
//   2. Preset selection round-trips: setting `group = .push` reads back
//      `.push` and `groupLabel == "Push"`.
//   3. Custom string round-trips: a `.custom` group with a non-empty
//      `customGroupLabel` reads back through `groupLabel`.
//   4. Empty / whitespace-only custom string falls back to nil at the
//      `WorkoutSession` init level so the chip helper doesn't render a
//      blank pill, and `groupLabel` returns the preset's display name
//      ("Custom") when the label is empty.
//
// Pure-model tests — no SwiftData container needed. The optional
// `groupRaw` / `customGroupLabel` fields default to nil in the @Model
// declaration, so the SwiftData migration is additive and these tests run
// without standing up a ModelContainer.

import XCTest
@testable import VoltraLive

final class WorkoutGroupTests: XCTestCase {

    // MARK: 1. Default is nil

    func testDefault_NoGroupSet_IsNil() {
        let s = WorkoutSession()
        XCTAssertNil(s.group, "A new session must have no group by default.")
        XCTAssertNil(s.groupLabel, "groupLabel must be nil when no group is set.")
        XCTAssertNil(s.groupRaw, "Underlying groupRaw must be nil for additive migration safety.")
        XCTAssertNil(s.customGroupLabel, "customGroupLabel must be nil by default.")
    }

    func testDefault_FromInit_IsNil() {
        // Init without group/customGroupLabel arguments must also yield nil.
        let s = WorkoutSession(dayType: .leg)
        XCTAssertNil(s.group)
        XCTAssertNil(s.groupLabel)
    }

    // MARK: 2. Preset round-trip

    func testPreset_Push_RoundTrips() {
        let s = WorkoutSession(dayType: .chest, group: .push)
        XCTAssertEqual(s.group, .push)
        XCTAssertEqual(s.groupRaw, "Push")
        XCTAssertEqual(s.groupLabel, "Push")
        XCTAssertNil(s.customGroupLabel,
                     "Preset selection must not set customGroupLabel.")
    }

    func testPreset_AllPresets_RoundTrip() {
        // Pin the full set of presets so a future enum-case rename surfaces here.
        let expected: [(WorkoutGroup, String)] = [
            (.push, "Push"),
            (.pull, "Pull"),
            (.legs, "Legs"),
            (.upper, "Upper"),
            (.lower, "Lower"),
            (.fullBody, "Full Body"),
        ]
        for (g, label) in expected {
            let s = WorkoutSession(dayType: .leg, group: g)
            XCTAssertEqual(s.group, g, "round-trip failed for \(g)")
            XCTAssertEqual(s.groupLabel, label, "label mismatch for \(g)")
        }
    }

    func testPreset_SetterClearsCustomLabel() {
        // The `group` setter must clear customGroupLabel when moving away
        // from .custom so a stale custom string doesn't leak into a preset.
        let s = WorkoutSession(
            dayType: .custom,
            group: .custom,
            customGroupLabel: "Hinge"
        )
        XCTAssertEqual(s.customGroupLabel, "Hinge")
        s.group = .push
        XCTAssertEqual(s.group, .push)
        XCTAssertNil(s.customGroupLabel,
                     "Switching from .custom to a preset must clear customGroupLabel.")
    }

    // MARK: 3. Custom string round-trip

    func testCustom_NonEmpty_RoundTrips() {
        let s = WorkoutSession(
            dayType: .custom,
            group: .custom,
            customGroupLabel: "Hinge"
        )
        XCTAssertEqual(s.group, .custom)
        XCTAssertEqual(s.customGroupLabel, "Hinge")
        XCTAssertEqual(s.groupLabel, "Hinge",
                       "groupLabel must surface the custom string when group == .custom.")
    }

    func testCustom_TrimsLeadingTrailingWhitespace() {
        // The init normalizes whitespace so the chip never renders a label
        // with stray padding.
        let s = WorkoutSession(
            dayType: .custom,
            group: .custom,
            customGroupLabel: "  Conditioning  "
        )
        XCTAssertEqual(s.customGroupLabel, "Conditioning")
        XCTAssertEqual(s.groupLabel, "Conditioning")
    }

    // MARK: 4. Empty custom string falls back to nil

    func testCustom_EmptyString_NormalizesToNil() {
        // The `group` is still set to .custom (the user picked Custom\u{2026}),
        // but customGroupLabel must be nil so groupLabel falls back to the
        // preset's display name "Custom" rather than rendering a blank pill.
        let s = WorkoutSession(
            dayType: .custom,
            group: .custom,
            customGroupLabel: ""
        )
        XCTAssertEqual(s.group, .custom)
        XCTAssertNil(s.customGroupLabel,
                     "Empty customGroupLabel must normalize to nil at init.")
        XCTAssertEqual(s.groupLabel, "Custom",
                       "With nil customGroupLabel and group == .custom, groupLabel must fall back to the preset display name, not nil and not an empty string.")
    }

    func testCustom_WhitespaceOnly_NormalizesToNil() {
        let s = WorkoutSession(
            dayType: .custom,
            group: .custom,
            customGroupLabel: "   \t\n  "
        )
        XCTAssertNil(s.customGroupLabel,
                     "Whitespace-only customGroupLabel must normalize to nil.")
    }

    // MARK: Cross-cutting: chip rendering contract

    func testGroupLabel_NilWhenNoGroup_RegardlessOfCustomLabel() {
        // Defensive: even if customGroupLabel somehow holds a value (e.g. a
        // future migration scenario), groupLabel must return nil when group
        // itself is nil so the chip stays hidden.
        let s = WorkoutSession(dayType: .leg)
        s.customGroupLabel = "stale"
        XCTAssertNil(s.group)
        XCTAssertNil(s.groupLabel)
    }
}
