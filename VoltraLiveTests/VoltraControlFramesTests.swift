// VoltraControlFramesTests.swift
// Verifies the Swift port of VoltraControlFrames + VoltraFrameBuilder against
// the same 17 byte vectors that the Apache-2.0 Kotlin reference uses (which
// were themselves cracked from official iOS PacketLogger captures).
//
// If any of these fail, the BLE writes will not be byte-identical to what the
// firmware expects — fix the codec before shipping.

import XCTest
@testable import VoltraLive

final class VoltraControlFramesTests: XCTestCase {

    // MARK: Inner payloads

    func testSetBaseWeight5Inner() throws {
        XCTAssertEqual(try VoltraControlFrames.setBaseWeightPayload(5).hexString, "0100863e0500")
    }

    func testSetChainsWeight30Inner() throws {
        XCTAssertEqual(try VoltraControlFrames.setChainsWeightPayload(30).hexString, "0100873e1e00")
    }

    func testSetEccentricWeightNegative20Inner() throws {
        XCTAssertEqual(try VoltraControlFrames.setEccentricWeightPayload(-20).hexString, "0100883eecff")
    }

    func testSetInverseChainsTrueInner() {
        XCTAssertEqual(VoltraControlFrames.setInverseChainsPayload(true).hexString, "0100b05301")
    }

    func testSetDamperLevel5Inner() throws {
        XCTAssertEqual(try VoltraControlFrames.setDamperLevelPayload(5).hexString, "0100035105")
    }

    func testSetResistanceBandMaxForce100Inner() throws {
        XCTAssertEqual(try VoltraControlFrames.setResistanceBandMaxForcePayload(100).hexString, "010062536400")
    }

    // MARK: Frame envelope — verified against captured iPad frames

    func testEnterWeightTrainingFrame() {
        let frame = VoltraFrameBuilder.build(
            cmd: VoltraControlFrames.CMD_PARAM_WRITE,
            payload: VoltraControlFrames.enterWeightTrainingPayload(),
            seq: 0x13
        )
        XCTAssertEqual(frame.hexString.uppercased(),
                       "551204C7AA1013002000110100B04F012ED4")
    }

    func testExitWeightTrainingFrame() {
        let frame = VoltraFrameBuilder.build(
            cmd: VoltraControlFrames.CMD_PARAM_WRITE,
            payload: VoltraControlFrames.exitWeightTrainingPayload(),
            seq: 0x14
        )
        XCTAssertEqual(frame.hexString.uppercased(),
                       "551204C7AA1014002000110100B04F005201")
    }

    func testFivePoundBaseWeightFrame() throws {
        let frame = VoltraFrameBuilder.build(
            cmd: VoltraControlFrames.CMD_PARAM_WRITE,
            payload: try VoltraControlFrames.setBaseWeightPayload(5),
            seq: 0x14
        )
        XCTAssertEqual(frame.hexString.uppercased(),
                       "55130403AA1014002000110100863E05005A6A")
    }

    func testTenPoundBaseWeightFrame() throws {
        let frame = VoltraFrameBuilder.build(
            cmd: VoltraControlFrames.CMD_PARAM_WRITE,
            payload: try VoltraControlFrames.setBaseWeightPayload(10),
            seq: 0x22
        )
        XCTAssertEqual(frame.hexString.uppercased(),
                       "55130403AA1022002000110100863E0A002A8F")
    }

    func testThirtyPoundChainsFrame() throws {
        let frame = VoltraFrameBuilder.build(
            cmd: VoltraControlFrames.CMD_PARAM_WRITE,
            payload: try VoltraControlFrames.setChainsWeightPayload(30),
            seq: 0x20
        )
        XCTAssertEqual(frame.hexString.uppercased(),
                       "55130403AA1020002000110100873E1E0042CA")
    }

    func testNegativeTwentyPoundEccentricFrame() throws {
        let frame = VoltraFrameBuilder.build(
            cmd: VoltraControlFrames.CMD_PARAM_WRITE,
            payload: try VoltraControlFrames.setEccentricWeightPayload(-20),
            seq: 0x23
        )
        XCTAssertEqual(frame.hexString.uppercased(),
                       "55130403AA1023002000110100883EECFFC8C6")
    }

    func testInverseChainsOffFrame() {
        let frame = VoltraFrameBuilder.build(
            cmd: VoltraControlFrames.CMD_PARAM_WRITE,
            payload: VoltraControlFrames.setInverseChainsPayload(false),
            seq: 0x27
        )
        XCTAssertEqual(frame.hexString.uppercased(),
                       "551204C7AA1027002000110100B05300ED37")
    }

    // MARK: Range guards

    func testBaseWeightOutOfRangeThrows() {
        XCTAssertThrowsError(try VoltraControlFrames.setBaseWeightPayload(0))
        XCTAssertThrowsError(try VoltraControlFrames.setBaseWeightPayload(201))
    }

    func testEccentricSignedRoundtrip() throws {
        XCTAssertEqual(try VoltraControlFrames.setEccentricWeightPayload(0).hexString,
                       "0100883e0000")
        XCTAssertEqual(try VoltraControlFrames.setEccentricWeightPayload(50).hexString,
                       "0100883e3200")
        XCTAssertEqual(try VoltraControlFrames.setEccentricWeightPayload(-1).hexString,
                       "0100883effff")
    }
}
