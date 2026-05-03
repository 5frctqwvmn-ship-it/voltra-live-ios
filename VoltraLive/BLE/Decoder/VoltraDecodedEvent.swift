// VoltraDecodedEvent.swift
// Telemetry v2 — additive decoder layer.
//
// One decoded event per recognized device-side state notification (or
// hand-back of an app-requested write). The legacy 0xAA telemetry path
// in `VoltraLive/Protocol/` (FrameAssembler → PacketParser →
// TelemetryExtractor) is sacred and untouched; this layer runs alongside
// it and consumes the SAME assembled frames.
//
// Scope of this slice (b79):
//   - Base weight only (`PARAM_BP_BASE_WEIGHT = 0x3E86`).
//   - Eccentric / chains / mode / inverse-chain confirmations are wired
//     up at the table level but intentionally NOT emitted yet — see
//     docs/handoff/03_CURRENT_FEATURE_SPEC.md "Telemetry v2".
//
// Source attribution is the whole point: we need to tell the difference
// between "the device just confirmed an app write" and "the user pressed
// a button on the machine". See `Source` below.

import Foundation

/// One field of the device's authoritative state. Add cases as we learn
/// more confirmation patterns. Keeping the enum closed (no `case raw`)
/// makes downstream `switch`-exhaustiveness do its job; unknown bytes
/// surface via `VoltraDecodedEvent.candidate(rawHex:)` instead.
enum DeviceStateField: String, Codable, Sendable, Equatable {
    case baseWeight
    // Future: eccentricWeight, chainsWeight, mode, inverseChain, damperLevel, bandMaxForce
}

/// Where a confirmation came from. `appRequestConfirmed` matches a
/// recently-issued outbound write; `deviceUnsolicited` is the user
/// hitting the +/- buttons on the machine itself; `unknownOrigin` is
/// the conservative fallback when we can't tell (e.g. the pending-
/// request window expired but the value still moved).
enum DeviceStateChangeSource: String, Codable, Sendable, Equatable {
    case appRequestConfirmed
    case deviceUnsolicited
    case unknownOrigin
}

/// One event emitted by `VoltraBLEFrameDecoder.decode(_:)`. Pass-through
/// for unknown frames — they become `.candidate(rawHex:)` and never
/// produce errors. The decoder is additive; an unknown frame is not a
/// failure of the legacy pipeline.
enum VoltraDecodedEvent: Equatable {
    /// Device reported (or echoed back) a value for one state field.
    /// `lb` is in pounds; the caller's reducer decides whether the
    /// value is a real change vs. a noop.
    case stateConfirmation(field: DeviceStateField,
                           lb: Int,
                           source: DeviceStateChangeSource,
                           rawHex: String)

    /// Frame did not match any known confirmation pattern. Carried
    /// through so callers (or future tests) can audit what the
    /// firmware is sending. `prefix` is the truncated hex prefix
    /// already used by the recorder (32 chars / 16 bytes).
    case candidate(rawHex: String, prefix: String)
}
