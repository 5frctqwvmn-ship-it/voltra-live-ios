// VoltraBLEManager.swift
// CoreBluetooth port of voltra-ble.js VoltraConnection.
//
// Scan → connect → discover service → subscribe to 3 notification chars
// → send BOOTSTRAP_WRITES at 60ms intervals to TRANSPORT_UUID with writeWithResponse.
// NEVER sends any control writes. Read-only only.

import Foundation
import CoreBluetooth
import Combine

// MARK: - Connection state

enum BLEConnectionState: Equatable {
    case idle
    case scanning
    case connecting
    case connected(deviceName: String)
    case disconnected(reason: String?)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - Log entry

struct BLELogEntry: Identifiable {
    enum Level { case info, warn, error }
    let id = UUID()
    let timestamp: Date
    let level: Level
    let message: String

    var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: timestamp)
    }
}

// MARK: - BLE Manager

@MainActor
final class VoltraBLEManager: NSObject, ObservableObject {

    // MARK: Published state
    @Published var connectionState: BLEConnectionState = .idle
    @Published var telemetry = LiveTelemetry()
    @Published var log: [BLELogEntry] = []
    @Published var batteryPercent: Int? = nil
    @Published var serial: String? = nil
    @Published var deviceName: String? = nil

    // Callback for callers that need raw telemetry (e.g. SessionStore)
    var onTelemetry: ((Telemetry) -> Void)?

    // MARK: Private CBCentral state
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var cmdChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var transportChar: CBCharacteristic?

    private let assembler = FrameAssembler()
    private var bootstrapTask: Task<Void, Never>?

    // MARK: Init
    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: Public API

    func startScan() {
        guard central.state == .poweredOn else {
            addLog("Bluetooth not ready (state=\(central.state.rawValue))", level: .warn)
            return
        }
        connectionState = .scanning
        addLog("Scanning for VOLTRA devices…")
        // Scan with service UUID filter first; CBCentralManager handles namePrefix in scanOptions
        central.scanForPeripherals(withServices: [VoltraUUID.service], options: nil)
    }

    func connect(to peripheral: CBPeripheral) {
        self.peripheral = peripheral
        central.stopScan()
        connectionState = .connecting
        addLog("Connecting to \(peripheral.name ?? "VOLTRA")…")
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        bootstrapTask?.cancel()
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
        handleDisconnect(reason: nil)
    }

    // MARK: Control writes
    //
    // The user explicitly granted permission to load weights into the VOLTRA
    // (Apr 2026). All control writes flow through this single entry point so
    // we can swap in a different transport later (e.g. a write-without-response
    // path on the just-write characteristic) without touching callers.

    /// Write a fully-built VOLTRA frame to the transport characteristic.
    /// Must be a complete 0x55-magic frame including CRC8 + CRC16.
    /// Currently fire-and-forget: we don't parse param-write ACKs from the
    /// device — we rely on `.withResponse` for radio-level delivery only.
    func writeControlFrame(_ data: Data) {
        guard let p = peripheral, p.state == .connected, let char = transportChar else {
            addLog("Control write skipped — not connected (\(data.count)B)", level: .warn)
            return
        }
        p.writeValue(data, for: char, type: .withResponse)
        addLog("Wrote control frame (\(data.count)B): \(data.hexString.prefix(24))…")
    }

    // MARK: Bootstrap

    func sendBootstrap() {
        guard let char = transportChar else {
            addLog("Cannot send bootstrap — transport characteristic not found", level: .warn)
            return
        }
        addLog("Sending read-only handshake (\(BOOTSTRAP_WRITES.count) frames)…")
        bootstrapTask?.cancel()
        bootstrapTask = Task { [weak self] in
            guard let self else { return }
            for (i, data) in BOOTSTRAP_WRITES.enumerated() {
                guard !Task.isCancelled else { break }
                guard let p = self.peripheral, p.state == .connected else { break }
                await MainActor.run {
                    p.writeValue(data, for: char, type: .withResponse)
                    self.addLog("Bootstrap [\(i+1)/\(BOOTSTRAP_WRITES.count)] sent (\(data.hexString.prefix(12))…)")
                }
                try? await Task.sleep(nanoseconds: 60_000_000) // 60ms
            }
            await MainActor.run {
                self.addLog("Handshake sent. Waiting for telemetry…")
            }
        }
    }

    // MARK: Private helpers

    private func handleDisconnect(reason: String?) {
        bootstrapTask?.cancel()
        assembler.clear()
        cmdChar = nil
        notifyChar = nil
        transportChar = nil
        if case .disconnected = connectionState { return }
        connectionState = .disconnected(reason: reason)
        addLog(reason.map { "Disconnected: \($0)" } ?? "Disconnected.")
    }

    private func handleNotification(data: Data) {
        let frames = assembler.accept(data)
        for frame in frames {
            guard let pkt = parsePacket(frame) else {
                addLog("Unparseable frame: \(frame.hexString.prefix(40))…", level: .warn)
                continue
            }
            if let telem = extractTelemetry(pkt) {
                mergeTelemetry(telem)
                onTelemetry?(telem)
            }
        }
    }

