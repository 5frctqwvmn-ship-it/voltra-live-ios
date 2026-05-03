// RecorderEvent.swift
// B74-F11 Session Recorder — event schema.
//
// One Codable record per logged event. Lives in `VoltraLive/Recorder/`.
//
// Spec: docs/handoff/SESSION_RECORDER_SPEC.md "Event Schema". The shape on
// disk MUST stay JSON-stable for the AI-readable `.json` export — see
// `RecorderExporter.schemaVersion`.

import Foundation

/// Top-level category for a recorded event. Names are dotted within each
/// category; see the spec's "Name Grammar" section.
enum RecorderCategory: String, Codable, Sendable, CaseIterable {
    case ui
    case nav
    case state
    case async
    case ble
    case `guard`
    case lifecycle
    case recorder
    /// Telemetry v2: authoritative device-side state changes (what the
    /// VOLTRA hardware confirmed, not what the app requested). Distinct
    /// from `.ble` (raw bytes) and `.state` (app/UI state) so semantic
    /// events stay easy to filter in the export.
    case device
}

/// Type-tagged value used in the metadata bag.
///
/// Encoded as a single JSON value (string / number / bool). Hex strings
/// are stored as `"hex:<bytes>"` so the type survives the round-trip
/// without a type tag wrapper.
enum RecorderValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case hex(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            if s.hasPrefix("hex:") {
                self = .hex(String(s.dropFirst(4)))
            } else {
                self = .string(s)
            }
            return
        }
        if let b = try? c.decode(Bool.self)   { self = .bool(b);   return }
        if let i = try? c.decode(Int64.self)  { self = .int(i);    return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "RecorderValue: unsupported JSON shape"))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v):    try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v):   try c.encode(v)
        case .hex(let v):    try c.encode("hex:\(v)")
        }
    }
}

/// Error attached to an event. `isUserVisible` distinguishes "the user saw
/// a banner" from "we logged an internal failure".
struct RecorderErrorRecord: Codable, Sendable, Equatable {
    let domain: String
    let code: Int
    let message: String
    let isUserVisible: Bool
}

/// Discriminator for the kind of BLE chokepoint event being recorded.
enum BLESubrecordKind: String, Codable, Sendable {
    case discovery
    case connect
    case disconnect
    case writeTx
    case writeAck
    case notifyRx
    case readRx
    case error
}

/// BLE-specific subrecord. `peripheralId` is the redactor's UUID-shaped
/// stand-in for the advertised name, NOT the CoreBluetooth identifier.
struct BLESubrecord: Codable, Sendable, Equatable {
    let kind: BLESubrecordKind
    let peripheralId: String?
    let side: String?
    let characteristic: String?
    let hex: String?
    let length: Int?
    let rssi: Int?
}

/// One event in the recorder timeline.
///
/// `monotonic` is `DispatchTime.now().uptimeNanoseconds` at emit time so
/// inter-event spacing is preserved across wall-clock adjustments. Wall
/// clock is in `timestamp`.
struct RecorderEvent: Codable, Identifiable, Sendable {
    let id: UUID
    let sessionId: UUID
    let actionId: UUID?
    let timestamp: Date
    let monotonic: UInt64
    let category: RecorderCategory
    let name: String
    let screen: String?
    let metadata: [String: RecorderValue]
    let error: RecorderErrorRecord?
    let ble: BLESubrecord?
}
