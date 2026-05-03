// VoltraBLEFrameDecoderTests.swift
// Telemetry v2 — first slice. Verifies the additive frame decoder
// recognizes `86 3E XX YY` as a base-weight confirmation and routes
// source attribution correctly through `PendingWriteTracker`.
//
// The byte vectors below come from `VoltraControlFramesTests` (the
// 17-frame iPad capture cracked by the Apache-2.0 reference). The
// device's confirmation re-uses the same param-id + value layout the
// app emits, so feeding outbound frames through the decoder is a
// faithful stand-in for the `863e5f`, `863e14`, `863e0f` samples
// observed during May-2026 hardware verification.

import XCTest
@testable import VoltraLive

final class VoltraBLEFrameDecoderTests: XCTestCase {

    // MARK: - Helpers

    /// Build the same 0x55-framed envelope the device produces for a
    /// base-weight confirmation. Reuses the writer-side builder; the
    /// decoder doesn't care which direction the frame travels.
    private func baseWeightFrame(lb: Int, seq: UInt16 = 0x14) throws -> Data {
        try VoltraFrameBuilder.build(
            cmd: VoltraControlFrames.CMD_PARAM_WRITE,
            payload: VoltraControlFrames.setBaseWeightPayload(lb),
            seq: seq
        )
    }

    // MARK: - Pattern matching (golden)

    func testDecodesBaseWeight5() throws {
        let decoder = VoltraBLEFrameDecoder()
        let events = decoder.decode(try baseWeightFrame(lb: 5))
        XCTAssertEqual(events.count, 1)
        guard case let .stateConfirmation(field, lb, source, _) = events[0] else {
            return XCTFail("expected stateConfirmation, got \(events[0])")
        }
        XCTAssertEqual(field, .baseWeight)
        XCTAssertEqual(lb, 5)
        // No pending write registered → unsolicited.
        XCTAssertEqual(source, .deviceUnsolicited)
    }

    func testDecodesBaseWeight15_observed() throws {
        // 0x0F == 15 lb (matches `86 3e 0f` field-observation).
        let decoder = VoltraBLEFrameDecoder()
        let events = decoder.decode(try baseWeightFrame(lb: 15))
        guard case let .stateConfirmation(_, lb, _, _) = events.first else {
            return XCTFail("no decode")
        }
        XCTAssertEqual(lb, 15)
    }

    func testDecodesBaseWeight20_observed() throws {
        // 0x14 == 20 lb (matches `86 3e 14`).
        let decoder = VoltraBLEFrameDecoder()
        let events = decoder.decode(try baseWeightFrame(lb: 20))
        guard case let .stateConfirmation(_, lb, _, _) = events.first else {
            return XCTFail("no decode")
        }
        XCTAssertEqual(lb, 20)
    }

    func testDecodesBaseWeight95_observed() throws {
        // 0x5F == 95 lb (matches `86 3e 5f`).
        let decoder = VoltraBLEFrameDecoder()
        let events = decoder.decode(try baseWeightFrame(lb: 95))
        guard case let .stateConfirmation(_, lb, _, _) = events.first else {
            return XCTFail("no decode")
        }
        XCTAssertEqual(lb, 95)
    }

    // MARK: - Source attribution

    func testAppRequestConfirmedWhenPendingMatches() throws {
        let decoder = VoltraBLEFrameDecoder()
        decoder.pendingTracker.record(field: .baseWeight, lb: 50)
        let events = decoder.decode(try baseWeightFrame(lb: 50))
        guard case let .stateConfirmation(_, _, source, _) = events.first else {
            return XCTFail("no decode")
        }
        XCTAssertEqual(source, .appRequestConfirmed)
        // Pending entry must be consumed (not left around for next frame).
        XCTAssertTrue(decoder.pendingTracker.snapshot.isEmpty)
    }

