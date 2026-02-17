import AppKit
import Combine

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
        button.image = Self.makeWaveBIcon()
        button.appearsDisabled = true
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
    }

    // MARK: - Click Handling

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            onLeftClick()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let statusTitle: String
        if transportManager.isConnected {
            statusTitle = "Connected"
        } else if store.pairedDevice != nil {
            statusTitle = "Disconnected"
        } else {
            statusTitle = "Not Paired"
        }
        let si = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        si.isEnabled = false
        menu.addItem(si)

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open App", action: #selector(openApp), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Buzzel", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openApp() { onLeftClick() }

    @objc private func quitApp() {
        transportManager.stop()
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
        button.image = Self.makeWaveBIcon()

        switch state {
        case .active:
            button.appearsDisabled = false

        case .connecting, .handshaking:
            button.appearsDisabled = false
            blinkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak button] _ in
                guard let button = button else { return }
                button.appearsDisabled = !button.appearsDisabled
            }

        case .idle:
            button.appearsDisabled = true
        }
    }

    // MARK: - Icon Drawing

    private static func makeWaveBIcon() -> NSImage {
        let size: CGFloat = 24
        let padding: CGFloat = 1
        let drawSize = size - padding * 2
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let path = NSBezierPath()
            let s = drawSize / 512
            let ox = padding
            let oy = padding
            path.move(to: NSPoint(x: ox + 170 * s, y: oy + (512 - 86) * s))
            path.curve(to: NSPoint(x: ox + 150 * s, y: oy + (512 - 150) * s),
                       controlPoint1: NSPoint(x: ox + 140 * s, y: oy + (512 - 86) * s),
                       controlPoint2: NSPoint(x: ox + 130 * s, y: oy + (512 - 120) * s))
            path.curve(to: NSPoint(x: ox + 150 * s, y: oy + (512 - 230) * s),
                       controlPoint1: NSPoint(x: ox + 170 * s, y: oy + (512 - 180) * s),
                       controlPoint2: NSPoint(x: ox + 170 * s, y: oy + (512 - 200) * s))
            path.curve(to: NSPoint(x: ox + 200 * s, y: oy + (512 - 400) * s),
                       controlPoint1: NSPoint(x: ox + 110 * s, y: oy + (512 - 290) * s),
                       controlPoint2: NSPoint(x: ox + 130 * s, y: oy + (512 - 370) * s))
            path.curve(to: NSPoint(x: ox + 380 * s, y: oy + (512 - 320) * s),
                       controlPoint1: NSPoint(x: ox + 270 * s, y: oy + (512 - 430) * s),
                       controlPoint2: NSPoint(x: ox + 370 * s, y: oy + (512 - 400) * s))
            path.curve(to: NSPoint(x: ox + 270 * s, y: oy + (512 - 190) * s),
                       controlPoint1: NSPoint(x: ox + 390 * s, y: oy + (512 - 240) * s),
                       controlPoint2: NSPoint(x: ox + 340 * s, y: oy + (512 - 190) * s))
            path.curve(to: NSPoint(x: ox + 180 * s, y: oy + (512 - 280) * s),
                       controlPoint1: NSPoint(x: ox + 220 * s, y: oy + (512 - 190) * s),
                       controlPoint2: NSPoint(x: ox + 180 * s, y: oy + (512 - 230) * s))
            path.lineWidth = 64 * s
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
