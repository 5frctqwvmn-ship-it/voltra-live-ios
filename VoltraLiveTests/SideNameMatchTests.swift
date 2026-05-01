// SideNameMatchTests.swift
// B74-F1 — pin the case-insensitive substring match used to auto-pair
// the L/R buttons to a Voltra by advertised name. If a refactor changes
// the matching predicate (e.g. exact-match instead of substring, or
// case-sensitive comparison), L tap pairs the wrong device again — that
// was the user-visible bug shipped in b74. These tests stay green to
// prevent the regression.

import XCTest
@testable import VoltraLive

final class SideNameMatchTests: XCTestCase {

    // MARK: - Positive matches

    func testLeft_matchesLowercaseSubstring() {
        XCTAssertTrue(DeviceSlot.left.matchesAdvertisedName("voltra-left"))
    }

    func testLeft_matchesMixedCase() {
        XCTAssertTrue(DeviceSlot.left.matchesAdvertisedName("VOLTRA Left"))
        XCTAssertTrue(DeviceSlot.left.matchesAdvertisedName("VoltraLEFT"))
    }

    func testRight_matchesLowercaseSubstring() {
        XCTAssertTrue(DeviceSlot.right.matchesAdvertisedName("voltra-right"))
    }

    func testRight_matchesMixedCase() {
        XCTAssertTrue(DeviceSlot.right.matchesAdvertisedName("VOLTRA Right"))
        XCTAssertTrue(DeviceSlot.right.matchesAdvertisedName("VoltraRIGHT"))
    }

    func testLeft_matchesNameWithSerialSuffix() {
        // Real BLE adverts often append a short hex tail.
        XCTAssertTrue(DeviceSlot.left.matchesAdvertisedName("Voltra Left A1B2"))
    }

    // MARK: - Negative matches (this is the b74 regression)

    func testLeft_doesNotMatchRightName() {
        XCTAssertFalse(DeviceSlot.left.matchesAdvertisedName("Voltra Right"))
    }

    func testRight_doesNotMatchLeftName() {
        XCTAssertFalse(DeviceSlot.right.matchesAdvertisedName("Voltra Left"))
    }

    func testLeft_doesNotMatchUnlabeled() {
        XCTAssertFalse(DeviceSlot.left.matchesAdvertisedName("VOLTRA"))
        XCTAssertFalse(DeviceSlot.left.matchesAdvertisedName(""))
    }

    func testRight_doesNotMatchUnlabeled() {
        XCTAssertFalse(DeviceSlot.right.matchesAdvertisedName("VOLTRA"))
        XCTAssertFalse(DeviceSlot.right.matchesAdvertisedName(""))
    }

    // MARK: - Keyword surface

    func testKeywords_areLowercase() {
        XCTAssertEqual(DeviceSlot.left.advertisedNameKeyword,  "left")
        XCTAssertEqual(DeviceSlot.right.advertisedNameKeyword, "right")
    }
}
