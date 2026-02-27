import AppKit
import Combine
import SwiftUI

class StatusBarController {
    private let store: AppStore
    private let transportManager: TransportManager
    private var cancellable: AnyCancellable?
    private var blinkTimer: Timer?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var onLeftClick: () -> Void

    init(store: AppStore, transportManager: TransportManager, onLeftClick: @escaping () -> Void) {
        self.store = store
        self.transportManager = transportManager
        self.onLeftClick = onLeftClick

        setupButton()
        observeConnectionState()
    }

    // MARK: - Setup

    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.image = Self.makeBuzzelIcon()
        button.appearsDisabled = true
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
    }

    // MARK: - Click Handling

    @objc private func statusItemClicked(_: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        event.type == .rightMouseUp ? showContextMenu() : onLeftClick()
    }

    private var connectionStatusTitle: String {
        if transportManager.isConnected { return "Connected" }
        if store.pairedDevice != nil { return "Disconnected" }
        return "Not Paired"
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let statusMenuItem = NSMenuItem(
            title: connectionStatusTitle, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open App", action: #selector(openApp), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Buzzel", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openApp() {
        onLeftClick()
    }

    @objc private func quitApp() {
        transportManager.disconnect()
        NSApp.terminate(nil)
    }

    // MARK: - Icon State

    private func observeConnectionState() {
        cancellable = transportManager.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.updateIcon(state) }
    }

    private func updateIcon(_ state: TransportManager.ConnectionState) {
        blinkTimer?.invalidate()
        blinkTimer = nil

        guard let button = statusItem.button else { return }
        button.image = Self.makeBuzzelIcon()

        switch state {
        case .active:
            button.appearsDisabled = false

        case .connecting, .handshaking:
            button.appearsDisabled = false
            blinkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
                [weak button] _ in
                guard let button else { return }
                button.appearsDisabled = !button.appearsDisabled
            }

        case .idle:
            button.appearsDisabled = true
        }
    }

    // MARK: - Icon Drawing

    private static func makeBuzzelIcon() -> NSImage {
        let size: CGFloat = 24
        let padding: CGFloat = 4.5
        let drawSize = size - padding * 2
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let scale = drawSize / Brand.logoViewbox
            context.translateBy(x: padding, y: padding)
            context.scaleBy(x: scale, y: scale)
            let cgPath = parseSVGPath(Brand.logoPath).cgPath
            context.addPath(cgPath)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }
}
