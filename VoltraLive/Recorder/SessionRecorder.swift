// SessionRecorder.swift
// B74-F11 Session Recorder — single shared service.
//
// Spec: docs/handoff/SESSION_RECORDER_SPEC.md "Service".
//
// One `SessionRecorder.shared` instance, injected at the app root via
// `.environmentObject(SessionRecorder.shared)`. Owns recording state,
// the FIFO buffer, the redactor, and the persistence path.
//
// Threading model:
//   - The class is NOT `@MainActor`. The `@Published` properties are
//     mutated from `start()`, `stop()`, and other UI-driven methods that
//     callers invoke from the main actor; SwiftUI binding flows through
//     normally.
//   - `record(...)` is callable from ANY thread (BLE delegate, HK
//     callback, background Task) and is the only cross-thread surface.
//     It snapshots its required state through a small lock, then hands
//     the event to the `RecorderBuffer` actor via an unstructured Task.
//
// Persistence:
//   - On app background or kill, `persist()` writes the current snapshot
//     to `Application Support/SessionRecorder/last_session.json`.
//   - No other disk writes. No network. No analytics. (Spec hard stop.)

import Foundation
import Combine

final class SessionRecorder: ObservableObject {

    /// App-wide singleton. Inject via `.environmentObject(SessionRecorder.shared)`.
    static let shared = SessionRecorder()

    // MARK: Published recording state

    @Published private(set) var isRecording: Bool = false
    @Published private(set) var sessionId: UUID = UUID()
    @Published private(set) var start: Date? = nil
    @Published private(set) var end: Date? = nil

    // MARK: Storage + redaction

    let buffer: RecorderBuffer = RecorderBuffer(capacity: 10_000)
    let redactor: RecorderRedactor = RecorderRedactor()

    // MARK: Cross-thread state mirror
    //
    // `record(...)` runs on arbitrary threads and needs to know
    // `isRecording` + `sessionId` without bouncing off the main actor.
    // We keep a locked mirror that the @MainActor mutators update in
    // lockstep with the @Published vars.

    private let stateLock = NSLock()
    private var mirrorIsRecording: Bool = false
    private var mirrorSessionId: UUID = UUID()

    // MARK: Bundle metadata (read once at init)

