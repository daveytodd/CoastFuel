import Combine
import CoreBluetooth
import Foundation

/// BLE OBD-II client. CoreBluetooth delegate callbacks are delivered on the main queue,
/// which keeps this ObservableObject's UI-facing state on the UI thread without actor isolation.
/// Classic Bluetooth/SPP adapters are not accessible through CoreBluetooth on iOS.
final class OBDManager: NSObject, ObservableObject {
    enum ConnectionState {
        case idle, scanning, connecting, discovering, initializing, ready, failed
    }

    @Published private(set) var isConnected = false
    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var fuelLevelPercentage: Double?
    @Published private(set) var lastFuelReadAt: Date?
    @Published private(set) var discoveredAdapters: [CBPeripheral] = []
    @Published private(set) var diagnosticLogs: [String] = []

    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var responseBuffer = ""
    private var commandQueue: [String] = []
    private var activeCommand: String?
    private var isScanning = false
    private let knownServiceUUIDs: Set<String> = ["FFF0", "18F0"]

    override init() {
        super.init()
        // Delegate callbacks are serialized on the main queue; public methods are called by SwiftUI there.
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
        guard central.state == .poweredOn else {
            log("Bluetooth is not ready (state: \(central.state.rawValue)).")
            return
        }
        discoveredAdapters.removeAll()
        connectionState = .scanning
        isScanning = true
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

    func requestFuelLevel() {
        guard isConnected, writeCharacteristic != nil else { return }
        commandQueue.append("012F")
        sendNextCommandIfReady()
    }

    private func sendNextCommandIfReady() {
        guard activeCommand == nil, !commandQueue.isEmpty,
              let peripheral = connectedPeripheral, let characteristic = writeCharacteristic else { return }
        let command = commandQueue.removeFirst()
        activeCommand = command
        responseBuffer = ""
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(Data((command + "\r").utf8), for: characteristic, type: type)
        log("> \(command)")
    }

    private func handleResponse(_ response: String) {
        let command = activeCommand
        log("< \(response.trimmingCharacters(in: .whitespacesAndNewlines))")
        if command == "012F" { parseFuelLevel(from: response) }
        activeCommand = nil
        sendNextCommandIfReady()
        if command == "ATSP0" {
            connectionState = .ready
            isConnected = true
            log("ELM327 initialization complete.")
        }
    }

    private func parseFuelLevel(from response: String) {
        let normalized = response.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: ">", with: " ").uppercased()
        let tokens = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let marker = tokens.firstIndex(of: "412F"), tokens.indices.contains(marker + 1),
              let raw = UInt8(tokens[marker + 1], radix: 16) else {
            log("Fuel-level PID 012F returned no valid 41 2F response; the ECU may not support it.")
            return
        }
        fuelLevelPercentage = Double(raw) * 100.0 / 255.0
        lastFuelReadAt = Date()
        log(String(format: "Fuel level: %.1f%%", fuelLevelPercentage ?? 0))
    }

    private func clearConnection(state: ConnectionState) {
        connectedPeripheral = nil
        writeCharacteristic = nil
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
}

extension OBDManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { log("Bluetooth is ready.") }
        else {
            if isScanning { central.stopScan(); isScanning = false }
            if central.state == .poweredOff || central.state == .unauthorized || central.state == .unsupported {
                connectionState = .failed
            }
            log("Bluetooth state changed (state: \(central.state.rawValue)).")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map { $0.uuidString.uppercased() }
        let candidate = name.localizedCaseInsensitiveContains("OBD")
            || name.localizedCaseInsensitiveContains("V-LINK")
            || name.localizedCaseInsensitiveContains("VLINK")
            || services.contains { knownServiceUUIDs.contains($0) }
        guard candidate, !discoveredAdapters.contains(where: { $0.identifier == peripheral.identifier }) else { return }
        discoveredAdapters.append(peripheral)
        log("Found adapter: \(name.isEmpty ? peripheral.identifier.uuidString : name) (RSSI \(RSSI)).")
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
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                writeCharacteristic = characteristic
            }
        }
        guard let readable = (peripheral.services ?? []).flatMap({ $0.characteristics ?? [] })
            .first(where: { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }),
              writeCharacteristic != nil, commandQueue.isEmpty, activeCommand == nil else { return }
        _ = readable
        connectionState = .initializing
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
            let response = responseBuffer
            responseBuffer = ""
            handleResponse(response)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { log("Write failed: \(error.localizedDescription)") }
    }
}
