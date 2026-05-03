// VoltraWriter.swift
// Owns the BLE write queue for VOLTRA control commands.
//
// Why this exists:
//   - Stepper UI emits a flood of changes when the user holds the +/- button.
//     Sending one BLE write per intermediate value chokes the characteristic
//     and causes visible lag on the device. We coalesce changes per-param
//     within a small debounce window so only the final value gets sent.
//   - Sequence numbers must be unique per write (the Kotlin reference uses
//     a monotonic counter). We own that counter here.
//   - Mode-switch writes (PARAM_FITNESS_WORKOUT_STATE) settle on the device
//     before subsequent param writes; we serialize behind a small post-mode
//     delay so the device has time to accept follow-up writes.
//
// Day-1 stance: fire-and-forget. We use `.withResponse` so iOS hands the
// write to the radio reliably, but we don't parse param-write ACKs from the
// device yet. The structure leaves room for a future ack-correlator without
// rewriting callers.

import Foundation
import CoreBluetooth

// MARK: - Public mode model — mirrors the prototype's state shape

/// The high-level workout mode the user picks on the detail screen.
/// Each top-level mode maps to a different PARAM_FITNESS_WORKOUT_STATE write.
enum VoltraMode: String, Equatable {
    case weight     // WORKOUT_STATE_ACTIVE
    case band       // WORKOUT_STATE_RESISTANCE_BAND
    case damper     // WORKOUT_STATE_DAMPER
}

/// Modifiers that only apply to `.weight` mode. `.chains` and `.inverse` are
/// mutually exclusive (the prototype enforces this in the UI). Eccentric
/// stacks independently.
struct VoltraModifiers: Equatable {
    var eccentric: Bool = false
    var chains: Bool = false
    var inverse: Bool = false
}

/// All weights the detail screen can write to the device.
struct VoltraWeights: Equatable {
    var baseLb: Int = 0
    var eccentricLb: Int = 0
    var chainsLb: Int = 0
    var bandMaxForceLb: Int = 0
    var damperLevel: Int = 0
}

/// One coherent device-state snapshot the writer should make true. The writer
/// diffs this against the last applied snapshot and only sends what changed.
struct VoltraDeviceState: Equatable {
    var mode: VoltraMode = .weight
    var modifiers: VoltraModifiers = .init()
    var weights: VoltraWeights = .init()
}

// MARK: - Writer protocol (so the detail view can be tested without BLE)

/// Abstracts the BLE characteristic write so the detail screen can be unit
/// tested against a mock writer in the future.
protocol VoltraWriting: AnyObject {
    func apply(_ state: VoltraDeviceState)
    func resetAppliedState()
}

// MARK: - Concrete writer

@MainActor
final class VoltraWriter: VoltraWriting {

    // MARK: Dependencies

    /// Closure that performs the actual BLE characteristic write. Injected so
    /// callers can swap in a mock for tests.
    private let writeFrame: (Data) -> Void
    /// Closure for log/UI surfacing. Same shape as VoltraBLEManager.addLog.
    private let log: (String) -> Void

    // MARK: Tunables (match the prototype's auto-write cadence)

    /// Minimum delay between coalesced apply()s of the same param.
    /// 80 ms is the prototype's default; the device tolerates faster but iOS
    /// `.withResponse` writes alone create natural backpressure.
    private let debounceMs: UInt64 = 80
    /// Wait after a mode-switch write before sending mode-specific params.
    /// The Android reference waits for an ACK on the notify char; we don't
    /// parse that yet, so a fixed delay matches the captured cadence.
    private let postModeSettleMs: UInt64 = 120

    // MARK: State

    /// Last fully-applied state we sent to the device. Used to diff.
    private var applied: VoltraDeviceState? = nil
    /// Last requested state — what apply() most recently asked for. The flush
    /// task always converges to this.
    private var pending: VoltraDeviceState? = nil
    /// Monotonic sequence counter. Wraps at 0xFFFF.
    private var seq: UInt16 = 0
    /// Active flush task (if any). Cancelled and replaced when apply() is
    /// called again before the previous flush ran.
    private var flushTask: Task<Void, Never>? = nil

    // MARK: Init

    init(writeFrame: @escaping (Data) -> Void, log: @escaping (String) -> Void) {
        self.writeFrame = writeFrame
        self.log = log
    }

    // MARK: Public API

    /// Ask the writer to make `state` the device's truth. Coalesces rapid
    /// stepper changes — only the most recent state survives the debounce.
    func apply(_ state: VoltraDeviceState) {
        pending = state
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: (self?.debounceMs ?? 80) * 1_000_000)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    /// Wipe our memory of what was last sent. Use after disconnect/reconnect
    /// so the next apply() re-sends everything.
    func resetAppliedState() {
        applied = nil
    }

    // MARK: Flush logic

