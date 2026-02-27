import CoreBluetooth
import Foundation

enum PowerButtonState: Equatable {
    case restricted
    case unpaired
    case connecting
    case connected
    case disconnected

    static func current(store: AppStore, transportManager: TransportManager) -> PowerButtonState {
        guard CBCentralManager.authorization == .allowedAlways else { return .restricted }
        guard store.pairedDevice != nil else { return .unpaired }

        switch transportManager.connectionState {
        case .active: return .connected
        case .idle: return .disconnected
        default: return .connecting
        }
    }
}
