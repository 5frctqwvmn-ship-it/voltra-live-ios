// DemoController.swift
// v0.4.6.3 / build 26
//
// Demo Mode is a global "no-side-effects" mode the user can enter from either
// the pre-pair Connect screen or the post-pair home screen. While active:
//
//   • Pairing, telemetry, drop-set/pulley math, charts — all behave normally.
//   • Pre-pair entry: a synthetic telemetry stream stands in for a real Voltra
//     so the menus/charts have plausible data flowing through them.
//   • Post-pair entry: the real device drives telemetry as usual.
//   • Absolutely nothing is written to disk: SwiftData saves go to a separate
//     in-memory container and `DemoTraceLogger` redirects UserDefaults writes
//     into a per-session dictionary.
//   • A sticky "DEMO MODE — nothing is recorded · build N" banner is rendered.
//   • Every nav/tap/telemetry/drop event is captured in a structured JSON
//     trace. On exit, the user can ship that trace to the developer for
//     higher-fidelity feedback than a screenshot.
//
// Exit (from the banner or Settings → Demo Mode toggle) discards all
// in-memory state. Relaunch does NOT auto-exit — the *toggle* is persisted in
// the real UserDefaults so you can stay in demo across launches if you want.
//
// SACRED-FILES NOTE: this entire subsystem lives in NEW files under
// VoltraLive/Demo/. The protocol layer (VoltraProtocol/PacketParser/etc) is
// untouched. The synthetic telemetry generator emits already-decoded
// `Telemetry` structs straight into the existing onTelemetry callback, so we
// don't have to fake raw BLE frames.

import Foundation
import SwiftData
import Combine

// MARK: - Entry source

enum DemoEntrySource: String, Codable {
    /// Tapped "Demo Mode" on the Connect screen, no Voltra paired.
    /// Synthetic telemetry will be emitted by `SyntheticTelemetryGenerator`.
    case prePair
    /// Tapped "Demo Mode" on the post-connect home screen with a real device
    /// already paired. Real telemetry flows through; we just don't persist.
    case postPair
    /// Re-enabled via the Settings toggle on a fresh launch (we don't know
    /// which screen they came from).
    case settingsRestore
}

// MARK: - Controller

/// Single source of truth for whether the app is in demo mode and which
/// in-memory ModelContext the stores should be writing to. Owns the
/// `DemoTraceLogger` and `SyntheticTelemetryGenerator` for the active session.
@MainActor
final class DemoController: ObservableObject {

    // MARK: Published state

    /// True if a demo session is active. SwiftUI views observe this to
    /// render the sticky banner and route SwiftData writes.
    @Published private(set) var isActive: Bool = false

    /// Source that started the current session, or `nil` when inactive.
    @Published private(set) var entrySource: DemoEntrySource? = nil

    /// Trace logger for the currently-active session. `nil` when inactive.
    @Published private(set) var trace: DemoTraceLogger? = nil

    // MARK: Persisted user preference (real UserDefaults, intentionally)

    /// Whether the Settings toggle is on. Persists across launches in REAL
    /// UserDefaults — this is the one bit of demo-related state that's
    /// allowed to outlive a session, because otherwise there'd be no way to
    /// "stay in demo" after backgrounding the app.
    private let toggleKey = "demoMode.toggleOn"

    /// Read-only convenience for the Settings toggle binding.
    var settingsToggleOn: Bool {
        get { UserDefaults.standard.bool(forKey: toggleKey) }
        set { UserDefaults.standard.set(newValue, forKey: toggleKey) }
    }

    // MARK: Synthetic telemetry pump

    /// Active when `entrySource == .prePair` and pumps synthetic Telemetry
    /// frames through the same callback the real BLE manager uses.
    private var synthetic: SyntheticTelemetryGenerator? = nil

    // MARK: In-memory ModelContext for demo writes

    /// Separate in-memory ModelContainer with the same schema as the real one.
    /// All SwiftData writes during demo go here; on exit, we drop it.
    private var demoContainer: ModelContainer? = nil
    private(set) var demoContext: ModelContext? = nil

    // MARK: Lifecycle

    /// Enter demo. Spins up an in-memory ModelContainer, a fresh trace
    /// logger, and (for pre-pair) the synthetic telemetry generator.
    ///
    /// - Parameters:
    ///   - source: which UI surface initiated the demo
    ///   - onTelemetry: closure to receive synthetic Telemetry frames
    ///       (`pre-pair` only). The caller passes the same handler the real
    ///       BLE manager uses so the rest of the app doesn't know the
    ///       difference.
    func enter(source: DemoEntrySource, onTelemetry: @escaping (Telemetry) -> Void) {
        guard !isActive else { return }

        // Build an in-memory SwiftData container that mirrors the real one's
        // schema exactly. CloudKit is OFF for demo — we don't want demo
        // writes leaking into the user's iCloud, and isStoredInMemoryOnly is
        // incompatible with cloudKitDatabase=.automatic anyway.
        var allModels: [any PersistentModel.Type] = [PastSession.self, PastSet.self]
        allModels.append(contentsOf: LoggingSchema.models)
        let schema = Schema(allModels)
        let cfg = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        do {
            let container = try ModelContainer(for: schema, configurations: cfg)
            self.demoContainer = container
            self.demoContext = ModelContext(container)
        } catch {
            // If we can't even build an in-memory container, just bail out
            // of entering demo. The user gets nothing scary, just no demo.
            print("[DemoController] failed to create in-memory container: \(error)")
            return
        }

        let logger = DemoTraceLogger(entrySource: source)
        self.trace = logger
        self.entrySource = source

        if source == .prePair {
            let gen = SyntheticTelemetryGenerator(onTelemetry: { [weak logger] telem in
                onTelemetry(telem)
                logger?.recordTelemetry(telem)
            })
            gen.start()
            self.synthetic = gen
        }

        // Persist the toggle so that if the user backgrounds the app and
        // comes back, the Settings toggle still reads ON.
        UserDefaults.standard.set(true, forKey: toggleKey)

        self.isActive = true
        logger.recordEvent(.sessionStart(source: source))
    }

    /// Exit demo. Stops the synthetic generator (if any), captures a final
    /// summary in the trace, drops the in-memory container, and flips
    /// `isActive` off.
    ///
    /// - Returns: the completed trace logger so a UI sheet can show it /
    ///     offer to upload it. Caller takes ownership.
    @discardableResult
    func exit() -> DemoTraceLogger? {
        guard isActive else { return nil }
        synthetic?.stop()
        synthetic = nil

        let finishedTrace = trace
        finishedTrace?.recordEvent(.sessionEnd)
        finishedTrace?.finalize()

        // Drop SwiftData state. The in-memory container has no on-disk
        // backing so this is purely a memory release.
        demoContext = nil
        demoContainer = nil

        trace = nil
        entrySource = nil
        isActive = false

        // Flip the persisted toggle off too. If the user wants to come back,
        // they'll re-enter explicitly.
        UserDefaults.standard.set(false, forKey: toggleKey)

        return finishedTrace
    }

    /// Forwarded from views: record a navigation or button-tap event into
    /// the active trace. No-op when inactive.
    func note(_ event: DemoTraceLogger.Event) {
        trace?.recordEvent(event)
    }
}
