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

        // v0.4.7 build 29 crash fix.
        //
        // Build 27 crashed at launch with a _assertionFailure inside
        // SwiftData.DefaultMigrationManager because cloudKitDatabase:
        // .automatic couldn't resolve the iCloud schema (Production env
        // didn't have the CloudKit schema deployed yet).
        //
        // Build 28 "fixed" that by removing cloudKitDatabase: .automatic,
        // BUT it kept the same on-disk store URL. The store created by
        // build 27 carries CloudKit metadata in its sqlite file. When
        // build 28 reopens that same store WITHOUT CloudKit, SwiftData's
        // DefaultMigrationManager runs to reconcile the metadata and
        // trips the SAME assertion. Swift assertions are not catchable
        // — the do/catch wrapping ModelContainer init never gets a chance.
        //
        // Fix: open SwiftData at a NEW store URL ('voltra-live-v2.store').
        // No prior file = no migration = no assertion. Anyone who shipped
        // build 27/28 loses their (already-broken-and-unreachable)
        // in-app history. HistoryImporter.runIfNeeded(…) on first launch
        // re-seeds the bundled exercises from history.md so the app
        // still feels populated. Single-Voltra users on this build start
        // logging fresh.
        //
        // Belt + suspenders: if the v2 URL ALSO fails for any reason,
        // fall back to an in-memory store so the app at least launches.
        // The user gets a session that doesn't persist, but they can
        // verify the build works and we can ship a follow-up.

        let v2URL: URL = {
            let docs = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            // Application Support is the conventional spot for SwiftData
            // stores. Create the directory if it doesn't exist (it usually
            // does, but on a clean install we may be the first to write).
            if let dir = docs {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                return dir.appendingPathComponent("voltra-live-v2.store")
            }
            return URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("voltra-live-v2.store")
        }()

        // Match Apple's public ModelConfiguration init exactly so we don't
        // depend on overload-resolution edge cases:
        //   init(_ name: String?, schema: Schema?, url: URL, allowsSave: Bool,
        //        cloudKitDatabase: ModelConfiguration.CloudKitDatabase)
        let v2Config = ModelConfiguration(
            "voltra-live-v2",
            schema: schema,
            url: v2URL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        if let c = try? ModelContainer(for: schema, configurations: v2Config) {
            print("[VoltraLive] SwiftData store opened at \(v2URL.path)")
            return c
        }

        // In-memory fallback. Last-resort so the app launches even if disk
        // I/O is somehow blocked (low storage, sandbox quirk, etc.).
        let memoryConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        do {
            print("[VoltraLive] WARNING: SwiftData v2 disk store failed; using in-memory fallback.")
            return try ModelContainer(for: schema, configurations: memoryConfig)
        } catch {
            fatalError("[VoltraLive] Failed to create any SwiftData ModelContainer: \(error)")
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