    private let appVersion: String
    private let build: String

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]
        self.appVersion = (info["CFBundleShortVersionString"] as? String) ?? "?"
        self.build      = (info["CFBundleVersion"] as? String) ?? "?"
        // Seed mirrors to match initial @Published values.
        self.mirrorSessionId = self.sessionId
        self.mirrorIsRecording = self.isRecording
    }

    // MARK: Toggle / lifecycle (call from MainActor)

    @MainActor
    func toggle() { isRecording ? stop() : start() }

    @MainActor
    func start() {
        guard !isRecording else { return }
        let newId = UUID()
        let newStart = Date()
        // Update mirror BEFORE @Published flip so any concurrent
        // `record(...)` that observes `isRecording == true` sees the
        // matching session id.
        stateLock.lock()
        mirrorSessionId = newId
        mirrorIsRecording = true
        stateLock.unlock()

        sessionId = newId
        start = newStart
        end = nil
        isRecording = true

        Task { await buffer.clear() }
        record(category: .recorder, name: "recorder.armed")
        record(category: .lifecycle, name: "lifecycle.sessionStart")
    }

    @MainActor
    func stop() {
        guard isRecording else { return }
        record(category: .lifecycle, name: "lifecycle.sessionEnd")
        record(category: .recorder, name: "recorder.disarmed")
        end = Date()
        isRecording = false
        stateLock.lock()
        mirrorIsRecording = false
        stateLock.unlock()
        persist()
    }

    /// Run a UI action inside a fresh `actionId` scope. Synchronous
    /// `body` variant; for async work see `actionAsync`.
    @MainActor
    func action<T>(_ name: String, screen: String? = nil, _ body: () throws -> T) rethrows -> T {
        let id = UUID()
        return try ActionScope.$currentActionId.withValue(id) {
            record(category: .ui, name: name, screen: screen,
                   metadata: ["actionId": .string(id.uuidString)])
            return try body()
        }
    }

    /// Async variant of `action(...)` — task-locals propagate into the
    /// async operation for the entire `await` chain.
    @MainActor
    func actionAsync<T>(_ name: String, screen: String? = nil, _ body: () async throws -> T) async rethrows -> T {
        let id = UUID()
        return try await ActionScope.$currentActionId.withValue(id) {
            record(category: .ui, name: name, screen: screen,
                   metadata: ["actionId": .string(id.uuidString)])
            return try await body()
        }
    }

    /// Loud-guard helper. Replace user-visible `guard … else { return }`
    /// with `rec.guardTrip(name:reason:state:); return` so blocked actions
    /// leave a trace.
    func guardTrip(name: String, reason: String, state: [String: RecorderValue] = [:]) {
        var meta = state
        meta["reason"] = .string(reason)
        record(category: .`guard`, name: "guard.trip.\(name)", metadata: meta)
    }

    // MARK: Emit (callable from any thread)

    /// Append one event to the buffer. Drops silently if not currently
    /// recording (the buffer is allocated regardless so the actor stays
    /// hot, but no event is written).
    func record(category: RecorderCategory,
                name: String,
                screen: String? = nil,
                metadata: [String: RecorderValue] = [:],
                error: RecorderErrorRecord? = nil,
                ble: BLESubrecord? = nil) {
        stateLock.lock()
        let recording = mirrorIsRecording
        let sid = mirrorSessionId
        stateLock.unlock()
        guard recording else { return }

        let actionId = ActionScope.currentActionId
        let event = RecorderEvent(
            id: UUID(),
            sessionId: sid,
            actionId: actionId,
            timestamp: Date(),
            monotonic: DispatchTime.now().uptimeNanoseconds,
            category: category,
            name: name,
            screen: screen,
            metadata: metadata,
            error: error,
            ble: ble
        )
        let buf = self.buffer
        Task { await buf.append(event) }
    }

    // MARK: Snapshot + export

    func snapshot() async -> [RecorderEvent] {
        await buffer.snapshot()
    }

    /// Build the `.txt` + `.json` payload pair for the current session.
    /// Used by `SessionRecorderViewer`'s `ShareLink`.
    func currentExport() async throws -> (txt: String, json: Data) {
        let events = await buffer.snapshot()
        // Capture published state on MainActor for a coherent header.
        let (sid, sStart, sEnd): (UUID, Date?, Date?) = await MainActor.run {
            (self.sessionId, self.start, self.end)
        }
        let json = try RecorderExporter.jsonData(
            sessionId: sid, start: sStart, end: sEnd,
            events: events, appVersion: appVersion, build: build)
        let txt = RecorderExporter.textReport(
            sessionId: sid, start: sStart, end: sEnd,
            events: events, appVersion: appVersion, build: build)
        return (txt, json)
    }

    // MARK: Persistence

    /// Write the current session JSON to `last_session.json`. Called from
    /// `stop()` and from app background / kill hooks. Best-effort: any
    /// error is swallowed — persistence is debug aid, not user data.
    func persist() {
        Task { [weak self] in
            guard let self else { return }
            let events = await self.buffer.snapshot()
            let (sid, sStart, sEnd): (UUID, Date?, Date?) = await MainActor.run {
                (self.sessionId, self.start, self.end)
            }
            do {
                let data = try RecorderExporter.jsonData(
                    sessionId: sid, start: sStart, end: sEnd,
                    events: events, appVersion: self.appVersion, build: self.build)
                guard let url = Self.persistenceURL() else { return }
                try data.write(to: url, options: .atomic)
            } catch {
                // Persistence is best-effort; do not surface to user.
            }
        }
    }

    /// Best-effort load of the previous session's JSON from disk. Returns
    /// `nil` if no file exists or it can't be decoded.
    static func loadLastSession() -> RecorderExportEnvelope? {
        guard let url = persistenceURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RecorderExportEnvelope.self, from: data)
    }

    private static func persistenceURL() -> URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("SessionRecorder", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("last_session.json")
    }
}
