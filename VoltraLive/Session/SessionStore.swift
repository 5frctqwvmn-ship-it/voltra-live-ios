// SessionStore.swift
// Tracks the current workout session: set-complete heuristic (port of app.js),
// rest timer, sample buffer. Persists completed sessions via SwiftData.
//
// Set-complete heuristic (verbatim from app.js):
//   - phase == .idle
//   - forceLb < 5
//   - repCount > 0 (within current set)
//   - idle duration >= 4000ms (IDLE_GRACE_MS)
// When finalized: archive set, start rest timer.
// Rest timer stops on next Pull or rep increment.

import Foundation
import SwiftData
import Combine

@MainActor
final class SessionStore: ObservableObject {

    // MARK: - Constants
    private let IDLE_GRACE_MS: TimeInterval = 4.0    // 4000ms
    private let MAX_STORED_SESSIONS = 50

    // MARK: - Published state
    @Published var sessionStartedAt: Date = Date()
    @Published var completedSets: [CompletedSet] = []
    @Published var currentSet: CurrentSet? = nil

    // Rest timer
    @Published var restActive: Bool = false
    @Published var restElapsedSeconds: Double = 0
    private var restStartedAt: Date? = nil
    private var restTimer: AnyCancellable? = nil

    // Set-complete idle tracking
    private var idleSince: Date? = nil

    // Last-rep-count for new-set detection
    private var lastRepCount: Int = 0

    // SwiftData context — injected from app
    var modelContext: ModelContext?

    // MARK: - Init

    init() {
        startRestTicker()
    }

    // MARK: - Public: called by BLE layer on each telemetry update

    func handleLiveSample(phase: VoltraPhase, forceLb: Double, repCount: Int) {
        let now = Date()

        // Detect new set start: Pull or rep bump while no active set
        if currentSet == nil && (phase == .pull || repCount > lastRepCount) {
            currentSet = CurrentSet(startedAt: now)
            restStartedAt = nil
            setRestActive(false)
        }

        // Accumulate into current set
        if currentSet != nil {
            let sample = ForceSample(timestamp: now, forceLb: forceLb, phase: phase)
            currentSet!.addSample(sample)
            if repCount > currentSet!.reps { currentSet!.reps = repCount }
        }

        // Set-complete heuristic (verbatim logic from app.js)
        if let cs = currentSet,
           phase == .idle && forceLb < 5 && cs.reps > 0 {
            if idleSince == nil { idleSince = now }
            if let since = idleSince, now.timeIntervalSince(since) >= IDLE_GRACE_MS {
                finalizeSet()
            }
        } else {
            idleSince = nil
        }

        lastRepCount = repCount
    }

    // MARK: - Set finalization

    private func finalizeSet() {
        guard let cs = currentSet else { return }
        let ended = Date()
        let done = CompletedSet(
            reps: cs.reps,
            peakLb: cs.peakLb,
            startedAt: cs.startedAt,
            endedAt: ended
        )
        completedSets.append(done)
        currentSet = nil
        idleSince = nil
        restStartedAt = Date()
        setRestActive(true)
        persistDraft()
    }

    // MARK: - Rest timer

    private func startRestTicker() {
        restTimer = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let start = self.restStartedAt else { return }
                self.restElapsedSeconds = Date().timeIntervalSince(start)
            }
    }

    func tapRestTile() {
        restStartedAt = Date()
        setRestActive(true)
    }

    private func setRestActive(_ active: Bool) {
        restActive = active
        if !active {
            restElapsedSeconds = 0
        }
    }

    var restFormatted: String {
        let sec = Int(restElapsedSeconds)
        return "\(sec / 60):\(String(format: "%02d", sec % 60))"
    }

    // MARK: - Session management

    func endSession() {
        if currentSet != nil { finalizeSet() }
        guard !completedSets.isEmpty else {
            sessionStartedAt = Date()
            return
        }
        saveToSwiftData()
        sessionStartedAt = Date()
        completedSets = []
        currentSet = nil
        restStartedAt = nil
        setRestActive(false)
    }

    func clearAll() {
        guard let ctx = modelContext else { return }
        do {
            let sessions = try ctx.fetch(FetchDescriptor<PastSession>())
            for s in sessions { ctx.delete(s) }
            try ctx.save()
        } catch {
            print("[SessionStore] Clear error: \(error)")
        }
        completedSets = []
        currentSet = nil
        sessionStartedAt = Date()
        setRestActive(false)
    }

    // MARK: - SwiftData persistence

    private func saveToSwiftData() {
        guard let ctx = modelContext else { return }
        let pastSets = completedSets.map {
            PastSet(reps: $0.reps, peakLb: $0.peakLb,
                    startedAt: $0.startedAt, endedAt: $0.endedAt)
        }
        let session = PastSession(startedAt: sessionStartedAt, endedAt: Date(), sets: pastSets)
        ctx.insert(session)
        do {
            try ctx.save()
            // Cap at 50 most-recent sessions
            let all = try ctx.fetch(
                FetchDescriptor<PastSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
            )
            if all.count > MAX_STORED_SESSIONS {
                for old in all.dropFirst(MAX_STORED_SESSIONS) {
                    ctx.delete(old)
                }
                try ctx.save()
            }
        } catch {
            print("[SessionStore] Save error: \(error)")
        }
    }

    private func persistDraft() {
        // Draft persistence is handled by SwiftData — nothing extra needed here
        // since we save completed sets on endSession. This is intentionally minimal.
    }

    // MARK: - Computed helpers for UI

    var totalRepsThisSession: Int {
        completedSets.reduce(0) { $0 + $1.reps } + (currentSet?.reps ?? 0)
    }

    var lastCompletedSet: CompletedSet? { completedSets.last }

    /// Fetch the last past session from SwiftData for compare strip
    func fetchLastPastSession() -> PastSession? {
        guard let ctx = modelContext else { return nil }
        var desc = FetchDescriptor<PastSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        desc.fetchLimit = 1
        return try? ctx.fetch(desc).first
    }

    func fetchPastSessions(limit: Int = 10) -> [PastSession] {
        guard let ctx = modelContext else { return [] }
        var desc = FetchDescriptor<PastSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        desc.fetchLimit = limit
        return (try? ctx.fetch(desc)) ?? []
    }
}
