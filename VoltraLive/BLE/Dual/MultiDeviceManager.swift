// MultiDeviceManager.swift
//
// v0.4.7 build 29: orchestrates dual-Voltra operation.
//
// Owns:
//   - Two VoltraBLEManager instances (one per slot: .left / .right).
//   - Two VoltraWriter instances bound to those managers.
//   - The DualMode the user has selected (.independent | .combined).
//   - The Combined-mode disconnect watchdog: if either drops, send UNLOAD
//     to the survivor (best-effort) and start auto-reconnect on the dropped
//     side.
//
// Does NOT own:
//   - The single-device VoltraBLEManager. That stays as-is in VoltraLiveApp,
//     so the existing single-Voltra flow has zero regression risk.
//   - SessionStore / LoggingStore wiring. The app is responsible for
//     subscribing to per-device telemetry via the onTelemetry hooks below
//     and routing into the right logging stream.
//
// State model:
//   .idle         \u2014 nothing connected on the dual track. (Single track may
//                   still be using the legacy bleManager.)
//   .pairing      \u2014 user picked first Voltra; waiting for second.
//   .pairedOne    \u2014 only one slot connected.
//   .pairedBoth   \u2014 both slots connected.
//   .errorBanner  \u2014 a Combined-mode drop just happened; UI shows the banner;
//                   reconnect is in flight.
//
// Telemetry routing:
//   The app sets `onLeftTelemetry` / `onRightTelemetry` to closures that route
//   each side's telemetry independently to LoggingStore (Independent mode) or
//   to a combined aggregator (Combined mode). The MDM does NOT decide which.
//   It also exposes `onCombinedTelemetry` which fires on every per-device
//   packet with the merged virtual-twin reading using CombinedMath.

import Foundation
import CoreBluetooth
import Combine

// MARK: - Public state

enum MultiState: Equatable {
    case idle
    /// One slot has a connected device; we're waiting on (or actively
    /// connecting) the second slot.
    case pairingSecond(connectedSlot: DeviceSlot)
    case pairedOne(slot: DeviceSlot)
    case pairedBoth
    /// Combined-mode drop just happened. `dropped` says which side fell.
    /// Reconnect attempt is running in the background.
    case errorReconnecting(dropped: DeviceSlot, message: String)
}

// MARK: - MultiDeviceManager

@MainActor
final class MultiDeviceManager: ObservableObject {

    // MARK: Devices (one per slot)
    @Published private(set) var left:  VoltraBLEManager
    @Published private(set) var right: VoltraBLEManager

    // Writers, one per slot. Bound to each manager's writeControlFrame.
    private(set) var leftWriter:  VoltraWriter!
    private(set) var rightWriter: VoltraWriter!

    // Stable identifiers we used to connect each slot. Used for auto-reconnect.
    private var leftIdentifier:  UUID? = nil
    private var rightIdentifier: UUID? = nil

    // MARK: Mode + state
    @Published var mode: DualMode = .independent
    @Published private(set) var state: MultiState = .idle

    /// Build 42: workout-scoped mode the user picks pre-workout when both
    /// Voltras are paired. Drives telemetry routing in VoltraLiveApp:
    ///   .singleLeft  -> only left telemetry forwarded.
    ///   .singleRight -> only right telemetry forwarded.
    ///   .independent -> both sides forwarded raw (no summing).
    ///   .combined    -> virtual-twin merged reading (force/reps summed).
    /// Default `.singleLeft` honors the user direction "having them dual
    /// mode by default is not by intent" \u2014 even when both are paired,
    /// only one is engaged unless they explicitly opt into a dual mode.
    /// Persisted in memory only; resets to .singleLeft on app relaunch.
    @Published var workoutMode: WorkoutMode = .singleLeft

    /// b48: Superset chain \u2014 which side is currently the ACTIVE exercise.
    /// The user does set A on this side, then taps the swap button (or
    /// finalizes a set, which auto-flips), and the active slot flips. State
    /// writes route only to the active side so each Voltra's standing
    /// resistance for its own exercise is preserved while the other is
    /// being used. Default `.left` so the user opens at exercise A.
    @Published var supersetActiveSlot: DeviceSlot = .left

