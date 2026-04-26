// LoggingStore.swift
// Owns the v0.2 active-session state machine on top of SessionStore (v0.1).
//
// Responsibilities:
//   1. Track the user-facing flow: pickedDayType → pickedExercise → activeInstance.
//   2. Observe SessionStore.completedSets and surface the most recent
//      auto-detected set to the SetLogView for confirmation.
//   3. Persist confirmed sets into SwiftData via the v0.2 logging schema.
//   4. Provide picker data: exercises sorted by recency for a given day type.
//   5. Generate markdown export for "End Session".
//
// It does NOT touch SessionStore's internals — only reads completedSets and
// calls clearAll/endSession when the user explicitly resets.

import Foundation
import SwiftData
import Combine

@MainActor
final class LoggingStore: ObservableObject {

    // MARK: - Published state

    @Published var activeSession: WorkoutSession? = nil
    @Published var activeInstance: ExerciseInstance? = nil
    /// The most recent completed set detected by SessionStore that hasn't
    /// been logged yet. Cleared on log() or skip().
    @Published var pendingTelemetrySet: CompletedSet? = nil
    /// Mirror of the running set count for the current instance — drives the
    /// "Set #" label in the UI.
    @Published var setNumberForCurrentInstance: Int = 1
    /// User-chosen starting weight from the smart-start toggle (or free entry)
    /// for the upcoming set. Read by SetLogView at prefill time and cleared
    /// after each set is logged.
    @Published var pendingPlannedWeightLb: Double? = nil

    // MARK: - Dependencies

    var modelContext: ModelContext?
    private weak var sessionStore: SessionStore?
    private var observers: Set<AnyCancellable> = []
    /// Number of completedSets we've already consumed from SessionStore so
    /// duplicates aren't re-prompted.
    private var consumedSetCount: Int = 0

    // MARK: - Lifecycle

    func wire(context: ModelContext, sessionStore: SessionStore) {
        self.modelContext = context
        self.sessionStore = sessionStore

        // Observe SessionStore.completedSets — when a new entry appears,
        // surface it as the pending set.
        sessionStore.$completedSets
            .receive(on: RunLoop.main)
            .sink { [weak self] sets in
                self?.handleCompletedSetsUpdate(sets)
            }
            .store(in: &observers)
    }

    private func handleCompletedSetsUpdate(_ sets: [CompletedSet]) {
        // Reset consumed counter when SessionStore was cleared underneath us.
        if sets.count < consumedSetCount {
            consumedSetCount = sets.count
            return
        }
        guard sets.count > consumedSetCount else { return }
        // Only surface the latest — earlier ones were either logged or skipped.
        if let latest = sets.last {
            pendingTelemetrySet = latest
        }
        consumedSetCount = sets.count
    }

    // MARK: - Session lifecycle

    func startSession(dayType: DayType, customLabel: String? = nil) {
        guard let ctx = modelContext else { return }
        let s = WorkoutSession(
            startedAt: Date(),
            dayType: dayType,
            customLabel: customLabel
        )
        ctx.insert(s)
        activeSession = s
        activeInstance = nil
        setNumberForCurrentInstance = 1
        sessionStore?.completedSets = []
        consumedSetCount = 0
        try? ctx.save()
    }

    func endSession() -> WorkoutSession? {
        guard let session = activeSession else { return nil }
        session.endedAt = Date()
        finalizeActiveInstance()
        try? modelContext?.save()

        let result = session
        activeSession = nil
        activeInstance = nil
        pendingTelemetrySet = nil
        setNumberForCurrentInstance = 1
        sessionStore?.completedSets = []
        consumedSetCount = 0
        return result
    }

    func cancelSession() {
        guard let ctx = modelContext, let session = activeSession else { return }
        ctx.delete(session)
        activeSession = nil
        activeInstance = nil
        pendingTelemetrySet = nil
        setNumberForCurrentInstance = 1
        try? ctx.save()
    }

    // MARK: - Exercise picking

    func pickExercise(_ exercise: Exercise) {
        guard let ctx = modelContext, let session = activeSession else { return }
        finalizeActiveInstance()
        let order = (session.instances?.count ?? 0) + 1
        let instance = ExerciseInstance(
            startedAt: Date(),
            orderIndex: order,
            equipment: exercise.equipment,
            session: session,
            exercise: exercise
        )
        ctx.insert(instance)
        activeInstance = instance
        setNumberForCurrentInstance = 1
        pendingPlannedWeightLb = nil

        // Bump exercise recency.
        exercise.lastUsedAt = Date()
        exercise.addDayType(session.dayType)

        try? ctx.save()
    }

    func createNewExercise(name: String, equipment: String, dayType: DayType) -> Exercise {
        let exercise = Exercise(
            name: name.trimmingCharacters(in: .whitespaces),
            equipment: equipment.trimmingCharacters(in: .whitespaces),
            primaryDayType: dayType,
            dayTypeTags: [dayType],
            lastUsedAt: Date(),
            seededFromHistory: false
        )
        modelContext?.insert(exercise)
        try? modelContext?.save()
        return exercise
    }

    private func finalizeActiveInstance() {
        if let inst = activeInstance, inst.endedAt == nil {
            inst.endedAt = Date()
        }
    }

    // MARK: - Set logging

