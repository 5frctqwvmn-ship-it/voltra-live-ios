// VoltraDiscoveryScanner.swift
//
// v0.4.7 build 29: Picker-mode BLE scanner.
//
// Why this exists:
//   The existing VoltraBLEManager.didDiscover auto-connects to the first
//   peripheral it finds. That's correct for the single-Voltra flow, but for
//   "Connect Two VOLTRAs" we need to SEE all advertising Voltras and let the
//   user assign Left vs Right by tapping. We do not want to alter the existing
//   single-device auto-connect path, so this scanner runs on its OWN
//   CBCentralManager instance and never connects to anything itself \u2014 it just
//   accumulates advertisements and exposes a sorted, deduplicated list. The
//   actual connect is handed off to VoltraBLEManager.connectKnown(...).
//
// CoreBluetooth notes:
//   - Multiple CBCentralManager instances in one app are supported. iOS shares
//     the radio across them; each gets its own delegate callbacks.
//   - The CBPeripheral handed to this scanner CANNOT be passed directly to
//     another central's connect() reliably across iOS versions. Always
//     re-resolve via central.retrievePeripherals(withIdentifiers:), which
//     VoltraBLEManager.connectKnown does for us.
//   - We filter on VoltraUUID.service so the user only sees Voltras, not
//     Beats headphones / random BLE clutter (per user choice).
//
// Lifecycle:
//   .start()            \u2014 begin scanning. Idempotent. Updates `state` to .scanning.
//   .stop()             \u2014 stop scanning. Keeps `discovered` populated.
//   .clear()            \u2014 wipe the discovered list (e.g. user cancels picker).
//
// Threading:
//   @MainActor for `state` / `discovered` so SwiftUI can observe directly.

import Foundation
import CoreBluetooth
import Combine

@MainActor
final class VoltraDiscoveryScanner: NSObject, ObservableObject {

    // MARK: - Discovered device record

    struct Discovered: Identifiable, Equatable {
        let id: UUID                // CBPeripheral.identifier
        var name: String            // best-effort label
        // b45 (D): displayed RSSI is now smoothed via an exponential moving
        // average so the discovery list doesn't bounce. CoreBluetooth fires
        // adverts at ~100\u20131000 ms cadence and instantaneous RSSI swings
        // \u00b110 dBm even when the device is stationary, which made the sort
        // order flip every few hundred ms and the dBm number jitter wildly.
        // We keep both: `rssi` is the smoothed value used for display + sort,
        // and `rawRssi` is the latest raw advertisement (for debugging only).
        var rssi: Int               // dBm, EMA-smoothed; what UI shows
        var rawRssi: Int            // dBm, last raw advertisement
        var lastSeen: Date
        // Held weakly through CB; the live peripheral used at connect-time.
        // CoreBluetooth retains it via the central, so a strong handle here is
        // safe for the brief window between discovery and connect.
        let peripheral: CBPeripheral

        static func == (a: Discovered, b: Discovered) -> Bool { a.id == b.id }
    }

    // MARK: - Published state

    enum State: Equatable {
        case idle
        case scanning
        case stopped
        case bluetoothOff
        case unauthorized
        case unsupported
    }

    @Published private(set) var state: State = .idle
    /// Sorted strongest-first by RSSI. Stale entries (>10s without an
    /// advertisement) get pruned by the periodic sweep.
    @Published private(set) var discovered: [Discovered] = []

    /// Build 39: Set when the caller has asked us to scan. We need this
    /// because CBCentralManager.state is asynchronous — `start()` is
    /// usually called before the central reaches `.poweredOn`. Without
    /// this flag the centralManagerDidUpdateState delegate had no way to
    /// know it should kick off the scan once the radio came up, so the
    /// dual-pair view sat forever showing "Scanning for VOLTRA devices…"
    /// with zero discoveries (was the b30 "no scan, all buttons static"
    /// report).
    private var startRequested: Bool = false

    // MARK: - Private

    private var central: CBCentralManager!
    private var byId: [UUID: Discovered] = [:]
    private var sweepTask: Task<Void, Never>?

    /// Stale window. iOS re-advertises every ~100\u20131000ms when nearby; 10s of
    /// silence is a strong signal the device walked away.
    private let staleAfter: TimeInterval = 10