    func testDeviceUnsolicitedWhenValueMismatches() throws {
        let decoder = VoltraBLEFrameDecoder()
        decoder.pendingTracker.record(field: .baseWeight, lb: 50)
        // Device confirms a DIFFERENT value than what we asked for —
        // user is overriding from the machine. Don't consume the
        // pending entry; classify as unsolicited.
        let events = decoder.decode(try baseWeightFrame(lb: 75))
        guard case let .stateConfirmation(_, lb, source, _) = events.first else {
            return XCTFail("no decode")
        }
        XCTAssertEqual(lb, 75)
        XCTAssertEqual(source, .deviceUnsolicited)
        XCTAssertEqual(decoder.pendingTracker.snapshot.count, 1)
    }

    func testPendingExpiresAndFallsBackToUnsolicited() throws {
        let decoder = VoltraBLEFrameDecoder(
            pending: PendingWriteTracker(defaultTimeout: -1) // already-expired
        )
        decoder.pendingTracker.record(field: .baseWeight, lb: 60)
        let events = decoder.decode(try baseWeightFrame(lb: 60))
        guard case let .stateConfirmation(_, _, source, _) = events.first else {
            return XCTFail("no decode")
        }
        XCTAssertEqual(source, .deviceUnsolicited)
    }

    // MARK: - Pass-through for unknown frames

    func testUnknownFrameProducesCandidateNotError() {
        let decoder = VoltraBLEFrameDecoder()
        // Random payload that doesn't contain the param-id token.
        let frame = Data([0x55, 0x10, 0x04, 0xFF, 0xAA, 0x10, 0x00, 0x00,
                          0x20, 0x00, 0x55, 0x01, 0x02, 0x03, 0x04, 0x05])
        let events = decoder.decode(frame)
        XCTAssertEqual(events.count, 1)
        guard case .candidate = events[0] else {
            return XCTFail("expected candidate, got \(events[0])")
        }
    }

    // MARK: - Reducer

    func testReducerRecordsTransitionFromNil() {
        let event: VoltraDecodedEvent = .stateConfirmation(
            field: .baseWeight, lb: 95,
            source: .deviceUnsolicited, rawHex: "deadbeef"
        )
        let r = DeviceStateReducer.apply(event, to: .empty)
        XCTAssertEqual(r.newState.baseWeightLb?.value, 95)
        XCTAssertEqual(r.change?.field, .baseWeight)
        XCTAssertNil(r.change?.from)
        XCTAssertEqual(r.change?.to, 95)
    }

    func testReducerIsIdempotentForRepeatedValue() {
        let event: VoltraDecodedEvent = .stateConfirmation(
            field: .baseWeight, lb: 95,
            source: .deviceUnsolicited, rawHex: "deadbeef"
        )
        let first  = DeviceStateReducer.apply(event, to: .empty)
        let second = DeviceStateReducer.apply(event, to: first.newState)
        XCTAssertNotNil(first.change)
        XCTAssertNil(second.change, "second confirmation of same value must NOT emit a change")
        XCTAssertEqual(second.newState, first.newState)
    }

    func testReducerEmitsFromToOnRealTransition() {
        let e1: VoltraDecodedEvent = .stateConfirmation(
            field: .baseWeight, lb: 50,
            source: .appRequestConfirmed, rawHex: "aa")
        let e2: VoltraDecodedEvent = .stateConfirmation(
            field: .baseWeight, lb: 75,
            source: .deviceUnsolicited, rawHex: "bb")
        let s1 = DeviceStateReducer.apply(e1, to: .empty).newState
        let r2 = DeviceStateReducer.apply(e2, to: s1)
        XCTAssertEqual(r2.change?.from, 50)
        XCTAssertEqual(r2.change?.to, 75)
        XCTAssertEqual(r2.change?.source, .deviceUnsolicited)
    }

    func testReducerIgnoresCandidateEvents() {
        let event: VoltraDecodedEvent = .candidate(rawHex: "ff", prefix: "ff")
        let r = DeviceStateReducer.apply(event, to: .empty)
        XCTAssertNil(r.change)
        XCTAssertEqual(r.newState, .empty)
    }
}
