// VoltraWatchApp.swift
// @main entry for the VOLTRA Live Watch companion.
// Sets up WCSession and injects the shared WatchTelemetryStore.

import SwiftUI
import WatchConnectivity

@main
struct VoltraWatchApp: App {

    @StateObject private var store = WatchTelemetryStore()
    private let sessionDelegate = WatchSessionDelegate.shared

    init() {
        // Activate WCSession early so delegate is ready before first scene render.
        WatchSessionDelegate.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    // Wire delegate → store after store is alive.
                    WatchSessionDelegate.shared.telemetryStore = store
                }
        }
    }
}
