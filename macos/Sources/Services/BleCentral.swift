import CoreBluetooth
import Foundation

private let logCategory = "BleCentral"

protocol BleCentralDelegate: AnyObject {
    func bleDidStartConnecting()
    func bleDidConnect()
    func bleDidDisconnect()
    func bleDidReceiveData(_ data: Data)
}

class BleCentral: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    weak var delegate: BleCentralDelegate?

    @Published var bluetoothAuthorization: CBManagerAuthorization = CBCentralManager.authorization
    @Published var bluetoothPoweredOff = false

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var dataCharacteristic: CBCharacteristic?
    private var isStopped = false

    private var receiveBuffer = Data()

    private static let defaultMaximumTransmissionUnit = 23
    private var negotiatedMaximumTransmissionUnit = defaultMaximumTransmissionUnit

    private var bluetoothMaximumPayloadSize: Int {
        let maximumFrameSize = BuzzelProtocol.maximumFrameSizeForMaximumTransmissionUnit(
            negotiatedMaximumTransmissionUnit
        )
        return BuzzelProtocol.maximumPayloadSize(maximumFrameSize)
    }

    // Write queue — Bluetooth Low Energy only allows one outstanding write at a time
    private var writeQueue: [Data] = []
    private var isWriting = false

    private let serviceUUID = CBUUID(string: BluetoothServiceUUIDs.service)
    private let dataCharacteristicUUID = CBUUID(string: BluetoothServiceUUIDs.dataCharacteristic)

    var isConnected: Bool {
        peripheral?.state == .connected
    }

    var peripheralIdentifier: UUID? {
        peripheral?.identifier
    }

    var hasQueuedWrites: Bool {
        isWriting || !writeQueue.isEmpty
    }

    // MARK: - Public API

    func start() {
        FileLogger.debug("start", category: logCategory)
        isStopped = false
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        } else if centralManager?.state == .poweredOn {
            centralManager?.scanForPeripherals(withServices: [serviceUUID], options: nil)
        }
    }

    func stop() {
        FileLogger.debug("stop", category: logCategory)
        isStopped = true
        centralManager?.stopScan()
        peripheral.map { centralManager?.cancelPeripheralConnection($0) }
        peripheral = nil
    }

    func requestAccess() {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
    }

    func send(_ data: Data) -> Bool {
        guard peripheral != nil, dataCharacteristic != nil else { return false }
        let frame = FrameCodec.encode(data, maximumPayloadSize: bluetoothMaximumPayloadSize)
        FileLogger.debug(
            "BLE send: \(data.count) bytes (\(frame.count) frame bytes)", category: logCategory
        )
        writeQueue.append(frame)
        drainWriteQueue()
        return true
    }

    private func drainWriteQueue() {
        guard !isWriting, let peripheral = peripheral, let characteristic = dataCharacteristic
        else {
            return
        }

        guard !writeQueue.isEmpty else { return }

        FileLogger.debug("Draining write queue: \(writeQueue.count) items", category: logCategory)
        let frame = writeQueue.removeFirst()
        isWriting = true
        peripheral.writeValue(frame, for: characteristic, type: .withResponse)
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        FileLogger.debug(
            "centralManagerDidUpdateState: \(central.state.rawValue)", category: logCategory
        )
        DispatchQueue.main.async {
            self.bluetoothAuthorization = CBCentralManager.authorization
            self.bluetoothPoweredOff = central.state == .poweredOff
        }
        if central.state == .poweredOn, !isStopped {
            central.scanForPeripherals(withServices: [serviceUUID], options: nil)
        }
    }

    func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData _: [String: Any], rssi _: NSNumber
    ) {
        FileLogger.debug(
            "didDiscover: \(peripheral.identifier.uuidString) (\(peripheral.name ?? "unnamed"))",
            category: logCategory
        )
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        delegate?.bleDidStartConnecting()
        central.connect(peripheral, options: nil)
    }

    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        FileLogger.debug("didConnect: \(peripheral.identifier.uuidString)", category: logCategory)
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(
        _: CBCentralManager, didFailToConnect _: CBPeripheral, error: Error?
    ) {
        FileLogger.error(
            "didFailToConnect: \(error?.localizedDescription ?? "unknown") (stopped=\(isStopped))",
            category: logCategory
        )
        resetConnectionState()
        guard !isStopped else { return }
        delegate?.bleDidDisconnect()
    }

    func centralManager(
        _: CBCentralManager, didDisconnectPeripheral _: CBPeripheral, error: Error?
    ) {
        FileLogger.debug(
            "didDisconnect: \(error?.localizedDescription ?? "clean") (stopped=\(isStopped))",
            category: logCategory
        )
        resetConnectionState()
        guard !isStopped else { return }
        delegate?.bleDidDisconnect()
    }

    private func resetConnectionState() {
        peripheral = nil
        dataCharacteristic = nil
        receiveBuffer = Data()
        negotiatedMaximumTransmissionUnit = Self.defaultMaximumTransmissionUnit
        writeQueue.removeAll()
        isWriting = false
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices _: Error?) {
        FileLogger.debug(
            "didDiscoverServices: \(peripheral.services?.count ?? 0)", category: logCategory
        )
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            FileLogger.error("Service not found", category: logCategory)
            return
        }
        peripheral.discoverCharacteristics([dataCharacteristicUUID], for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
        error _: Error?
    ) {
        FileLogger.debug(
            "didDiscoverCharacteristics: \(service.characteristics?.count ?? 0)",
            category: logCategory
        )
        guard
            let characteristic = service.characteristics?.first(where: {
                $0.uuid == dataCharacteristicUUID
            })
        else { return }

        dataCharacteristic = characteristic
        let writePayloadSize = peripheral.maximumWriteValueLength(for: .withResponse)
        negotiatedMaximumTransmissionUnit =
            writePayloadSize + BuzzelProtocol.attributeProtocolOverhead
        FileLogger.debug(
            "BLE negotiated MTU: \(negotiatedMaximumTransmissionUnit) (write payload: \(writePayloadSize))",
            category: logCategory
        )
        peripheral.setNotifyValue(true, for: characteristic)
    }

    func peripheral(
        _: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        FileLogger.debug(
            "Notification state for \(characteristic.uuid): \(error?.localizedDescription ?? "ok")",
            category: logCategory
        )
        if characteristic.uuid == dataCharacteristicUUID, error == nil {
            delegate?.bleDidConnect()
        }
    }

    func peripheral(
        _: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error _: Error?
    ) {
        guard let data = characteristic.value else { return }
        FileLogger.debug("BLE received \(data.count) bytes", category: logCategory)
        receiveBuffer.append(data)
        FrameCodec.extractFrames(
            from: &receiveBuffer, maximumPayloadSize: bluetoothMaximumPayloadSize
        ) { [weak self] payload in
            self?.delegate?.bleDidReceiveData(payload)
        }
    }

    func peripheral(
        _: CBPeripheral, didWriteValueFor _: CBCharacteristic, error: Error?
    ) {
        if let error {
            FileLogger.error("BLE write error: \(error.localizedDescription)", category: logCategory)
        }
        isWriting = false
        drainWriteQueue()
    }
}