    /// b48: Per-side standing weight in Superset mode. Each Voltra holds
    /// its OWN exercise's resistance independently; flipping `supersetActiveSlot`
    /// must NOT clobber the other side's setting. The view layer reads
    /// these to render the inactive-side preview chip and writes them when
    /// the user changes resistance for whichever side is currently active.
    /// Stored in lb on the device coordinate (not effective).
    @Published var supersetLeftWeightLb:  Double = 0
    @Published var supersetRightWeightLb: Double = 0

    /// b48: Per-side exercise label. Free-form because the user picks
    /// arbitrary exercise names from the catalog \u2014 we don't try to
    /// validate. Empty string means "no name set yet" (UI shows a hint).
    @Published var supersetLeftExercise:  String = ""
    @Published var supersetRightExercise: String = ""

    // b48 v2 (build 48): Superset CHAIN. The user can queue an arbitrary
    // number of exercises into a chain BEFORE the live capture screen
    // starts; each entry is bound to a specific Voltra slot. The SWAP
    // button advances through the chain (left/right alternation comes
    // from the entry order, not from a hardcoded toggle). Empty chain =
    // legacy two-exercise mode (left = A, right = B).
    //
    // User direction (verbatim, this session): "there should be another
    // button under it. It says Add Another Superset. and then that
    // should take you back up to the main tile screen." The chain is
    // built up via that button on ExerciseStartView; LiveCaptureView
    // just consumes it.

    /// One entry in the superset chain.
    struct SupersetChainEntry: Equatable, Identifiable {
        let id: UUID
        /// Display name from the Exercise catalog (e.g. "Back Squat").
        let exerciseName: String
        /// Which Voltra is loaded for this exercise.
        let slot: DeviceSlot
        /// Planned starting weight in lb (device coordinate).
        let plannedWeightLb: Double
        init(exerciseName: String, slot: DeviceSlot, plannedWeightLb: Double) {
            self.id = UUID()
            self.exerciseName = exerciseName
            self.slot = slot
            self.plannedWeightLb = plannedWeightLb
        }
    }

    /// Ordered queue of exercises in the current superset. Empty before
    /// the user adds anything (or in non-superset modes). The active
    /// entry is `supersetChain[supersetChainIndex]` if the index is in
    /// range; SWAP advances the index modulo chain length.
    @Published var supersetChain: [SupersetChainEntry] = []

    /// Index into `supersetChain` of the currently-active entry. Wraps
    /// modulo chain length on SWAP. Ignored when chain is empty.
    @Published var supersetChainIndex: Int = 0

    /// Tick that ExerciseStartView bumps when the user taps "Add Another
    /// Superset". LoggingHomeView watches this in `.onChange` and pops
    /// its NavigationStack back to the day-tile screen so the user can
    /// pick the next exercise without leaving superset mode. Same
    /// pattern as `LoggingStore.sessionExitTick`.
    @Published var supersetReturnToHomeTick: Int = 0

    /// Append an exercise to the superset chain. Called by ExerciseStartView
    /// when the user taps "Add Another Superset" or "Start" in superset
    /// mode. Also stamps the per-side weight + label so the live banner
    /// renders correctly even if the chain is read piecemeal.
    func appendSupersetEntry(name: String, slot: DeviceSlot, weightLb: Double) {
        let entry = SupersetChainEntry(
            exerciseName: name,
            slot: slot,
            plannedWeightLb: weightLb
        )
        supersetChain.append(entry)
        // Mirror onto the per-side caches that LiveCaptureView's banner
        // consults so the OFF-active preview chip shows the right name +
        // weight even before the user has SWAPped into that side.
        switch slot {
        case .left:
            supersetLeftExercise = name
            supersetLeftWeightLb = weightLb
        case .right:
            supersetRightExercise = name
            supersetRightWeightLb = weightLb
        }
        // The active slot tracks whichever entry is at
        // supersetChainIndex. If the new entry is the first one, point
        // the index at it so the user opens at THIS exercise.
        if supersetChain.count == 1 {
            supersetChainIndex = 0
            supersetActiveSlot = slot
        }
    }

    /// Reset the chain. Called when the user exits a session or picks a
    /// non-superset workoutMode.
    func clearSupersetChain() {
        supersetChain.removeAll()
        supersetChainIndex = 0
        supersetLeftExercise = ""
        supersetRightExercise = ""
        supersetLeftWeightLb = 0
        supersetRightWeightLb = 0
    }

