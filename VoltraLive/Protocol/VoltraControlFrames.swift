// VoltraControlFrames.swift
// Swift port of the Apache-2.0 reference implementation in
// dylanmaniatakes/Beyond-Power-Voltra-Android, file
// core/protocol/.../VoltraControlFrames.kt + VoltraFrameBuilder.kt.
//
// Builds the inner CMD_PARAM_WRITE / CMD_PARAM_READ payloads AND wraps them
// in the full 0x55-magic frame with CRC8 header + CRC16 trailer that the
// VOLTRA characteristic expects.
//
// Cracked by the reference project against 17 captured iOS app frames; this
// file is verified against the same byte vectors in VoltraControlFramesTests.
//
// IMPORTANT: this is NEW protocol code. The sacred files
// (VoltraProtocol.swift, FrameAssembler.swift, PacketParser.swift,
// TelemetryExtractor.swift) are not modified.

import Foundation

// MARK: - Errors

enum VoltraFrameError: Error, CustomStringConvertible {
    case outOfRange(field: String, min: Int, max: Int, got: Int)
    case invalidPayload(reason: String)

    var description: String {
        switch self {
        case .outOfRange(let f, let lo, let hi, let g):
            return "\(f) must be between \(lo) and \(hi), got \(g)."
        case .invalidPayload(let r):
            return "Invalid VOLTRA payload: \(r)."
        }
    }
}

// MARK: - VoltraControlFrames

enum VoltraControlFrames {

    // ── Command IDs (the byte at offset 10 of every frame) ──
    static let CMD_PARAM_READ: UInt8        = 0x0F
    static let CMD_PARAM_WRITE: UInt8       = 0x11
    static let CMD_VENDOR: UInt8            = 0xAA
    static let CMD_BULK_PARAM_WRITE: UInt8  = 0xAF
    static let CMD_SET_DEVICE_NAME: UInt8   = 0x4E
    static let CMD_READ_DEVICE_NAME: UInt8  = 0x4F

    // ── Range limits (must match Kotlin reference 1:1) ──
    static let MIN_TARGET_LB           = 5
    static let MAX_TARGET_LB           = 200
    static let MIN_EXTRA_WEIGHT_LB     = 0
    static let MAX_EXTRA_WEIGHT_LB     = 200
    static let MIN_ECCENTRIC_WEIGHT_LB = -200
    static let MAX_ECCENTRIC_WEIGHT_LB = 200
    static let MIN_RB_FORCE_LB         = 15
    static let MAX_RB_FORCE_LB         = 200
    static let MIN_DAMPER_LEVEL        = 0
    static let MAX_DAMPER_LEVEL        = 9

    // ── Param IDs (u16, written little-endian) ──
    static let PARAM_BP_BASE_WEIGHT: UInt16        = 0x3E86
    static let PARAM_BP_CHAINS_WEIGHT: UInt16      = 0x3E87
    static let PARAM_BP_ECCENTRIC_WEIGHT: UInt16   = 0x3E88
    static let PARAM_FITNESS_WORKOUT_STATE: UInt16 = 0x4FB0
    static let PARAM_FITNESS_DAMPER_RATIO_IDX: UInt16 = 0x5103
    static let PARAM_FITNESS_INVERSE_CHAIN: UInt16 = 0x53B0
    static let PARAM_RESISTANCE_BAND_MAX_FORCE: UInt16 = 0x5362

    // ── Workout-state constants (1 byte) ──
    static let WORKOUT_STATE_INACTIVE: UInt8        = 0x00
    static let WORKOUT_STATE_ACTIVE: UInt8          = 0x01   // weight training
    static let WORKOUT_STATE_RESISTANCE_BAND: UInt8 = 0x02
    static let WORKOUT_STATE_DAMPER: UInt8          = 0x04

    // MARK: Payload builders (CMD_PARAM_WRITE inner bytes)

    /// Inner payload for the strength target weight (lb).
    static func setBaseWeightPayload(_ lb: Int) throws -> Data {
        try requireRange("Target load", lb, MIN_TARGET_LB, MAX_TARGET_LB)
        return paramWritePayload(PARAM_BP_BASE_WEIGHT, uint16Le(lb))
    }

