import SwiftUI

private enum SettingsTab: String, CaseIterable {
    case general
    case filters
    case device

    var title: String {
        switch self {
        case .general: return "General"
        case .filters: return "Filters"
        case .device: return "Device"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var transportManager: TransportManager
    @State private var activeTab: SettingsTab = .general

    var body: some View {
        ViewLayout {
            HeaderTitle(icon: "gearshape", title: "Settings")
        } headerRight: {
            HStack(spacing: 2) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            activeTab = tab
                        }
                    } label: {
                        Text(tab.title)
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(activeTab == tab ? Color.primary.opacity(0.08) : .clear)
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(activeTab == tab ? .primary : .tertiary)
                }
            }
        } content: {
            switch activeTab {
            case .general:
                GeneralSettingsContent(store: store, transportManager: transportManager)
            case .filters:
                FiltersView(store: store, transportManager: transportManager)
            case .device:
                DeviceView(store: store, transportManager: transportManager)
            }
        }
    }
}

// MARK: - General

struct GeneralSettingsContent: View {
    @ObservedObject var store: AppStore
    @ObservedObject var transportManager: TransportManager

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Text("Transport")
                        .font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $store.transportMethod) {
                        Text("Auto").tag("auto")
                        Text("BLE").tag("ble")
                        Text("WiFi").tag("wifi")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    .onChange(of: store.transportMethod) { _ in
                        store.save()
                        syncConfig()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider()
                    .padding(.horizontal, 12)

                HStack {
                    Text("Launch at Login")
                        .font(.system(size: 13))
                    Spacer()
                    Toggle("", isOn: $store.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: store.launchAtLogin) { _ in store.save() }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func syncConfig() {
        transportManager.syncConfig(store: store)
    }
}
