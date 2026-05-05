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
    // v0.4.8 build 30: dual-Voltra coordinator. Owns its own pair of
    // VoltraBLEManagers; the single-device `bleManager` above is
    // unchanged so the existing single-Voltra flow has zero regression
    // risk. The dual flow is reachable from a small "Pair 2 Voltras"
    // entry point inside ConnectView and is ignored otherwise.
    @StateObject private var multi = MultiDeviceManager()
    /// b67 (Bug 07): single source-of-truth for the pair-sheet gesture.
    /// Owned at the app root so its identity survives view re-renders.
    @StateObject private var pairing = PairingCoordinator()

    /// B74-F11: shared SessionRecorder singleton, injected at the app
    /// root via `.environmentObject(recorder)`. Owns the 10k FIFO event
    /// buffer and the recorder UI's `isRecording` binding.
    @StateObject private var recorder = SessionRecorder.shared

    /// B74-F11: observe scene transitions so we can persist the
    /// recorder buffer to `Application Support/SessionRecorder/last_session.json`
    /// when the app backgrounds or becomes inactive (best-effort; the OS
    /// may kill us before the write completes).
    @Environment(\.scenePhase) private var scenePhase

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
                .environmentObject(multi)
                .environmentObject(pairing)
                // B74-F11: SessionRecorder injection. Placed before
                // .demoModeOverlay() so the modifier and every descendant
                // can resolve @EnvironmentObject SessionRecorder.
                .environmentObject(recorder)
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
                    // b52: also pass healthStore so finalizeActiveInstance
                    // can fire a windowed HK snapshot (avg HR + kcal) when
                    // an instance ends.
                    loggingStore.wire(context: ctx, sessionStore: sessionStore, healthStore: healthStore)

                    // Build 35: prompt for HealthKit at app launch. Until
                    // build 34 the only requestAuthorization call site was
                    // LiveCaptureView.onAppear, so anyone who didn't start
                    // a workout never saw the prompt. Eager auth here means
                    // the system sheet appears on first launch as soon as
                    // the home screen renders. Apple-side idempotent so a
                    // second prompt never appears.
                    healthStore.requestAuthIfNeeded()

                    // BLE → SessionStore + LoggingStore.
                    // v0.4.6.1: every telemetry packet also pings
                    // LoggingStore.noteTelemetryActivity() so an active drop
                    // cascade resets its 4s/10s timers (no auto-drop while
                    // the user is mid-rep).
                    // v0.4.6.3: Telemetry router shared by BLE and synthetic
                    // sources. The DemoController.enter(.prePair) path
                    // hands the SAME closure to SyntheticTelemetryGenerator
                    // so downstream code can't tell real from fake.
                    let telemetryHandler: (Telemetry) -> Void = { [weak sessionStore, weak loggingStore, weak demo, weak bleManager] telem in
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
                            // b51: mirror routed telemetry into the
                            // single-source bleManager so LiveCaptureView's
                            // reps + force tiles (which read `ble.telemetry`)
                            // update in chain + merge modes. Without this,
                            // bleManager.telemetry only mutates when the
                            // singleton is the one decoding frames \u2014 i.e.
                            // single-Voltra pairings only.
                            bleManager?.ingestRoutedTelemetry(telem)
                        }
                    }
                    bleManager.onTelemetry = telemetryHandler
                    // Stash a reference so DemoController can hand the
                    // synthetic generator the same handler.
                    DemoTelemetryBridge.shared.handler = telemetryHandler

                    // b70 / V4-D17: cold-launch demo rehydration.
                    //
                    // Pre-b70 the persisted toggle (`demoMode.toggleOn`) was
                    // re-engaged via `.settingsRestore`, which never started
                    // the synthetic pump. The b69 user report ("Demo
                    // simulation broken") was the consequence: backgrounding
                    // the app while in demo and reopening produced a live
                    // screen with no force flow.
                    //
                    // Fix: rehydrate via `.prePair` so the synthetic pump is
                    // built. We don't know which screen the user came from
                    // \u2014 `.prePair` is the only enum case that guarantees a
                    // pump, so it's the safe choice. If a Voltra is already
                    // connected by the time rehydration runs (rare), the
                    // root .onChange observer in ContentView will swap us
                    // back to live by calling `demo.exit()`.
                    if demo.settingsToggleOn && !demo.isActive {
                        demo.enter(source: .prePair, onTelemetry: telemetryHandler)
                    }

                    // Build 41: route MultiDeviceManager telemetry into
                    // the SAME pipeline as the single-device flow.
                    //
                    // Before b41, the dual-Voltra screen wired its own
                    // local closures inside DualCaptureView.onAppear, so
                    // anyone who paired two Voltras and went to the regular
                    // home screen (the b40 default) saw zero telemetry from
                    // either side. The user reported this as 'when I combine
                    // them, it only works on one of the Voltras' / 'left
                    // shows connected but no phase, reps, or force'.
                    //
                    // Routing rule:
                    //   - If BOTH MDM slots have produced telemetry, use the
                    //     combined virtual-twin reading (force=sum,
                    //     reps=sum) which fires after every per-device
                    //     packet from MDM.handleTelemetry.
                    //   - If only ONE side is connected, that side's raw
                    //     telemetry passes through unchanged.
                    // This makes both single-paired-via-MDM and dual-paired
                    // flows feed the same SessionStore + LoggingStore that
                    // the legacy single-device manager does.
                    // Build 42: routing now honors `multi.workoutMode`.
                    //   .singleLeft  -> only left forwarded
                    //   .singleRight -> only right forwarded
                    //   .independent -> both forwarded raw (no summing,
                    //                   user sees combined activity in tile)
                    //   .combined    -> merged virtual-twin reading
                    // b49: with both Voltras paired, the user is only
                    // physically on ONE side at a time. b48 .independent
                    // forwarded BOTH sides into the same telemetry sink,
                    // which made reps + force flap between the two streams
                    // (regression report: "reps not counting, force not
                    // tracking"). Fix: route only the supersetActiveSlot's
                    // stream into the session, regardless of whether the
                    // chain has been used. The Merge button switches to
                    // .combined which falls through to onCombinedTelemetry.
                    multi.onLeftTelemetry = { [weak multi] t in
                        guard let m = multi else { return }
                        let bothConnected = m.left.connectionState.isConnected
                                          && m.right.connectionState.isConnected
                        if !bothConnected {
                            // Only one side connected: pass through.
                            if !m.right.connectionState.isConnected {
                                telemetryHandler(t)
                            }
                            return
                        }
                        // Both connected: respect workoutMode.
                        switch m.workoutMode {
                        case .singleLeft:
                            telemetryHandler(t)
                        case .singleRight, .combined:
                            break  // singleRight ignores left; combined waits for onCombinedTelemetry
                        case .independent, .superset:
                            // b49: route only the active slot \u2014 user
                            // is only on one side at a time. SWAP flips
                            // supersetActiveSlot, which atomically moves
                            // the telemetry stream to the other side.
                            if m.supersetActiveSlot == .left { telemetryHandler(t) }
                        }
                    }
                    multi.onRightTelemetry = { [weak multi] t in
                        guard let m = multi else { return }
                        let bothConnected = m.left.connectionState.isConnected
                                          && m.right.connectionState.isConnected
                        if !bothConnected {
                            if !m.left.connectionState.isConnected {
                                telemetryHandler(t)
                            }
                            return
                        }
                        switch m.workoutMode {
                        case .singleRight:
                            telemetryHandler(t)
                        case .singleLeft, .combined:
                            break
                        case .independent, .superset:
                            // b49: same active-side rule as the left handler.
                            if m.supersetActiveSlot == .right { telemetryHandler(t) }
                        }
                    }
                    multi.onCombinedTelemetry = { [weak multi] c in
                        // Combined virtual-twin reading: only forwarded when
                        // BOTH sides are connected AND user picked .combined.
                        guard let m = multi,
                              m.left.connectionState.isConnected,
                              m.right.connectionState.isConnected,
                              m.workoutMode == .combined else { return }
                        // Synthesize a Telemetry struct from the merged
                        // combined reading. Phase comes from whichever side
                        // is currently in a non-idle phase (caller-side
                        // logic prefers the more 'active' phase).
                        let phase: VoltraPhase = {
                            if c.phaseLeft != .idle { return c.phaseLeft }
                            return c.phaseRight
                        }()
                        var merged = Telemetry()
                        merged.phase     = phase
                        merged.forceLb   = c.forceLb
                        merged.repCount  = c.repCount
                        merged.peakPowerWatts = c.peakPower
                        telemetryHandler(merged)
                    }

                    // First-launch: seed Exercise/WorkoutSession rows from
                    // the bundled history.md.
                    HistoryImporter.runIfNeeded(context: ctx)
                }
                // B74-F11: persist the recorder buffer to disk on
                // background / inactive transitions so the last session
                // survives the app being killed.
                //
                // Commit 3 extension: also emit lifecycle.appBackground /
                // lifecycle.appForeground so the recorder timeline shows
                // the scene-phase transitions alongside the persist call.
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .background, .inactive:
                        recorder.record(
                            category: .lifecycle,
                            name: "lifecycle.appBackground",
                            metadata: ["phase": .string(String(describing: newPhase))])
                        recorder.persist()
                    case .active:
                        recorder.record(
                            category: .lifecycle,
                            name: "lifecycle.appForeground")
                    @unknown default:
                        break
                    }
                }
                // B74-F11: root-level recorder dot in the bottom-trailing
                // safe area. Hidden until the user triple-taps the
                // build-badge chip (UserDefaults["VOLTRARecorderUnlocked"]).
                // Sits above the build badge via the toggle's own padding.
                //
                // b78 launch-crash fix: `.overlay { content }` does NOT
                // propagate env-objects from the modifier chain to the
                // overlay content — the content is a sibling of the
                // modified view, not a descendant. Without re-injecting
                // `recorder` here, SwiftUI's DynamicProperty resolution
                // for SessionRecorderToggle's @EnvironmentObject crashes
                // at view setup with `EnvironmentObject.error()` even
                // when the toggle's body returns EmptyView (because
                // VOLTRARecorderUnlocked is false on a fresh install).
                // See KI-13 in 06_KNOWN_ISSUES.md.
                .overlay(alignment: .bottomTrailing) {
                    SessionRecorderToggle()
                        .environmentObject(recorder)
                }
                // b82: bottom-left Session Tracker indicator. Visible when
                // a VOLTRA is connected. Tapping opens SessionRecorderViewer.
                // Env-objects re-injected per KI-13 / AGENTS.md E5:
                // .overlay content does not inherit parent env-objects.
                .overlay(alignment: .bottomLeading) {
                    SessionTrackerIndicator()
                        .environmentObject(bleManager)
                        .environmentObject(multi)
                        .environmentObject(recorder)
                }
        }
        .modelContainer(modelContainer)
    }
}