    /// Inner payload for chains weight (lb). Range 0..200.
    static func setChainsWeightPayload(_ lb: Int) throws -> Data {
        try requireRange("Chains load", lb, MIN_EXTRA_WEIGHT_LB, MAX_EXTRA_WEIGHT_LB)
        return paramWritePayload(PARAM_BP_CHAINS_WEIGHT, uint16Le(lb))
    }

    /// Inner payload for eccentric overload (lb). Signed -200..+200.
    static func setEccentricWeightPayload(_ lb: Int) throws -> Data {
        try requireRange("Eccentric load", lb, MIN_ECCENTRIC_WEIGHT_LB, MAX_ECCENTRIC_WEIGHT_LB)
        return paramWritePayload(PARAM_BP_ECCENTRIC_WEIGHT, int16Le(lb))
    }

    /// Inner payload toggling the inverse-chains flag.
    static func setInverseChainsPayload(_ enabled: Bool) -> Data {
        paramWritePayload(PARAM_FITNESS_INVERSE_CHAIN, Data([enabled ? 1 : 0]))
    }

    /// Inner payload for damper-ratio index 0..9.
    static func setDamperLevelPayload(_ level: Int) throws -> Data {
        try requireRange("Damper level", level, MIN_DAMPER_LEVEL, MAX_DAMPER_LEVEL)
        return paramWritePayload(PARAM_FITNESS_DAMPER_RATIO_IDX, Data([UInt8(level)]))
    }

    /// Inner payload for resistance-band max force (lb). 15..200.
    static func setResistanceBandMaxForcePayload(_ lb: Int) throws -> Data {
        try requireRange("Resistance Band force", lb, MIN_RB_FORCE_LB, MAX_RB_FORCE_LB)
        return paramWritePayload(PARAM_RESISTANCE_BAND_MAX_FORCE, uint16Le(lb))
    }

    // ── Workout-state mode switches ──

    static func enterWeightTrainingPayload() -> Data {
        paramWritePayload(PARAM_FITNESS_WORKOUT_STATE, Data([WORKOUT_STATE_ACTIVE]))
    }

    static func exitWeightTrainingPayload() -> Data {
        paramWritePayload(PARAM_FITNESS_WORKOUT_STATE, Data([WORKOUT_STATE_INACTIVE]))
    }

    static func enterResistanceBandPayload() -> Data {
        paramWritePayload(PARAM_FITNESS_WORKOUT_STATE, Data([WORKOUT_STATE_RESISTANCE_BAND]))
    }

    static func enterDamperPayload() -> Data {
        paramWritePayload(PARAM_FITNESS_WORKOUT_STATE, Data([WORKOUT_STATE_DAMPER]))
    }

    // MARK: Generic builders

    /// `[01 00 paramLo paramHi <value...>]` — exact wire format the device
    /// expects after a CMD_PARAM_WRITE command byte.
    static func paramWritePayload(_ paramId: UInt16, _ value: Data) -> Data {
        var out = Data(capacity: 4 + value.count)
        out.append(0x01)
        out.append(0x00)
        out.append(UInt8(paramId & 0xFF))
        out.append(UInt8((paramId >> 8) & 0xFF))
        out.append(value)
        return out
    }

    // MARK: Encoding helpers

    static func uint16Le(_ v: Int) -> Data {
        let u = UInt16(truncatingIfNeeded: v)
        return Data([UInt8(u & 0xFF), UInt8((u >> 8) & 0xFF)])
    }

    /// Signed int16 little-endian (two's complement). -20 → `EC FF`.
    static func int16Le(_ v: Int) -> Data {
        let u = UInt16(bitPattern: Int16(v))
        return Data([UInt8(u & 0xFF), UInt8((u >> 8) & 0xFF)])
    }

    private static func requireRange(_ field: String, _ v: Int, _ lo: Int, _ hi: Int) throws {
        if v < lo || v > hi {
            throw VoltraFrameError.outOfRange(field: field, min: lo, max: hi, got: v)
        }
    }
}

