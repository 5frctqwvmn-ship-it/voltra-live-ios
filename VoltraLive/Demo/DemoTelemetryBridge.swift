// DemoTelemetryBridge.swift
// v0.4.6.3 / build 26
//
// Tiny singleton that holds the canonical telemetry handler (registered
// once at app launch in VoltraLiveApp). DemoController consults it when
// entering pre-pair demo so the synthetic generator routes through the
// exact same code path the real BLE manager uses.
//
// This avoids smuggling a closure parameter through ConnectView →
// DemoModeButton → DemoController and keeps the demo subsystem decoupled
// from the app's main wiring.

import Foundation

@MainActor
final class DemoTelemetryBridge {
    static let shared = DemoTelemetryBridge()
    private init() {}

    /// Set once at app launch. The closure is the same one assigned to
    /// `bleManager.onTelemetry`.
    var handler: ((Telemetry) -> Void)? = nil
}
