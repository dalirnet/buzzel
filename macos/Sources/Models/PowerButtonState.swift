import CoreBluetooth
import Foundation

enum PowerButtonState: Equatable {
  case noPermission
  case unpaired
  case connecting
  case connected
  case disconnected

  static func current(store: AppStore, transportManager: TransportManager) -> PowerButtonState {
    let bleAuth = CBCentralManager.authorization
    if bleAuth == .notDetermined || bleAuth == .denied {
      return .noPermission
    }

    guard store.pairedDevice != nil else { return .unpaired }

    switch transportManager.connectionState {
    case .active:
      return .connected
    default:
      return transportManager.hasBeenConnected ? .disconnected : .connecting
    }
  }
}
