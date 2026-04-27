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

    // MARK: - v0.4.0: Upcoming-set context (drives auto-log on telemetry)
    //
    // These fields hold the user's CURRENTLY-CONFIGURED next-set plan, set
    // from ExerciseDetailView and live-edited inline on LiveCaptureView via
    // ±1/±5 nudges. When SessionStore reports a telemetry-detected set
    // boundary, autoLogTelemetrySet() snapshots these into a new LoggedSet
    // (with telemetry reps + peak force overlaid) and clears them only as
    // appropriate (added load PERSISTS across sets in the same instance;
    // weight/ecc/mode are reused too so the user sees a hot prefill until
    // they nudge it).
    @Published var upcomingMode: SetMode = .working
    @Published var upcomingEccLb: Double = 0
    @Published var upcomingTargetReps: Int = 0
    /// Generalized non-Voltra added load. Persists across sets in the
    /// active instance — you don't usually re-rack chains between sets.
    /// Reset to nil on `pickExercise`.
    @Published var upcomingAddedLoadLb: Double? = nil
    @Published var upcomingAddedLoadType: String? = nil

    // MARK: - v0.4.5: Drop-set state
    //
    // When the user starts a drop set, we hand SessionStore a planned chain
    // and a boundary callback. SessionStore fires the callback every time
    // its idle-grace heuristic would normally finalize a set. We advance
    // through the chain by writing the next planned weight to the device,
    // buffer the per-drop telemetry snapshot, and on the FINAL drop return
    // `.finalize` so the parent set finalizes normally and our
    // `handleCompletedSetsUpdate` hook converts it into a drop-set LoggedSet.

    /// Whether the user is currently in a drop-set chain (vs a normal set).
    /// Drives UI affordances on LiveCaptureView.
    @Published var dropSetActive: Bool = false
    /// Planned per-drop Voltra base weights for the active chain. Populated
    /// by `startDropSet`; read by the boundary callback to push the next
    /// weight to the device.
    @Published var dropChainPlannedLb: [Double] = []
    /// 1-based current drop within the active chain. nil when no chain.
    @Published var currentDropIndex: Int = 1
    /// Per-drop telemetry snapshots collected during the chain. The parent
    /// LoggedSet's top-level fields will be populated from element [0]; any
    /// elements [1..N] become Drop rows.
    private var pendingDropSnapshots: [DropBoundarySnapshot] = []
    /// Per-drop planned weight at index — kept aligned with snapshots so
    /// the persisted Drop carries the planned Voltra weight (which the user
    /// configured) rather than relying on `pendingPlannedWeightLb` mutating
    /// during the chain.
    private var pendingDropPlannedWeights: [Double] = []
    /// Bumped each time the user fully exits the post-session export sheet,
    /// so the home view can pop the entire navigation stack back to root.
    /// Avoids the user being stranded on the (now-empty) capture screen.
    @Published var sessionExitTick: Int = 0
    /// When the rest timer should anchor (count up from). Driven by:
    ///   - Telemetry: when the Vulture reports an idle boundary (set ended on
    ///     the device), we set this to that endedAt — so rest starts the
    ///     instant the user racks the weight, BEFORE they tap Log.
    ///   - Manual log: if the user logs without a telemetry boundary, we fall
    ///     back to the moment they tapped Log so the timer at least starts.
    /// Cleared at session start / instance change. The anchor persists across
    /// the next set's logging so the user can see the actual rest duration.
    @Published var restAnchor: Date? = nil

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
        // v0.4.0: auto-log every newly-detected telemetry set. The user no
        // longer confirms via SetLogView — it's logged immediately with the
        // upcoming-set context (weight/ecc/mode/added-load) overlaid by
        // telemetry reps + peak force. They can tap a row to edit or swipe
        // to delete (with undo).
        //
        // v0.4.5: when a drop chain JUST finalized, route through the
        // drop-aware logger which builds the parent LoggedSet from drop #1
        // and attaches Drop rows for drops 2..N.
        let newOnes = sets[consumedSetCount..<sets.count]
        for telemetrySet in newOnes {
            if !pendingDropSnapshots.isEmpty {
                autoLogDropChain(parentTelemetry: telemetrySet)
            } else {
                autoLogTelemetrySet(telemetrySet)
            }
        }
        consumedSetCount = sets.count
    }

    /// v0.4.0: snapshot the current upcoming-set plan into a real LoggedSet,
    /// overlay telemetry reps + peak force, persist immediately. Triggered by
    /// `handleCompletedSetsUpdate` when the Vulture reports an idle boundary.
    /// No SetLogView prompt — the user can edit the row inline if they want.
    func autoLogTelemetrySet(_ telemetry: CompletedSet) {
        guard let ctx = modelContext, let instance = activeInstance else { return }
        let order = (instance.sets?.count ?? 0) + 1
        let weight = pendingPlannedWeightLb ?? 0
        let ecc = upcomingEccLb > 0 ? upcomingEccLb : nil
        let reps = telemetry.reps  // telemetry-overridden
        let logged = LoggedSet(
            completedAt: Date(),
            startedAt: telemetry.startedAt,
            endedAt: telemetry.endedAt,
            orderIndex: order,
            weightLb: weight,
            eccentricLb: ecc,
            reps: reps,
            chainsLb: nil,
            peakForceLb: telemetry.peakLb,
            avgForceLb: nil,
            mode: upcomingMode,
            labelText: upcomingMode.label,
            notes: nil,
            autofilledFromTelemetry: true,
            importedFromHistory: false,
            inverseChains: false,
            damperLevel: nil,
            bandMaxForceLb: nil,
            addedLoadLb: upcomingAddedLoadLb,
            addedLoadType: upcomingAddedLoadType,
            instance: instance
        )
        ctx.insert(logged)
        setNumberForCurrentInstance = order + 1
        // Anchor REST so any legacy consumers still work; the new
        // LiveCaptureView reads SessionStore.restActive directly anyway.
        restAnchor = telemetry.endedAt
        // Clear the one-shot pending-set indicator so any old code paths
        // that still react to it stop showing the SetLogView sheet.
        pendingTelemetrySet = nil
        try? ctx.save()
    }

    // MARK: - v0.4.5: Drop-set state machine

    /// Start a drop set with a pre-planned chain of Voltra base weights.
    /// `plannedDropsLb` is the FULL chain including drop #1, e.g.
    /// [100, 80, 60] for a 3-drop set. The first weight is written to the
    /// device immediately so the user lifts at drop #1's load. Each
    /// subsequent drop is auto-advanced when SessionStore reports an idle
    /// boundary (>= IDLE_GRACE_MS of no movement).
    func startDropSet(plannedDropsLb: [Double], pushWeight: @escaping (Double) -> Void) {
        guard plannedDropsLb.count >= 2 else { return } // a 1-drop "chain" isn't a drop set
        guard let session = sessionStore else { return }

        dropSetActive = true
        dropChainPlannedLb = plannedDropsLb
        currentDropIndex = 1
        pendingDropSnapshots = []
        pendingDropPlannedWeights = []

        // Snapshot the upcoming "working set" weight as drop #1 so the
        // existing nudge UI keeps reflecting drop #1 throughout the chain.
        // (We track the live device target separately via `pushWeight`.)
        pendingPlannedWeightLb = plannedDropsLb[0]

        // Lock the parent set's logging mode to .dropSet so the row is
        // labeled correctly in history.
        upcomingMode = .dropSet

        // Wire SessionStore: enable mode + register the callback. We use
        // [weak self] so SessionStore doesn't hold a retain cycle on us.
        session.beginDropChain()
        session.onDropBoundary = { [weak self] snap in
            return self?.handleDropBoundary(snap, pushWeight: pushWeight) ?? .finalize
        }

        // Push drop #1's weight to the device right now so the user lifts
        // at the configured load. The caller's pushWeight closure is the
        // bridge to VoltraWriter.
        pushWeight(plannedDropsLb[0])
    }

    /// Cancel an in-flight drop chain WITHOUT finalizing the set. Used when
    /// the user backs out of drop-set mode mid-chain. The currently
    /// in-flight set keeps accumulating but as a normal set; SessionStore
    /// will finalize it via the standard heuristic on next idle.
    func cancelDropSet() {
        dropSetActive = false
        dropChainPlannedLb = []
        currentDropIndex = 1
        pendingDropSnapshots = []
        pendingDropPlannedWeights = []
        sessionStore?.endDropChainModeOnly()
    }

    /// Helper: compute the next drop weight given a step percentage and a
    /// current weight, rounded to 2.5 lb. Exposed so the UI "Add drop"
    /// button can preview the next planned drop without duplicating the
    /// rounding rule.
    static func dropStepLb(stepPercent: Double, from currentLb: Double) -> Double {
        let raw = currentLb * (1.0 - stepPercent)
        // Round down to nearest 2.5 (drops should never go HIGHER than the
        // mathematical step, only at-or-below).
        let stepped = (raw / 2.5).rounded(.down) * 2.5
        return max(0, stepped)
    }

    /// Build a default 3-drop chain from a starting weight using the
    /// exercise's `defaultDropPercent` (or 0.20 if the exercise is unknown).
    func defaultDropChain(startingLb: Double, exercise: Exercise?) -> [Double] {
        let pct = exercise?.defaultDropPercent ?? 0.20
        var chain: [Double] = [startingLb]
        var cur = startingLb
        for _ in 0..<2 {
            let next = LoggingStore.dropStepLb(stepPercent: pct, from: cur)
            // Stop the chain if we'd hit zero or fail to actually drop.
            if next <= 0 || next >= cur { break }
            chain.append(next)
            cur = next
        }
        return chain
    }

    /// Boundary callback registered with SessionStore. Invoked every time
    /// the idle-grace heuristic would normally finalize a set during a drop
    /// chain. We buffer the snapshot, advance to the next planned weight
    /// (or finalize if this was the last drop), and tell SessionStore which
    /// path to take.
    private func handleDropBoundary(
        _ snap: DropBoundarySnapshot,
        pushWeight: @escaping (Double) -> Void
    ) -> DropDecision {
        // Buffer this drop's telemetry. `currentDropIndex` is 1-based; the
        // first time the callback fires, we're recording drop #1's slice.
        pendingDropSnapshots.append(snap)
        let plannedThis = (currentDropIndex - 1) < dropChainPlannedLb.count
            ? dropChainPlannedLb[currentDropIndex - 1]
            : (pendingPlannedWeightLb ?? 0)
        pendingDropPlannedWeights.append(plannedThis)

        // Was this the last drop in the planned chain?
        if currentDropIndex >= dropChainPlannedLb.count {
            // Final drop — fall through to normal finalize.
            // `handleCompletedSetsUpdate` will then route to autoLogDropChain.
            return .finalize
        }

        // Advance: write the next drop's weight to the device, bump index.
        currentDropIndex += 1
        let nextLb = dropChainPlannedLb[currentDropIndex - 1]
        pushWeight(nextLb)
        return .advance
    }

    /// Build a drop-set LoggedSet from the buffered per-drop snapshots and
    /// the parent's combined telemetry. Called by `handleCompletedSetsUpdate`
    /// when a drop chain has just finalized.
    private func autoLogDropChain(parentTelemetry telemetry: CompletedSet) {
        guard let ctx = modelContext, let instance = activeInstance else {
            // Defensive: if we can't persist, at least clear state.
            pendingDropSnapshots = []
            pendingDropPlannedWeights = []
            dropSetActive = false
            dropChainPlannedLb = []
            currentDropIndex = 1
            return
        }

        let order = (instance.sets?.count ?? 0) + 1
        // Drop #1 source-of-truth: prefer the buffered snapshot; fall back
        // to the parent telemetry if for some reason we missed buffering.
        let firstSnap = pendingDropSnapshots.first
        let drop1Weight = pendingDropPlannedWeights.first ?? (pendingPlannedWeightLb ?? 0)
        let drop1Reps = firstSnap?.reps ?? telemetry.reps
        let drop1Peak = firstSnap?.peakLb ?? telemetry.peakLb
        let drop1Started = firstSnap?.startedAt ?? telemetry.startedAt
        let drop1Ended = firstSnap?.endedAt ?? telemetry.endedAt

        let parent = LoggedSet(
            completedAt: Date(),
            startedAt: drop1Started,
            endedAt: drop1Ended,
            orderIndex: order,
            weightLb: drop1Weight,
            eccentricLb: upcomingEccLb > 0 ? upcomingEccLb : nil,
            reps: drop1Reps,
            chainsLb: nil,
            peakForceLb: drop1Peak,
            avgForceLb: nil,
            mode: .dropSet,
            labelText: SetMode.dropSet.label,
            notes: nil,
            autofilledFromTelemetry: true,
            importedFromHistory: false,
            inverseChains: false,
            damperLevel: nil,
            bandMaxForceLb: nil,
            addedLoadLb: upcomingAddedLoadLb,
            addedLoadType: upcomingAddedLoadType,
            instance: instance
        )
        ctx.insert(parent)

        // Persist drops 2..N as Drop rows. Snapshots are 1-indexed by chain
        // order; index [0] is drop #1 and lives on the parent.
        for i in 1..<pendingDropSnapshots.count {
            let snap = pendingDropSnapshots[i]
            let plannedW = i < pendingDropPlannedWeights.count
                ? pendingDropPlannedWeights[i]
                : 0
            let drop = Drop(
                order: i + 1,                       // 2..N (1-based)
                weightLb: plannedW,
                addedPlatesLb: upcomingAddedLoadLb,  // inherit from parent
                eccentricLb: upcomingEccLb > 0 ? upcomingEccLb : nil,
                reps: snap.reps,
                startedAt: snap.startedAt,
                endedAt: snap.endedAt,
                peakForceLb: snap.peakLb,
                avgForceLb: nil,
                loggedSet: parent
            )
            ctx.insert(drop)
        }

        setNumberForCurrentInstance = order + 1
        restAnchor = telemetry.endedAt
        pendingTelemetrySet = nil

        // Reset drop state — chain is done.
        pendingDropSnapshots = []
        pendingDropPlannedWeights = []
        dropSetActive = false
        dropChainPlannedLb = []
        currentDropIndex = 1
        // Restore upcoming mode to .working so the next set isn't accidentally
        // a drop set unless the user explicitly starts another one.
        upcomingMode = .working

        try? ctx.save()
    }

    /// v0.4.0: tap-to-edit on a logged-set row. Apply user-edited values to
    /// an existing LoggedSet and persist.
    func updateLoggedSet(
        _ set: LoggedSet,
        weightLb: Double,
        eccentricLb: Double?,
        reps: Int,
        addedLoadLb: Double?,
        addedLoadType: String?,
        mode: SetMode,
        notes: String?
    ) {
        set.weightLb = weightLb
        set.eccentricLb = eccentricLb
        set.reps = reps
        set.addedLoadLb = addedLoadLb
        set.addedLoadType = addedLoadType
        set.mode = mode
        set.labelText = mode.label
        set.notes = notes
        try? modelContext?.save()
    }

    /// v0.4.0: swipe-to-delete on a logged-set row. Returns a snapshot for the
    /// undo toast; call `restoreDeletedSet` within ~5 seconds to put it back.
    func deleteLoggedSet(_ set: LoggedSet) -> DeletedSetSnapshot? {
        guard let ctx = modelContext, let inst = set.instance else { return nil }
        let snap = DeletedSetSnapshot(set: set, instance: inst)
        ctx.delete(set)
        // Renumber remaining sets in this instance so orderIndex stays 1..N.
        let remaining = inst.orderedSets
        for (i, s) in remaining.enumerated() { s.orderIndex = i + 1 }
        setNumberForCurrentInstance = (inst.sets?.count ?? 0) + 1
        try? ctx.save()
        return snap
    }

    /// v0.4.0: restore a snapshot from `deleteLoggedSet`. Recreates the row
    /// at the end of its instance — the user's undoing a delete, exact
    /// position isn't critical.
    func restoreDeletedSet(_ snap: DeletedSetSnapshot) {
        guard let ctx = modelContext else { return }
        let order = (snap.instance.sets?.count ?? 0) + 1
        let revived = LoggedSet(
            completedAt: snap.completedAt,
            startedAt: snap.startedAt,
            endedAt: snap.endedAt,
            orderIndex: order,
            weightLb: snap.weightLb,
            eccentricLb: snap.eccentricLb,
            reps: snap.reps,
            chainsLb: snap.chainsLb,
            peakForceLb: snap.peakForceLb,
            avgForceLb: snap.avgForceLb,
            mode: snap.mode,
            labelText: snap.labelText,
            notes: snap.notes,
            autofilledFromTelemetry: snap.autofilledFromTelemetry,
            importedFromHistory: snap.importedFromHistory,
            inverseChains: snap.inverseChains,
            damperLevel: snap.damperLevel,
            bandMaxForceLb: snap.bandMaxForceLb,
            addedLoadLb: snap.addedLoadLb,
            addedLoadType: snap.addedLoadType,
            instance: snap.instance
        )
        ctx.insert(revived)
        setNumberForCurrentInstance = order + 1
        try? ctx.save()
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
        restAnchor = nil
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
        restAnchor = nil
        return result
    }

    func cancelSession() {
        guard let ctx = modelContext, let session = activeSession else { return }
        ctx.delete(session)
        activeSession = nil
        activeInstance = nil
        pendingTelemetrySet = nil
        setNumberForCurrentInstance = 1
        restAnchor = nil
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
        // New exercise = new rest baseline. The user just picked it; we don't
        // want a stale anchor from the prior exercise's last set carrying over.
        restAnchor = nil
        // v0.4.0 — sync our consumed-set marker to whatever SessionStore is
        // already holding so the FIRST telemetry-detected set on this new
        // instance actually fires `handleCompletedSetsUpdate` (the previous
        // bug: stale consumedSetCount left over from the prior exercise meant
        // sets.count > consumedSetCount was false on instance #1's first set).
        consumedSetCount = sessionStore?.completedSets.count ?? 0
        // v0.4.0 — added-load is per-instance. New exercise, fresh start.
        upcomingAddedLoadLb = nil
        upcomingAddedLoadType = nil

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
        // Anchor the rest timer to this set's actual end. Prefer the
        // telemetry-detected endedAt (the moment the Vulture went idle and
        // "reloaded" the weight) over Date() (which is when the user finally
        // tapped Log, possibly seconds later). If neither is available we
        // anchor to now so manual flows still get a rest countdown.
        // We DO overwrite any prior telemetry anchor here so each logged set
        // resets the rest counter — the user wants to track time since the
        // most recent set, not the first one in the instance.
        restAnchor = endedAt ?? restAnchor ?? Date()
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

    /// v0.4.0: ALL logged sets for an exercise across all prior sessions
    /// (excluding the active one). Drives the per-exercise progress chart on
    /// ExerciseDetailView. Includes imported-from-history rows so the chart
    /// reflects the user's full baseline. Sorted oldest → newest.
    func historicalSets(for exercise: Exercise) -> [LoggedSet] {
        let instances = (exercise.instances ?? []).filter { inst in
            guard let s = inst.session else { return false }
            if let active = activeSession, s.id == active.id { return false }
            return s.endedAt != nil || s.importedFromHistory
        }
        let allSets = instances.flatMap { $0.sets ?? [] }
        return allSets.sorted { (a, b) in
            let aDate = a.instance?.session?.startedAt ?? a.completedAt
            let bDate = b.instance?.session?.startedAt ?? b.completedAt
            return aDate < bDate
        }
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
                let baseLabel = s.labelText.isEmpty ? s.mode.label : s.labelText
                let chain = s.fullDropChain
                let label: String = {
                    if chain.count > 1 {
                        return "\(baseLabel) (drop×\(chain.count))"
                    }
                    return baseLabel
                }()
                let notes = s.notes ?? ""
                out += "\(s.orderIndex)      \(label.padded(8))  \(w.padded(10))  \(e.padded(11))  \(s.reps)     \(notes)\n"

                // v0.4.5: Drop-set chain. Render an indented arrow line
                // listing each drop's weight×reps, plus a per-drop peak
                // force line below it for the data nerds.
                if chain.count > 1 {
                    let arrow = chain
                        .map { "\(formatLb($0.weightLb))×\($0.reps)" }
                        .joined(separator: " → ")
                    out += "         ↳ \(arrow)\n"
                    let peaks = chain
                        .map { "\(formatLb($0.peakForceLb))" }
                        .joined(separator: " / ")
                    out += "         peak lb: \(peaks)\n"
                }
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

// MARK: - DeletedSetSnapshot (undo support)

/// Lightweight value-type snapshot of a LoggedSet captured at delete time so
/// the user can undo. We can't keep the SwiftData model alive after delete,
/// so we copy the fields out and recreate on restore.
struct DeletedSetSnapshot {
    let completedAt: Date
    let startedAt: Date?
    let endedAt: Date?
    let weightLb: Double
    let eccentricLb: Double?
    let reps: Int
    let chainsLb: Double?
    let peakForceLb: Double
    let avgForceLb: Double?
    let mode: SetMode
    let labelText: String
    let notes: String?
    let autofilledFromTelemetry: Bool
    let importedFromHistory: Bool
    let inverseChains: Bool
    let damperLevel: Int?
    let bandMaxForceLb: Double?
    let addedLoadLb: Double?
    let addedLoadType: String?
    let instance: ExerciseInstance

    init(set: LoggedSet, instance: ExerciseInstance) {
        self.completedAt = set.completedAt
        self.startedAt = set.startedAt
        self.endedAt = set.endedAt
        self.weightLb = set.weightLb
        self.eccentricLb = set.eccentricLb
        self.reps = set.reps
        self.chainsLb = set.chainsLb
        self.peakForceLb = set.peakForceLb
        self.avgForceLb = set.avgForceLb
        self.mode = set.mode
        self.labelText = set.labelText
        self.notes = set.notes
        self.autofilledFromTelemetry = set.autofilledFromTelemetry
        self.importedFromHistory = set.importedFromHistory
        self.inverseChains = set.inverseChains
        self.damperLevel = set.damperLevel
        self.bandMaxForceLb = set.bandMaxForceLb
        self.addedLoadLb = set.addedLoadLb
        self.addedLoadType = set.addedLoadType
        self.instance = instance
    }
}
