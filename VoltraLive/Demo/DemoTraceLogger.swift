// DemoTraceLogger.swift
// v0.4.6.3 / build 26
//
// Captures a structured, replay-friendly JSON trace of everything the user
// did during a Demo Mode session: nav events, button taps, telemetry packets,
// drop-set state transitions, errors. The whole thing is shipped to the
// developer (via DemoTraceUploader) when the user taps "Send to Developer"
// at session end.
//
// Schema design notes:
//
//   • Single flat array of `TraceRecord`. Each record has a relative-time
//     `tMs` field (ms since session start) so playback / charting tools
//     don't need to align on wall clock.
//   • Telemetry frames are subsampled to one every 100 ms (10 Hz) to keep
//     the trace file under a few hundred KB even for 30-minute sessions.
//     Force/rep/phase transitions are still captured at full fidelity via
//     `phaseTransition` events.
//   • Build version is captured at session start so I can see exactly
//     which binary produced the trace.
//
// Privacy: traces are all-local until the user explicitly taps Send. The
// upload path goes through a Cloudflare Worker → GitHub Issues so no API
// token ever ships in the binary.

import Foundation

@MainActor
final class DemoTraceLogger: ObservableObject {

    // MARK: - Event taxonomy

    enum Event: Codable {
        case sessionStart(source: DemoEntrySource)
        case sessionEnd

        // UI / nav
        case navTo(screen: String)
        case buttonTap(label: String, screen: String)
        case settingsToggle(key: String, value: Bool)

        // Workout / drop-set state machine
        case dropSetStarted(startingLb: Double)
        case dropSetCascadeFired(tier: Int, fromLb: Double, toLb: Double)
        case dropSetCancelled(reason: String)
        case dropSetFinalized(snapshotCount: Int)
        case setLogged(exercise: String, weightLb: Double, reps: Int)

        // Pairing
        case pairingStateChanged(state: String, detail: String?)

        // Catch-all for things I haven't bothered to type yet
        case note(message: String, context: [String: String])
    }

    /// One row in the trace timeline. We store the event payload as a
    /// dictionary because Swift's enum-with-associated-values Codable
    /// support produces ugly tagged-union JSON; a flat dict reads cleanly
    /// in GitHub issue bodies and is easy to grep.
    struct TraceRecord: Codable {
        let tMs: Int
        let kind: String
        let payload: [String: AnyCodable]
    }

    // MARK: - Header

    /// Static metadata captured at session start.
    struct Header: Codable {
        let traceVersion: Int
        let appShort: String
        let appBuild: String
        let entrySource: String
        let startedAtIso: String
        let device: String
        let osVersion: String
    }

    // MARK: - State

    let header: Header
    private(set) var records: [TraceRecord] = []
    private let startEpoch = Date()

    /// Last time we emitted a periodic telemetry sample. Subsamples to 10 Hz.
    private var lastTelemetryEmit: Date = .distantPast

    /// Last seen phase, used to emit phaseTransition events at full fidelity
    /// even though raw telemetry frames are subsampled.
    private var lastPhase: VoltraPhase? = nil

    /// Counters for a session-end summary.
    private(set) var totalEvents: Int = 0
    private(set) var droppedTelemetryFrames: Int = 0

    /// Set true on `finalize()` so callers can't keep mutating after the
    /// trace has been packaged for upload.
    private(set) var isFinalized = false

    // MARK: - Init

    init(entrySource: DemoEntrySource) {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        #if canImport(UIKit)
        let osVer = ProcessInfo.processInfo.operatingSystemVersionString
        let device = "iOS"
        #else
        let osVer = ProcessInfo.processInfo.operatingSystemVersionString
        let device = "unknown"
        #endif

        self.header = Header(
            traceVersion: 1,
            appShort: short,
            appBuild: build,
            entrySource: entrySource.rawValue,
            startedAtIso: iso.string(from: Date()),
            device: device,
            osVersion: osVer
        )
    }

    // MARK: - Recording

    func recordEvent(_ event: Event) {
        guard !isFinalized else { return }
        let (kind, payload) = encode(event)
        records.append(TraceRecord(
            tMs: relativeMs(),
            kind: kind,
            payload: payload
        ))
        totalEvents += 1
    }

