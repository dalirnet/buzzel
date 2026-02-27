import SwiftUI

// MARK: - App Entry

@main
struct BuzzelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var splashFinished = false

    init() {
        Brand.load()
        FileLogger.info("=== App started — log: \(FileLogger.logPath()) ===", category: "BuzzelApp")
    }

    var body: some Scene {
        Window("Buzzel", id: "main") {
            if splashFinished {
                MainView(store: AppStore.shared, transportManager: TransportManager.shared)
            } else {
                SplashView { splashFinished = true }
            }
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

    func applicationDidFinishLaunching(_: Notification) {
        statusBar = StatusBarController(
            store: store,
            transportManager: transportManager,
            onLeftClick: { [weak self] in self?.showMainWindow() }
        )
        configureMainWindow()
    }

    func applicationDidBecomeActive(_: Notification) {
        FileLogger.debug("App became active", category: "AppDelegate")
        transportManager.sendFocus()
    }

    func applicationDidResignActive(_: Notification) {
        FileLogger.debug("App resigned active", category: "AppDelegate")
        transportManager.sendBlur()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        showMainWindow()
        return true
    }

    // MARK: - Window

    private func findMainWindow() -> NSWindow? {
        NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true })
            ?? NSApp.windows.first
    }

    private func configureMainWindow() {
        DispatchQueue.main.async {
            guard let window = self.findMainWindow() else { return }
            window.delegate = self
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
        }
    }

    private func showMainWindow() {
        findMainWindow()?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
