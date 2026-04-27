// VoltraLiveApp.swift
// @main entry point. Sets up SwiftData modelContainer with CloudKit sync and
// injects environment objects.

import SwiftUI
import SwiftData

@main
struct VoltraLiveApp: App {
    @StateObject private var bleManager = VoltraBLEManager()
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var loggingStore = LoggingStore()
    @StateObject private var healthStore = HealthKitStore()

    let modelContainer: ModelContainer = {
        // v0.1 dashboard models + v0.2 logging models in one container so
        // cross-queries (e.g. "last leg-day session") work and CloudKit syncs
        // everything together.
        var allModels: [any PersistentModel.Type] = [PastSession.self, PastSet.self]
        allModels.append(contentsOf: LoggingSchema.models)
        let schema = Schema(allModels)

        // CloudKit-backed config — automatic mode means SwiftData picks the
        // default container "iCloud.<bundle-id>" if entitlements include it.
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            // Fallback: try local-only if CloudKit fails (e.g. user not signed
            // in to iCloud). Logging still works; sync just won't happen.
            print("[VoltraLive] CloudKit init failed: \(error). Falling back to local-only.")
            let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            do {
                return try ModelContainer(for: schema, configurations: localConfig)
            } catch {
                fatalError("[VoltraLive] Failed to create SwiftData ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleManager)
                .environmentObject(sessionStore)
                .environmentObject(loggingStore)
                .environmentObject(healthStore)
                .onAppear {
                    let ctx = modelContainer.mainContext

                    // Wire SwiftData context into both stores.
                    sessionStore.modelContext = ctx
                    loggingStore.wire(context: ctx, sessionStore: sessionStore)

                    // BLE → SessionStore + LoggingStore.
                    // v0.4.6.1: every telemetry packet also pings
                    // LoggingStore.noteTelemetryActivity() so an active drop
                    // cascade resets its 4s/10s timers (no auto-drop while
                    // the user is mid-rep).
                    bleManager.onTelemetry = { [weak sessionStore, weak loggingStore] telem in
                        guard let ss = sessionStore else { return }
                        let phase    = telem.phase    ?? .idle
                        let forceLb  = telem.forceLb  ?? 0
                        let repCount = telem.repCount ?? 0
                        Task { @MainActor in
                            ss.handleLiveSample(phase: phase, forceLb: forceLb, repCount: repCount)
                            loggingStore?.noteTelemetryActivity()
                        }
                    }

                    // First-launch: seed Exercise/WorkoutSession rows from
                    // the bundled history.md.
                    HistoryImporter.runIfNeeded(context: ctx)
                }
        }
        .modelContainer(modelContainer)
    }
}
