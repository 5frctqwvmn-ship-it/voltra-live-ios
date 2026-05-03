// VoltraBLEFrameDecoder.swift
// Telemetry v2 — additive frame decoder.
//
// Sits ALONGSIDE the sacred Protocol pipeline, never replacing it. The
// caller (VoltraBLEManager) hands us each assembled frame after the
// legacy `ble.notify.rx` recorder hook. We:
//
//   1. Skim the frame for any pattern in `VoltraDecodeTable`.
//   2. Decide whether the value matches a recently-issued app write
//      (→ `appRequestConfirmed`) or appears spontaneously (→
//      `deviceUnsolicited`).
//   3. Return one or more `VoltraDecodedEvent`s for the caller to feed
//      into the `DeviceState` reducer.
//
// Unknown frames produce a single `.candidate(rawHex:prefix:)` event —
// they are not errors. The whole point of this layer is to be honest
// about what we don't yet understand.
//
// Threading: the decoder itself is a pure function over its inputs,
// but `PendingWriteTracker` mutates state. Calls from VoltraBLEManager
// happen on the @MainActor (handleNotification hops there explicitly).

import Foundation

// MARK: - Pending-write tracker

/// One outbound app-issued param-write the decoder might see confirmed
/// shortly afterwards. The writer (or the BLE manager) records each
/// write here right before / right after it leaves the radio; the
/// decoder consumes from the same buffer when classifying frames.
///
/// We track by `(field, lb, deadline)` rather than by sequence number
/// because the device's confirmation does NOT carry the request's seq —
/// the param-id + value is the only thing both sides agree on.
///
/// When the same value is written twice (e.g. user taps + then -), the
/// FIFO order matters: the first matching pending entry consumes the
/// confirmation. That keeps source attribution conservative — if we
/// later see an unexpected mismatch we'll surface it as `unknownOrigin`.
struct PendingDeviceWrite: Equatable {
    let field: DeviceStateField
    let lb: Int
    let deadline: Date

    var isExpired: Bool { Date() > deadline }
}

/// FIFO buffer of recently-issued app writes. Cap is small — confirmations
/// arrive within ~200 ms typically, so a 32-deep buffer with a 2 s deadline
/// is plenty without risking false positives across stale writes.
final class PendingWriteTracker {

    private var entries: [PendingDeviceWrite] = []
    private let maxEntries: Int
    private let defaultTimeout: TimeInterval

    init(maxEntries: Int = 32, defaultTimeout: TimeInterval = 2.0) {
        self.maxEntries = maxEntries
        self.defaultTimeout = defaultTimeout
    }

    /// Record an outbound write the app just issued. Call this from the
    /// writer before/after `peripheral.writeValue(...)` — order doesn't
    /// matter; the deadline is what gates expiry.
    func record(field: DeviceStateField, lb: Int, timeout: TimeInterval? = nil) {
        prune()
        let entry = PendingDeviceWrite(
            field: field,
            lb: lb,
            deadline: Date().addingTimeInterval(timeout ?? defaultTimeout)
        )
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    /// Consume the first pending entry that matches `(field, lb)`. Returns
    /// `true` if a match was found and removed.
    @discardableResult
    func consume(field: DeviceStateField, lb: Int) -> Bool {
        prune()
        guard let idx = entries.firstIndex(where: { $0.field == field && $0.lb == lb }) else {
            return false
        }
        entries.remove(at: idx)
        return true
    }

    /// Drop expired entries. Cheap — called on every record/consume.
    private func prune() {
        let now = Date()
        entries.removeAll { $0.deadline < now }
    }

    /// Test hook.
    var snapshot: [PendingDeviceWrite] { entries }
}

// MARK: - Frame decoder

final class VoltraBLEFrameDecoder {

    private let pending: PendingWriteTracker
    private let table: [VoltraDecodePattern]

    init(pending: PendingWriteTracker = PendingWriteTracker(),
         table: [VoltraDecodePattern] = VoltraDecodeTable.all) {
        self.pending = pending
        self.table = table
    }

    /// Decode one assembled frame into zero or more events. The current
    /// pattern set produces at most one `.stateConfirmation` per frame
    /// (only base-weight is wired up); if no pattern matches we return
    /// a single `.candidate`. We never throw.
    func decode(_ frame: Data) -> [VoltraDecodedEvent] {
        for pattern in table {
            guard let valueBytes = pattern.locate(in: frame) else { continue }
            guard let lb = pattern.decodeValue(valueBytes) else { continue }
            let source: DeviceStateChangeSource =
                pending.consume(field: pattern.field, lb: lb)
                    ? .appRequestConfirmed
                    : .deviceUnsolicited
            return [.stateConfirmation(
                field: pattern.field,
                lb: lb,
                source: source,
                rawHex: frame.hexString
            )]
        }
        return [.candidate(
            rawHex: frame.hexString,
            prefix: String(frame.hexString.prefix(32))
        )]
    }

    /// Surface the pending tracker so the writer / BLE manager can
    /// register their outbound writes. Public-by-design.
    var pendingTracker: PendingWriteTracker { pending }
}
