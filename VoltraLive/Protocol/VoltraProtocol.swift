// VoltraProtocol.swift
// VOLTRA BLE protocol constants — Swift port of voltra-protocol.js
// Source: github.com/dylanmaniatakes/Beyond-Power-Voltra-Android (Apache-licensed reverse engineering)
// All UUIDs, frame format, command IDs, and telemetry offsets mirror the JS reference exactly.

import Foundation
import CoreBluetooth

// MARK: - UUIDs

enum VoltraUUID {
    static let service    = CBUUID(string: "e4dada34-0867-8783-9f70-2ca29216c7e4")
    static let cmdChar    = CBUUID(string: "55ca1e52-7354-25de-6afc-b7df1e8816ac")  // command + notify (responses)
    static let notifyChar = CBUUID(string: "ca94658c-0525-5046-e78b-5391b65f47ad")  // notify
    static let transport  = CBUUID(string: "a010891d-f50f-44f0-901f-9a2421a9e050")  // read/write/notify — bootstrap writes go here
    static let justWrite  = CBUUID(string: "19de84ed-0a69-482c-a8a6-c75cb5bb4389")  // write-no-response
}

// MARK: - Bootstrap Writes
// Read-only handshake captures from the official iPad app.
// These prevent the VOLTRA from disconnecting after ~5s with status 19.
// We do NOT send any control writes (load/unload/mode change) — read-only.

let BOOTSTRAP_WRITES: [Data] = [
    // commonHandshake (app hello, contains ASCII "iPad")
    Data(hex: "552904c90110000020004f69506164000000000000000000000000000000000084ab1a5f292001ea4f")!,
    // commonConnectRequest candidate
    Data(hex: "550f0801aad200002000ff00aa0419")!,
    // handshake-finish/check candidate
    Data(hex: "551f044eaa10000020002781105eab9ef41c864ff5877a9c8c1d5f0d603e86")!,
    // common state read
    Data(hex: "550d0433aa10000020007403bc")!,
    // firmware/serial/activation/security reads
    Data(hex: "550e0466aa100100200077003889")!,
    Data(hex: "550e0466aa10020020007701cc94")!,
    Data(hex: "550e0466aa100300200019002b7e")!,
    Data(hex: "550e0466aa1004002000ab01ad7a")!,
    // safe battery state read (BMS_RSOC params)
    Data(hex: "55130403aa10050020000f02002d4e5d1b8e20")!,
]

// MARK: - Frame constants (mirror JS exactly)

let VOLTRA_MAGIC: UInt8               = 0x55
let HEADER_BYTES_FOR_LENGTH: Int      = 3
let MIN_FRAME_LENGTH: Int             = 13
let EXTENDED_RESPONSE_PACKET_TYPE: UInt8    = 0x09
let EXTENDED_APP_WRITE_PACKET_TYPE: UInt8   = 0x05
let EXTENDED_RESPONSE_LENGTH_OFFSET: Int    = 0x100

// MARK: - Telemetry command IDs

let CMD_TELEMETRY: UInt8    = 0xAA
let CMD_ASYNC_STATE: UInt8  = 0x10
let CMD_SERIAL_INFO: UInt8  = 0x19
let CMD_FIRMWARE_INFO: UInt8 = 0x77

// MARK: - Rep telemetry offsets

let TELEMETRY_REP_TYPE: UInt8             = 0x81
let TELEMETRY_REP_LENGTH_MARKER: UInt8    = 0x2B
let TELEMETRY_REP_PHASE_OFFSET: Int       = 2
let TELEMETRY_SET_COUNT_OFFSET: Int       = 3
let TELEMETRY_REP_COUNT_OFFSET: Int       = 4
let TELEMETRY_REP_MIN_BYTES: Int          = 6
let MAX_REASONABLE_SET_COUNT: Int         = 1000
let MAX_REASONABLE_REP_COUNT: Int         = 10000

// MARK: - Power workout live force offsets

