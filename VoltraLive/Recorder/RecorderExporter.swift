// RecorderExporter.swift
// B74-F11 Session Recorder — `.txt` + `.json` builders.
//
// Spec: docs/handoff/SESSION_RECORDER_SPEC.md "Export".
//
// Pure functions; no disk I/O. Persistence to
// `Application Support/SessionRecorder/last_session.json` happens in
// `SessionRecorder.persist()` which calls `jsonData(...)` and writes the
// result. The viewer's `ShareLink` calls both `jsonData` and
// `textReport` and attaches the two payloads together.

import Foundation

/// On-disk envelope for the `.json` export.
///
/// `schemaVersion` MUST be bumped for any breaking change to the event
/// shape so consumers can fail loudly on unknown versions.
struct RecorderExportEnvelope: Codable {
    let schemaVersion: Int
    let appVersion: String
    let build: String
    let session: SessionMeta
    let events: [RecorderEvent]

    struct SessionMeta: Codable {
        let id: UUID
        let start: Date?
        let end: Date?
        let timezone: String
    }
}

enum RecorderExporter {
    static let schemaVersion: Int = 1

    // MARK: JSON

    static func jsonData(sessionId: UUID,
                         start: Date?,
                         end: Date?,
                         events: [RecorderEvent],
                         appVersion: String,
                         build: String,
                         timezone: TimeZone = .current) throws -> Data {
        let envelope = RecorderExportEnvelope(
            schemaVersion: schemaVersion,
            appVersion: appVersion,
            build: build,
            session: .init(id: sessionId, start: start, end: end, timezone: timezone.identifier),
            events: events
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    // MARK: TXT (AI-readable report)

    static func textReport(sessionId: UUID,
                           start: Date?,
                           end: Date?,
                           events: [RecorderEvent],
                           appVersion: String,
                           build: String,
                           timezone: TimeZone = .current) -> String {
        var out = ""

        // Header
        out += "VOLTRA Live · Session Recorder\n"
        out += "App: \(appVersion) (build \(build))\n"
        out += "Session: \(sessionId.uuidString)\n"
        out += "Start: \(formatDate(start, in: timezone))\n"
        out += "End: \(formatDate(end, in: timezone))\n"
        out += "Timezone: \(timezone.identifier)\n"
        out += "Events: \(events.count)\n"
        out += String(repeating: "=", count: 60) + "\n\n"

        // Timeline grouped by actionId. Ambient (nil-actionId) events first,
        // then each distinct action in first-seen order.
        out += "## Timeline\n\n"
        let ambient = events.filter { $0.actionId == nil }
        if !ambient.isEmpty {
            out += "[ambient]\n"
            for e in ambient { out += format(e, in: timezone) + "\n" }
            out += "\n"
        }
        var seenActions: Set<UUID> = []
        for e in events {
            guard let aid = e.actionId, !seenActions.contains(aid) else { continue }
            seenActions.insert(aid)
            let chunk = events.filter { $0.actionId == aid }
            out += "[action \(aid.uuidString.prefix(8))] (\(chunk.count) events)\n"
            for ev in chunk { out += format(ev, in: timezone) + "\n" }
            out += "\n"
        }

        // Errors / guards subsection
        let issues = events.filter { $0.error != nil || $0.category == .`guard` }
        if !issues.isEmpty {
            out += "## Errors / Guards\n\n"
            for e in issues { out += format(e, in: timezone) + "\n" }
            out += "\n"
        }

        // BLE transcript
        let bleEvents = events.filter { $0.category == .ble || $0.ble != nil }
        if !bleEvents.isEmpty {
            out += "## BLE Transcript\n\n"
            for e in bleEvents { out += format(e, in: timezone) + "\n" }
            out += "\n"
        }

        return out
    }

    // MARK: Helpers

    private static func format(_ e: RecorderEvent, in tz: TimeZone) -> String {
        var line = "\(formatDate(e.timestamp, in: tz)) [\(e.category.rawValue)] \(e.name)"
        if let s = e.screen { line += " (screen=\(s))" }
        if !e.metadata.isEmpty {
            let pairs = e.metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\(describe($0.value))" }
                .joined(separator: " ")
            line += " {\(pairs)}"
        }
        if let err = e.error {
            line += " err={domain=\(err.domain) code=\(err.code) msg=\(err.message) userVisible=\(err.isUserVisible)}"
        }
        if let b = e.ble {
            line += " ble={kind=\(b.kind.rawValue)"
            if let p = b.peripheralId    { line += " peripheral=\(p)" }
            if let s = b.side            { line += " side=\(s)" }
            if let c = b.characteristic  { line += " char=\(c)" }
            if let l = b.length          { line += " len=\(l)" }
            if let h = b.hex             { line += " hex=\(h)" }
            if let r = b.rssi            { line += " rssi=\(r)" }
            line += "}"
        }
        return line
    }

    private static func describe(_ v: RecorderValue) -> String {
        switch v {
        case .string(let s): return "\"\(s)\""
        case .int(let i):    return String(i)
        case .double(let d): return String(d)
        case .bool(let b):   return String(b)
        case .hex(let h):    return "hex:\(h)"
        }
    }

    private static func formatDate(_ d: Date?, in tz: TimeZone) -> String {
        guard let d else { return "(none)" }
        let f = ISO8601DateFormatter()
        f.timeZone = tz
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }
}
