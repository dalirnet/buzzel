import CoreBluetooth
import Foundation

private let cat = "BleCentral"

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
  @Published var bluetoothPoweredOff = false

  private var centralManager: CBCentralManager?
  private var peripheral: CBPeripheral?
  private var dataCharacteristic: CBCharacteristic?
  private var isDiscoveryMode = false
  private var isStopped = false
  private var reconnectWork: DispatchWorkItem?

  // Reassembly buffer for length-prefixed frames
  private var recvBuffer = Data()

  // MTU-based frame limit
  private var negotiatedMtu = 23  // BLE default

  private var bleMaxPayload: Int {
    BuzzelProtocol.maxPayload(BuzzelProtocol.maxFrameForMtu(negotiatedMtu))
  }

  // Write queue — BLE only allows one outstanding write at a time
  private var writeQueue: [Data] = []
  private var isWriting = false

  private let serviceUUID = CBUUID(string: BleUuids.service)
  private let dataUUID = CBUUID(string: BleUuids.dataChar)

  var isConnected: Bool { peripheral?.state == .connected }
  var peripheralIdentifier: UUID? { peripheral?.identifier }

  // MARK: - Public API

  func start() {
    FileLogger.debug("start", category: cat)
    reconnectWork?.cancel()
    reconnectWork = nil
    isStopped = false
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
    FileLogger.debug("stop", category: cat)
    reconnectWork?.cancel()
    reconnectWork = nil
    isStopped = true
    isDiscoveryMode = false
    discoveredDevices = []
    centralManager?.stopScan()
    if let p = peripheral {
      centralManager?.cancelPeripheralConnection(p)
    }
    peripheral = nil
  }

  func disconnect() {
    FileLogger.debug("BLE disconnect requested", category: cat)
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
    let frame = FrameCodec.encode(data, maxPayload: bleMaxPayload)
    FileLogger.debug("BLE send: \(data.count) bytes (\(frame.count) frame bytes)", category: cat)
    writeQueue.append(frame)
    drainWriteQueue()
    return true
  }

  private func drainWriteQueue() {
    guard !isWriting, let peripheral = peripheral, let characteristic = dataCharacteristic else {
      return
    }
    guard !writeQueue.isEmpty else { return }
    FileLogger.debug("Draining write queue: \(writeQueue.count) items", category: cat)
    let frame = writeQueue.removeFirst()
    isWriting = true
    peripheral.writeValue(frame, for: characteristic, type: .withResponse)
  }

  // MARK: - CBCentralManagerDelegate

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    FileLogger.debug("centralManagerDidUpdateState: \(central.state.rawValue)", category: cat)
    DispatchQueue.main.async {
      self.bluetoothAuthorization = CBCentralManager.authorization
      self.bluetoothPoweredOff = central.state == .poweredOff
    }
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

  func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber
  ) {
    if isDiscoveryMode {
      let name =
        advertisementData[CBAdvertisementDataLocalNameKey] as? String
        ?? peripheral.name
        ?? "Unknown"
      let rssi = RSSI.intValue

      if let idx = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
        discoveredDevices[idx].rssi = rssi
        discoveredDevices[idx].name = name
      } else {
        discoveredDevices.append(
          DiscoveredDevice(
            id: peripheral.identifier, peripheral: peripheral, name: name, rssi: rssi)
        )
      }
    } else {
      FileLogger.debug(
        "didDiscover: \(peripheral.identifier.uuidString) (\(peripheral.name ?? "unnamed"))",
        category: cat)
      self.peripheral = peripheral
      peripheral.delegate = self
      central.stopScan()
      central.connect(peripheral, options: nil)
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    FileLogger.debug("didConnect: \(peripheral.identifier.uuidString)", category: cat)
    peripheral.delegate = self
    peripheral.discoverServices([serviceUUID])
  }

  func centralManager(
    _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
  ) {
    FileLogger.error(
      "didFailToConnect: \(error?.localizedDescription ?? "unknown") (stopped=\(isStopped))",
      category: cat)
    resetConnectionState()
    if isStopped { return }
    if !isDiscoveryMode {
      scheduleReconnect()
    }
  }

  func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
  ) {
    FileLogger.debug(
      "didDisconnect: \(error?.localizedDescription ?? "clean") (stopped=\(isStopped))",
      category: cat)
    resetConnectionState()
    if isStopped { return }
    delegate?.bleDidDisconnect()
    if !isDiscoveryMode {
      scheduleReconnect()
    }
  }

  private func resetConnectionState() {
    peripheral = nil
    dataCharacteristic = nil
    recvBuffer = Data()
    negotiatedMtu = 23
    writeQueue.removeAll()
    isWriting = false
  }

  private func scheduleReconnect() {
    FileLogger.debug("scheduleReconnect", category: cat)
    reconnectWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self = self, !self.isStopped else { return }
      self.centralManager?.scanForPeripherals(withServices: [self.serviceUUID], options: nil)
    }
    reconnectWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.reconnectDelay, execute: work)
  }

  // MARK: - CBPeripheralDelegate

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    FileLogger.debug(
      "didDiscoverServices: \(peripheral.services?.count ?? 0)", category: cat)
    guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
      FileLogger.error("Service not found", category: cat)
      return
    }
    peripheral.discoverCharacteristics([dataUUID], for: service)
  }

  func peripheral(
    _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
  ) {
    FileLogger.debug(
      "didDiscoverCharacteristics: \(service.characteristics?.count ?? 0)", category: cat)
    for char in service.characteristics ?? [] {
      if char.uuid == dataUUID {
        dataCharacteristic = char
        let mtuPayload = peripheral.maximumWriteValueLength(for: .withResponse)
        negotiatedMtu = mtuPayload + BuzzelProtocol.attOverhead
        FileLogger.debug(
          "BLE negotiated MTU: \(negotiatedMtu) (write payload: \(mtuPayload))", category: cat)
        peripheral.setNotifyValue(true, for: char)
      }
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    FileLogger.debug(
      "Notification state for \(characteristic.uuid): \(error?.localizedDescription ?? "ok")",
      category: cat)
    if characteristic.uuid == dataUUID && error == nil {
      delegate?.bleDidConnect()
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    guard let data = characteristic.value else { return }
    FileLogger.debug("BLE received \(data.count) bytes", category: cat)
    recvBuffer.append(data)
    FrameCodec.extractFrames(from: &recvBuffer, maxPayload: bleMaxPayload) { [weak self] payload in
      self?.delegate?.bleDidReceiveData(payload)
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    if let error = error {
      FileLogger.error("BLE write error: \(error.localizedDescription)", category: cat)
    }
    isWriting = false
    drainWriteQueue()
  }
}
