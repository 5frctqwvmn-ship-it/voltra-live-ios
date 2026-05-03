// VoltraDecodeTable.swift
// Telemetry v2 — pattern table.
//
// The VOLTRA notify stream interleaves three classes of frame:
//   1. 0xAA real-time telemetry (force / phase / rep count) — already
//      decoded by the sacred TelemetryExtractor pipeline. We DO NOT
//      re-decode those here.
//   2. 0x11 (CMD_PARAM_WRITE) confirmations the device emits after a
//      param change — whether the change came from the app or the
//      physical buttons on the machine.
//   3. 0x0F (CMD_PARAM_READ) responses — bulk state dumps. Out of
//      scope for this slice.
//
// All confirmations carry the same inner shape as the outbound write
// (verified against `VoltraControlFramesTests` byte vectors):
//
//     [01] [00] [paramLo] [paramHi] [valueBytes...]
//
// where `paramId` is uint16 little-endian. So for base weight
// (`PARAM_BP_BASE_WEIGHT = 0x3E86`) the inner payload contains the byte
// pair `86 3E` followed by the value as uint16 LE. Observations from
// hardware verification (May 2026):
//
//     86 3E 5F 00   →  base weight 95 lb
//     86 3E 14 00   →  base weight 20 lb
//     86 3E 0F 00   →  base weight 15 lb
//
// We scan the assembled frame's bytes for the param-id token and read
// the next 2 bytes as the value. We DO NOT validate CRC here — the
// frame already came through `FrameAssembler`, which only emits frames
// that passed the legacy length check. CRC verification stays in the
// sacred Protocol pipeline.
//
// Pattern table is data, not code: adding eccentric / chains / inverse-
// chain in a follow-up is a one-line addition.

import Foundation

/// One pattern the decoder knows how to recognize.
///
/// `paramId` is the uint16 (little-endian on the wire). `field` is the
/// `DeviceStateField` we map it to. `decodeValue` reads the value
/// bytes after the param-id and returns the canonical pound value, or
/// `nil` if the bytes are out-of-range / corrupt.
struct VoltraDecodePattern {
    let paramId: UInt16
    let field: DeviceStateField
    let valueByteCount: Int
    let decodeValue: (Data) -> Int?

    /// Locate this pattern's `paramId` token (low, high) inside `bytes`
    /// and return the `valueByteCount` bytes that immediately follow.
    /// Returns `nil` if the token isn't present or the value bytes
    /// would run past the end of `bytes`.
    func locate(in bytes: Data) -> Data? {
        let lo = UInt8(paramId & 0xFF)
        let hi = UInt8((paramId >> 8) & 0xFF)
        guard bytes.count >= 2 + valueByteCount else { return nil }
        // `Data.indices` are NOT zero-based when the Data is sliced;
        // use offset arithmetic against `startIndex` so this works for
        // both fresh and sliced buffers.
        let start = bytes.startIndex
        let last = bytes.endIndex - (2 + valueByteCount)
        if last < start { return nil }
        for i in start...last {
            if bytes[i] == lo && bytes[i + 1] == hi {
                let valueStart = i + 2
                let valueEnd = valueStart + valueByteCount
                return bytes.subdata(in: valueStart..<valueEnd)
            }
        }
        return nil
    }
}

enum VoltraDecodeTable {

    /// Mirrors `VoltraControlFrames.PARAM_BP_BASE_WEIGHT`. Duplicated
    /// here intentionally so the decoder doesn't import the writer side
    /// of the protocol — the decoder is read-only.
    static let baseWeight = VoltraDecodePattern(
        paramId: 0x3E86,
        field: .baseWeight,
        valueByteCount: 2,
        decodeValue: { data in
            guard data.count == 2 else { return nil }
            // uint16 little-endian, in pounds. Range gate matches
            // VoltraControlFrames.MIN_TARGET_LB / MAX_TARGET_LB plus a
            // small slop for the unloaded sentinel (0).
            let lo = UInt16(data[data.startIndex])
            let hi = UInt16(data[data.startIndex + 1])
            let lb = Int(lo | (hi << 8))
            guard lb >= 0, lb <= 250 else { return nil }
            return lb
        }
    )

    /// All patterns the decoder recognizes in this build. Order does
    /// not matter — patterns are independent.
    static let all: [VoltraDecodePattern] = [
        baseWeight
    ]
}