    /// Persist a confirmed set under the active instance.
    func logSet(
        weightLb: Double,
        eccentricLb: Double?,
        reps: Int,
        chainsLb: Double?,
        peakForceLb: Double,
        startedAt: Date?,
        endedAt: Date?,
        mode: SetMode,
        labelText: String,
        notes: String?,
        autofilledFromTelemetry: Bool
    ) {
        guard let ctx = modelContext, let instance = activeInstance else { return }
        let order = (instance.sets?.count ?? 0) + 1
        let logged = LoggedSet(
            completedAt: Date(),
            startedAt: startedAt,
            endedAt: endedAt,
            orderIndex: order,
            weightLb: weightLb,
            eccentricLb: eccentricLb,
            reps: reps,
            chainsLb: chainsLb,
            peakForceLb: peakForceLb,
            avgForceLb: nil,
            mode: mode,
            labelText: labelText,
            notes: notes,
            autofilledFromTelemetry: autofilledFromTelemetry,
            importedFromHistory: false,
            instance: instance
        )
        ctx.insert(logged)
        setNumberForCurrentInstance = order + 1
        pendingTelemetrySet = nil
        pendingPlannedWeightLb = nil
        try? ctx.save()
    }

    func skipPendingSet() {
        pendingTelemetrySet = nil
    }

    // MARK: - Picker queries

    /// Exercises ordered by relevance for a chosen day type, using the
    /// HistoryAnalytics sequence model (lower slot = appears earlier in a
    /// typical session, weighted by recency).
    func exercises(for dayType: DayType) -> [Exercise] {
        guard let ctx = modelContext else { return [] }
        let all = (try? ctx.fetch(FetchDescriptor<Exercise>())) ?? []
        let pool = (dayType == .custom) ? all : all.filter { $0.dayTypeTags.contains(dayType) }
        let sessions = (try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        return HistoryAnalytics.exercisesOrderedBySequence(
            candidates: pool,
            sessions: sessions,
            dayType: dayType
        )
    }

    /// Last set logged for a given exercise — used to autofill weight/ecc/reps.
    func lastSet(for exercise: Exercise) -> LoggedSet? {
        guard let ctx = modelContext else { return nil }
        var desc = FetchDescriptor<LoggedSet>(
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        desc.fetchLimit = 50
        let candidates = (try? ctx.fetch(desc)) ?? []
        return candidates.first { $0.instance?.exercise?.id == exercise.id }
    }

    /// Sets from the most recent prior session that included this exercise,
    /// in 1..N order. Drives the smart-start toggle.
    func previousSetSeries(for exercise: Exercise) -> [LoggedSet] {
        HistoryAnalytics.previousSetSeries(
            for: exercise,
            excluding: activeSession
        )
    }

    /// Sets the user has already logged in the *active* instance, in order.
    /// Empty before the first set is logged.
    func currentInstanceSets() -> [LoggedSet] {
        guard let inst = activeInstance else { return [] }
        return inst.orderedSets
    }

    /// One-stop convenience: build a SetSuggestion for the next set the user
    /// is about to log on the active instance.
    func nextSetSuggestion() -> SetSuggestion {
        guard let inst = activeInstance, let exercise = inst.exercise else {
            return SetSuggestion(source: .freeEntry, anchorLb: nil, offsets: [])
        }
        let prev = previousSetSeries(for: exercise)
        let curr = inst.orderedSets
        return SetSuggestionEngine.suggestion(
            forSetIndex: setNumberForCurrentInstance,
            currentInstanceSets: curr,
            previousSeries: prev
        )
    }

    // MARK: - Markdown export

    /// Generate markdown identical in spirit to the master history file so the
    /// user's logs can be appended. Output for one session.
    func markdownExport(for session: WorkoutSession, sessionNumber: Int) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMMM d, yyyy"
        df.locale = Locale(identifier: "en_US_POSIX")

        let timeF = DateFormatter()
        timeF.dateFormat = "h:mm a"

        let ended = session.endedAt ?? Date()
        let dur = ended.timeIntervalSince(session.startedAt)
        let durStr = formatDuration(dur)

        var out = ""
        out += "Session \(sessionNumber) — \(df.string(from: session.startedAt)) — \(session.displayLabel)\n"
        out += "Equipment: \(uniqueEquipment(in: session))   "
        out += "Time: \(timeF.string(from: session.startedAt)) – \(timeF.string(from: ended))   "
        out += "Duration: \(durStr)\n\n"

        for inst in (session.instances ?? []).sorted(by: { $0.orderIndex < $1.orderIndex }) {
            let title = inst.equipment.isEmpty
                ? (inst.exercise?.name ?? "Exercise")
                : "\(inst.exercise?.name ?? "Exercise") (\(inst.equipment))"
            out += "\(title)\n\n"
            out += "Set    Label      Weight     Eccentric    Reps    Notes\n"
            for s in inst.orderedSets {
                let w = s.weightLb > 0 ? "\(formatLb(s.weightLb)) lbs" : "—"
                let e = (s.eccentricLb ?? 0) > 0 ? "+\(formatLb(s.eccentricLb!)) ecc" : "—"
                let label = s.labelText.isEmpty ? s.mode.label : s.labelText
                let notes = s.notes ?? ""
                out += "\(s.orderIndex)      \(label.padded(8))  \(w.padded(10))  \(e.padded(11))  \(s.reps)     \(notes)\n"
            }
            out += "\n"
        }
        return out
    }

    private func uniqueEquipment(in session: WorkoutSession) -> String {
        let pieces = (session.instances ?? []).map(\.equipment).filter { !$0.isEmpty }
        let unique = Array(Set(pieces)).sorted()
        return unique.joined(separator: ", ")
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h) hour\(h == 1 ? "" : "s"), \(m) minutes" }
        return "\(m) minutes, \(s) seconds"
    }

    private func formatLb(_ d: Double) -> String {
        if d == d.rounded() { return String(Int(d)) }
        return String(format: "%.1f", d)
    }
}

private extension String {
    func padded(_ n: Int) -> String {
        if count >= n { return self }
        return self + String(repeating: " ", count: n - count)
    }
}
