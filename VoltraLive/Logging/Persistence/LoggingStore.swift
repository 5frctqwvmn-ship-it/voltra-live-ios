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

    // MARK: - v0.4.6: Pulley Mode
    //
    // When the user routes the cable through a single pulley on a single
    // Voltra, the user-felt load is 2× the device's setting. Pulley Mode is
    // a per-set toggle that's STICKY across sets within an exercise instance
    // and reset on pickExercise. It affects user-facing display (force chart,
    // RESISTANCE/TOTAL VOL/FORCE tiles), drop-cascade math (cascade operates
    // on EFFECTIVE load and back-computes the device setting), and the
    // persisted weightLb / peakForceLb on each LoggedSet (we store EFFECTIVE
    // load so analytics reflect what the user actually moved).
    @Published var pulleyMode: Bool = false
    /// 2.0 when pulley mode is on, else 1.0.
    var pulleyMultiplier: Double { pulleyMode ? 2.0 : 1.0 }

    // MARK: - v0.4.6: Drop-set state (time-driven cascade)
    //
    // v0.4.6 redesign: drop sets are no longer planner-configured & telemetry-
    // driven. Tap the button → weight drops 20% IMMEDIATELY → an internal 4s
    // cascade timer keeps dropping another 20% on each tick → a separate 10s
    // "no movement" watchdog finalizes the set. The user sees a live preview
    // of the next two upcoming weights and two countdown progress bars on the
    // DROP SET tile.

    /// Whether the user is currently in a drop-set cascade.
    /// Drives UI affordances on LiveCaptureView.
    @Published var dropSetActive: Bool = false
    /// Realized per-drop Voltra base weights so far in the active cascade.
    /// Element [0] is the user's starting weight; [1..N] are the cascade
    /// drops fired by the 4s timer. Read by the UI to render the chain.
    @Published var dropChainPlannedLb: [Double] = []
    /// 1-based current drop within the active chain.
    @Published var currentDropIndex: Int = 1
    /// Cascade tick interval — every 4s we push the next drop using the
    /// current step tier.
    private let cascadeIntervalSec: Double = 4.0
    /// No-movement watchdog — set finalizes after this many seconds with
    /// no rep increment.
    private let cascadeIdleFinalizeSec: Double = 10.0
    /// v0.4.6.2: Force threshold for what counts as "real activity". Telemetry
    /// packets with sample force at-or-below this floor (machine jitter, slack
    /// cable noise, accelerometer drift) do NOT reset the 4s/10s idle timers.
    /// Without this floor, a noisy machine kept resetting the 4s fuse, so the
    /// 4s drop felt like 8s in the wild.
    private let cascadeIdleForceFloorLb: Double = 3.0
    /// v0.4.6.2: cooldown after cancelDropSet() during which a UI tap can NOT
    /// re-arm the cascade. Prevents long-press cancel from being immediately
    /// followed by SwiftUI's button tap firing startDropSet again.
    private var dropChainArmCooldownUntil: Date? = nil
    /// v0.4.6.2: original starting weight at chain-start, used as the anchor
    /// for tier-relative cascade math. Each cascade fire computes the next
    /// weight as `anchor − stepSize × stepIndex`, never compounding off the
    /// most recently dropped weight.
    private var chainAnchorLb: Double = 0
    /// v0.4.6.2: how many cascade drops have actually been pushed to the
    /// device since chain-start (drop #2, #3, ...). Drop #1 = the anchor itself.
    private var cascadeStepIndex: Int = 0
    /// Tier increment per tap. Tap #1 → 5 lb / 5%, tap #2 → 10/10%, etc.
    private let cascadeTierStepLb: Double = 5.0
    private let cascadeTierStepPct: Double = 0.05
    /// Current step tier. Starts at 1 (= 5 lb / 5%) on first tap; bumped
    /// by 1 every additional tap while a cascade is active.
    @Published var cascadeTier: Int = 1
    /// Human-readable label for the current step ("5 lb / 5%").
    var cascadeStepLabel: String {
        let lb = Double(cascadeTier) * cascadeTierStepLb
        let pct = Double(cascadeTier) * cascadeTierStepPct * 100
        return "\(formatLb(lb)) lb / \(formatLb(pct))%"
    }
    /// Wall-clock at which the next cascade drop will fire. Drives the 4s
    /// progress bar on the DROP SET tile. nil when cascade isn't running.
    @Published var nextDropFiresAt: Date? = nil
    /// Wall-clock at which the no-movement watchdog will finalize the set.
    /// Reset every time SessionStore reports a rep increment. nil when no
    /// cascade is running.
    @Published var dropFinalizeAt: Date? = nil
    /// Internal timer publishers and rep observation.
    private var cascadeTimer: AnyCancellable? = nil
    private var idleWatchdog: AnyCancellable? = nil
    private var dropRepObserver: AnyCancellable? = nil
    private var lastObservedReps: Int = 0
    /// Bridge to the BLE writer captured at startDropSet — invoked on each
    /// cascade tick to retarget the device.
    private var dropPushWeight: ((Double) -> Void)? = nil
    /// Per-drop telemetry snapshots collected during the chain. The parent
    /// LoggedSet's top-level fields will be populated from element [0]; any
    /// elements [1..N] become Drop rows.
    private var pendingDropSnapshots: [DropBoundarySnapshot] = []
    /// Per-drop planned weight at index — kept aligned with snapshots so
    /// the persisted Drop carries the planned Voltra weight rather than
    /// relying on `pendingPlannedWeightLb` mutating during the chain.
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
        // Pulley mode multiplies the user-felt load. We persist EFFECTIVE
        // weight + EFFECTIVE peak force so analytics reflect what the user
        // actually moved, not the device setting.
        let m = pulleyMultiplier
        let weight = (pendingPlannedWeightLb ?? 0) * m
        let ecc = upcomingEccLb > 0 ? upcomingEccLb * m : nil
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
            peakForceLb: telemetry.peakLb * m,
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

    /// v0.4.6: Start a time-driven drop cascade from the current weight.
    /// Behavior:
    ///   1. Drops the device weight by 20% IMMEDIATELY (drop #2).
    ///   2. Every `cascadeIntervalSec` seconds, drops another 20% until the
    ///      computed step no longer decreases (rounded to 2.5 lb floor).
    ///   3. A separate `cascadeIdleFinalizeSec` watchdog finalizes the set
    ///      when no rep has been seen for that long, finalizing the set
    ///      via SessionStore's normal flow.
    /// `pushWeight` bridges to the BLE writer; called on each cascade tick.
    func startDropSet(startingLb: Double, pushWeight: @escaping (Double) -> Void) {
        guard let session = sessionStore else { return }
        guard startingLb > 0 else { return }
        // v0.4.6.2: refuse to (re-)arm during the cancel cooldown so a long-press
        // cancel + simultaneous button tap doesn't immediately restart the chain.
        if let cd = dropChainArmCooldownUntil, Date() < cd { return }

        // Tear down any prior cascade state defensively.
        stopCascadeTimers()

        dropSetActive = true
        currentDropIndex = 1
        cascadeTier = 1            // tap #1 = tier 1 (5 lb / 5%)
        pendingDropSnapshots = []
        pendingDropPlannedWeights = []
        dropPushWeight = pushWeight
        // v0.4.6.2: anchor the chain to the starting weight. All subsequent
        // cascade weights are computed as `anchor − step×index` (or the pct
        // equivalent) NEVER compounding off the previously-dropped value.
        chainAnchorLb = startingLb
        cascadeStepIndex = 0

        // Drop #1 = the starting weight (what the user was just lifting).
        // We seed the chain with it so history rendering stays consistent.
        dropChainPlannedLb = [startingLb]
        pendingPlannedWeightLb = startingLb

        // Lock the parent set's logging mode to .dropSet.
        upcomingMode = .dropSet

        // Tell SessionStore we're in drop mode + register a boundary
        // callback that ALWAYS returns .advance until we explicitly stop.
        // This lets us reuse SessionStore's per-drop reps/peak slicing for
        // the snapshot record while we drive cascade timing ourselves.
        session.beginDropChain()
        session.onDropBoundary = { [weak self] snap in
            self?.recordDropSnapshot(snap)
            return .advance
        }

        // Fire drop #2 IMMEDIATELY (−20%). The user wants the press of
        // the button to feel instant.
        fireNextCascadeStep()

        // Start the recurring cascade timer (drops #3, #4, …).
        scheduleCascadeTimer()

        // Start the no-movement watchdog (10s of no rep increment → finalize).
        startIdleWatchdog()
    }

    /// Cancel an in-flight drop cascade WITHOUT finalizing the set. The
    /// currently in-flight set keeps accumulating but as a normal set.
    func cancelDropSet() {
        stopCascadeTimers()
        dropSetActive = false
        dropChainPlannedLb = []
        currentDropIndex = 1
        cascadeTier = 1
        chainAnchorLb = 0
        cascadeStepIndex = 0
        pendingDropSnapshots = []
        pendingDropPlannedWeights = []
        nextDropFiresAt = nil
        dropFinalizeAt = nil
        dropPushWeight = nil
        // v0.4.6.2: 1.5s arm cooldown. The SwiftUI Button + simultaneous
        // LongPressGesture both fire on touch-up, so without a cooldown
        // the cancel is immediately re-armed by the same gesture's tap.
        dropChainArmCooldownUntil = Date().addingTimeInterval(1.5)
        sessionStore?.endDropChainModeOnly()
    }

    /// v0.4.6: User tapped the DROP SET tile while a cascade is already
    /// running. Bump the tier (5→10→15…), fire an immediate drop using
    /// the new tier, and reset the 4s next-drop fuse so auto-cascade keeps
    /// pace from now using the new tier.
    /// v0.4.6.2: tap rolls 5→10→15→5 (mod 3). Each fired drop is computed
    /// as `anchor − stepSize×index` so subsequent taps don't compound off
    /// the previously-dropped weight.
    ///
    /// v0.4.8 (build 30): tier bump is now PREVIEW-ONLY. It does NOT fire a
    /// cascade step — earlier behavior fired one drop per tap, which made it
    /// impossible to use tap as a tier selector (every tap dropped the
    /// weight). The 4s fuse (`scheduleCascadeTimer` / `nextDropFiresAt`)
    /// remains the sole trigger for committing a drop. The fuse is reset
    /// here so the user has a fresh 4s window to bump again before any
    /// drop commits at the new tier.
    func bumpCascadeTier() {
        guard dropSetActive else { return }
        // Roll 1 → 2 → 3 → 1… (5/10/15 lb steps).
        cascadeTier = (cascadeTier % 3) + 1
        // Reset the 4s fuse so the user has a full window after each bump
        // to keep tapping. Do NOT fire a step here.
        cascadeTimer?.cancel(); cascadeTimer = nil
        scheduleCascadeTimer()
        // Bumping counts as activity — push the no-movement watchdog out.
        dropFinalizeAt = Date().addingTimeInterval(cascadeIdleFinalizeSec)
    }

    /// v0.4.6.1: Called from the BLE pipeline on every telemetry packet.
    /// While a drop cascade is active, ANY packet (motion, force, phase
    /// change) resets BOTH timers:
    ///   - the 4s next-drop fuse (`nextDropFiresAt`) so the cable doesn't
    ///     auto-drop while the user is mid-rep, and
    ///   - the 10s no-movement finalize watchdog (`dropFinalizeAt`) so the
    ///     set isn't ended out from under them.
    /// No-op when `dropSetActive == false` so this is safe to call on every
    /// packet regardless of session state.
    func noteTelemetryActivity(forceLb: Double = .infinity) {
        guard dropSetActive else { return }
        // v0.4.6.2: ignore sub-threshold packets so machine jitter doesn't
        // hold the timers open indefinitely. The default `.infinity` keeps
        // older callers (no force info) behaving as "always reset".
        guard forceLb > cascadeIdleForceFloorLb else { return }
        let now = Date()
        nextDropFiresAt = now.addingTimeInterval(cascadeIntervalSec)
        dropFinalizeAt = now.addingTimeInterval(cascadeIdleFinalizeSec)
        // Also restart the 4s recurring timer so its next tick is 4s from
        // NOW, not 4s from when the last drop fired. Without this, the
        // Combine timer keeps its original phase and may fire mid-rep.
        if cascadeTimer != nil {
            cascadeTimer?.cancel()
            cascadeTimer = Timer.publish(every: cascadeIntervalSec, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.fireNextCascadeStep()
                }
        }
        // Bump the watchdog's reps anchor so checkCascadeIdle sees activity.
        lastObservedReps = sessionStore?.currentSet?.reps ?? lastObservedReps
    }

    // MARK: - v0.4.6: Cascade machinery

    /// v0.4.6.2: Compute the next cascade weight from the chain ANCHOR (not
    /// the most recently dropped weight). Each fire takes one step
    /// `cascadeStepIndex+1` away from the original starting weight, sized by
    /// the current tier. This way, bumping the tier mid-chain doesn't compound
    /// past drops — it re-applies to the original anchor at the deeper step.
    /// Drop math runs on EFFECTIVE load and back-computes the device setting,
    /// so a 100 lb effective set under 2× pulley drops as 100→95 effective
    /// (= 50→47.5 on the device), not 50→45.
    private func nextCascadeWeight() -> Double? {
        guard chainAnchorLb > 0 else { return nil }
        let nextIndex = cascadeStepIndex + 1
        let next = LoggingStore.cascadeAnchoredDeviceWeight(
            anchorDeviceLb: chainAnchorLb,
            tier: cascadeTier,
            stepIndex: nextIndex,
            multiplier: pulleyMultiplier
        )
        // Stop if we've hit the floor or rounding made the step a no-op.
        let prev = dropChainPlannedLb.last ?? chainAnchorLb
        if next <= 0 || next >= prev { return nil }
        return next
    }

    /// Compute a preview of the upcoming next-N cascade weights using the
    /// caller-supplied tier (defaults to current `cascadeTier`). Pure —
    /// does not mutate state. Returns EFFECTIVE (user-felt) weights so the UI
    /// tile shows what the user will actually be lifting under pulley mode.
    /// `currentLb` is the current EFFECTIVE weight (i.e. already multiplied).
    func previewNextCascade(from currentLb: Double, count: Int, tier: Int? = nil) -> [Double] {
        let useTier = tier ?? cascadeTier
        var out: [Double] = []
        // v0.4.6.2: preview now matches anchor-relative math — each step is
        // computed off the original `currentLb` (the anchor) at increasing
        // stepIndex, NOT compounded off the previous result. Otherwise the
        // tile preview would lie about what the cascade will actually do.
        for i in 1...max(1, count) {
            let next = LoggingStore.cascadeAnchoredDeviceWeight(
                anchorDeviceLb: currentLb,
                tier: useTier,
                stepIndex: i,
                multiplier: 1.0
            )
            // Stop on floor or non-progress (each step must be smaller than
            // the previous, which under fixed step size is guaranteed unless
            // we hit zero).
            if next <= 0 { break }
            if let last = out.last, next >= last { break }
            out.append(next)
            if out.count >= count { break }
        }
        return out
    }

    /// Push the next cascade step to the device. Updates state and the
    /// next-fire timestamp. If the cascade can't go any lower, stops the
    /// cascade timer (the watchdog will eventually finalize).
    /// v0.4.6.2: increments `cascadeStepIndex` so the next call walks one
    /// more step away from the anchor.
    private func fireNextCascadeStep() {
        guard let next = nextCascadeWeight() else {
            // Bottomed out — stop dropping but leave watchdog running so
            // the set can still finalize on idle.
            cascadeTimer?.cancel()
            cascadeTimer = nil
            nextDropFiresAt = nil
            return
        }
        cascadeStepIndex += 1
        dropChainPlannedLb.append(next)
        currentDropIndex = dropChainPlannedLb.count
        pendingPlannedWeightLb = next
        dropPushWeight?(next)
        nextDropFiresAt = Date().addingTimeInterval(cascadeIntervalSec)
    }

    /// Schedule a recurring 4s timer that fires the next cascade step.
    private func scheduleCascadeTimer() {
        nextDropFiresAt = Date().addingTimeInterval(cascadeIntervalSec)
        cascadeTimer = Timer.publish(every: cascadeIntervalSec, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fireNextCascadeStep()
            }
    }

    /// Start a periodic check that finalizes the set when no rep has been
    /// observed for `cascadeIdleFinalizeSec`. We DON'T finalize via
    /// SessionStore's normal idle path (which is 4s) — cascade sets get a
    /// longer fuse so a slow last drop isn't cut off.
    private func startIdleWatchdog() {
        lastObservedReps = sessionStore?.currentSet?.reps ?? 0
        dropFinalizeAt = Date().addingTimeInterval(cascadeIdleFinalizeSec)
        idleWatchdog = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkCascadeIdle()
            }
    }

    /// 0.5s tick: if reps incremented, reset the no-movement deadline.
    /// Otherwise, if the deadline has passed, finalize the set.
    private func checkCascadeIdle() {
        guard dropSetActive, let session = sessionStore else { return }
        let reps = session.currentSet?.reps ?? 0
        if reps > lastObservedReps {
            lastObservedReps = reps
            dropFinalizeAt = Date().addingTimeInterval(cascadeIdleFinalizeSec)
            return
        }
        if let deadline = dropFinalizeAt, Date() >= deadline {
            finalizeCascade()
        }
    }

    /// Cleanly end the cascade and finalize the parent set.
    private func finalizeCascade() {
        // Stop our own timers FIRST so we don't re-enter.
        stopCascadeTimers()
        nextDropFiresAt = nil
        dropFinalizeAt = nil
        // Tell SessionStore to drop boundary mode (so the next idle goes
        // through the normal finalize path) then trigger finalize via the
        // public path. SessionStore's onDropBoundary is wired to .advance,
        // so we have to clear it before letting normal finalize fire.
        sessionStore?.endDropChainModeOnly()
        sessionStore?.forceFinalizeCurrentSet()
        // Drop UI state cleared in autoLogDropChain when handleCompletedSetsUpdate
        // routes the just-finalized parent telemetry through us.
    }

    /// Cancel all timers but leave dropSetActive untouched (caller decides).
    private func stopCascadeTimers() {
        cascadeTimer?.cancel(); cascadeTimer = nil
        idleWatchdog?.cancel(); idleWatchdog = nil
    }

    /// SessionStore boundary callback handler. Buffers the per-drop snapshot
    /// so autoLogDropChain can persist Drop rows.
    private func recordDropSnapshot(_ snap: DropBoundarySnapshot) {
        pendingDropSnapshots.append(snap)
        let plannedThis = (snap.order - 1) < dropChainPlannedLb.count
            ? dropChainPlannedLb[snap.order - 1]
            : (pendingPlannedWeightLb ?? 0)
        pendingDropPlannedWeights.append(plannedThis)
    }

    /// v0.4.6 cascade rule: drop = MAX(absoluteLb, percent × current).
    /// We take the LARGER drop — the user wants aggressive cascades.
    /// `tier` multiplies the base step (5 lb / 5%): tier 1 = 5/5%, tier 2 =
    /// 10/10%, etc. Operates on the input coordinate space directly.
    static func cascadeNextWeight(from currentLb: Double, tier: Int,
                                  baseLb: Double = 5.0,
                                  basePct: Double = 0.05) -> Double {
        guard currentLb > 0, tier >= 1 else { return 0 }
        let absDrop = baseLb * Double(tier)
        let pctDrop = currentLb * basePct * Double(tier)
        let drop = max(absDrop, pctDrop)
        let raw = currentLb - drop
        // Round to 2.5 lb. Round to nearest (not down) so 47.5 stays 47.5
        // and 48.7 → 50 only when the rounded result is still < current.
        let stepped = (raw / 2.5).rounded() * 2.5
        // Guard against rounding pushing the result back up to/above current.
        if stepped >= currentLb { return max(0, currentLb - 2.5) }
        return max(0, stepped)
    }

    /// v0.4.6.2: Anchor-relative cascade. Given the original starting weight
    /// and a step index N (1, 2, 3, …), returns the device weight after the
    /// Nth drop. Each step is `max(tier×5 lb, anchor×0.05×tier)` measured
    /// off the ANCHOR — NEVER compounding off prior drops. This is what makes
    /// retiering mid-chain behave correctly: bumping tier from 1 to 2 with
    /// stepIndex=2 means next weight is `anchor − 10×2 = anchor − 20`, not
    /// `prev_drop − 20`. Pulley-aware: math runs on EFFECTIVE load.
    static func cascadeAnchoredDeviceWeight(anchorDeviceLb: Double,
                                            tier: Int,
                                            stepIndex: Int,
                                            multiplier: Double) -> Double {
        guard anchorDeviceLb > 0, tier >= 1, stepIndex >= 1, multiplier > 0 else { return 0 }
        let anchorEffective = anchorDeviceLb * multiplier
        // Per-step magnitude (constant across the chain at the current tier).
        let perStepLb = 5.0 * Double(tier)
        let perStepPct = 0.05 * Double(tier)
        let perStep = max(perStepLb, anchorEffective * perStepPct)
        let totalDrop = perStep * Double(stepIndex)
        let nextEffective = anchorEffective - totalDrop
        if nextEffective <= 0 { return 0 }
        let backToDevice = nextEffective / multiplier
        let stepped = (backToDevice / 2.5).rounded() * 2.5
        if stepped >= anchorDeviceLb { return max(0, anchorDeviceLb - 2.5) }
        return max(0, stepped)
    }

    /// Cascade variant that respects pulley mode. Converts device weight →
    /// effective, applies the tiered drop on EFFECTIVE load, back-computes
    /// the device weight (effective / multiplier), and re-rounds to 2.5 lb.
    /// Pass `multiplier: 1.0` to operate directly on whatever coordinate
    /// space `fromDeviceLb` is already in (effective or device).
    static func cascadeNextDeviceWeight(fromDeviceLb deviceLb: Double,
                                        tier: Int,
                                        multiplier: Double) -> Double {
        guard deviceLb > 0, tier >= 1, multiplier > 0 else { return 0 }
        let effective = deviceLb * multiplier
        let nextEffective = cascadeNextWeight(from: effective, tier: tier)
        if nextEffective <= 0 || nextEffective >= effective { return 0 }
        let backToDevice = nextEffective / multiplier
        // Re-round to 2.5 lb on the device coordinate.
        let stepped = (backToDevice / 2.5).rounded() * 2.5
        if stepped >= deviceLb { return max(0, deviceLb - 2.5) }
        return max(0, stepped)
    }

    /// Legacy helper kept for any callers that still reference flat-percent
    /// drop math (e.g. preview computations on initial entry). Forwards to
    /// the new max(abs, pct) rule using tier 1 by default.
    static func dropStepLb(stepPercent: Double, from currentLb: Double) -> Double {
        return cascadeNextWeight(from: currentLb, tier: 1)
    }

    /// Build a drop-set LoggedSet from the buffered per-drop snapshots and
    /// the parent's combined telemetry. Called by `handleCompletedSetsUpdate`
    /// when a drop chain has just finalized.
    private func autoLogDropChain(parentTelemetry telemetry: CompletedSet) {
        guard let ctx = modelContext, let instance = activeInstance else {
            // Defensive: if we can't persist, at least clear state.
            stopCascadeTimers()
            pendingDropSnapshots = []
            pendingDropPlannedWeights = []
            dropSetActive = false
            dropChainPlannedLb = []
            currentDropIndex = 1
            cascadeTier = 1
            chainAnchorLb = 0
            cascadeStepIndex = 0
            nextDropFiresAt = nil
            dropFinalizeAt = nil
            dropPushWeight = nil
            return
        }

        let order = (instance.sets?.count ?? 0) + 1
        // Pulley mode → persist EFFECTIVE load on every drop row.
        let m = pulleyMultiplier
        // Drop #1 source-of-truth: prefer the buffered snapshot; fall back
        // to the parent telemetry if for some reason we missed buffering.
        let firstSnap = pendingDropSnapshots.first
        let drop1Weight = (pendingDropPlannedWeights.first ?? (pendingPlannedWeightLb ?? 0)) * m
        let drop1Reps = firstSnap?.reps ?? telemetry.reps
        let drop1Peak = (firstSnap?.peakLb ?? telemetry.peakLb) * m
        let drop1Started = firstSnap?.startedAt ?? telemetry.startedAt
        let drop1Ended = firstSnap?.endedAt ?? telemetry.endedAt

        let parent = LoggedSet(
            completedAt: Date(),
            startedAt: drop1Started,
            endedAt: drop1Ended,
            orderIndex: order,
            weightLb: drop1Weight,
            eccentricLb: upcomingEccLb > 0 ? upcomingEccLb * m : nil,
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
                ? pendingDropPlannedWeights[i] * m
                : 0
            let drop = Drop(
                order: i + 1,                       // 2..N (1-based)
                weightLb: plannedW,
                addedPlatesLb: upcomingAddedLoadLb,  // inherit from parent
                eccentricLb: upcomingEccLb > 0 ? upcomingEccLb * m : nil,
                reps: snap.reps,
                startedAt: snap.startedAt,
                endedAt: snap.endedAt,
                peakForceLb: snap.peakLb * m,
                avgForceLb: nil,
                loggedSet: parent
            )
            ctx.insert(drop)
        }

        setNumberForCurrentInstance = order + 1
        restAnchor = telemetry.endedAt
        pendingTelemetrySet = nil

        // Reset drop state — chain is done.
        stopCascadeTimers()
        pendingDropSnapshots = []
        pendingDropPlannedWeights = []
        dropSetActive = false
        dropChainPlannedLb = []
        currentDropIndex = 1
        cascadeTier = 1
        chainAnchorLb = 0
        cascadeStepIndex = 0
        nextDropFiresAt = nil
        dropFinalizeAt = nil
        dropPushWeight = nil
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
        // v0.4.6 — pulley mode is sticky-to-next-set within an instance,
        // but resets on a new exercise.
        pulleyMode = false

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

    /// Most recent warmup set logged for a given exercise.
    /// Used by SetLogView to pre-fill the warmup weight on the first set of a
    /// new instance. Returns nil if the user has never logged a warmup for
    /// this exercise — caller should fall back to 50% of the last working set.
    func lastWarmup(for exercise: Exercise) -> LoggedSet? {
        guard let ctx = modelContext else { return nil }
        var desc = FetchDescriptor<LoggedSet>(
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        // Look back further than lastSet because warmups are rarer than
        // working sets; 200 covers many months of training history.
        desc.fetchLimit = 200
        let candidates = (try? ctx.fetch(desc)) ?? []
        return candidates.first {
            $0.instance?.exercise?.id == exercise.id && $0.mode == .warmUp
        }
    }

    /// Last *working* set for a given exercise — used as the anchor for the
    /// 50%-of-working-weight warmup fallback when the user has no prior
    /// warmup logged for the exercise.
    func lastWorkingSet(for exercise: Exercise) -> LoggedSet? {
        guard let ctx = modelContext else { return nil }
        var desc = FetchDescriptor<LoggedSet>(
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        desc.fetchLimit = 200
        let candidates = (try? ctx.fetch(desc)) ?? []
        return candidates.first {
            guard $0.instance?.exercise?.id == exercise.id else { return false }
            // Working OR eccentric/dropSet — anything that's not a warmup —
            // counts as a working anchor.
            return $0.mode != .warmUp
        }
    }

    /// True when the active instance has no logged sets yet — i.e. the next
    /// set will be the first set on this exercise this session. Used by
    /// SetLogView to decide whether to auto-suggest warmup mode.
    var isFirstSetOfActiveInstance: Bool {
        guard let inst = activeInstance else { return false }
        return setNumberForCurrentInstance == 1 && (inst.sets?.isEmpty ?? true)
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

// MARK: - Test hooks (build-30: drop-set regression tests)
//
// DEBUG-only surface so XCTest can drive the cascade synchronously without
// waiting on the real 4s `Timer.publish` recurrence. Production binaries are
// unaffected: `#if DEBUG` is set by the test target's xcodebuild config and
// not by Release archives.

#if DEBUG
extension LoggingStore {
    /// Test-only pair: a LoggingStore plus the SessionStore it depends on.
    /// `LoggingStore.sessionStore` is declared `weak`, so the test owner
    /// MUST hold the returned `session` for the lifetime of the test —
    /// otherwise the weak ref deallocates the moment the factory returns
    /// and `startDropSet` early-exits at `guard let session = sessionStore`.
    @MainActor
    static func makeForTestingWithSession() -> (store: LoggingStore, session: SessionStore) {
        let store = LoggingStore()
        let session = SessionStore()
        store.sessionStore = session
        return (store, session)
    }

    /// Convenience for callers that don't need a handle on the SessionStore.
    /// Note: with this overload the SessionStore is owned only by the
    /// LoggingStore's weak ref, so it deallocates immediately. Tests that
    /// drive `startDropSet` MUST use `makeForTestingWithSession()` and
    /// retain the returned session.
    @MainActor
    static func makeForTesting() -> LoggingStore {
        return makeForTestingWithSession().store
    }

    /// Synchronously advance the cascade by one step. Bypasses the 4s
    /// recurring timer so tests stay deterministic. Mirrors what the
    /// internal `Timer.publish` sink would do on each tick.
    @MainActor
    func testFireCascadeStep() {
        fireNextCascadeStep()
    }
}
#endif
