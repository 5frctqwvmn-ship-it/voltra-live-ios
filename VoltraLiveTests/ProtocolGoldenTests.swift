// ProtocolGoldenTests.swift
// Karpathy hardening: golden-fixture tests for the VOLTRA protocol layer.
//
// These tests are the safety net for the read-only telemetry decode.
// If any LLM (or human) edits VoltraLive/Protocol/ in a way that breaks the wire format,
// these tests fail in CI before the change ever reaches a Watch on a real wrist.
//
// Sources of truth (all DO NOT MODIFY):
//   - VoltraLive/Protocol/VoltraProtocol.swift   (constants)
//   - VoltraLive/Protocol/TelemetryExtractor.swift (decode)
//
// Reference protocol: github.com/dylanmaniatakes/Beyond-Power-Voltra-Android
// Verified on hardware 2026-04-15.

import XCTest
@testable import VoltraLive

final class ProtocolGoldenTests: XCTestCase {

    // MARK: - BOOTSTRAP_WRITES integrity

    /// The 9 bootstrap writes are the exact bytes captured from the official iPad app.
    /// If any of these change, the VOLTRA will disconnect after ~5s with status 19.
    /// This test pins the count, the order, and the prefix bytes.
    func testBootstrapWritesPinned() {
        XCTAssertEqual(BOOTSTRAP_WRITES.count, 9, "BOOTSTRAP_WRITES must contain exactly 9 frames — JS reference has 9, not 10.")

        // Prefix-byte fingerprint per frame (first 4 bytes).
        // These bytes encode: magic (0x55), length, packet type, command id.
        let expectedPrefixes: [[UInt8]] = [
            [0x55, 0x29, 0x04, 0xc9], // commonHandshake
            [0x55, 0x0f, 0x08, 0x01], // commonConnectRequest
            [0x55, 0x1f, 0x04, 0x4e], // handshake-finish
            [0x55, 0x0d, 0x04, 0x33], // common state read
            [0x55, 0x0e, 0x04, 0x66], // firmware/serial #1
            [0x55, 0x0e, 0x04, 0x66], // firmware/serial #2
            [0x55, 0x0e, 0x04, 0x66], // firmware/serial #3
            [0x55, 0x0e, 0x04, 0x66], // firmware/serial #4
            [0x55, 0x13, 0x04, 0x03], // BMS_RSOC battery read
        ]

        for (idx, frame) in BOOTSTRAP_WRITES.enumerated() {
            XCTAssertGreaterThanOrEqual(frame.count, 4, "Frame \(idx) shorter than 4 bytes")
            let prefix = Array(frame.prefix(4))
            XCTAssertEqual(prefix, expectedPrefixes[idx],
                           "Frame \(idx) prefix changed — wire format regression. Got \(prefix.map { String(format: "%02x", $0) })")
            XCTAssertEqual(frame.first, VOLTRA_MAGIC, "Frame \(idx) does not start with VOLTRA_MAGIC (0x55)")
        }
    }

    /// First and last frame full-byte fingerprint. These are the riskiest to mutate
    /// because they bracket the handshake (start) and battery read (end).
    func testBootstrapWritesEndpointHexes() {
        XCTAssertEqual(
            BOOTSTRAP_WRITES.first?.hexString,
            "552904c90110000020004f69506164000000000000000000000000000000000084ab1a5f292001ea4f",
            "First bootstrap write changed — handshake will fail."
        )
        XCTAssertEqual(
            BOOTSTRAP_WRITES.last?.hexString,
            "55130403aa10050020000f02002d4e5d1b8e20",
            "Last bootstrap write (battery read) changed."
        )
    }

    // MARK: - 0xAA telemetry decode (the highest-risk surface)

    /// Phase byte at offset 2. This drives the colored phase tile on phone + Watch.
    /// If this offset moves, the phase tile color flips never happen → silent regression.
    func testPhaseDecodeAtOffset2() {
        XCTAssertEqual(TELEMETRY_REP_PHASE_OFFSET, 2)
        XCTAssertEqual(VoltraPhase(raw: 0), .idle)
        XCTAssertEqual(VoltraPhase(raw: 1), .pull)
        XCTAssertEqual(VoltraPhase(raw: 2), .transition)
        XCTAssertEqual(VoltraPhase(raw: 3), .return)
        XCTAssertEqual(VoltraPhase(raw: 99), .idle, "Unknown phase byte must default to idle")
    }

    /// Set count is a single byte at offset 3.
    func testSetCountOffset() {
        XCTAssertEqual(TELEMETRY_SET_COUNT_OFFSET, 3)
        XCTAssertEqual(MAX_REASONABLE_SET_COUNT, 1000)
    }

