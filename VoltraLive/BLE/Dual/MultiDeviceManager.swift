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
    func load(target: DeviceSlot? = nil) {
        let payload = VoltraControlFrames.loadPayload()
        sendControlPayload(payload, label: "LOAD", target: target)
    }

    /// Send UNLOAD to one side (Independent) or both (Combined).
    func unload(target: DeviceSlot? = nil) {
        let payload = VoltraControlFrames.unloadPayload()
        sendControlPayload(payload, label: "UNLOAD", target: target)
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
        // Build a frame with a per-call seq. We don't share the writer's
        // monotonic counter because LOAD/UNLOAD aren't part of the diffed
        // device state; collisions with writer seq numbers are harmless on
        // the device (it doesn't enforce uniqueness across cmds).
        let frame = VoltraFrameBuilder.build(
            cmd: VoltraControlFrames.CMD_PARAM_WRITE,
            payload: payload,
            seq: nextAdHocSeq()
        )
        switch target {
        case .none:
            // Default to "both", which is what Combined mode wants.
            left.writeControlFrame(frame)
            right.writeControlFrame(frame)
            left.addLog("\u{2192} \(label) (combined)")
            right.addLog("\u{2192} \(label) (combined)")
        case .some(.left):
            left.writeControlFrame(frame)
            left.addLog("\u{2192} \(label)")
        case .some(.right):
            right.writeControlFrame(frame)
            right.addLog("\u{2192} \(label)")
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
