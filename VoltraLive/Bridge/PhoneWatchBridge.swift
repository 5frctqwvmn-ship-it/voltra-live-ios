// PhoneWatchBridge.swift
// Phone-side WatchConnectivity bridge.
//
// Observes SessionStore + VoltraBLEManager via Combine and pushes
// WatchTelemetryMessage to the paired Watch via transferUserInfo (queued,
// reliable delivery even when Watch is asleep).
//
// Throttle rules:
//   - Force updates: max 5 Hz (200ms minimum interval)
//   - Phase changes: immediate
//   - Rep increments: immediate + .repTick event
//   - Set complete: immediate + .setComplete event
//   - Rest timer tick: 1 Hz while restActive
//   - restEnd (first Pull after rest): immediate + .restEnd event

import Foundation
import Combine
import WatchConnectivity

// MARK: - Message type (must match WatchTelemetryStore.swift exactly)

struct WatchTelemetryMessage: Codable {
    let timestamp: Date
    let reps: Int
    let phase: String     // "Idle" | "Pull" | "Transition" | "Return"
    let forceLb: Double
    let restSeconds: Int  // 0 if not resting
    let setNumber: Int
    let isConnectedToVoltra: Bool
    let event: WatchEvent?

    enum WatchEvent: String, Codable {
        case repTick
        case setComplete
        case restEnd
    }
}

// MARK: - Bridge

@MainActor
final class PhoneWatchBridge: NSObject, WCSessionDelegate {

    // MARK: Singleton

    static let shared = PhoneWatchBridge()
    private override init() {}

    // MARK: Weak references to stores (injected from VoltraLiveApp)

    weak var sessionStore: SessionStore?
    weak var bleManager: VoltraBLEManager?

    // MARK: Private state

    private var cancellables = Set<AnyCancellable>()
    private var lastForceSent: Double = 0
    private var lastForceSendTime: Date = .distantPast
    private let forceThrottleInterval: TimeInterval = 0.2   // 5 Hz max
    private var lastPhase: VoltraPhase = .idle
    private var lastReps: Int = 0
    private var lastRestActive: Bool = false
    private var restTickCancellable: AnyCancellable?

    private var isActivated = false

    // MARK: - Activate

    func activate() {
        guard WCSession.isSupported() else {
            print("[PhoneWatchBridge] WCSession not supported on this device.")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Wire to stores

    /// Call this after both stores exist (from VoltraLiveApp.onAppear).
    func wire(sessionStore: SessionStore, bleManager: VoltraBLEManager) {
        self.sessionStore = sessionStore
        self.bleManager = bleManager
        subscribeToCombine()
    }

    // MARK: - Combine subscriptions

    private func subscribeToCombine() {
        guard let ss = sessionStore, let ble = bleManager else { return }
        cancellables.removeAll()

        // ── Rep count changes ──────────────────────────────────────────────
        ss.$currentSet
            .receive(on: RunLoop.main)
            .sink { [weak self] cs in
                guard let self else { return }
                let newReps = cs?.reps ?? 0
                if newReps > self.lastReps {
                    self.lastReps = newReps
                    self.push(event: .repTick)
                } else {
                    self.lastReps = newReps
                }
            }
            .store(in: &cancellables)

        // ── Set complete ───────────────────────────────────────────────────
        ss.$completedSets
            .receive(on: RunLoop.main)
            .sink { [weak self] sets in
                guard let self, !sets.isEmpty else { return }
                self.push(event: .setComplete)
            }
            .store(in: &cancellables)

        // ── Rest timer (1 Hz tick while resting) ──────────────────────────
        ss.$restActive
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                guard let self else { return }
                if active && !self.lastRestActive {
                    // Rest just started
                    self.lastRestActive = true
                    self.startRestTick()
                } else if !active && self.lastRestActive {
                    // Rest ended
                    self.lastRestActive = false
                    self.stopRestTick()
                    self.push(event: .restEnd)
                }
            }
            .store(in: &cancellables)

        // ── Phase changes ──────────────────────────────────────────────────
        ble.$telemetry
            .receive(on: RunLoop.main)
            .sink { [weak self] telem in
                guard let self else { return }

                // Phase change → immediate push
                if telem.phase != self.lastPhase {
                    self.lastPhase = telem.phase
                    self.push(event: nil)
                    return
                }

                // Force update (throttled to 5 Hz)
                let now = Date()
                let forceDelta = abs(telem.forceLb - self.lastForceSent)
                if forceDelta > 5 || now.timeIntervalSince(self.lastForceSendTime) >= self.forceThrottleInterval {
                    self.lastForceSent = telem.forceLb
                    self.lastForceSendTime = now
                    self.push(event: nil)
                }
            }
            .store(in: &cancellables)

        // ── BLE connection state ───────────────────────────────────────────
        ble.$connectionState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.push(event: nil)
            }
            .store(in: &cancellables)
    }

    // MARK: - Rest tick timer

    private func startRestTick() {
        restTickCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.push(event: nil)
            }
    }

    private func stopRestTick() {
        restTickCancellable?.cancel()
        restTickCancellable = nil
    }

    // MARK: - Push message to Watch

    private func push(event: WatchTelemetryMessage.WatchEvent?) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isPaired
        else { return }

        let ss = sessionStore
        let ble = bleManager

        let reps = ss?.currentSet?.reps ?? 0
        let phase = ble?.telemetry.phase.watchLabel ?? "Idle"
        let forceLb = ble?.telemetry.forceLb ?? 0
        let restSeconds = (ss?.restActive == true) ? Int(ss?.restElapsedSeconds ?? 0) : 0
        let setNumber = ss?.completedSets.count ?? 0
        let isConnected = ble?.connectionState.isConnected ?? false

        let msg = WatchTelemetryMessage(
            timestamp: Date(),
            reps: reps,
            phase: phase,
            forceLb: forceLb,
            restSeconds: restSeconds,
            setNumber: setNumber,
            isConnectedToVoltra: isConnected,
            event: event
        )

        guard let dict = msg.asDictionary else { return }

        // Use transferUserInfo for reliable queued delivery.
        // Falls back to sendMessage when Watch is reachable (lower latency).
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(dict, replyHandler: nil, errorHandler: { error in
                // Fallback to queue if direct send fails
                WCSession.default.transferUserInfo(dict)
                print("[PhoneWatchBridge] sendMessage failed, queued: \(error.localizedDescription)")
            })
        } else {
            WCSession.default.transferUserInfo(dict)
        }
    }

    // MARK: - WCSessionDelegate (required on iOS)

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        if let error {
            print("[PhoneWatchBridge] Activation error: \(error.localizedDescription)")
        } else {
            print("[PhoneWatchBridge] WCSession activated, state=\(activationState.rawValue)")
        }
        Task { @MainActor in
            self.isActivated = (activationState == .activated)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        print("[PhoneWatchBridge] Session became inactive.")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        print("[PhoneWatchBridge] Session deactivated — reactivating.")
        session.activate()
    }
}

// MARK: - VoltraPhase → Watch label

private extension VoltraPhase {
    var watchLabel: String {
        switch self {
        case .pull:       return "Pull"
        case .return:     return "Return"
        case .transition: return "Transition"
        case .idle:       return "Idle"
        }
    }
}

// MARK: - Codable → Dictionary helper

private extension Encodable {
    var asDictionary: [String: Any]? {
        guard let data = try? JSONEncoder().encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return dict
    }
}
