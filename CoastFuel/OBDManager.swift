import Combine
import CoreBluetooth
import Foundation

/// BLE OBD-II client. Adapter BLE availability is distinct from active ECU/engine status.
final class OBDManager: NSObject, ObservableObject {
    enum ConnectionState { case idle, scanning, connecting, discovering, initializing, ready, failed }

    @Published private(set) var isConnected = false
    @Published private(set) var isVehicleRunning = false
    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var fuelLevelPercentage: Double?
    @Published private(set) var estimatedRangeKm: Double?
    @Published private(set) var lastFuelReadAt: Date?
    @Published private(set) var discoveredAdapters: [CBPeripheral] = []
    @Published private(set) var diagnosticLogs: [String] = []

    private let savedPeripheralKey = "CoastFuel.savedOBDPeripheralUUID"
    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var readCharacteristic: CBCharacteristic?
    private var responseBuffer = ""
    private var commandQueue: [String] = []
    private var activeCommand: String?
    private var isScanning = false
    private var reconnectAttemptScheduled = false
    private let knownServiceUUIDs: Set<String> = ["FFF0", "18F0"]
    private let tankCapacityLitres = 51.0
    private let consumptionLitresPer100Km = 7.0

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
        guard central.state == .poweredOn else { log("Bluetooth is not ready."); return }
        discoveredAdapters.removeAll()
        connectionState = .scanning
        isScanning = true
        // Scan without a service filter: many BLE adapters advertise proprietary,
        // changing, or no service UUIDs. Candidate selection happens in didDiscover.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        log("Scanning for nearby OBD-II adapters…")
    }

    func stopScanning() {
        guard isScanning else { return }
        central.stopScan(); isScanning = false
        if connectionState == .scanning { connectionState = .idle }
    }

    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let peripheral = connectedPeripheral { central.cancelPeripheralConnection(peripheral) }
        clearConnection(state: .idle)
    }

    func requestFuelLevel() {
        guard isConnected, isVehicleRunning else { return }
        commandQueue.append("012F")
        sendNextCommandIfReady()
    }

    private func sendNextCommandIfReady() {
        guard activeCommand == nil, !commandQueue.isEmpty,
              let peripheral = connectedPeripheral, let characteristic = writeCharacteristic else { return }
        let command = commandQueue.removeFirst()
        activeCommand = command; responseBuffer = ""
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(Data((command + "\r").utf8), for: characteristic, type: type)
        log("> \(command)")
    }

    private func handleResponse(_ response: String) {
        let command = activeCommand
        let normalized = response.uppercased()
        log("< \(response.trimmingCharacters(in: .whitespacesAndNewlines))")
        if command == "010C" {
            let tokens = normalized.replacingOccurrences(of: ">", with: " ").split(whereSeparator: { $0.isWhitespace })
            if let marker = tokens.firstIndex(of: "410C"), tokens.indices.contains(marker + 2),
               let a = UInt8(tokens[marker + 1], radix: 16), let b = UInt8(tokens[marker + 2], radix: 16) {
                isVehicleRunning = (Double(a) * 256 + Double(b)) / 4.0 > 0
            } else { isVehicleRunning = false }
        }
        if command == "012F" { parseFuelLevel(from: response) }
        activeCommand = nil
        if command == "ATSP0" {
            connectionState = .ready
            isConnected = true
            UserDefaults.standard.set(connectedPeripheral?.identifier.uuidString, forKey: savedPeripheralKey)
            commandQueue.append("010C")
        }
        sendNextCommandIfReady()
    }

    private func parseFuelLevel(from response: String) {
        let tokens = response.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: ">", with: " ").uppercased().split(whereSeparator: { $0.isWhitespace })
        guard let marker = tokens.firstIndex(of: "412F"), tokens.indices.contains(marker + 1), let raw = UInt8(tokens[marker + 1], radix: 16) else { log("PID 012F unavailable."); return }
        let percentage = Double(raw) * 100 / 255
        fuelLevelPercentage = percentage
        estimatedRangeKm = (tankCapacityLitres * percentage / 100) / consumptionLitresPer100Km * 100
        lastFuelReadAt = Date()
    }

    private func clearConnection(state: ConnectionState) {
        connectedPeripheral = nil; writeCharacteristic = nil; readCharacteristic = nil
        commandQueue.removeAll(); activeCommand = nil; responseBuffer = ""
        isConnected = false; isVehicleRunning = false; connectionState = state
    }

    private func scheduleReconnect() {
        guard !reconnectAttemptScheduled, let id = UserDefaults.standard.string(forKey: savedPeripheralKey), let uuid = UUID(uuidString: id) else { return }
        reconnectAttemptScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self else { return }
            self.reconnectAttemptScheduled = false
            guard self.central.state == .poweredOn, !self.isConnected else { return }
            let peripherals = self.central.retrievePeripherals(withIdentifiers: [uuid])
            if let peripheral = peripherals.first { self.connect(to: peripheral) }
            else { self.startScanning() }
        }
    }

    private func log(_ message: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        diagnosticLogs.append("[\(stamp)] \(message)")
        if diagnosticLogs.count > 200 { diagnosticLogs.removeFirst(diagnosticLogs.count - 200) }
    }
}

