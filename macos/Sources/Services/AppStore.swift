import Foundation
import Combine
import os.log

private let log = OSLog(subsystem: "com.buzzel", category: "AppStore")

class AppStore: ObservableObject {

    static let shared = AppStore()

    @Published var pairedDevice: DeviceInfo?
    @Published var transportMethod: String = "wifi"
    @Published var launchAtLogin: Bool = false

    private let defaults = UserDefaults.standard

    init() { load() }

    func load() {
        if let data = defaults.data(forKey: "pairedDevice"),
           let device = try? JSONDecoder().decode(DeviceInfo.self, from: data) {
            pairedDevice = device
        }
        transportMethod = defaults.string(forKey: "transportMethod") ?? "wifi"
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        os_log("Config loaded: transport=%{public}@", log: log, type: .debug, transportMethod)
    }

    func save() {
        os_log("Config saved", log: log, type: .debug)
        if let device = pairedDevice, let data = try? JSONEncoder().encode(device) {
            defaults.set(data, forKey: "pairedDevice")
        } else {
            defaults.removeObject(forKey: "pairedDevice")
        }
        defaults.set(transportMethod, forKey: "transportMethod")
        defaults.set(launchAtLogin, forKey: "launchAtLogin")
    }
}