    private func mergeTelemetry(_ telem: Telemetry) {
        if let v = telem.batteryPercent { batteryPercent = v }
        if let v = telem.serial         { serial = v }
        if let v = telem.forceLb        { telemetry.forceLb = v }
        if let v = telem.tick           { telemetry.tick = v }
        if let v = telem.repCount       { telemetry.repCount = v }
        if let v = telem.setCount       { telemetry.setCount = v }
        if let v = telem.phase          { telemetry.phase = v; telemetry.phaseRaw = telem.phaseRaw }
        if let v = telem.peakForceLb    { telemetry.peakForceLb = v }
        if let v = telem.peakPowerWatts { telemetry.peakPowerWatts = v }
        if let v = telem.timeToPeakMs   { telemetry.timeToPeakMs = v }
        if let v = telem.lastRepTimeToPeakMs { telemetry.lastRepTimeToPeakMs = v }
        telemetry.lastUpdate = Date()
    }

    func addLog(_ message: String, level: BLELogEntry.Level = .info) {
        let entry = BLELogEntry(timestamp: Date(), level: level, message: message)
        log.append(entry)
        if log.count > 200 { log.removeFirst() }
        switch level {
        case .error: print("[VOLTRA][ERROR]", message)
        case .warn:  print("[VOLTRA][WARN] ", message)
        case .info:  print("[VOLTRA]", message)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension VoltraBLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                self.addLog("Bluetooth powered on.")
            case .poweredOff:
                self.addLog("Bluetooth powered off.", level: .warn)
                self.handleDisconnect(reason: "Bluetooth powered off")
            case .unauthorized:
                self.addLog("Bluetooth unauthorized — check Settings > Privacy > Bluetooth.", level: .error)
            case .unsupported:
                self.addLog("Bluetooth LE not supported on this device.", level: .error)
            default:
                self.addLog("Bluetooth state: \(central.state.rawValue)", level: .warn)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        Task { @MainActor in
            let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "VOLTRA"
            self.addLog("Found: \(name) (RSSI \(RSSI))")
            // Auto-connect to first match
            self.connect(to: peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.addLog("Connected to \(peripheral.name ?? "VOLTRA"). Discovering services…")
            self.deviceName = peripheral.name
            peripheral.delegate = self
            peripheral.discoverServices([VoltraUUID.service])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            self.handleDisconnect(reason: error?.localizedDescription ?? "Failed to connect")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            self.handleDisconnect(reason: error?.localizedDescription)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension VoltraBLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard error == nil else {
                self.addLog("Service discovery error: \(error!.localizedDescription)", level: .error)
                return
            }
            guard let service = peripheral.services?.first(where: { $0.uuid == VoltraUUID.service }) else {
                self.addLog("VOLTRA service not found", level: .error)
                return
            }
            self.addLog("VOLTRA service found. Discovering characteristics…")
            peripheral.discoverCharacteristics(
                [VoltraUUID.cmdChar, VoltraUUID.notifyChar, VoltraUUID.transport, VoltraUUID.justWrite],
                for: service
            )
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didDiscoverCharacteristicsFor service: CBService,
                                 error: Error?) {
        Task { @MainActor in
            guard error == nil else {
                self.addLog("Char discovery error: \(error!.localizedDescription)", level: .error)
                return
            }
            let chars = service.characteristics ?? []

            for char in chars {
                switch char.uuid {
                case VoltraUUID.cmdChar:
                    self.cmdChar = char
                    peripheral.setNotifyValue(true, for: char)
                    self.addLog("Subscribed CMD_CHAR (55CA)")
                case VoltraUUID.notifyChar:
                    self.notifyChar = char
                    peripheral.setNotifyValue(true, for: char)
                    self.addLog("Subscribed NOTIFY_CHAR (CA94)")
                case VoltraUUID.transport:
                    self.transportChar = char
                    if char.properties.contains(.notify) {
                        peripheral.setNotifyValue(true, for: char)
                        self.addLog("Subscribed TRANSPORT (A010)")
                    }
                default:
                    break
                }
            }

            // Mark connected once transport char is available
            if self.transportChar != nil {
                let name = peripheral.name ?? "VOLTRA"
                self.connectionState = .connected(deviceName: name)
                self.addLog("Connected. Sending read-only handshake…")
                self.sendBootstrap()
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                 error: Error?) {
        if let error = error {
            Task { @MainActor in
                self.addLog("Notify subscribe error for \(characteristic.uuid): \(error.localizedDescription)", level: .warn)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didUpdateValueFor characteristic: CBCharacteristic,
                                 error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        Task { @MainActor in
            self.handleNotification(data: data)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didWriteValueFor characteristic: CBCharacteristic,
                                 error: Error?) {
        if let error = error {
            Task { @MainActor in
                self.addLog("Bootstrap write error: \(error.localizedDescription)", level: .warn)
            }
        }
    }
}

// MARK: - LiveTelemetry value type

struct LiveTelemetry {
    var forceLb: Double = 0
    var tick: UInt32 = 0
    var repCount: Int = 0
    var setCount: Int = 0
    var phase: VoltraPhase = .idle
    var phaseRaw: UInt8? = nil
    var peakForceLb: Double? = nil
    var peakPowerWatts: Int? = nil
    var timeToPeakMs: Int? = nil
    var lastRepTimeToPeakMs: Int? = nil
    var lastUpdate: Date = .distantPast
}
