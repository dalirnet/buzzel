import SwiftUI

// MARK: - App Entry

@main
struct BuzzelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var store = AppStore.shared
    @ObservedObject private var transportManager = TransportManager.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store, transportManager: transportManager)
        } label: {
            Image(systemName: transportManager.isConnected
                ? "antenna.radiowaves.left.and.right"
                : "antenna.radiowaves.left.and.right.slash")
        }

        Window("Settings", id: "settings") {
            SettingsView(store: store, transportManager: transportManager)
                .frame(width: 312, height: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Window("Pair", id: "pair") {
            PairingView(store: store, transportManager: transportManager)
                .frame(width: 312, height: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Window("Activity", id: "activity") {
            ActivityLogView(transportManager: transportManager)
                .frame(width: 312, height: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {

    private let store = AppStore.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        for window in NSApp.windows {
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }

        let nm = BuzzelNotificationManager.shared
        nm.requestPermission()

        let tm = TransportManager.shared
        tm.onSmsReceived = { sms in
            nm.showSms(sender: sms.sender, contactName: sms.contactName, body: sms.body)
        }
        tm.onQueueFlushed = { messages in
            for sms in messages {
                nm.showSms(sender: sms.sender, contactName: sms.contactName, body: sms.body)
            }
        }
        tm.onDeviceReady = { [weak self] in
            guard let store = self?.store else { return }
            tm.syncConfig(store: store)
        }

        if store.pairedDevice != nil {
            tm.start()
        }
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var transportManager: TransportManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        deviceItem

        Divider()

        Button("Activity Log...") {
            openWindow(id: "activity")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Settings...") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit") {
            transportManager.sendGoodbye()
            NSApp.terminate(nil)
        }
    }

    @ViewBuilder
    private var deviceItem: some View {
        if let device = store.pairedDevice {
            if transportManager.isConnected {
                Button {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text(device.name)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text(device.name)
                            .foregroundColor(.secondary)
                    }
                    Text("Reconnecting...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 14)
                }
                .padding(.horizontal, 4)
            }
        } else {
            Button("Pair Device...") {
                openWindow(id: "pair")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
