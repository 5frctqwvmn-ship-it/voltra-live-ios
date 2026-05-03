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

    // MARK: Telemetry v2 — additive decoder + authoritative device state
    //
    // Runs ALONGSIDE the legacy 0xAA telemetry pipeline (FrameAssembler →
    // PacketParser → TelemetryExtractor). Sees the same assembled frames
    // and looks for param-write confirmations the legacy path ignores.
    // Currently models base-weight only; eccentric / chains / mode land
    // in follow-up commits.
    @Published private(set) var deviceState: DeviceState = .empty
    let frameDecoder = VoltraBLEFrameDecoder()

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
            // B74-F11: emit ble.error so the recorder shows the user-visible
            // "scan didn't happen" with the actual central state.
            SessionRecorder.shared.record(
                category: .ble, name: "ble.error",
                error: RecorderErrorRecord(
                    domain: "BLE",
                    code: Int(central.state.rawValue),
                    message: "scan skipped — central state \(central.state.rawValue)",
                    isUserVisible: false),
                ble: BLESubrecord(kind: .error, peripheralId: nil, side: nil,
                                  characteristic: nil, hex: nil, length: nil, rssi: nil))
            return
        }
        connectionState = .scanning
        addLog("Scanning for VOLTRA devices…")
        // B74-F11: discovery start.
        SessionRecorder.shared.record(
            category: .ble, name: "ble.discovery",
            ble: BLESubrecord(kind: .discovery, peripheralId: nil, side: nil,
                              characteristic: nil, hex: nil, length: nil, rssi: nil))
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

    /// Connect by stable peripheral identifier. Used by the dual-Voltra
    /// flow (`MultiDeviceManager`) where a separate `VoltraDiscoveryScanner`
    /// instance discovered the device on its own central, and the
    /// `CBPeripheral` it found can't be passed directly to OUR central
    /// reliably. We re-resolve via `central.retrievePeripherals` first; if
    /// that returns an empty list (Bluetooth still warming up, or iOS hasn't
    /// cached the identifier yet), we fall back to the raw peripheral the
    /// caller handed us — still better than a hard failure.
    ///
    /// This entry point is intentionally additive. It does NOT change the
    /// existing single-device auto-connect flow that lives in `connect(to:)`
    /// and the scan didDiscover delegate. Build-29 risk surface is unchanged.
    func connectKnown(identifier: UUID, fallback: CBPeripheral) {
        guard central.state == .poweredOn else {
            addLog("connectKnown deferred — BT state=\(central.state.rawValue)", level: .warn)
            // Park the fallback so didUpdateState picks it up on power-on.
            self.peripheral = fallback
            connectionState = .connecting
            return
        }
        let resolved = central.retrievePeripherals(withIdentifiers: [identifier]).first
        let target = resolved ?? fallback
        connect(to: target)
    }

    func disconnect() {
        bootstrapTask?.cancel()
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
        handleDisconnect(reason: nil)
    }

    /// Internal accessor used by the dual-Voltra reconnect path. Returns
    /// the cached `CBPeripheral` for an identifier if our own central still
    /// has it (typical for a device that just dropped). Lives on the type
    /// (not in `Dual/`) because it needs access to the private `central`.
    func retrievePeripheralFromOwnCentral(identifier: UUID) -> CBPeripheral? {
        guard central.state == .poweredOn else { return nil }
        return central.retrievePeripherals(withIdentifiers: [identifier]).first
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
            // B74-F11: surface the user-visible "write didn't happen" through
            // the recorder's BLE category, not just the local log buffer.
            SessionRecorder.shared.record(
                category: .ble, name: "ble.error",
                error: RecorderErrorRecord(
                    domain: "BLE", code: 0,
                    message: "writeControlFrame skipped — not connected",
                    isUserVisible: false),
                ble: BLESubrecord(kind: .error, peripheralId: nil, side: nil,
                                  characteristic: "transport", hex: nil,
                                  length: data.count, rssi: nil))
            return
        }
        p.writeValue(data, for: char, type: .withResponse)
        addLog("Wrote control frame (\(data.count)B): \(data.hexString.prefix(24))…")
        // B74-F11: write.tx with first 16 bytes (32 hex chars) for header
        // inspection without bloating the buffer.
        SessionRecorder.shared.record(
            category: .ble, name: "ble.write.tx",
            ble: BLESubrecord(kind: .writeTx, peripheralId: nil, side: nil,
                              characteristic: "transport",
                              hex: String(data.hexString.prefix(32)),
                              length: data.count, rssi: nil))
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
                    // B74-F11: per-bootstrap write.tx so the recorder shows
                    // the 9-frame handshake sequence in order.
                    SessionRecorder.shared.record(
                        category: .ble, name: "ble.write.tx",
                        metadata: ["bootstrap": .int(Int64(i + 1)),
                                   "total": .int(Int64(BOOTSTRAP_WRITES.count))],
                        ble: BLESubrecord(kind: .writeTx, peripheralId: nil, side: nil,
                                          characteristic: "transport",
                                          hex: String(data.hexString.prefix(32)),
                                          length: data.count, rssi: nil))
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
            // B74-F11: emit per assembled frame so the recorder shows the
            // raw notify stream alongside parsed telemetry.
            SessionRecorder.shared.record(
                category: .ble, name: "ble.notify.rx",
                ble: BLESubrecord(kind: .notifyRx, peripheralId: nil, side: nil,
                                  characteristic: nil,
                                  hex: String(frame.hexString.prefix(32)),
                                  length: frame.count, rssi: nil))

            // Telemetry v2 (additive): feed the same frame through the
            // device-state decoder and apply any confirmations to the
            // authoritative `deviceState`. The legacy pipeline below is
            // unchanged. Unknown frames produce a `.candidate` event
            // which we currently drop — adding a sampled candidate-trace
            // recorder event is a follow-up.
            for event in frameDecoder.decode(frame) {
                let reduction = DeviceStateReducer.apply(event, to: deviceState)
                deviceState = reduction.newState
                if let change = reduction.change {
                    let fromMeta: RecorderValue = change.from.map { .int(Int64($0)) } ?? .string("nil")
                    SessionRecorder.shared.record(
                        category: .device, name: "device.state.change",
                        metadata: [
                            "field": .string(change.field.rawValue),
                            "from": fromMeta,
                            "to": .int(Int64(change.to)),
                            "source": .string(change.source.rawValue),
                            "rawHex": .hex(String(change.rawHex.prefix(32)))
                        ])
                    addLog("Device \(change.field.rawValue): \(change.from.map(String.init) ?? "?") → \(change.to) lb (\(change.source.rawValue))")
                }
            }

            guard let pkt = parsePacket(frame) else {
                addLog("Unparseable frame: \(frame.hexString.prefix(40))…", level: .warn)
                // B74-F11: surface the parser-failure case in the recorder too.
                SessionRecorder.shared.record(
                    category: .ble, name: "ble.error",
                    error: RecorderErrorRecord(
                        domain: "BLE", code: 0,
                        message: "unparseable frame",
                        isUserVisible: false),
                    ble: BLESubrecord(kind: .error, peripheralId: nil, side: nil,
                                      characteristic: nil,
                                      hex: String(frame.hexString.prefix(32)),
                                      length: frame.count, rssi: nil))
                continue
            }
            if let telem = extractTelemetry(pkt) {
                mergeTelemetry(telem)
                onTelemetry?(telem)
            }
        }
    }

    /// Telemetry v2: register an outbound app-issued param write so the
    /// decoder can attribute the resulting confirmation to
    /// `appRequestConfirmed` (vs. `deviceUnsolicited` for machine-side
    /// button presses). Called by `VoltraWriter.send(...)` for fields the
    /// decoder currently understands. Safe noop for unrecognized fields.
    func recordOutboundParamWrite(field: DeviceStateField, lb: Int) {
        frameDecoder.pendingTracker.record(field: field, lb: lb)
    }

    /// b51: Public mirror so routed telemetry (from MultiDeviceManager when
    /// 2 Voltras are paired) can update this manager's @Published
    /// `telemetry`, which LiveCaptureView reads to drive the reps + force
    /// tiles. Pre-b51 the routed packet only updated SessionStore, so the
    /// tiles were stuck at zero in any 2-Voltra flow (chain or merge).
    func ingestRoutedTelemetry(_ telem: Telemetry) {
        mergeTelemetry(telem)
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
            // B74-F11: discovery hit with redacted peripheral id + RSSI.
            SessionRecorder.shared.record(
                category: .ble, name: "ble.discovery",
                ble: BLESubrecord(
                    kind: .discovery,
                    peripheralId: SessionRecorder.shared.redactor.redactedPeripheralId(name: name),
                    side: nil, characteristic: nil, hex: nil, length: nil,
                    rssi: RSSI.intValue))
            // Auto-connect to first match
            self.connect(to: peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.addLog("Connected to \(peripheral.name ?? "VOLTRA"). Discovering services…")
            // B74-F11: connection-up event, peripheral name redacted.
            let pname = peripheral.name ?? "VOLTRA"
            SessionRecorder.shared.record(
                category: .ble, name: "ble.connect",
                ble: BLESubrecord(
                    kind: .connect,
                    peripheralId: SessionRecorder.shared.redactor.redactedPeripheralId(name: pname),
                    side: nil, characteristic: nil, hex: nil, length: nil, rssi: nil))
            self.deviceName = peripheral.name
            peripheral.delegate = self
            peripheral.discoverServices([VoltraUUID.service])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            // B74-F11: emit ble.error with the underlying CB error message.
            SessionRecorder.shared.record(
                category: .ble, name: "ble.error",
                error: RecorderErrorRecord(
                    domain: "BLE", code: 0,
                    message: error?.localizedDescription ?? "Failed to connect",
                    isUserVisible: false),
                ble: BLESubrecord(
                    kind: .error,
                    peripheralId: SessionRecorder.shared.redactor.redactedPeripheralId(name: peripheral.name ?? "?"),
                    side: nil, characteristic: nil, hex: nil, length: nil, rssi: nil))
            self.handleDisconnect(reason: error?.localizedDescription ?? "Failed to connect")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            // B74-F11: disconnect, with err record only if iOS gave us one.
            SessionRecorder.shared.record(
                category: .ble, name: "ble.disconnect",
                error: error.map {
                    RecorderErrorRecord(domain: "BLE", code: 0,
                                        message: $0.localizedDescription,
                                        isUserVisible: false)
                },
                ble: BLESubrecord(
                    kind: .disconnect,
                    peripheralId: SessionRecorder.shared.redactor.redactedPeripheralId(name: peripheral.name ?? "?"),
                    side: nil, characteristic: nil, hex: nil, length: nil, rssi: nil))
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
                // B74-F11: surface the notify-subscribe failure.
                SessionRecorder.shared.record(
                    category: .ble, name: "ble.error",
                    error: RecorderErrorRecord(
                        domain: "BLE", code: 0,
                        message: error.localizedDescription,
                        isUserVisible: false),
                    ble: BLESubrecord(kind: .error, peripheralId: nil, side: nil,
                                      characteristic: characteristic.uuid.uuidString,
                                      hex: nil, length: nil, rssi: nil))
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
                // B74-F11: write failure (per-frame, after iOS hands the
                // result back from the radio).
                SessionRecorder.shared.record(
                    category: .ble, name: "ble.error",
                    error: RecorderErrorRecord(
                        domain: "BLE", code: 0,
                        message: error.localizedDescription,
                        isUserVisible: false),
                    ble: BLESubrecord(kind: .error, peripheralId: nil, side: nil,
                                      characteristic: characteristic.uuid.uuidString,
                                      hex: nil, length: nil, rssi: nil))
            }
        } else {
            // B74-F11: success ack for every confirmed write. Recorder is
            // thread-safe so no MainActor hop needed.
            SessionRecorder.shared.record(
                category: .ble, name: "ble.write.ack",
                ble: BLESubrecord(kind: .writeAck, peripheralId: nil, side: nil,
                                  characteristic: characteristic.uuid.uuidString,
                                  hex: nil, length: nil, rssi: nil))
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