extension OBDManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { scheduleReconnect() }
        else if central.state == .poweredOff || central.state == .unauthorized || central.state == .unsupported { connectionState = .failed; isConnected = false; isVehicleRunning = false }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = (advertisedName ?? peripheral.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = name.uppercased()
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map { $0.uuidString.uppercased() }
        let namePatterns = ["OBD", "VEEPEAK", "V-LINK", "VLINK", "VIECAR", "KONNWEI", "ELM327", "OBDCHECK", "IOS-VLINK"]
        let isCandidate = namePatterns.contains(where: { normalizedName.contains($0) }) || services.contains { knownServiceUUIDs.contains($0) }

        // If a device has no recognizable name or advertised service, retain it
        // in the scan results too, so adapters with opaque BLE names aren't hidden.
        if !isCandidate && !name.isEmpty { return }
        if !discoveredAdapters.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredAdapters.append(peripheral)
            log("Found BLE device: \(name.isEmpty ? "Unnamed device" : name) (RSSI \(RSSI))")
        }
        if let saved = UserDefaults.standard.string(forKey: savedPeripheralKey), saved == peripheral.identifier.uuidString { connect(to: peripheral) }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral; peripheral.delegate = self; connectionState = .discovering
        peripheral.discoverServices(nil)
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("Connection failed: \(error?.localizedDescription ?? "unknown error")")
        clearConnection(state: .failed); scheduleReconnect()
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("Disconnected; waiting for adapter/vehicle to become available.")
        clearConnection(state: .idle); scheduleReconnect()
    }
}

extension OBDManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services, !services.isEmpty else { clearConnection(state: .failed); scheduleReconnect(); return }
        services.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { return }
        for characteristic in service.characteristics ?? [] {
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) { readCharacteristic = characteristic; peripheral.setNotifyValue(true, for: characteristic) }
            if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) { writeCharacteristic = characteristic }
        }
        guard readCharacteristic != nil, writeCharacteristic != nil, commandQueue.isEmpty, activeCommand == nil else { return }
        connectionState = .initializing; commandQueue = ["ATZ", "ATE0", "ATL0", "ATSP0"]; sendNextCommandIfReady()
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) { if let error { log("Notify setup failed: \(error.localizedDescription)") } }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, let text = String(data: data, encoding: .utf8) else { return }
        responseBuffer += text
        if responseBuffer.contains(">") { let response = responseBuffer; responseBuffer = ""; handleResponse(response) }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) { if let error { log("Write failed: \(error.localizedDescription)") } }
}
