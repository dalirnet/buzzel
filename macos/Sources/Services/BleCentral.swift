import Foundation
import CoreBluetooth
import os.log

private let log = OSLog(subsystem: "com.buzzel", category: "BleCentral")

protocol BleCentralDelegate: AnyObject {
    func bleDidConnect()
    func bleDidDisconnect()
    func bleDidReceiveData(_ data: Data)
}

class BleCentral: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    private static let maxFrameSize = 1_000_000
    private static let reconnectDelay: TimeInterval = 2

    weak var delegate: BleCentralDelegate?

    @Published var discoveredDevices: [DiscoveredDevice] = []

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var configCharacteristic: CBCharacteristic?
    private var smsCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var isDiscoveryMode = false

    // Reassembly buffer for length-prefixed frames
    private var recvBuffer = Data()

    // Write queue — BLE only allows one outstanding write at a time
    private var writeQueue: [Data] = []
    private var isWriting = false
    private var pendingNotifyCount = 0

    private let serviceUUID = CBUUID(string: BleUuids.service)
    private let configUUID = CBUUID(string: BleUuids.configChar)
    private let smsUUID = CBUUID(string: BleUuids.smsChar)
    private let statusUUID = CBUUID(string: BleUuids.statusChar)

    var isConnected: Bool { peripheral?.state == .connected }
    var peripheralName: String? { peripheral?.name }
    var peripheralIdentifier: UUID? { peripheral?.identifier }

    // MARK: - Public API

    func start() {
        os_log("start", log: log, type: .debug)
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        } else if centralManager?.state == .poweredOn {
            centralManager?.scanForPeripherals(withServices: [serviceUUID], options: nil)
        }
    }

    func startDiscovery() {
        isDiscoveryMode = true
        discoveredDevices = []
        centralManager?.stopScan()
        if let p = peripheral {
            centralManager?.cancelPeripheralConnection(p)
            peripheral = nil
            configCharacteristic = nil
            smsCharacteristic = nil
            statusCharacteristic = nil
        }
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        } else if centralManager?.state == .poweredOn {
            centralManager?.scanForPeripherals(
                withServices: [serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        }
    }

    func stopDiscovery() {
        isDiscoveryMode = false
        centralManager?.stopScan()
    }

    func connect(to device: DiscoveredDevice) {
        stopDiscovery()
        self.peripheral = device.peripheral
        device.peripheral.delegate = self
        centralManager?.connect(device.peripheral, options: nil)
    }

    func stop() {
        os_log("stop", log: log, type: .debug)
        isDiscoveryMode = false
        discoveredDevices = []
        centralManager?.stopScan()
        if let p = peripheral {
            centralManager?.cancelPeripheralConnection(p)
        }
        peripheral = nil
    }

    func disconnect() {
        if let p = peripheral {
            centralManager?.cancelPeripheralConnection(p)
        }
    }

    func send(_ data: Data) -> Bool {
        guard peripheral != nil, configCharacteristic != nil else { return false }
        // Frame: 4-byte big-endian length prefix + payload
        var frame = Data(count: 4)
        let length = UInt32(data.count)
        frame[0] = UInt8((length >> 24) & 0xFF)
        frame[1] = UInt8((length >> 16) & 0xFF)
        frame[2] = UInt8((length >> 8) & 0xFF)
        frame[3] = UInt8(length & 0xFF)
        frame.append(data)
        writeQueue.append(frame)
        drainWriteQueue()
        return true
    }

    private func drainWriteQueue() {
        guard !isWriting, let p = peripheral, let char = configCharacteristic else { return }
        guard !writeQueue.isEmpty else { return }
        let frame = writeQueue.removeFirst()
        isWriting = true
        p.writeValue(frame, for: char, type: .withResponse)
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        os_log("centralManagerDidUpdateState: %{public}d", log: log, type: .debug, central.state.rawValue)
        if central.state == .poweredOn {
            if isDiscoveryMode {
                central.scanForPeripherals(
                    withServices: [serviceUUID],
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
                )
            } else {
                central.scanForPeripherals(withServices: [serviceUUID], options: nil)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if isDiscoveryMode {
            let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
                       ?? peripheral.name
                       ?? "Unknown"
            let rssi = RSSI.intValue

            if let idx = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                discoveredDevices[idx].rssi = rssi
                discoveredDevices[idx].name = name
            } else {
                discoveredDevices.append(
                    DiscoveredDevice(id: peripheral.identifier, peripheral: peripheral, name: name, rssi: rssi)
                )
            }
        } else {
            os_log("didDiscover: %{public}@ (%{public}@)", log: log, type: .debug,
                   peripheral.identifier.uuidString, peripheral.name ?? "unnamed")
            self.peripheral = peripheral
            peripheral.delegate = self
            central.stopScan()
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        os_log("didConnect: %{public}@", log: log, type: .debug, peripheral.identifier.uuidString)
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        os_log("didFailToConnect: %{public}@", log: log, type: .error, error?.localizedDescription ?? "unknown")
        resetConnectionState()
        if !isDiscoveryMode {
            scheduleReconnect()
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        os_log("didDisconnect: %{public}@", log: log, type: .debug, error?.localizedDescription ?? "clean")
        resetConnectionState()
        delegate?.bleDidDisconnect()
        if !isDiscoveryMode {
            scheduleReconnect()
        }
    }

    private func resetConnectionState() {
        peripheral = nil
        configCharacteristic = nil
        smsCharacteristic = nil
        statusCharacteristic = nil
        recvBuffer = Data()
        writeQueue.removeAll()
        isWriting = false
    }

    private func scheduleReconnect() {
        os_log("scheduleReconnect", log: log, type: .debug)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reconnectDelay) { [weak self] in
            guard let self = self else { return }
            self.centralManager?.scanForPeripherals(withServices: [self.serviceUUID], options: nil)
        }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        os_log("didDiscoverServices: %{public}d", log: log, type: .debug, peripheral.services?.count ?? 0)
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            os_log("Service not found", log: log, type: .error)
            return
        }
        peripheral.discoverCharacteristics([configUUID, smsUUID, statusUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        os_log("didDiscoverCharacteristics: %{public}d", log: log, type: .debug, service.characteristics?.count ?? 0)
        pendingNotifyCount = 0
        for char in service.characteristics ?? [] {
            switch char.uuid {
            case configUUID:
                configCharacteristic = char
            case smsUUID:
                smsCharacteristic = char
                pendingNotifyCount += 1
                peripheral.setNotifyValue(true, for: char)
            case statusUUID:
                statusCharacteristic = char
                pendingNotifyCount += 1
                peripheral.setNotifyValue(true, for: char)
            default:
                break
            }
        }
        if pendingNotifyCount == 0 {
            delegate?.bleDidConnect()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        pendingNotifyCount -= 1
        if pendingNotifyCount <= 0 {
            pendingNotifyCount = 0
            delegate?.bleDidConnect()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }

        // Append to reassembly buffer
        recvBuffer.append(data)

        // Process complete frames (4-byte big-endian length prefix + payload)
        while recvBuffer.count >= 4 {
            let length = Int(recvBuffer[0]) << 24
                       | Int(recvBuffer[1]) << 16
                       | Int(recvBuffer[2]) << 8
                       | Int(recvBuffer[3])

            guard length > 0, length < Self.maxFrameSize else {
                recvBuffer = Data()
                return
            }

            let totalNeeded = 4 + length
            if recvBuffer.count < totalNeeded {
                break
            }

            let payload = recvBuffer.subdata(in: 4..<totalNeeded)
            recvBuffer = Data(recvBuffer.suffix(from: totalNeeded))
            delegate?.bleDidReceiveData(payload)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        isWriting = false
        drainWriteQueue()
    }
}
