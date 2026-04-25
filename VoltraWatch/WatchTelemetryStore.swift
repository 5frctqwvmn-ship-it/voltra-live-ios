// WatchTelemetryStore.swift
// ObservableObject that holds the live telemetry mirrored from the phone.
// The Watch UI observes this store; WatchSessionDelegate writes to it.

import Foundation
import Combine

// MARK: - Shared message type (must match PhoneWatchBridge.swift exactly)

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

// MARK: - Store

final class WatchTelemetryStore: ObservableObject {

    // Live telemetry values
    @Published var reps: Int = 0
    @Published var phase: String = "Idle"
    @Published var forceLb: Double = 0
    @Published var restSeconds: Int = 0
    @Published var setNumber: Int = 0
    @Published var isConnected: Bool = false   // connected to phone (WC reachable)
    @Published var isConnectedToVoltra: Bool = false  // phone is connected to VOLTRA device

    /// Apply a decoded message from the phone.
    @MainActor
    func apply(_ msg: WatchTelemetryMessage) {
        reps = msg.reps
        phase = msg.phase
        forceLb = msg.forceLb
        restSeconds = msg.restSeconds
        setNumber = msg.setNumber
        isConnectedToVoltra = msg.isConnectedToVoltra
    }
}
