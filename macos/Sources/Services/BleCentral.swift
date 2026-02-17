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

    private static let reconnectDelay: TimeInterval = 2

    weak var delegate: BleCentralDelegate?

    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var bluetoothAuthorization: CBManagerAuthorization = CBCentralManager.authorization

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var dataCharacteristic: CBCharacteristic?
    private var isDiscoveryMode = false

    // Reassembly buffer for length-prefixed frames
    private var recvBuffer = Data()

    // Write queue — BLE only allows one outstanding write at a time
    private var writeQueue: [Data] = []
    private var isWriting = false

    private let serviceUUID = CBUUID(string: BleUuids.service)
    private let dataUUID = CBUUID(string: BleUuids.dataChar)

    var isConnected: Bool { peripheral?.state == .connected }
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
            dataCharacteristic = nil
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
        os_log("BLE disconnect requested", log: log, type: .debug)
        if let p = peripheral {
            centralManager?.cancelPeripheralConnection(p)
        }
    }

    func requestAccess() {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
    }

    func send(_ data: Data) -> Bool {
        guard peripheral != nil, dataCharacteristic != nil else { return false }
        let frame = FrameCodec.encode(data)
        os_log("BLE send: %d bytes (%d frame bytes)", log: log, type: .debug, data.count, frame.count)
        writeQueue.append(frame)
        drainWriteQueue()
        return true
    }

    private func drainWriteQueue() {
        guard !isWriting, let peripheral = peripheral, let characteristic = dataCharacteristic else { return }
        guard !writeQueue.isEmpty else { return }
        os_log("Draining write queue: %d items", log: log, type: .debug, writeQueue.count)
        let frame = writeQueue.removeFirst()
        isWriting = true
        peripheral.writeValue(frame, for: characteristic, type: .withResponse)
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        os_log("centralManagerDidUpdateState: %{public}d", log: log, type: .debug, central.state.rawValue)
        DispatchQueue.main.async { self.bluetoothAuthorization = CBCentralManager.authorization }
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
        dataCharacteristic = nil
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
        peripheral.discoverCharacteristics([dataUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        os_log("didDiscoverCharacteristics: %{public}d", log: log, type: .debug, service.characteristics?.count ?? 0)
        for char in service.characteristics ?? [] {
            if char.uuid == dataUUID {
                dataCharacteristic = char
                // Subscribe to notifications on data char
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        os_log("Notification state for %{public}@: %{public}@", log: log, type: .debug,
               characteristic.uuid.uuidString, error?.localizedDescription ?? "ok")
        if characteristic.uuid == dataUUID && error == nil {
            delegate?.bleDidConnect()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        os_log("BLE received %d bytes", log: log, type: .debug, data.count)
        recvBuffer.append(data)
        FrameCodec.extractFrames(from: &recvBuffer) { [weak self] payload in
            self?.delegate?.bleDidReceiveData(payload)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            os_log("BLE write error: %{public}@", log: log, type: .error, error.localizedDescription)
        }
        isWriting = false
        drainWriteQueue()
    }
}