// MARK: - VoltraFrameBuilder

/// Wraps a CMD/payload pair into a complete 0x55-framed BLE write.
///
/// Frame layout (verified against 17 captured iOS frames):
///   [55][len][type][crc8][sender][receiver][seq_lo][seq_hi]
///   [proto_lo][proto_hi][cmd][payload...][crc16_lo][crc16_hi]
///
/// CRC8: poly 0x31, init 0xEE, reflect_in/out=true, xor_out 0x00. Covers
///       the first 3 bytes [55, len, type].
/// CRC16: poly 0x1021, init 0x496C, reflect_in/out=true, xor_out 0x0000.
///        Covers the entire body excluding the trailing CRC16 bytes,
///        stored little-endian.
enum VoltraFrameBuilder {

    static let MAGIC: UInt8        = 0x55
    static let TYPE_APP_WRITE: UInt8 = 0x04
    static let TYPE_EXTENDED_APP_WRITE: UInt8 = 0x05
    static let APP_SENDER: UInt8   = 0xAA
    static let DEVICE_RECV: UInt8  = 0x10
    static let PROTO: UInt16       = 0x0020

    private static let FIXED_HEADER_BYTES = 11
    private static let CRC16_BYTES        = 2

    /// Build a complete VOLTRA frame ready to write to the transport char.
    static func build(
        cmd: UInt8,
        payload: Data,
        seq: UInt16,
        sender: UInt8 = APP_SENDER,
        receiver: UInt8 = DEVICE_RECV,
        proto: UInt16 = PROTO,
        frameType: UInt8 = TYPE_APP_WRITE
    ) -> Data {
        let totalLength = FIXED_HEADER_BYTES + payload.count + CRC16_BYTES
        let encodedLength = UInt8(totalLength & 0xFF)

        // CRC8 covers [magic, len, type].
        let crc8Val = crc8(Data([MAGIC, encodedLength, frameType]))

        var body = Data(capacity: totalLength - CRC16_BYTES)
        body.append(MAGIC)
        body.append(encodedLength)
        body.append(frameType)
        body.append(UInt8(crc8Val))
        body.append(sender)
        body.append(receiver)
        body.append(UInt8(seq & 0xFF))
        body.append(UInt8((seq >> 8) & 0xFF))
        body.append(UInt8(proto & 0xFF))
        body.append(UInt8((proto >> 8) & 0xFF))
        body.append(cmd)
        body.append(payload)

        let crc16Val = crc16(body)
        body.append(UInt8(crc16Val & 0xFF))
        body.append(UInt8((crc16Val >> 8) & 0xFF))

        return body
    }

    // MARK: CRC8 — poly 0x31, init 0xEE, reflected in/out, xor_out 0x00

    static func crc8(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xEE
        for byte in data {
            crc ^= UInt32(reflect8(byte))
            for _ in 0..<8 {
                if (crc & 0x80) != 0 {
                    crc = ((crc << 1) ^ 0x31) & 0xFF
                } else {
                    crc = (crc << 1) & 0xFF
                }
            }
        }
        return UInt32(reflect8(UInt8(crc & 0xFF)))
    }

    // MARK: CRC16 — poly 0x1021, init 0x496C, reflected in/out

    static func crc16(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0x496C
        for byte in data {
            crc ^= UInt32(reflect8(byte)) << 8
            for _ in 0..<8 {
                if (crc & 0x8000) != 0 {
                    crc = ((crc << 1) ^ 0x1021) & 0xFFFF
                } else {
                    crc = (crc << 1) & 0xFFFF
                }
            }
        }
        return reflect16(UInt16(crc & 0xFFFF))
    }

    private static func reflect8(_ value: UInt8) -> UInt8 {
        var v = value
        var r: UInt8 = 0
        for _ in 0..<8 {
            r = (r << 1) | (v & 1)
            v >>= 1
        }
        return r
    }

    private static func reflect16(_ value: UInt16) -> UInt32 {
        var v = value
        var r: UInt32 = 0
        for _ in 0..<16 {
            r = (r << 1) | UInt32(v & 1)
            v >>= 1
        }
        return r
    }
}
