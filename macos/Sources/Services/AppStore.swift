import Combine
import Foundation

private let cat = "AppStore"

class AppStore: ObservableObject {

  static let shared = AppStore()

  @Published var pairedDevice: DeviceInfo?
  @Published var transportMethod: String = "wifi"
  @Published var launchAtLogin: Bool = false

  private let defaults = UserDefaults.standard

  init() { load() }

  func load() {
    if let data = defaults.data(forKey: "pairedDevice"),
      let device = try? JSONDecoder().decode(DeviceInfo.self, from: data)
    {
      pairedDevice = device
    }
    transportMethod = defaults.string(forKey: "transportMethod") ?? "wifi"
    launchAtLogin = defaults.bool(forKey: "launchAtLogin")
    FileLogger.debug("Config loaded: transport=\(transportMethod)", category: cat)
  }

  func save() {
    FileLogger.debug("Config saved", category: cat)
    if let device = pairedDevice, let data = try? JSONEncoder().encode(device) {
      defaults.set(data, forKey: "pairedDevice")
    } else {
      defaults.removeObject(forKey: "pairedDevice")
    }
    defaults.set(transportMethod, forKey: "transportMethod")
    defaults.set(launchAtLogin, forKey: "launchAtLogin")
  }
}