    /// Bump the home-return tick. ExerciseStartView calls this from
    /// "Add Another Superset" so LoggingHomeView pops to root.
    func requestSupersetReturnToHome() {
        supersetReturnToHomeTick &+= 1
    }

    /// b48: Flip the active side. Called by:
    ///   - The user tapping the SWAP tile in the live grid.
    ///   - LoggingStore on set finalize (auto-advance through the chain).
    /// When the chain has 2+ entries, advances chainIndex modulo length
    /// and points supersetActiveSlot at the new entry's slot. With an
    /// empty chain (legacy mode), just toggles left/right.
    func flipSupersetActiveSlot() {
        if supersetChain.count >= 2 {
            supersetChainIndex = (supersetChainIndex + 1) % supersetChain.count
            supersetActiveSlot = supersetChain[supersetChainIndex].slot
        } else {
            supersetActiveSlot = supersetActiveSlot.other
        }
    }

    /// Read the active chain entry, or nil if the chain is empty.
    var activeSupersetEntry: SupersetChainEntry? {
        guard supersetChain.indices.contains(supersetChainIndex) else { return nil }
        return supersetChain[supersetChainIndex]
    }

    /// Read the NEXT chain entry (what SWAP will land on), or nil if the
    /// chain has fewer than 2 entries.
    var nextSupersetEntry: SupersetChainEntry? {
        guard supersetChain.count >= 2 else { return nil }
        let next = (supersetChainIndex + 1) % supersetChain.count
        return supersetChain[next]
    }

    // MARK: Telemetry routing hooks (set by the app)
    /// Fired on every Telemetry packet from the LEFT device.
    var onLeftTelemetry:  ((Telemetry) -> Void)?
    /// Fired on every Telemetry packet from the RIGHT device.
    var onRightTelemetry: ((Telemetry) -> Void)?
    /// Fired with the merged virtual-twin reading after every per-device
    /// telemetry. Only meaningful in `.combined` mode \u2014 the app may choose
    /// to ignore it in Independent mode.
    var onCombinedTelemetry: ((CombinedTelemetry) -> Void)?

    // MARK: Subscriptions
    private var bag = Set<AnyCancellable>()

    // MARK: Reconnect controller
    /// Outstanding auto-reconnect tasks per slot. Cancelled if the user
    /// manually disconnects or a fresh connect succeeds.
    private var reconnectTasks: [DeviceSlot: Task<Void, Never>] = [:]
    /// Maximum total time we'll keep retrying before giving up and switching
    /// the banner to "manual reconnect required".
    private let reconnectTimeoutSeconds: TimeInterval = 30

    // MARK: Init

    init() {
        self.left  = VoltraBLEManager()
        self.right = VoltraBLEManager()

        // Bind writers to each manager's BLE characteristic write.
        // The writer holds a closure, so the strong reference is one-way and
        // doesn't create a retain cycle with the manager.
        self.leftWriter = VoltraWriter(
            writeFrame: { [weak self] data in self?.left.writeControlFrame(data)  },
            log:        { [weak self] msg  in self?.left.addLog(msg) }
        )
        self.rightWriter = VoltraWriter(
            writeFrame: { [weak self] data in self?.right.writeControlFrame(data) },
            log:        { [weak self] msg  in self?.right.addLog(msg) }
        )

        // Wire each device's onTelemetry to its slot-specific hook + the
        // Combined aggregator. The actual write to LoggingStore is the app's
        // responsibility; MDM just fans out.
        self.left.onTelemetry  = { [weak self] t in self?.handleTelemetry(slot: .left,  t: t) }
        self.right.onTelemetry = { [weak self] t in self?.handleTelemetry(slot: .right, t: t) }

        // Watch each device's connection state for state transitions and the
        // Combined-mode disconnect watchdog.
        observeConnections()
    }

    // MARK: - Public API

    /// Connect to both Voltras at once. Use for the "Connect to Both" auto-pair
    /// button: caller passes the two strongest discoveries.
    func connectBoth(left leftDisc:  VoltraDiscoveryScanner.Discovered,
                     right rightDisc: VoltraDiscoveryScanner.Discovered) {
        connect(slot: .left,  discovered: leftDisc)
        connect(slot: .right, discovered: rightDisc)
    }