let POWER_WORKOUT_LIVE_TYPE: UInt8            = 0x81
let POWER_WORKOUT_LIVE_LENGTH_MARKER: UInt8   = 0x2B
let POWER_WORKOUT_LIVE_MIN_BYTES: Int         = 45
let POWER_WORKOUT_LIVE_FORCE_TENTHS_LB_OFFSET: Int = 11
let POWER_WORKOUT_LIVE_TICK_OFFSET: Int       = 27
let POWER_WORKOUT_FORCE_TENTHS_PER_LB: Double = 10.0
let MAX_REASONABLE_POWER_WORKOUT_FORCE_TENTHS_LB: Int = 5000

// MARK: - Power workout rep summary offsets

let POWER_WORKOUT_REP_SUMMARY_TYPE: UInt8           = 0x82
let POWER_WORKOUT_REP_SUMMARY_LENGTH_MARKER: UInt8  = 0x3B
let POWER_WORKOUT_REP_SUMMARY_MIN_BYTES: Int         = 61

// MARK: - Power workout final summary offsets

let POWER_WORKOUT_SUMMARY_TYPE: UInt8                = 0x85
let POWER_WORKOUT_SUMMARY_LENGTH_MARKER: UInt8       = 0x5F
let POWER_WORKOUT_SUMMARY_MIN_BYTES: Int              = 97
let POWER_WORKOUT_SUMMARY_PEAK_FORCE_TENTHS_LB_OFFSET: Int    = 17
let POWER_WORKOUT_SUMMARY_PEAK_POWER_WATTS_OFFSET: Int         = 21
let POWER_WORKOUT_SUMMARY_TIME_TO_PEAK_CENTISECONDS_OFFSET: Int = 69
let MAX_REASONABLE_POWER_WORKOUT_WATTS: Int           = 5000
let MAX_REASONABLE_POWER_WORKOUT_TIME_TO_PEAK_CENTISECONDS: Int = 3000

// MARK: - Battery async-state params

let PARAM_BMS_RSOC_A: UInt16 = 0x4E2D
let PARAM_BMS_RSOC_B: UInt16 = 0x1B5D

// MARK: - Phase

enum VoltraPhase: String, Equatable {
    case idle       = "Idle"
    case pull       = "Pull"
    case transition = "Transition"
    case `return`   = "Return"

    init(raw: UInt8) {
        switch raw {
        case 1:  self = .pull
        case 2:  self = .transition
        case 3:  self = .return
        default: self = .idle
        }
    }

    var color: String {
        switch self {
        case .pull:       return "#00d4aa"
        case .return:     return "#ffb84d"
        case .transition: return "#6c8de0"
        case .idle:       return "#4a5f5b"
        }
    }
}

// MARK: - Data hex helpers

extension Data {
    /// Initialize from a hex string (spaces/colons stripped).
    init?(hex: String) {
        let compact = hex.replacingOccurrences(of: " ", with: "")
                        .replacingOccurrences(of: ":", with: "")
                        .replacingOccurrences(of: "-", with: "")
        guard compact.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(compact.count / 2)
        var idx = compact.startIndex
        while idx < compact.endIndex {
            let next = compact.index(idx, offsetBy: 2)
            guard let byte = UInt8(compact[idx..<next], radix: 16) else { return nil }
            bytes.append(byte)
            idx = next
        }
        self.init(bytes)
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Byte read helpers (mirror JS u16le / u16be / u32le)

extension [UInt8] {
    func u16le(at offset: Int) -> UInt16 {
        guard offset + 1 < count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }
    func u16be(at offset: Int) -> UInt16 {
        guard offset + 1 < count else { return 0 }
        return (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }
    func u32le(at offset: Int) -> UInt32 {
        guard offset + 3 < count else { return 0 }
        return UInt32(self[offset])
             | (UInt32(self[offset + 1]) << 8)
             | (UInt32(self[offset + 2]) << 16)
             | (UInt32(self[offset + 3]) << 24)
    }
}