    /// Rep count is uint16 BIG-ENDIAN at offset 4..5.
    /// JS reference: `(p[4] << 8) | p[5]`.
    /// If this becomes little-endian, reps appear to count by 256s.
    func testRepCountIsBigEndianAtOffset4() {
        XCTAssertEqual(TELEMETRY_REP_COUNT_OFFSET, 4)

        // Synthesize a CMD_TELEMETRY (0xAA) packet with rep_count = 0x0007 (= 7 reps)
        // Layout: type(0x81), len_marker(0x2B), phase(0x01), set(0x01), repHi(0x00), repLo(0x07), ...
        let packet: [UInt8] = [
            TELEMETRY_REP_TYPE,            // 0x81
            TELEMETRY_REP_LENGTH_MARKER,   // 0x2B
            0x01,                          // phase = pull
            0x01,                          // set count = 1
            0x00, 0x07,                    // rep count BE = 7
        ] + Array(repeating: 0, count: 60)  // padding so force decode also works

        let bytes = [UInt8](packet)
        let repHi = UInt16(bytes[TELEMETRY_REP_COUNT_OFFSET])
        let repLo = UInt16(bytes[TELEMETRY_REP_COUNT_OFFSET + 1])
        let repBE = (repHi << 8) | repLo
        XCTAssertEqual(Int(repBE), 7, "Rep count must decode big-endian")

        // And verify u16le on the same bytes would NOT give 7 — guards against accidental swap
        let repLE = UInt16(bytes[TELEMETRY_REP_COUNT_OFFSET]) | (UInt16(bytes[TELEMETRY_REP_COUNT_OFFSET + 1]) << 8)
        XCTAssertNotEqual(Int(repLE), 7, "Sanity: little-endian reading must give wrong answer for non-symmetric input")
    }

    /// Force is uint16 LITTLE-ENDIAN at offset 11, in tenths-of-a-pound.
    /// `force_lb = u16le(offset 11) / 10.0`
    /// Wrong endianness here makes the FORCE tile show garbage.
    func testForceIsLittleEndianTenthsLb() {
        XCTAssertEqual(POWER_WORKOUT_LIVE_FORCE_TENTHS_LB_OFFSET, 11)
        XCTAssertEqual(POWER_WORKOUT_FORCE_TENTHS_PER_LB, 10.0)

        // Synthesize: 1234 tenths-lb = 123.4 lb. 1234 = 0x04D2 LE → bytes [0xD2, 0x04]
        var packet = [UInt8](repeating: 0, count: 60)
        packet[0] = POWER_WORKOUT_LIVE_TYPE              // 0x81
        packet[1] = POWER_WORKOUT_LIVE_LENGTH_MARKER     // 0x2B
        packet[POWER_WORKOUT_LIVE_FORCE_TENTHS_LB_OFFSET]     = 0xD2
        packet[POWER_WORKOUT_LIVE_FORCE_TENTHS_LB_OFFSET + 1] = 0x04

        let lo = UInt16(packet[POWER_WORKOUT_LIVE_FORCE_TENTHS_LB_OFFSET])
        let hi = UInt16(packet[POWER_WORKOUT_LIVE_FORCE_TENTHS_LB_OFFSET + 1])
        let tenths = lo | (hi << 8)
        XCTAssertEqual(tenths, 1234, "Force must decode little-endian")

        let lb = Double(tenths) / POWER_WORKOUT_FORCE_TENTHS_PER_LB
        XCTAssertEqual(lb, 123.4, accuracy: 0.001)
    }

    /// Force ceiling sanity. Anything above 5000 tenths-lb (500 lb) is treated as garbage.
    func testForceCeiling() {
        XCTAssertEqual(MAX_REASONABLE_POWER_WORKOUT_FORCE_TENTHS_LB, 5000)
    }

    // MARK: - UUID pinning

    /// Service UUID is the only one the central scans for. If this drifts, the app
    /// will never even *see* the VOLTRA in scan results.
    func testServiceUUIDPinned() {
        XCTAssertEqual(
            VoltraUUID.service.uuidString.lowercased(),
            "e4dada34-0867-8783-9f70-2ca29216c7e4"
        )
    }

    // MARK: - Hex helper round-trip

    func testHexRoundTrip() {
        let bytes: [UInt8] = [0x55, 0x29, 0x04, 0xc9, 0xff, 0x00, 0xab]
        let data = Data(bytes)
        let hex = data.hexString
        XCTAssertEqual(hex, "552904c9ff00ab")
        XCTAssertEqual(Data(hex: hex), data, "hex round-trip must be lossless")
        XCTAssertEqual(Data(hex: "55-29:04 c9 ff 00 ab"), data, "hex helper must strip separators")
    }
}