    /// Connect ONE side. Used by the tap-to-assign picker.
    func connect(slot: DeviceSlot, discovered: VoltraDiscoveryScanner.Discovered) {
        switch slot {
        case .left:
            leftIdentifier = discovered.id
            left.connectKnown(identifier: discovered.id, fallback: discovered.peripheral)
            leftWriter.resetAppliedState()
        case .right:
            rightIdentifier = discovered.id
            right.connectKnown(identifier: discovered.id, fallback: discovered.peripheral)
            rightWriter.resetAppliedState()
        }
    }

    /// Manual disconnect. Cancels any reconnect tasks for that slot.
    func disconnect(slot: DeviceSlot) {
        reconnectTasks[slot]?.cancel()
        reconnectTasks[slot] = nil
        switch slot {
        case .left:
            leftIdentifier = nil
            left.disconnect()
        case .right:
            rightIdentifier = nil
            right.disconnect()
        }
    }

    /// Disconnect both. Used when leaving the dual flow.
    func disconnectBoth() {
        for s in DeviceSlot.allCases { disconnect(slot: s) }
        state = .idle
    }

    /// Send LOAD to one side (Independent) or both (Combined).
    /// b47 (v0.4.25): when `target` is nil, route per `workoutMode` so combined
    /// fires BOTH sides while singleLeft/singleRight only fires the engaged
    /// side. Previously target=nil unconditionally fanned out, but only one
    /// side actually loaded \u2014 likely because the same frame (same seq) was
    /// being deduplicated somewhere in the BLE stack on rapid back-to-back
    /// writes. b47 builds an INDEPENDENT frame per side with its own seq.
    func load(target: DeviceSlot? = nil) {
        let payload = VoltraControlFrames.loadPayload()
        sendControlPayload(payload, label: "LOAD", target: target)
    }

    /// Send UNLOAD to one side (Independent) or both (Combined).
    /// b47: same workoutMode-aware routing + per-side seqs as `load()`.
    func unload(target: DeviceSlot? = nil) {
        let payload = VoltraControlFrames.unloadPayload()
        sendControlPayload(payload, label: "UNLOAD", target: target)
    }

    /// b47: workout-mode-aware control fan-out. Returns the slots that should
    /// receive a given control command when the caller hasn't named a
    /// specific target. Mirrors the routing matrix in WriterRouter so command
    /// fan-out matches state-write fan-out (e.g. combined writes to both,
    /// singleLeft to left only).
    private func slotsForWorkoutMode() -> [DeviceSlot] {
        let leftOn  = left.connectionState.isConnected
        let rightOn = right.connectionState.isConnected
        switch (leftOn, rightOn) {
        case (true, true):
            switch workoutMode {
            case .combined, .independent:
                return [.left, .right]
            case .singleLeft:
                return [.left]
            case .singleRight:
                return [.right]
            case .superset:
                // b48: LOAD/UNLOAD targets the ACTIVE Voltra only (the one
                // hosting the exercise the user is doing right now).
                // Sending to both unloaded the inactive side mid-rest,
                // which broke the chain. Per user (b48 feedback):
                // "Unload Tonsion isn't tied to whatever exercise A or B
                // it's on, it unloads both of them, which is not the
                // intended behavior."
                return [supersetActiveSlot]
            }
        case (true, false):  return [.left]
        case (false, true):  return [.right]
        case (false, false): return []
        }
    }

    // MARK: - Combined-mode device-state apply

    /// Apply a Combined-mode device state. Splits weight values per
    /// CombinedMath and writes per-side. Modifiers/mode mirror exactly.
    func applyCombined(_ state: VoltraDeviceState) {
        let split = CombinedMath.splitWeight(total: state.weights.baseLb)
        let eccSplit = CombinedMath.splitWeight(total: state.weights.eccentricLb)
        let chainsSplit = CombinedMath.splitWeight(total: state.weights.chainsLb)

        var leftState = state
        leftState.weights.baseLb       = split.left
        leftState.weights.eccentricLb  = eccSplit.left
        leftState.weights.chainsLb     = chainsSplit.left

        var rightState = state
        rightState.weights.baseLb      = split.right
        rightState.weights.eccentricLb = eccSplit.right
        rightState.weights.chainsLb    = chainsSplit.right

        leftWriter.apply(leftState)
        rightWriter.apply(rightState)
    }

    // MARK: - Private: connection observation

