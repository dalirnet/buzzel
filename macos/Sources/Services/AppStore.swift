import Foundation
import Combine

class AppStore: ObservableObject {

    static let shared = AppStore()

    @Published var pairedDevice: DeviceInfo?
    @Published var filters: [FilterRule] = []
    @Published var transportMethod: String = "auto"
    @Published var wifiHost: String = ""
    @Published var wifiPort: Int = 9876
    @Published var launchAtLogin: Bool = false

    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    func load() {
        // Paired device
        if let data = defaults.data(forKey: "pairedDevice"),
           let device = try? JSONDecoder().decode(DeviceInfo.self, from: data) {
            pairedDevice = device
        }

        // Filters
        if let data = defaults.data(forKey: "filters"),
           let decoded = try? JSONDecoder().decode([FilterRule].self, from: data) {
            filters = decoded
        }

        transportMethod = defaults.string(forKey: "transportMethod") ?? "auto"
        wifiHost = defaults.string(forKey: "wifiHost") ?? ""
        wifiPort = defaults.integer(forKey: "wifiPort").nonZero ?? 9876
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
    }

    func save() {
        if let device = pairedDevice, let data = try? JSONEncoder().encode(device) {
            defaults.set(data, forKey: "pairedDevice")
        } else {
            defaults.removeObject(forKey: "pairedDevice")
        }

        if let data = try? JSONEncoder().encode(filters) {
            defaults.set(data, forKey: "filters")
        }

        defaults.set(transportMethod, forKey: "transportMethod")
        defaults.set(wifiHost, forKey: "wifiHost")
        defaults.set(wifiPort, forKey: "wifiPort")
        defaults.set(launchAtLogin, forKey: "launchAtLogin")
    }

    func addFilter(_ filter: FilterRule) {
        filters.append(filter)
        save()
    }

    func removeFilter(at index: Int) {
        guard filters.indices.contains(index) else { return }
        filters.remove(at: index)
        save()
    }

    func addPreset(_ preset: FilterPreset) {
        filters.append(contentsOf: preset.filters)
        save()
    }

    func unpair() {
        pairedDevice = nil
        save()
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
