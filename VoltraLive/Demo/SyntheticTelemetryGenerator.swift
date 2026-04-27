// SyntheticTelemetryGenerator.swift
// v0.4.6.3 / build 26
//
// Drives plausible-looking Telemetry frames at the same ~50 Hz cadence the
// real BLE manager produces during a workout. Used by Demo Mode's pre-pair
// path so the dashboards have something to render when no Voltra is paired.
//
// Behavior model — we don't try to be physiologically perfect. Goal is "looks
// believable in a screenshot and exercises every code path:"
//
//   • Cycles through reps deterministically: idle → pull → transition →
//     return → idle, each with a realistic duration window.
//   • Force curve during pull: sinusoidal hump centered on the rep peak,
//     with a configurable peak weight (defaults around 145 lb).
//   • Every ~5 reps, drops the working weight by 25 lb to fire the
//     drop-set detection logic.
//   • Sets a sentinel `tick` so the existing PacketParser-side logic that
//     uses it for ordering doesn't get confused.
//
// SACRED-FILES NOTE: emits decoded `Telemetry` directly. Does NOT touch the
// protocol layer.

import Foundation

@MainActor
final class SyntheticTelemetryGenerator {

    // 50 Hz packet cadence to match what we observe from the real device.
    private let tickInterval: TimeInterval = 1.0 / 50.0

    // State machine ----------------------------------------------------------

    /// Remaining time in the current phase, in seconds.
    private var phaseRemaining: TimeInterval = 0
    private var currentPhase: VoltraPhase = .idle

    /// Monotonic packet counter — used as `tick` and to pace state changes.
    private var packetTick: UInt32 = 0

    /// Working weight (lb) for the current cluster. Drops every 5 reps.
    private var workingLb: Double = 145

    /// Reps completed at the current weight, for drop-set firing.
    private var repsAtThisWeight: Int = 0

    /// Total reps overall, monotonic.
    private var totalReps: Int = 0

    /// Total sets — ticks once per N reps to exercise multi-set views.
    private var totalSets: Int = 1

    /// Phase elapsed (used to shape the force curve).
    private var phaseElapsed: TimeInterval = 0

    /// Peak hold target for the active rep's pull (lb).
    private var pullPeakLb: Double = 145

    // Output -----------------------------------------------------------------

    private let onTelemetry: (Telemetry) -> Void
    private var timer: Timer?

    init(onTelemetry: @escaping (Telemetry) -> Void) {
        self.onTelemetry = onTelemetry
    }

    func start() {
        // Kick the state machine into idle for ~1.5 s before the first rep
        // so the dashboards have a moment to render their empty state.
        currentPhase = .idle
        phaseRemaining = 1.5
        phaseElapsed = 0

        // Send one initial telemetry frame so the connection-state UI flips.
        emitFrame(force: 0)

        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Tick

    private func tick() {
        packetTick &+= 1
        phaseElapsed += tickInterval
        phaseRemaining -= tickInterval

        if phaseRemaining <= 0 {
            advancePhase()
        }

        emitFrame(force: forceForCurrentPhase())
    }

    /// Move to the next phase in the rep cycle. Also handles drop-set firing.
    private func advancePhase() {
        switch currentPhase {
        case .idle:
            // Start a new rep.
            currentPhase = .pull
            // 1.4–1.8 s pull
            phaseRemaining = 1.4 + Double.random(in: 0...0.4)
            // Vary peak slightly within ±4% so the curves don't look canned.
            pullPeakLb = workingLb * (0.96 + Double.random(in: 0...0.08))

        case .pull:
            currentPhase = .transition
            phaseRemaining = 0.25 + Double.random(in: 0...0.15)

        case .transition:
            currentPhase = .return
            phaseRemaining = 1.1 + Double.random(in: 0...0.4)

        case .return:
            // Rep complete.
            totalReps += 1
            repsAtThisWeight += 1
            currentPhase = .idle
            // Inter-rep pause 0.6–1.4 s.
            phaseRemaining = 0.6 + Double.random(in: 0...0.8)

            // Every 5 reps, fire a drop-set step. The existing
            // LoggingStore.startDropSet flow will catch the weight change.
            if repsAtThisWeight >= 5 {
                workingLb = max(45, workingLb - 25)
                repsAtThisWeight = 0
                // Bump set counter if we've cascaded enough times.
                if workingLb <= 70 {
                    workingLb = 145
                    totalSets += 1
                }
            }
        }

        phaseElapsed = 0
    }

    /// Sinusoidal pull curve, flat-ish during transition/return.
    private func forceForCurrentPhase() -> Double {
        switch currentPhase {
        case .idle:
            // Sub-3 lb resting noise — important: noteTelemetryActivity()
            // explicitly ignores < 3 lb so this won't keep the cascade
            // timer alive.
            return Double.random(in: 0...2)

        case .pull:
            // sin curve from 0 → peak → ~0 over the phase duration
            let total = max(0.001, phaseElapsed + max(0, phaseRemaining))
            let progress = min(1.0, max(0.0, phaseElapsed / total))
            // Half-sine peak at progress=0.5
            let envelope = sin(progress * .pi)
            // Light noise so the chart looks real
            let noise = Double.random(in: -2...2)
            return max(0, pullPeakLb * envelope + noise)

        case .transition:
            // Settling — small force as user resets.
            return 5 + Double.random(in: -2...2)

        case .return:
            // Eccentric / slow return — meaningful negative-pulling resistance,
            // around 35-45% of pull peak.
            let load = pullPeakLb * 0.4
            return load + Double.random(in: -3...3)
        }
    }

    private func emitFrame(force: Double) {
        var telem = Telemetry()
        telem.tick = packetTick
        telem.phase = currentPhase
        telem.phaseRaw = {
            switch currentPhase {
            case .idle:       return 0
            case .pull:       return 1
            case .transition: return 2
            case .return:     return 3
            }
        }()
        telem.forceLb = force
        telem.repCount = totalReps
        telem.setCount = totalSets
        // Battery static — keep it in a friendly range.
        if packetTick % 250 == 0 {
            telem.batteryPercent = 87
        }
        onTelemetry(telem)
    }
}