    private func observeConnections() {
        left.$connectionState
            .receive(on: RunLoop.main)
            .sink { [weak self] s in self?.connectionChanged(slot: .left,  s: s) }
            .store(in: &bag)
        right.$connectionState
            .receive(on: RunLoop.main)
            .sink { [weak self] s in self?.connectionChanged(slot: .right, s: s) }
            .store(in: &bag)

        // Rebroadcast each child's objectWillChange so SwiftUI views that
        // read e.g. `mdm.left.connectionState` redraw when the child
        // updates. Without this, only `mdm.state` and `mdm.mode` would
        // trigger view refreshes — sub-properties of the children would
        // be invisible to SwiftUI.
        left.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
        right.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
    }

    private func connectionChanged(slot: DeviceSlot, s: BLEConnectionState) {
        // Recompute high-level state.
        recomputeState()

        switch s {
        case .connected:
            // A successful connection cancels any pending reconnect task for
            // that slot and clears any error banner that points at it.
            reconnectTasks[slot]?.cancel()
            reconnectTasks[slot] = nil
            if case .errorReconnecting(let dropped, _) = state, dropped == slot {
                recomputeState()
            }
        case .disconnected:
            // In Combined mode, a drop on EITHER side stops both: send UNLOAD
            // to the survivor and start auto-reconnect on the dropped side.
            if mode == .combined {
                handleCombinedDrop(dropped: slot)
            }
            // Independent mode: do nothing automatic. The user will see the
            // disconnected side and reconnect manually if they want.
        default:
            break
        }
    }

    private func recomputeState() {
        let leftConnected  = left.connectionState.isConnected
        let rightConnected = right.connectionState.isConnected

        // Don't clobber an active error banner unless both reconnected.
        if case .errorReconnecting = state {
            if leftConnected && rightConnected {
                state = .pairedBoth
            }
            return
        }

        switch (leftConnected, rightConnected) {
        case (false, false): state = .idle
        case (true, false):  state = .pairedOne(slot: .left)
        case (false, true):  state = .pairedOne(slot: .right)
        case (true, true):   state = .pairedBoth
        }
    }

    // MARK: - Combined-mode disconnect watchdog

    private func handleCombinedDrop(dropped: DeviceSlot) {
        let survivor = dropped.other
        // Best-effort UNLOAD on the survivor. If the survivor is itself not
        // connected (rare race), VoltraBLEManager.writeControlFrame logs a
        // warn and does nothing \u2014 still safe.
        unload(target: survivor)

        let msg = "\(dropped.label) device dropped \u{2014} unloading \(survivor.label), attempting reconnect\u{2026}"
        state = .errorReconnecting(dropped: dropped, message: msg)

        scheduleReconnect(slot: dropped)
    }

