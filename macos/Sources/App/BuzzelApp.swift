import SwiftUI
import Combine

// MARK: - App Entry

@main
struct BuzzelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Buzzel", id: "main") {
            MainView(store: AppStore.shared, transportManager: TransportManager.shared)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private let store = AppStore.shared
    private let transportManager = TransportManager.shared

    private var statusBar: StatusBarController!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController(
            store: store,
            transportManager: transportManager,
            onLeftClick: { [weak self] in self?.showMainWindow() }
        )
        configureMainWindow()
        observeBluetoothAuth()

        if store.pairedDevice != nil && transportManager.bleAuthorized {
            transportManager.start()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    // MARK: - Window

    private func configureMainWindow() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true }) ?? NSApp.windows.first else { return }
            window.delegate = self
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
            window.setContentSize(NSSize(width: 320, height: 480))
            window.center()
        }
    }

    private func showMainWindow() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true }) ?? NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    // MARK: - Bluetooth Authorization

    private func observeBluetoothAuth() {
        transportManager.$bleAuthorized
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] authorized in
                guard let self = self, authorized, self.store.pairedDevice != nil else { return }
                if self.transportManager.connectionState == .idle {
                    self.transportManager.start()
                }
            }
            .store(in: &cancellables)
    }
}
