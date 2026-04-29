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
//
// v0.4.5 — Drop-set mode:
//   When `dropSetMode == true`, the SAME idle-grace heuristic that normally
//   finalizes a set instead invokes `onDropBoundary` with a snapshot of the
//   reps/peak/samples since the previous drop boundary (or set start). The
//   callback returns either `.advance` (more drops remain — keep currentSet
//   open, reset reps/peak, no rest timer) or `.finalize` (last drop — fall
//   through to normal finalize, which starts the rest timer). LoggingStore
//   wires this to its planned drop chain and the BLE writer.

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

    /// v0.4.5: After a set finalizes, we keep the just-completed set's
    /// samples around so the live chart can keep displaying the waveform
    /// until the next set starts. Cleared on the first sample of the next
    /// set. Without this, the chart blanked the moment the idle-grace
    /// finalize fired and the user lost their post-set review window.
    @Published var lastFinalizedSamples: [ForceSample] = []
    @Published var lastFinalizedPeakLb: Double = 0
    @Published var lastFinalizedStartedAt: Date? = nil
    @Published var lastFinalizedEndedAt: Date? = nil

    /// b49: per-exercise-name samples cache for the superset force chart.
    /// When a set finalizes, we stash its samples under the exercise name
    /// the set was attributed to (LoggingStore.activeInstance.exercise.
    /// name). The chart then draws BOTH sides' last set as two distinct
    /// labeled traces during a superset, so the user can compare the two
    /// exercises' force profiles side-by-side without scrolling history.
    /// Keyed by exercise name; value is the most-recent finalized trace
    /// for that exercise within this session. LiveCaptureView writes the
    /// active side's name on each finalize via stashFinalizedFor(name:).
    @Published var lastFinalizedByExercise: [String: [ForceSample]] = [:]

    // Rest timer
    @Published var restActive: Bool = false
    @Published var restElapsedSeconds: Double = 0
    private var restStartedAt: Date? = nil
    private var restTimer: AnyCancellable? = nil

    // Set-complete idle tracking
    @Published private(set) var idleSince: Date? = nil

    // Last-rep-count for new-set detection
    private var lastRepCount: Int = 0

    // MARK: - v0.4.5: Drop-set mode
    /// True while a drop set is in flight. Flipped on by LoggingStore at the
    /// start of the chain and flipped off after the final drop fires.
    @Published var dropSetMode: Bool = false
    /// Telemetry-aware boundary callback. SessionStore invokes this in place
    /// of `finalizeSet()` when `dropSetMode == true`. The callback may return
    /// `.advance` to continue the chain (we keep currentSet open and reset
    /// the per-drop counters) or `.finalize` to fall through to normal
    /// finalize (last drop — starts rest timer).
    var onDropBoundary: ((DropBoundarySnapshot) -> DropDecision)? = nil
    /// Marker for slicing per-drop telemetry. Set when a drop chain begins
    /// and re-set on every advance. nil when no drop set is active.
    private var currentDropStartedAt: Date? = nil
    /// Per-drop reps/peak baselines so we can compute the drop's slice
    /// without separating sample arrays. (We snapshot reps/peak DELTAS by
    /// resetting these on each advance.)
    private var currentDropPeakLb: Double = 0
    private var currentDropReps: Int = 0
    /// 1-based drop index within the active chain. Drop #1 is implicit
    /// (the parent set’s top-level fields); subsequent drops are 2..N.
    private var currentDropOrder: Int = 1

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
            // v0.4.5: clear the post-finalize trace so the chart
            // transitions cleanly to the new set.
            lastFinalizedSamples = []
            lastFinalizedPeakLb = 0
            lastFinalizedStartedAt = nil
            lastFinalizedEndedAt = nil
        }

        // Accumulate into current set
        if currentSet != nil {
            let sample = ForceSample(timestamp: now, forceLb: forceLb, phase: phase)
            currentSet!.addSample(sample)
            if repCount > currentSet!.reps { currentSet!.reps = repCount }
            // Track per-drop peak relative to the in-flight drop (used when
            // the user is in a drop set so we can attribute force per drop
            // rather than only per parent set).
            if forceLb > currentDropPeakLb { currentDropPeakLb = forceLb }
            currentDropReps = currentSet!.reps - dropRepBaseline
        }

        // Set-complete heuristic (verbatim logic from app.js).
        // b57 V3 §6: also accept `cs.peakLb > 10` so the first set can
        // finalize even if the BLE rep counter never propagated. Prior
        // to this fix the very first set after app launch sometimes
        // skipped the rest timer because reps stayed 0 — the idle
        // detector was correctly observing idle+force-low but bailing
        // on the rep gate.
        if let cs = currentSet,
           phase == .idle && forceLb < 5 && (cs.reps > 0 || cs.peakLb > 10) {
            if idleSince == nil { idleSince = now }
            if let since = idleSince, now.timeIntervalSince(since) >= IDLE_GRACE_MS {
                // v0.4.5: in drop-set mode, defer to the boundary callback.
                // The callback decides whether this is another drop (keep set
                // open) or the final drop (fall through to normal finalize).
                if dropSetMode, let cb = onDropBoundary {
                    let snap = DropBoundarySnapshot(
                        order: currentDropOrder,
                        reps: currentDropReps > 0 ? currentDropReps : cs.reps,
                        peakLb: currentDropPeakLb,
                        startedAt: currentDropStartedAt ?? cs.startedAt,
                        endedAt: now
                    )
                    let decision = cb(snap)
                    switch decision {
                    case .advance:
                        advanceDropSubSet(now: now)
                    case .finalize:
                        finalizeSet()
                    }
                } else {
                    finalizeSet()
                }
            }
        } else {
            idleSince = nil
        }

        lastRepCount = repCount
    }

    // MARK: - v0.4.5: Drop-set advance

    /// Per-drop rep baseline. `currentSet.reps` is the total across drops in
    /// the chain; per-drop reps = total - this baseline. Recomputed on each
    /// advance.
    private var dropRepBaseline: Int = 0

    /// Called by LoggingStore when a drop chain begins. Resets per-drop
    /// counters but does NOT touch `currentSet` — the in-flight set keeps
    /// accumulating samples normally.
    func beginDropChain() {
        dropSetMode = true
        currentDropOrder = 1
        currentDropStartedAt = currentSet?.startedAt ?? Date()
        currentDropPeakLb = 0
        currentDropReps = 0
        dropRepBaseline = currentSet?.reps ?? 0
    }

    /// Called automatically when `onDropBoundary` returns `.advance`. Keeps
    /// currentSet open (no finalize, no rest timer), resets the per-drop
    /// slice counters so the next drop is measured cleanly.
    private func advanceDropSubSet(now: Date) {
        currentDropOrder += 1
        currentDropStartedAt = now
        currentDropPeakLb = 0
        currentDropReps = 0
        dropRepBaseline = currentSet?.reps ?? 0
        idleSince = nil
    }

    /// Called by LoggingStore when the chain unconditionally ends (e.g. user
    /// taps a Stop button). Clears drop-set mode without finalizing.
    func endDropChainModeOnly() {
        dropSetMode = false
        onDropBoundary = nil
        currentDropStartedAt = nil
        currentDropPeakLb = 0
        currentDropReps = 0
        currentDropOrder = 1
        dropRepBaseline = 0
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
        // v0.4.5: stash this set's samples so the chart keeps showing the
        // trace through the rest period instead of blanking.
        lastFinalizedSamples = cs.samples
        lastFinalizedPeakLb = cs.peakLb
        lastFinalizedStartedAt = cs.startedAt
        lastFinalizedEndedAt = ended
        currentSet = nil
        idleSince = nil
        // b49: backdate the rest start by 2s so the visible rest clock
        // already reads 0:02 the moment the set finalizes. The 4s idle
        // grace effectively eats the first 4 seconds of rest from the
        // user's perspective; surfacing 2 of those in the rest counter
        // makes the wall-clock feel honest. (User feedback: rest timer
        // felt "-2s out of sync" with their phone clock.)
        let restAnchor = Date().addingTimeInterval(-2.0)
        restStartedAt = restAnchor
        // P1-2 (b66): publish restElapsedSeconds NOW so SwiftUI mounts
        // the rest bar on the same run loop as finalize. Without this,
        // the value stays at 0 until the 0.25s ticker next fires,
        // which caused the very first set after launch to silently
        // miss the rest-bar engagement (the LiveCaptureViewV2
        // mount predicate is `Int(restElapsedSeconds.rounded()) > 0`).
        restElapsedSeconds = Date().timeIntervalSince(restAnchor)
        setRestActive(true)
        persistDraft()
        // v0.4.5: clear drop-set mode after finalize so the next set isn't
        // accidentally treated as part of a chain. LoggingStore is also
        // responsible for clearing its own drop state.
        dropSetMode = false
        onDropBoundary = nil
        currentDropStartedAt = nil
        currentDropPeakLb = 0
        currentDropReps = 0
        currentDropOrder = 1
        dropRepBaseline = 0
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
        let now = Date()
        restStartedAt = now
        // P1-2 (b66): kick `restElapsedSeconds` so SwiftUI sees a
        // published change on this run loop. The view-side mount
        // predicate now keys on `restActive` (not the rounded-seconds
        // value) so the bar appears immediately on tap; this assignment
        // is just to ensure observers re-fire if the value happens to
        // already be 0.
        restElapsedSeconds = 0
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

    // MARK: - v0.4.6: External finalize hook (drop cascade watchdog)

    /// Forcibly finalize the in-flight set as if the idle-grace heuristic
    /// fired. Used by LoggingStore's drop-cascade watchdog (10s of no rep
    /// increment finalizes the set). Safe to call when no set is active.
    func forceFinalizeCurrentSet() {
        guard currentSet != nil else { return }
        // Defensive: clear drop-mode hooks first so finalize takes the
        // normal path (LoggingStore's caller is responsible for clearing
        // its own drop state via the completedSets observer).
        dropSetMode = false
        onDropBoundary = nil
        finalizeSet()
    }

    /// 0–1 progress through the idle-grace window (`IDLE_GRACE_MS`).
    /// 0 = not idle yet; 1 = about to finalize. Drives the under-REPS
    /// idle countdown bar on LiveCaptureView. Returns 0 when no set is
    /// active or the user is mid-rep.
    var idleProgress01: Double {
        guard currentSet != nil, let since = idleSince else { return 0 }
        let elapsed = Date().timeIntervalSince(since)
        return min(1.0, max(0, elapsed / IDLE_GRACE_MS))
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