    private func scheduleReconnect(slot: DeviceSlot) {
        reconnectTasks[slot]?.cancel()
        guard let id = (slot == .left ? leftIdentifier : rightIdentifier) else { return }

        reconnectTasks[slot] = Task { [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(self.reconnectTimeoutSeconds)
            // Backoff: 0.5s, 1s, 2s, 4s, then stick at 4s until deadline.
            var delayMs: UInt64 = 500
            while !Task.isCancelled, Date() < deadline {
                let manager: VoltraBLEManager = (slot == .left ? self.left : self.right)
                if manager.connectionState.isConnected { return }
                // Try via retrievePeripherals (fast path), else fall back to
                // a brief scan window. retrievePeripherals returns the
                // CBPeripheral if the system still has it cached \u2014 typical
                // for a device that just dropped.
                let known = manager.knownPeripheralOrNil(identifier: id)
                if let p = known {
                    manager.connectKnown(identifier: id, fallback: p)
                } else {
                    // Fallback: bring the manager back through scan. Cheap
                    // because the central is already up.
                    manager.startScan()
                }
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                if delayMs < 4000 { delayMs = min(4000, delayMs * 2) }
            }
            await MainActor.run { [weak self] in
                // Final state check after the timeout window.
                guard let self else { return }
                let manager: VoltraBLEManager = (slot == .left ? self.left : self.right)
                if !manager.connectionState.isConnected {
                    self.state = .errorReconnecting(
                        dropped: slot,
                        message: "\(slot.label) device could not reconnect. Reconnect manually or switch to Independent mode."
                    )
                }
            }
        }
    }

    // MARK: - Telemetry fan-out

    private func handleTelemetry(slot: DeviceSlot, t: Telemetry) {
        switch slot {
        case .left:  onLeftTelemetry?(t);  cacheLeft  = t
        case .right: onRightTelemetry?(t); cacheRight = t
        }
        // Fan out the merged combined reading too (cheap; the consumer can
        // ignore in Independent mode).
        let merged = CombinedTelemetry(
            forceLb:    CombinedMath.combineForceLb(left: cacheLeft?.forceLb,    right: cacheRight?.forceLb),
            repCount:   CombinedMath.combineRepCount(left: cacheLeft?.repCount ?? 0, right: cacheRight?.repCount ?? 0),
            peakPower:  CombinedMath.combinePeakPower(left: cacheLeft?.peakPowerWatts, right: cacheRight?.peakPowerWatts),
            phaseLeft:  cacheLeft?.phase  ?? .idle,
            phaseRight: cacheRight?.phase ?? .idle
        )
        onCombinedTelemetry?(merged)
    }

    // Most-recent per-side cache so the combined merge can read both sides
    // even when only one side just produced a packet.
    private var cacheLeft:  Telemetry? = nil
    private var cacheRight: Telemetry? = nil

    // MARK: - Control payload routing

    /// Send a fully-built control payload to one side or both. The frame
    /// builder owns sequence numbers; we use each writer's `seq` indirectly
    /// via writer.apply() for state-driven writes, but for ad-hoc commands
    /// (LOAD/UNLOAD) we frame here using a static seq slot per call.
    private func sendControlPayload(_ payload: Data, label: String, target: DeviceSlot?) {
        // b47: build a SEPARATE frame per recipient with its own seq. Earlier
        // code reused one frame across both peripherals \u2014 user reported
        // "only one Voltra unloads in Combined," most likely because both
        // writes went out with identical bytes back-to-back and one of the
        // peripherals' transport stacks coalesced or dropped the duplicate.
        // Per-side seqs guarantee distinct frames at the wire.
        let recipients: [DeviceSlot]
        if let t = target {
            recipients = [t]
        } else {
            recipients = slotsForWorkoutMode()
        }
        let suffix = (recipients.count == 2) ? " (\(workoutMode.label.lowercased()))" : ""
        for slot in recipients {
            let frame = VoltraFrameBuilder.build(
                cmd: VoltraControlFrames.CMD_PARAM_WRITE,
                payload: payload,
                seq: nextAdHocSeq()
            )
            switch slot {
            case .left:
                left.writeControlFrame(frame)
                left.addLog("\u{2192} \(label)\(suffix)")
            case .right:
                right.writeControlFrame(frame)
                right.addLog("\u{2192} \(label)\(suffix)")
            }
        }
        if recipients.isEmpty {
            // No connected recipients \u2014 nothing to do, but log it once on
            // either side so the BLE log makes the no-op visible.
            left.addLog("\u{26a0} \(label) skipped \u{2014} no devices connected", level: .warn)
        }
    }

    private var adHocSeq: UInt16 = 0xC000  // start far from writer's 0..N
    private func nextAdHocSeq() -> UInt16 {
        adHocSeq = (adHocSeq &+ 1) & 0xFFFF
        return adHocSeq
    }
}

// MARK: - CombinedTelemetry

/// Virtual-twin reading produced by merging the two per-device telemetry
/// streams. Field semantics:
///   forceLb    \u2014 SUM (user-felt force across both cables).
///   repCount   \u2014 SUM (each side counts its own reps).
///   peakPower  \u2014 SUM.
///   phaseLeft / phaseRight \u2014 raw phases per side; the UI decides whether to
///                              show them combined or separately.
struct CombinedTelemetry: Equatable {
    var forceLb:    Double
    var repCount:   Int
    var peakPower:  Int?
    var phaseLeft:  VoltraPhase
    var phaseRight: VoltraPhase
}

// MARK: - VoltraBLEManager helper used by reconnect

extension VoltraBLEManager {
    /// Return the cached CBPeripheral for an identifier if our central still
    /// has it. Used by the dual-Voltra reconnect path.
    func knownPeripheralOrNil(identifier: UUID) -> CBPeripheral? {
        // Access the same retrievePeripherals API as connectKnown.
        return retrievePeripheralFromOwnCentral(identifier: identifier)
    }
}