    /// b45 (D): EMA smoothing factor for RSSI.
    /// new = alpha*raw + (1-alpha)*previous. Lower = smoother but slower to
    /// react when the user actually moves. 0.25 is a good middle ground:
    /// after ~10 adverts (~2\u20133 s) the smoothed value tracks reality, but
    /// single-frame noise spikes barely move the bar.
    private let rssiEmaAlpha: Double = 0.25

    // MARK: - Init

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    deinit {
        sweepTask?.cancel()
    }

    // MARK: - Public API

    func start() {
        startRequested = true
        guard central.state == .poweredOn else {
            // Radio not ready yet. centralManagerDidUpdateState will
            // call beginScanning() when .poweredOn arrives.
            state = mapPoweredState(central.state)
            return
        }
        beginScanning()
    }

    func stop() {
        startRequested = false
        if central.state == .poweredOn {
            central.stopScan()
        }
        sweepTask?.cancel()
        sweepTask = nil
        if state == .scanning { state = .stopped }
    }

    /// Build 39: actually issue the BLE scan. Split out of start() so the
    /// delegate can call it once the central reaches .poweredOn.
    private func beginScanning() {
        if state == .scanning { return }
        state = .scanning
        // CBCentralManagerScanOptionAllowDuplicatesKey: we WANT duplicate
        // advertisements so RSSI updates as the user moves around.
        central.scanForPeripherals(
            withServices: [VoltraUUID.service],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        startSweep()
    }

    func clear() {
        discovered = []
        byId = [:]
    }

    /// Number of currently-fresh discoveries.
    var count: Int { discovered.count }

    // MARK: - Internals

    private func mapPoweredState(_ s: CBManagerState) -> State {
        switch s {
        case .poweredOn:    return .idle
        case .poweredOff:   return .bluetoothOff
        case .unauthorized: return .unauthorized
        case .unsupported:  return .unsupported
        default:            return .idle
        }
    }

    private func upsert(_ rec: Discovered) {
        byId[rec.id] = rec
        // Sort strongest-first; ties broken by name for stable ordering.
        discovered = byId.values.sorted { lhs, rhs in
            if lhs.rssi != rhs.rssi { return lhs.rssi > rhs.rssi }
            return lhs.name < rhs.name
        }
    }

    private func startSweep() {
        sweepTask?.cancel()
        sweepTask = Task { [weak self] in
            // Prune stale entries every 2s.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    self?.pruneStale()
                }
            }
        }
    }

    private func pruneStale() {
        let cutoff = Date().addingTimeInterval(-staleAfter)
        let before = byId.count
        byId = byId.filter { $0.value.lastSeen >= cutoff }
        if byId.count != before {
            discovered = byId.values.sorted { lhs, rhs in
                if lhs.rssi != rhs.rssi { return lhs.rssi > rhs.rssi }
                return lhs.name < rhs.name
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension VoltraDiscoveryScanner: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                // Build 39: if start() was called before the radio came up,
                // actually kick off the scan now. The original code only
                // updated the published state — it never called
                // scanForPeripherals — so the dual-pair view stayed empty
                // forever even though the radio was ready.
                if self.startRequested {
                    self.beginScanning()
                } else if self.state == .bluetoothOff || self.state == .idle {
                    self.state = .idle
                }
            case .poweredOff:    self.state = .bluetoothOff
            case .unauthorized:  self.state = .unauthorized
            case .unsupported:   self.state = .unsupported
            default:             break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        // Capture name on the BG-callback thread; everything else hops to main.
        let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        let name = peripheral.name ?? advName ?? "VOLTRA"
        let rssi = RSSI.intValue
        let id = peripheral.identifier
        Task { @MainActor in
            // b45 (D): blend new raw RSSI into the existing smoothed value
            // when we've seen this peripheral before; otherwise seed with raw.
            let smoothed: Int
            if let prev = self.byId[id] {
                let blended = self.rssiEmaAlpha * Double(rssi)
                            + (1.0 - self.rssiEmaAlpha) * Double(prev.rssi)
                smoothed = Int(blended.rounded())
            } else {
                smoothed = rssi
            }
            let rec = Discovered(
                id: id,
                name: name,
                rssi: smoothed,
                rawRssi: rssi,
                lastSeen: Date(),
                peripheral: peripheral
            )
            self.upsert(rec)
        }
    }
}
