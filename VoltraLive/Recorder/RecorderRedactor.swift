// RecorderRedactor.swift
// B74-F11 Session Recorder — PII redaction rules.
//
// Spec: docs/handoff/SESSION_RECORDER_SPEC.md "Redaction".
//
// - BLE peripheral name → stable per-recorder UUID (so two events about
//   the same device share an id without exposing the raw name).
// - Free text (exercise name, custom day name, user-entered strings)
//   → `<redacted:len=N>` so structural facts (presence, length) survive
//   without leaking the content.
// - Hex / numeric / screen names / dotted event names: pass through raw.
//   These do not flow through the redactor at all — the recorder emits
//   them as `RecorderValue.hex` / `.int` / `.string` directly.
// - `unsafeRaw(_:)` is the explicit opt-in for callers that have already
//   confirmed the value is safe to log verbatim.

import Foundation

/// Per-recorder redactor. Owns the in-memory peripheral-name → UUID map
/// for the lifetime of one app launch (matches the recorder lifetime).
final class RecorderRedactor: @unchecked Sendable {
    private var peripheralTable: [String: UUID] = [:]
    private let lock = NSLock()

    init() {}

    /// Map a BLE advertised name to a stable UUID for the lifetime of this
    /// redactor. Same name in → same UUID string out.
    func redactedPeripheralId(name: String) -> String {
        lock.lock(); defer { lock.unlock() }
        if let id = peripheralTable[name] {
            return id.uuidString
        }
        let id = UUID()
        peripheralTable[name] = id
        return id.uuidString
    }

    /// Replace free text with a length-only stand-in.
    func redactedFreeText(_ text: String) -> String {
        return "<redacted:len=\(text.count)>"
    }

    /// Pass a value through unchanged. Use only after confirming the
    /// value contains no PII (e.g. hex frames, numeric counters,
    /// developer-controlled enum names).
    func unsafeRaw<T>(_ value: T) -> T { value }
}
