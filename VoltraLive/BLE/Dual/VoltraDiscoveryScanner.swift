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
        var rssi: Int               // dBm; updated on each advertisement
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

    // MARK: - Private

    private var central: CBCentralManager!
    private var byId: [UUID: Discovered] = [:]
    private var sweepTask: Task<Void, Never>?

    /// Stale window. iOS re-advertises every ~100\u20131000ms when nearby; 10s of
    /// silence is a strong signal the device walked away.
    private let staleAfter: TimeInterval = 10

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
        guard central.state == .poweredOn else {
            // Will start once the central comes up via centralManagerDidUpdateState.
            state = mapPoweredState(central.state)
            return
        }
        if state == .scanning { return }
        state = .scanning
        // CBCentralManagerScanOptionAllowDuplicatesKey: we WANT duplicate
        // advertisements so RSSI updates as the user moves around. Without
        // this we'd only see each device once and live RSSI would freeze.
        central.scanForPeripherals(
            withServices: [VoltraUUID.service],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        startSweep()
    }

    func stop() {
        if central.state == .poweredOn {
            central.stopScan()
        }
        sweepTask?.cancel()
        sweepTask = nil
        if state == .scanning { state = .stopped }
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
                // If caller had already asked us to start, kick the scan now.
                if self.state == .bluetoothOff || self.state == .idle {
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
            let rec = Discovered(
                id: id,
                name: name,
                rssi: rssi,
                lastSeen: Date(),
                peripheral: peripheral
            )
            self.upsert(rec)
        }
    }
}
