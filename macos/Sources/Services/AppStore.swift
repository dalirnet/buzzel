import Combine
import Foundation

private let logCategory = "AppStore"

class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var pairedDevice: DeviceInfo?
    @Published var transportMethod: String = "auto"
    @Published var launchAtLogin: Bool = false

    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    func load() {
        pairedDevice = defaults.data(forKey: "pairedDevice")
            .flatMap { try? JSONDecoder().decode(DeviceInfo.self, from: $0) }
        transportMethod = defaults.string(forKey: "transportMethod") ?? "auto"
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        FileLogger.debug("Config loaded: transport=\(transportMethod)", category: logCategory)
    }

    func save() {
        FileLogger.debug("Config saved", category: logCategory)
        if let device = pairedDevice, let data = try? JSONEncoder().encode(device) {
            defaults.set(data, forKey: "pairedDevice")
        } else {
            defaults.removeObject(forKey: "pairedDevice")
        }
        defaults.set(transportMethod, forKey: "transportMethod")
        defaults.set(launchAtLogin, forKey: "launchAtLogin")
    }
}
