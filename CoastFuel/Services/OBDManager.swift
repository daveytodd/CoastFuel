import Combine
import CoreBluetooth
import Foundation

/// Connects to BLE OBD-II adapters that expose a writable and notifying characteristic.
/// Classic Bluetooth/SPP adapters are not accessible through CoreBluetooth on iOS.
@MainActor
final class OBDManager: NSObject, ObservableObject {
    enum ConnectionState: String {
        case idle = "Idle"
        case scanning = "Scanning for OBD-II adapters…"
        case connecting = "Connecting…"
        case discovering = "Finding adapter services…"
        case initializing = "Initializing ELM327…"
        case ready = "Connected"
        case failed = "Connection failed"
    }

    @Published private(set) var isConnected = false
    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var fuelLevelPercentage: Double?
    @Published private(set) var discoveredAdapters: [CBPeripheral] = []
    @Published private(set) var diagnosticLogs: [String] = []

    private let centralQueue = DispatchQueue(label: "com.daveytodd.CoastFuel.obd-central")
    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var responseBuffer = ""
    private var commandQueue: [String] = []
    private var activeCommand: String?
    private var isScanning = false

    private let knownServiceUUIDs: Set<String> = ["FFF0", "18F0"]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: centralQueue)
    }

    func startScanning() {
        guard central.state == .poweredOn else {
            log("Bluetooth is not ready (state: \(centralStateDescription(central.state))).")
            return
        }
        discoveredAdapters.removeAll()
        connectionState = .scanning
        isScanning = true
        // Scan broadly: many BLE adapters use vendor-specific service UUIDs. Filter candidates
        // after discovery by advertised name or common OBD service UUID.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        log("Scanning for BLE OBD-II adapters. Make sure the scanner is powered and not connected elsewhere.")
    }

    func stopScanning() {
        guard isScanning else { return }
        central.stopScan()
        isScanning = false
        if connectionState == .scanning { connectionState = .idle }
    }

    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting
        log("Connecting to \(peripheral.name ?? "OBD-II adapter")…")
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let peripheral = connectedPeripheral { central.cancelPeripheralConnection(peripheral) }
        clearConnection(state: .idle)
    }

    /// Requests Mode 01 PID 2F (fuel tank level). The ECU may not support this PID.
    func requestFuelLevel() {
        guard isConnected, writeCharacteristic != nil else {
            log("Cannot request fuel level: no ready OBD-II connection.")
            return
        }
        enqueue("012F")
    }

    private func enqueue(_ command: String) {
        commandQueue.append(command)
        sendNextCommandIfReady()
    }

    private func sendNextCommandIfReady() {
        guard activeCommand == nil, !commandQueue.isEmpty,
              let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic else { return }
        let command = commandQueue.removeFirst()
        activeCommand = command
        responseBuffer = ""
        let data = Data((command + "\r").utf8)
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: writeType)
        log("> \(command)")
    }

    private func handleResponse(_ response: String) {
        let command = activeCommand
        log("< \(response.trimmingCharacters(in: .whitespacesAndNewlines))")
        if command == "012F" { parseFuelLevel(from: response) }
        if command == "ATZ" {
            connectionState = .initializing
        }
        activeCommand = nil
        sendNextCommandIfReady()
        if commandQueue.isEmpty, command == "ATSP0" || (commandQueue.isEmpty && command != nil && command != "012F") {
            connectionState = .ready
            isConnected = true
            log("ELM327 initialization complete.")
        }
    }

    private func parseFuelLevel(from response: String) {
        let normalized = response
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: ">", with: " ")
            .uppercased()
        let tokens = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let marker = tokens.firstIndex(of: "412F"), tokens.indices.contains(marker + 1),
              let raw = UInt8(tokens[marker + 1], radix: 16) else {
            log("Fuel-level PID 012F returned no valid 41 2F response; the ECU may not support it.")
            return
        }
        fuelLevelPercentage = Double(raw) * 100.0 / 255.0
        log(String(format: "Fuel level: %.1f%%", fuelLevelPercentage ?? 0))
    }

    private func clearConnection(state: ConnectionState) {
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        commandQueue.removeAll()
        activeCommand = nil
        responseBuffer = ""
        isConnected = false
        connectionState = state
    }

    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        diagnosticLogs.append("[\(timestamp)] \(message)")
        if diagnosticLogs.count > 200 { diagnosticLogs.removeFirst(diagnosticLogs.count - 200) }
    }

    private func centralStateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: return "powered on"
        case .poweredOff: return "powered off"
        case .resetting: return "resetting"
        case .unauthorized: return "unauthorized"
        case .unsupported: return "unsupported"
        case .unknown: return "unknown"
        @unknown default: return "unknown"
        }
    }
}

extension OBDManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            if isScanning { central.stopScan(); isScanning = false }
            if central.state == .poweredOff || central.state == .unauthorized || central.state == .unsupported {
                connectionState = .failed
            }
            log("Bluetooth state changed: \(centralStateDescription(central.state)).")
        } else {
            log("Bluetooth is ready.")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        let advertisedServices = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString)
        let looksLikeOBD = advertisedName.localizedCaseInsensitiveContains("OBD")
            || advertisedName.localizedCaseInsensitiveContains("V-LINK")
            || advertisedName.localizedCaseInsensitiveContains("VLINK")
            || advertisedServices.contains { knownServiceUUIDs.contains($0.uppercased()) }
        guard looksLikeOBD, !discoveredAdapters.contains(where: { $0.identifier == peripheral.identifier }) else { return }
        discoveredAdapters.append(peripheral)
        log("Found adapter: \(advertisedName.isEmpty ? peripheral.identifier.uuidString : advertisedName) (RSSI \(RSSI)).")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        connectionState = .discovering
        log("Connected; discovering services.")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("Could not connect: \(error?.localizedDescription ?? "unknown error").")
        clearConnection(state: .failed)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("Disconnected\(error.map { ": \($0.localizedDescription)" } ?? "").")
        clearConnection(state: .idle)
    }
}

extension OBDManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { log("Service discovery failed: \(error.localizedDescription)"); clearConnection(state: .failed); return }
        guard let services = peripheral.services, !services.isEmpty else {
            log("Adapter exposes no BLE services."); clearConnection(state: .failed); return
        }
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { log("Characteristic discovery failed: \(error.localizedDescription)"); return }
        for characteristic in service.characteristics ?? [] {
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                writeCharacteristic = characteristic
            }
        }
        guard writeCharacteristic != nil, notifyCharacteristic != nil else { return }
        guard commandQueue.isEmpty, activeCommand == nil else { return }
        connectionState = .initializing
        isConnected = true
        commandQueue = ["ATZ", "ATE0", "ATL0", "ATSP0"]
        log("Found BLE read/write characteristics; initializing ELM327.")
        sendNextCommandIfReady()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error { log("Could not enable adapter notifications: \(error.localizedDescription)") }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { log("Read failed: \(error.localizedDescription)"); return }
        guard let data = characteristic.value, let text = String(data: data, encoding: .utf8) else { return }
        responseBuffer += text
        if responseBuffer.contains(">") {
            let completeResponse = responseBuffer
            responseBuffer = ""
            handleResponse(completeResponse)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { log("Write failed: \(error.localizedDescription)") }
    }
}
