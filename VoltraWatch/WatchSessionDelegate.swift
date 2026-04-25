// WatchSessionDelegate.swift
// Receives WatchConnectivity messages from the paired iPhone,
// decodes WatchTelemetryMessage, updates the store, and fires haptics.

import Foundation
import WatchConnectivity
import WatchKit

final class WatchSessionDelegate: NSObject, WCSessionDelegate, @unchecked Sendable {

    static let shared = WatchSessionDelegate()
    private override init() {}

    /// Injected by VoltraWatchApp after store is created.
    weak var telemetryStore: WatchTelemetryStore?

    // MARK: - Activation

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - WCSessionDelegate — required on watchOS

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let error {
            print("[WatchSession] Activation error: \(error.localizedDescription)")
        } else {
            print("[WatchSession] Activated, state=\(activationState.rawValue)")
        }
        // Update connectivity status on main actor
        Task { @MainActor [weak self] in
            self?.telemetryStore?.isConnected = (activationState == .activated)
        }
    }

    // MARK: - Receive queued messages (transferUserInfo)

    func session(_ session: WCSession,
                 didReceiveUserInfo userInfo: [String: Any] = [:]) {
        decodeAndApply(userInfo)
    }

    // MARK: - Receive direct messages (sendMessage — fallback)

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any]) {
        decodeAndApply(message)
    }

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        decodeAndApply(message)
        replyHandler([:])
    }

    // MARK: - Reachability changes

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.telemetryStore?.isConnected = session.isReachable
        }
    }

    // MARK: - Private decode + apply

    private func decodeAndApply(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let msg = try? JSONDecoder().decode(WatchTelemetryMessage.self, from: data)
        else {
            print("[WatchSession] Failed to decode message: \(dict.keys.joined(separator: ", "))")
            return
        }

        Task { @MainActor [weak self] in
            guard let self, let store = self.telemetryStore else { return }

            let previousReps = store.reps
            store.apply(msg)

            // Handle haptic events
            if let event = msg.event {
                switch event {
                case .repTick:
                    WKInterfaceDevice.current().play(.click)
                case .setComplete:
                    WKInterfaceDevice.current().play(.success)
                case .restEnd:
                    WKInterfaceDevice.current().play(.notification)
                }
            } else if msg.reps > previousReps {
                // Fallback: fire click haptic on rep increment even without explicit event
                WKInterfaceDevice.current().play(.click)
            }
        }
    }
}
