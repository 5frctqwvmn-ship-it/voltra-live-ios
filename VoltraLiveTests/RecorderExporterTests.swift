// RecorderExporterTests.swift
// B74-F11 — `.txt` + `.json` export shape and round-trip.

import XCTest
@testable import VoltraLive

final class RecorderExporterTests: XCTestCase {

    // MARK: JSON

    func testJSONRoundTripPreservesEnvelopeAndEvents() throws {
        let aid = UUID()
        let events = [
            makeEvent(name: "ui.tap.start", category: .ui, actionId: aid),
            makeEvent(name: "ble.write.tx", category: .ble, actionId: aid),
            makeEvent(name: "ble.notify.rx", category: .ble, actionId: nil),
        ]
        let sessionId = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end   = Date(timeIntervalSince1970: 1_700_000_060)

        let data = try RecorderExporter.jsonData(
            sessionId: sessionId, start: start, end: end,
            events: events, appVersion: "0.4.49", build: "76")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let env = try decoder.decode(RecorderExportEnvelope.self, from: data)

        XCTAssertEqual(env.schemaVersion, 1)
        XCTAssertEqual(env.appVersion, "0.4.49")
        XCTAssertEqual(env.build, "76")
        XCTAssertEqual(env.session.id, sessionId)
        XCTAssertEqual(env.events.count, 3)
        XCTAssertEqual(env.events.map(\.name),
                       ["ui.tap.start", "ble.write.tx", "ble.notify.rx"])
        XCTAssertEqual(env.events[0].actionId, aid)
        XCTAssertNil(env.events[2].actionId)
    }

    func testJSONIncludesSchemaVersion() throws {
        let data = try RecorderExporter.jsonData(
            sessionId: UUID(), start: Date(), end: nil,
            events: [], appVersion: "v", build: "b")
        let s = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(s.contains("\"schemaVersion\""))
        XCTAssertTrue(s.contains("\"events\""))
        XCTAssertTrue(s.contains("\"session\""))
    }

    func testJSONHexValueRoundTripsThroughPrefix() throws {
        let event = makeEvent(name: "ble.write.tx", category: .ble,
                              metadata: ["frame": .hex("55AA01020304")])
        let data = try RecorderExporter.jsonData(
            sessionId: UUID(), start: nil, end: nil,
            events: [event], appVersion: "v", build: "b")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let env = try decoder.decode(RecorderExportEnvelope.self, from: data)
        XCTAssertEqual(env.events[0].metadata["frame"], .hex("55AA01020304"))
    }

    // MARK: TXT report

    func testTextReportContainsHeaderAndEvent() {
        let events = [makeEvent(name: "ui.tap.start", category: .ui)]
        let txt = RecorderExporter.textReport(
            sessionId: UUID(), start: Date(), end: nil,
            events: events, appVersion: "0.4.49", build: "76")
        XCTAssertFalse(txt.isEmpty)
        XCTAssertTrue(txt.contains("VOLTRA"))
        XCTAssertTrue(txt.contains("0.4.49"))
        XCTAssertTrue(txt.contains("build 76"))
        XCTAssertTrue(txt.contains("ui.tap.start"))
        XCTAssertTrue(txt.contains("Timeline"))
    }

    func testTextReportGroupsByActionId() {
        let aid = UUID()
        let events = [
            makeEvent(name: "ui.tap.connect", category: .ui, actionId: aid),
            makeEvent(name: "ble.write.tx",   category: .ble, actionId: aid),
            makeEvent(name: "ble.notify.rx",  category: .ble, actionId: nil),
        ]
        let txt = RecorderExporter.textReport(
            sessionId: UUID(), start: Date(), end: nil,
            events: events, appVersion: "0.4.49", build: "76")
        XCTAssertTrue(txt.contains(String(aid.uuidString.prefix(8))))
        XCTAssertTrue(txt.contains("[ambient]"),
                      "ambient (nil-actionId) section must be present")
    }

    func testTextReportIncludesGuardSection() {
        let events = [
            makeEvent(name: "guard.trip.notConnected", category: .`guard`,
                      metadata: ["reason": .string("not connected")]),
        ]
        let txt = RecorderExporter.textReport(
            sessionId: UUID(), start: Date(), end: nil,
            events: events, appVersion: "v", build: "b")
        XCTAssertTrue(txt.contains("Errors / Guards"))
        XCTAssertTrue(txt.contains("guard.trip.notConnected"))
        XCTAssertTrue(txt.contains("reason="))
    }

    func testTextReportIncludesBLETranscript() {
        let events = [
            makeEvent(name: "ble.write.tx", category: .ble,
                      ble: BLESubrecord(kind: .writeTx, peripheralId: nil,
                                        side: "left", characteristic: "A010",
                                        hex: "55AA", length: 2, rssi: nil)),
        ]
        let txt = RecorderExporter.textReport(
            sessionId: UUID(), start: Date(), end: nil,
            events: events, appVersion: "v", build: "b")
        XCTAssertTrue(txt.contains("BLE Transcript"))
        XCTAssertTrue(txt.contains("kind=writeTx"))
        XCTAssertTrue(txt.contains("hex=55AA"))
    }

    // MARK: Helpers

    private func makeEvent(name: String,
                           category: RecorderCategory,
                           actionId: UUID? = nil,
                           metadata: [String: RecorderValue] = [:],
                           ble: BLESubrecord? = nil) -> RecorderEvent {
        RecorderEvent(
            id: UUID(),
            sessionId: UUID(),
            actionId: actionId,
            timestamp: Date(),
            monotonic: 0,
            category: category,
            name: name,
            screen: nil,
            metadata: metadata,
            error: nil,
            ble: ble
        )
    }
}