    /// Telemetry has its own path because of the 10 Hz subsampling. Phase
    /// transitions are always recorded; force samples are throttled.
    func recordTelemetry(_ t: Telemetry) {
        guard !isFinalized else { return }

        // Always record phase transitions at full fidelity.
        if let p = t.phase, p != lastPhase {
            lastPhase = p
            recordEvent(.note(message: "phase", context: [
                "phase": p.rawValue,
                "forceLb": String(format: "%.1f", t.forceLb ?? 0),
                "repCount": String(t.repCount ?? 0)
            ]))
        }

        // Subsample raw force frames to 10 Hz.
        let now = Date()
        if now.timeIntervalSince(lastTelemetryEmit) >= 0.1 {
            lastTelemetryEmit = now
            var ctx: [String: String] = [:]
            if let f = t.forceLb { ctx["forceLb"] = String(format: "%.1f", f) }
            if let r = t.repCount { ctx["repCount"] = String(r) }
            if let s = t.setCount { ctx["setCount"] = String(s) }
            if let p = t.phase { ctx["phase"] = p.rawValue }
            if let b = t.batteryPercent { ctx["batt"] = String(b) }
            recordEvent(.note(message: "telemetry", context: ctx))
        } else {
            droppedTelemetryFrames += 1
        }
    }

    // MARK: - Finalize / serialize

    func finalize() {
        guard !isFinalized else { return }
        recordEvent(.note(message: "summary", context: [
            "totalEvents": String(totalEvents),
            "subsampledTelemetryFrames": String(droppedTelemetryFrames),
            "durationMs": String(relativeMs())
        ]))
        isFinalized = true
    }

    /// Serialize the trace to pretty JSON suitable for an issue body.
    /// Returns nil if encoding fails (shouldn't happen with our types).
    func encodedJSON() -> Data? {
        struct TraceFile: Codable {
            let header: Header
            let records: [TraceRecord]
        }
        let file = TraceFile(header: header, records: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(file)
    }

    /// Convenience: returns the trace as a string for inlining in an
    /// issue body.
    func encodedJSONString() -> String {
        guard let d = encodedJSON(), let s = String(data: d, encoding: .utf8) else {
            return "{\"error\":\"failed to encode trace\"}"
        }
        return s
    }

    // MARK: - Helpers

    private func relativeMs() -> Int {
        Int(Date().timeIntervalSince(startEpoch) * 1000)
    }

    /// Encode a typed `Event` to (kind, payload-dict). Keeps the on-disk
    /// JSON readable and grep-friendly.
    private func encode(_ event: Event) -> (String, [String: AnyCodable]) {
        switch event {
        case .sessionStart(let source):
            return ("sessionStart", ["source": .init(source.rawValue)])
        case .sessionEnd:
            return ("sessionEnd", [:])
        case .navTo(let screen):
            return ("navTo", ["screen": .init(screen)])
        case .buttonTap(let label, let screen):
            return ("buttonTap", ["label": .init(label), "screen": .init(screen)])
        case .settingsToggle(let key, let value):
            return ("settingsToggle", ["key": .init(key), "value": .init(value)])
        case .dropSetStarted(let startingLb):
            return ("dropSetStarted", ["startingLb": .init(startingLb)])
        case .dropSetCascadeFired(let tier, let fromLb, let toLb):
            return ("dropSetCascadeFired", [
                "tier": .init(tier),
                "fromLb": .init(fromLb),
                "toLb": .init(toLb)
            ])
        case .dropSetCancelled(let reason):
            return ("dropSetCancelled", ["reason": .init(reason)])
        case .dropSetFinalized(let snapshotCount):
            return ("dropSetFinalized", ["snapshotCount": .init(snapshotCount)])
        case .setLogged(let exercise, let weightLb, let reps):
            return ("setLogged", [
                "exercise": .init(exercise),
                "weightLb": .init(weightLb),
                "reps": .init(reps)
            ])
        case .pairingStateChanged(let state, let detail):
            var p: [String: AnyCodable] = ["state": .init(state)]
            if let detail { p["detail"] = .init(detail) }
            return ("pairingStateChanged", p)
        case .note(let message, let context):
            var p: [String: AnyCodable] = ["message": .init(message)]
            for (k, v) in context { p[k] = .init(v) }
            return ("note", p)
        }
    }
}

// MARK: - AnyCodable

/// Minimal JSON-compatible value type. Trace events have heterogeneous
/// payloads (strings, numbers, bools) so we pick a small lowest-common-
/// denominator type instead of pulling in Foundation's JSONSerialization
/// untyped Any path or a 3rd-party dependency.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }
    init(_ value: String) { self.value = value }
    init(_ value: Int) { self.value = value }
    init(_ value: Double) { self.value = value }
    init(_ value: Bool) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self.value = s }
        else if let i = try? c.decode(Int.self) { self.value = i }
        else if let d = try? c.decode(Double.self) { self.value = d }
        else if let b = try? c.decode(Bool.self) { self.value = b }
        else { self.value = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let s as String: try c.encode(s)
        case let i as Int:    try c.encode(i)
        case let d as Double: try c.encode(d)
        case let b as Bool:   try c.encode(b)
        default:              try c.encodeNil()
        }
    }
}
