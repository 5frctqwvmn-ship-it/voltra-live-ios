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
    // v0.4.6.3: Demo Mode controller, owns synthetic telemetry + trace logger.
    @StateObject private var demo = DemoController()

    let modelContainer: ModelContainer = {
        // v0.1 dashboard models + v0.2 logging models in one container so
        // cross-queries (e.g. "last leg-day session") work.
        var allModels: [any PersistentModel.Type] = [PastSession.self, PastSet.self]
        allModels.append(contentsOf: LoggingSchema.models)
        let schema = Schema(allModels)

        // v0.4.6 build 28 hotfix: build 27 crashed on launch with a
        // _assertionFailure inside SwiftData.DefaultMigrationManager when
        // cloudKitDatabase: .automatic tried to materialize against the
        // iCloud.com.voltralive.app container — most likely because the
        // CloudKit schema hasn't been promoted from Development to
        // Production yet, so the TestFlight (Production-env) build can't
        // resolve the schema. Swift assertions are not catchable, so the
        // do/catch local-only fallback below never ran.
        //
        // For now: force local-only on every launch. CloudKit sync gets
        // re-enabled in a follow-up build once the schema is deployed to
        // Production via the CloudKit Dashboard. Local data continues to
        // work; users just don't get cross-device sync until then.
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("[VoltraLive] Failed to create local SwiftData ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleManager)
                .environmentObject(sessionStore)
                .environmentObject(loggingStore)
                .environmentObject(healthStore)
                // v0.4.6.3: .demoModeOverlay() is a ViewModifier that itself
                // reads @EnvironmentObject DemoController. Modifiers cannot
                // see env objects injected ABOVE them in the chain — only
                // the wrapped content can. So inject `demo` AFTER the
                // overlay so the overlay's own body can resolve it.
                .demoModeOverlay()
                .environmentObject(demo)
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
                    // v0.4.6.3: Telemetry router shared by BLE and synthetic
                    // sources. The DemoController.enter(.prePair) path
                    // hands the SAME closure to SyntheticTelemetryGenerator
                    // so downstream code can't tell real from fake.
                    let telemetryHandler: (Telemetry) -> Void = { [weak sessionStore, weak loggingStore, weak demo] telem in
                        guard let ss = sessionStore else { return }
                        let phase    = telem.phase    ?? .idle
                        let forceLb  = telem.forceLb  ?? 0
                        let repCount = telem.repCount ?? 0
                        Task { @MainActor in
                            ss.handleLiveSample(phase: phase, forceLb: forceLb, repCount: repCount)
                            // v0.4.6.2: pass forceLb so sub-3lb jitter doesn't
                            // hold the cascade timers open.
                            loggingStore?.noteTelemetryActivity(forceLb: forceLb)
                            // v0.4.6.3: real-device telemetry also gets logged
                            // into the active demo trace, when applicable.
                            demo?.trace?.recordTelemetry(telem)
                        }
                    }
                    bleManager.onTelemetry = telemetryHandler
                    // Stash a reference so DemoController can hand the
                    // synthetic generator the same handler.
                    DemoTelemetryBridge.shared.handler = telemetryHandler

                    // First-launch: seed Exercise/WorkoutSession rows from
                    // the bundled history.md.
                    HistoryImporter.runIfNeeded(context: ctx)
                }
        }
        .modelContainer(modelContainer)
    }
}