    private func flush() async {
        guard let target = pending else { return }
        let prior = applied

        // 1. Mode change first.
        if prior?.mode != target.mode {
            send(modePayload(for: target.mode), label: "mode→\(target.mode.rawValue)")
            // Settle so the device accepts mode-specific params next.
            try? await Task.sleep(nanoseconds: postModeSettleMs * 1_000_000)
        }

        // 2. Mode-specific param writes.
        switch target.mode {
        case .weight:
            // Inverse-chains flag must be coherent with chains weight:
            // turning inverse off must clear the flag before we change weight.
            if prior?.modifiers.inverse != target.modifiers.inverse {
                send(VoltraControlFrames.setInverseChainsPayload(target.modifiers.inverse),
                     cmd: VoltraControlFrames.CMD_PARAM_WRITE,
                     label: "inverse=\(target.modifiers.inverse)")
            }
            // Base weight (always sent in weight mode).
            if prior?.weights.baseLb != target.weights.baseLb || prior?.mode != .weight {
                trySend("base=\(target.weights.baseLb)") {
                    try VoltraControlFrames.setBaseWeightPayload(target.weights.baseLb)
                }
            }
            // Eccentric weight is only meaningful when the eccentric modifier
            // is on; if it's off we explicitly send 0 to clear any prior load.
            let eccLb = target.modifiers.eccentric ? target.weights.eccentricLb : 0
            if (prior?.weights.eccentricLb ?? 0) != eccLb || prior?.mode != .weight {
                // Clamp into the protocol's signed window so we never throw.
                let clamped = max(VoltraControlFrames.MIN_ECCENTRIC_WEIGHT_LB,
                                  min(VoltraControlFrames.MAX_ECCENTRIC_WEIGHT_LB, eccLb))
                trySend("ecc=\(clamped)") {
                    try VoltraControlFrames.setEccentricWeightPayload(clamped)
                }
            }
            // Chains weight, only if either chain modifier is engaged.
            let chainsLb = (target.modifiers.chains || target.modifiers.inverse)
                ? target.weights.chainsLb : 0
            if (prior?.weights.chainsLb ?? 0) != chainsLb || prior?.mode != .weight {
                let clamped = max(VoltraControlFrames.MIN_EXTRA_WEIGHT_LB,
                                  min(VoltraControlFrames.MAX_EXTRA_WEIGHT_LB, chainsLb))
                trySend("chains=\(clamped)") {
                    try VoltraControlFrames.setChainsWeightPayload(clamped)
                }
            }
        case .band:
            if prior?.weights.bandMaxForceLb != target.weights.bandMaxForceLb || prior?.mode != .band {
                let clamped = max(VoltraControlFrames.MIN_RB_FORCE_LB,
                                  min(VoltraControlFrames.MAX_RB_FORCE_LB,
                                      target.weights.bandMaxForceLb))
                trySend("band=\(clamped)") {
                    try VoltraControlFrames.setResistanceBandMaxForcePayload(clamped)
                }
            }
        case .damper:
            if prior?.weights.damperLevel != target.weights.damperLevel || prior?.mode != .damper {
                let clamped = max(VoltraControlFrames.MIN_DAMPER_LEVEL,
                                  min(VoltraControlFrames.MAX_DAMPER_LEVEL,
                                      target.weights.damperLevel))
                trySend("damper=\(clamped)") {
                    try VoltraControlFrames.setDamperLevelPayload(clamped)
                }
            }
        }

        applied = target
    }

    // MARK: Helpers

    private func modePayload(for mode: VoltraMode) -> Data {
        switch mode {
        case .weight: return VoltraControlFrames.enterWeightTrainingPayload()
        case .band:   return VoltraControlFrames.enterResistanceBandPayload()
        case .damper: return VoltraControlFrames.enterDamperPayload()
        }
    }

    /// Frame `mode` payload as a CMD_PARAM_WRITE write.
    private func send(_ payload: Data, label: String) {
        send(payload, cmd: VoltraControlFrames.CMD_PARAM_WRITE, label: label)
    }

    private func send(_ payload: Data, cmd: UInt8, label: String) {
        let frame = VoltraFrameBuilder.build(cmd: cmd, payload: payload, seq: nextSeq())
        writeFrame(frame)
        log("→ \(label) (\(frame.count)B)")
        // B74-F11: writer-level write.tx with the high-level intent label
        // (e.g. "base=120", "ecc=20", "mode→weight"). The BLE manager also
        // emits a write.tx when the closure-injected writeFrame actually
        // transmits — intentional layering: this captures the intent, that
        // captures the bytes leaving the radio.
        SessionRecorder.shared.record(
            category: .ble, name: "ble.write.tx",
            metadata: ["label": .string(label),
                       "cmd": .hex(String(format: "%02X", cmd))],
            ble: BLESubrecord(kind: .writeTx, peripheralId: nil, side: nil,
                              characteristic: nil,
                              hex: String(frame.hexString.prefix(32)),
                              length: frame.count, rssi: nil))
    }

    /// Try-build wrapper that swallows out-of-range errors and logs them, so
    /// a bad UI value never crashes the writer. Range clamping above means
    /// this should never fire in practice.
    private func trySend(_ label: String, _ build: () throws -> Data) {
        do {
            let payload = try build()
            send(payload, label: label)
        } catch {
            log("✗ \(label) skipped: \(error)")
            // B74-F11: surface the payload-build failure. Range clamping
            // upstream means this should never fire in practice; if it
            // does, we want a trace.
            SessionRecorder.shared.record(
                category: .ble, name: "ble.error",
                error: RecorderErrorRecord(
                    domain: "VoltraWriter", code: 0,
                    message: "\(label) skipped: \(error)",
                    isUserVisible: false),
                ble: BLESubrecord(kind: .error, peripheralId: nil, side: nil,
                                  characteristic: nil, hex: nil, length: nil, rssi: nil))
        }
    }

    private func nextSeq() -> UInt16 {
        seq = (seq &+ 1) & 0xFFFF
        return seq
    }
}

// MARK: - Mock for previews / unit tests

#if DEBUG
final class MockVoltraWriter: VoltraWriting {
    private(set) var lastApplied: VoltraDeviceState? = nil
    private(set) var applyCount: Int = 0
    func apply(_ state: VoltraDeviceState) {
        lastApplied = state
        applyCount += 1
    }
    func resetAppliedState() { lastApplied = nil }
}
#endif
