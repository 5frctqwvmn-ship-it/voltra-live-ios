// VoltraLiveApp.swift
// @main entry point. Sets up SwiftData modelContainer and injects environment objects.

import SwiftUI
import SwiftData

@main
struct VoltraLiveApp: App {
    @StateObject private var bleManager = VoltraBLEManager()
    @StateObject private var sessionStore = SessionStore()

    let modelContainer: ModelContainer = {
        let schema = Schema([PastSession.self, PastSet.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("[VoltraLive] Failed to create SwiftData ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleManager)
                .environmentObject(sessionStore)
                .onAppear {
                    // Wire model context and BLE → session callback on first appear
                    sessionStore.modelContext = modelContainer.mainContext
                    bleManager.onTelemetry = { [weak sessionStore] telem in
                        guard let ss = sessionStore else { return }
                        let phase    = telem.phase    ?? .idle
                        let forceLb  = telem.forceLb  ?? 0
                        let repCount = telem.repCount ?? 0
                        Task { @MainActor in
                            ss.handleLiveSample(phase: phase, forceLb: forceLb, repCount: repCount)
                        }
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
