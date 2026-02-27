import SwiftUI

// MARK: - Main View

struct MainView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var transportManager: TransportManager

    @State private var showQRCode = false
    @State private var showActivityLog = false
    @State private var showSettings = false
    @State private var qrCodeMatrix: [[Bool]]?
    @State private var pairingCode = ""
    @State private var sessionIdentifier = ""
    @State private var displayedStatusText = ""
    @State private var statusFlipAngle: Double = 0
    @State private var statusOverride: String?
    private var powerState: PowerButtonState {
        PowerButtonState.current(store: store, transportManager: transportManager)
    }

    private var isSubView: Bool {
        showQRCode || showActivityLog || showSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(height: 48)

            if showActivityLog {
                ActivityLogView(transportManager: transportManager)
            } else if showSettings {
                SettingsView(store: store)
            } else {
                mainPanel
            }
        }
        .frame(width: 360, height: 640)
        .background(DesignColor.surface)
        .onChange(of: powerState) { state in
            if state == .connected && showQRCode {
                closeQRCode()
            }
        }
    }

    // MARK: - Header

    private var headerTitle: String {
        if showActivityLog { return "Activity Log" }
        if showSettings { return "Settings" }
        if showQRCode { return "Quick Setup" }
        return "Buzzel"
    }

    private var header: some View {
        HStack(spacing: 8) {
            if isSubView {
                Button {
                    if showActivityLog {
                        withAnimation(.easeInOut(duration: 0.2)) { showActivityLog = false }
                    } else if showSettings {
                        withAnimation(.easeInOut(duration: 0.2)) { showSettings = false }
                    } else {
                        closeQRCode()
                    }
                } label: {
                    AppHeaderLabel(title: headerTitle)
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .help("Back")
            } else {
                AppHeaderLabel(title: headerTitle)
            }

            Spacer()

            if showActivityLog {
                Button {
                    transportManager.logEntries.removeAll()
                } label: {
                    SVGIconView(
                        paths: Self.iconClear,
                        size: 20,
                        color: DesignColor.text,
                        mode: .fill
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .help("Clear logs")
            } else if !isSubView {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showSettings = true }
                } label: {
                    SVGIconView(
                        paths: Self.iconSettings,
                        size: 20,
                        color: DesignColor.text,
                        mode: .fill
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .help("Settings")
            }
        }
    }

    // MARK: - Main Panel

    private var mainPanel: some View {
        VStack(spacing: 0) {
            Spacer()

            OrbitRingsView(
                deviceName: store.pairedDevice?.name,
                isConnected: powerState == .connected,
                isRemoteFocused: transportManager.remoteInFocus
            ) {
                AnimatedSwitcher(key: showQRCode) { isShowingQRCode in
                    if isShowingQRCode {
                        qrCodeContent
                    } else {
                        PowerButtonView(
                            state: powerState,
                            ready: powerState == .disconnected
                                && !transportManager.hasBeenConnected,
                            onTap: { onPowerButtonTap() },
                            onUnpairWarning: { onPowerButtonHoldWarning() },
                            onUnpair: { onPowerButtonUnpair() },
                            onHoldCancel: { onPowerButtonHoldCancel() }
                        )
                        .frame(width: 94, height: 94)
                    }
                }
                .frame(width: showQRCode ? 150 : 126, height: showQRCode ? 150 : 126)
            }

            Spacer()

            statusLine
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
    }

    // MARK: - QR Code Content

    @ViewBuilder
    private var qrCodeContent: some View {
        if let matrix = qrCodeMatrix {
            CircularQRCodeView(matrix: matrix, size: 150)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 24))
                    .foregroundColor(DesignColor.secondary)
                Text("No network")
                    .font(Brand.font(size: 12))
                    .foregroundColor(DesignColor.secondary)
            }
        }
    }

    // MARK: - Status Line

    private var statusText: String {
        if let override = statusOverride {
            return override
        }
        if showQRCode {
            if let error = transportManager.pairingError {
                return error
            } else if transportManager.isPairing {
                return "Waiting for device to connect"
            } else {
                return "Scan QR code with Android"
            }
        }
        switch powerState {
        case .restricted:
            return "Bluetooth access is required"

        case .unpaired:
            return "No device paired"

        case .connecting:
            let via = transportManager.connectingTransport
            return via.isEmpty ? "Searching for device" : "Searching via \(via)"

        case .connected:
            let via = transportManager.activeTransport
            return via.isEmpty ? "Connected" : "Connected via \(via)"

        case .disconnected:
            return transportManager.hasBeenConnected ? "Connection lost" : "Ready to connect"
        }
    }

    private var statusLine: some View {
        Text(displayedStatusText)
            .font(Brand.font(size: 12))
            .foregroundColor(DesignColor.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(DesignColor.secondary.opacity(0.05))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .rotation3DEffect(.degrees(statusFlipAngle), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { showActivityLog = true }
            }
            .onAppear { displayedStatusText = statusText }
            .onChange(of: statusText) { newText in
                guard newText != displayedStatusText else { return }
                animateStatusFlip(to: newText)
            }
    }

    private func animateStatusFlip(to newText: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            statusFlipAngle = 90
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            displayedStatusText = newText
            statusFlipAngle = -90
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                statusFlipAngle = 0
            }
        }
    }

    // MARK: - Actions

    private func openQRCode() {
        generateQRCode()
        transportManager.onPairingComplete = { name in
            store.pairedDevice = DeviceInfo(
                name: name,
                address: store.transportMethod,
                peripheralIdentifier: transportManager.ble.peripheralIdentifier?.uuidString
            )
            store.save()
            closeQRCode()
        }
        transportManager.startPairingMode(sessionIdentifier: sessionIdentifier, code: pairingCode)
        showQRCode = true
    }

    private func closeQRCode() {
        showQRCode = false
        transportManager.stopPairingMode()
        transportManager.onPairingComplete = nil
    }

    private func onPowerButtonHoldWarning() {
        switch powerState {
        case .connecting, .connected, .disconnected:
            overrideStatusText("Keep pressing to unpair")
        default:
            break
        }
    }

    private func onPowerButtonUnpair() {
        switch powerState {
        case .connecting, .connected, .disconnected:
            statusOverride = nil
            transportManager.stop()
        default:
            break
        }
    }

    private func onPowerButtonHoldCancel() {
        overrideStatusText(nil)
    }

    private func overrideStatusText(_ text: String?) {
        statusOverride = text
    }

    private func onPowerButtonTap() {
        switch powerState {
        case .restricted:
            transportManager.ble.requestAccess()
        case .unpaired:
            openQRCode()
        case .connecting:
            transportManager.disconnect()
        case .connected:
            transportManager.disconnect()
        case .disconnected:
            transportManager.start()
        }
    }

    private func generateQRCode() {
        guard
            let result = QRGenerator.generateQRCodePayload(
                preferredTransport: store.transportMethod
            )
        else {
            qrCodeMatrix = nil
            return
        }
        sessionIdentifier = BuzzelProtocol.deriveSessionIdentifier(result.seed)
        pairingCode = BuzzelProtocol.derivePairingCode(result.seed)
        qrCodeMatrix = QRGenerator.generateQRCodeMatrix(from: result.payload)
    }

    // MARK: - Icon Path Data

    static let iconClear: [[String]] = [
        [
            "M12.752,1.25 L12.816,1.25 C13.309,1.25 13.727,1.25 14.075,1.281 C14.444,1.314 14.788,1.386 15.122,1.559 C15.254,1.628 15.381,1.707 15.5,1.796 C15.802,2.021 16.016,2.299 16.207,2.617 C16.386,2.916 16.569,3.293 16.784,3.736 L16.784,3.736 L17.275,4.75 L21.75,4.75 C22.164,4.75 22.5,5.086 22.5,5.5 C22.5,5.914 22.164,6.25 21.75,6.25 L20.955,6.25 L20.376,15.61 C20.299,16.858 20.238,17.848 20.113,18.639 C19.984,19.45 19.778,20.126 19.366,20.717 C18.989,21.257 18.504,21.714 17.941,22.056 C17.326,22.431 16.639,22.595 15.821,22.674 C15.024,22.75 14.032,22.75 12.782,22.75 L12.704,22.75 C11.452,22.75 10.459,22.75 9.66,22.673 C8.842,22.595 8.154,22.431 7.539,22.055 C6.975,21.712 6.49,21.255 6.113,20.713 C5.701,20.121 5.496,19.445 5.368,18.632 C5.244,17.84 5.184,16.849 5.108,15.599 L4.544,6.25 L3.75,6.25 C3.336,6.25 3,5.914 3,5.5 C3,5.086 3.336,4.75 3.75,4.75 L8.32,4.75 L8.739,3.831 L8.739,3.831 C8.949,3.371 9.127,2.981 9.304,2.671 C9.492,2.342 9.705,2.052 10.011,1.818 C10.131,1.726 10.259,1.643 10.393,1.572 C10.733,1.391 11.085,1.317 11.462,1.282 C11.818,1.25 12.246,1.25 12.751,1.25 L12.752,1.25 Z M6.603,15.47 C6.682,16.767 6.738,17.687 6.85,18.399 C6.96,19.1 7.114,19.526 7.344,19.856 C7.602,20.227 7.934,20.54 8.32,20.775 C8.663,20.984 9.098,21.113 9.804,21.18 C10.522,21.249 11.443,21.25 12.743,21.25 C14.04,21.25 14.961,21.249 15.678,21.18 C16.383,21.113 16.817,20.985 17.16,20.775 C17.546,20.541 17.878,20.229 18.135,19.859 C18.366,19.529 18.52,19.104 18.631,18.404 C18.744,17.692 18.802,16.774 18.882,15.479 L19.452,6.25 L6.047,6.25 Z M9.75,10.985 L15.75,10.985 C16.164,10.985 16.5,11.321 16.5,11.735 C16.5,12.149 16.164,12.485 15.75,12.485 L9.75,12.485 C9.336,12.485 9,12.149 9,11.735 C9,11.321 9.336,10.985 9.75,10.985 Z M15.608,4.75 L15.448,4.419 C15.215,3.939 15.062,3.624 14.921,3.389 C14.787,3.166 14.692,3.065 14.603,2.998 C14.549,2.958 14.491,2.922 14.431,2.89 C14.333,2.839 14.2,2.798 13.941,2.775 C13.668,2.751 13.317,2.75 12.784,2.75 C12.238,2.75 11.878,2.751 11.598,2.776 C11.333,2.8 11.198,2.843 11.098,2.896 C11.037,2.929 10.978,2.966 10.924,3.008 C10.833,3.077 10.739,3.183 10.607,3.414 C10.467,3.658 10.318,3.985 10.091,4.482 L9.969,4.75 Z M11.25,14.904 L14.25,14.904 C14.664,14.904 15,15.24 15,15.654 C15,16.069 14.664,16.404 14.25,16.404 L11.25,16.404 C10.836,16.404 10.5,16.069 10.5,15.654 C10.5,15.24 10.836,14.904 11.25,14.904 Z"
        ]
    ]

    static let iconSettings: [[String]] = [
        [
            "M10.026,2.25 L13.974,2.25 C14.744,2.25 15.376,2.25 15.896,2.301 C16.441,2.355 16.921,2.468 17.376,2.73 C17.831,2.991 18.17,3.349 18.49,3.793 C18.795,4.217 19.111,4.763 19.497,5.428 L21.458,8.808 C21.845,9.475 22.163,10.024 22.38,10.5 C22.608,11 22.75,11.474 22.75,12 C22.75,12.526 22.608,13 22.38,13.5 C22.163,13.976 21.845,14.525 21.458,15.192 L21.458,15.192 L19.497,18.572 L19.497,18.572 C19.111,19.237 18.795,19.783 18.49,20.207 C18.17,20.651 17.831,21.009 17.376,21.27 C16.921,21.532 16.441,21.645 15.896,21.699 C15.376,21.75 14.744,21.75 13.974,21.75 L10.026,21.75 C9.256,21.75 8.624,21.75 8.104,21.699 C7.559,21.645 7.079,21.532 6.624,21.27 C6.169,21.009 5.83,20.651 5.51,20.207 C5.205,19.783 4.889,19.237 4.503,18.572 L2.542,15.192 C2.155,14.525 1.837,13.977 1.62,13.5 C1.392,13 1.25,12.526 1.25,12 C1.25,11.474 1.392,11 1.62,10.5 C1.837,10.024 2.155,9.475 2.542,8.808 L4.503,5.428 C4.889,4.763 5.205,4.217 5.51,3.793 C5.83,3.349 6.169,2.991 6.624,2.73 C7.079,2.468 7.559,2.355 8.104,2.301 C8.624,2.25 9.256,2.25 10.026,2.25 L10.026,2.25 Z M7.372,4.03 C7.166,4.148 6.975,4.326 6.728,4.67 C6.471,5.026 6.191,5.508 5.782,6.213 L3.858,9.528 C3.448,10.236 3.168,10.72 2.985,11.122 C2.809,11.508 2.75,11.763 2.75,12 C2.75,12.237 2.809,12.492 2.985,12.878 C3.168,13.28 3.448,13.764 3.858,14.472 L5.782,17.787 C6.191,18.492 6.471,18.974 6.728,19.33 C6.975,19.674 7.166,19.852 7.372,19.97 C7.578,20.088 7.828,20.165 8.25,20.206 C8.688,20.249 9.247,20.25 10.063,20.25 L13.937,20.25 C14.753,20.25 15.311,20.249 15.75,20.206 C16.172,20.165 16.422,20.088 16.628,19.97 C16.834,19.852 17.025,19.674 17.272,19.33 C17.529,18.974 17.809,18.492 18.218,17.787 L20.142,14.472 C20.552,13.764 20.832,13.28 21.015,12.878 C21.191,12.492 21.25,12.237 21.25,12 C21.25,11.763 21.191,11.508 21.015,11.122 C20.832,10.72 20.552,10.236 20.142,9.528 L18.218,6.213 C17.809,5.508 17.529,5.026 17.272,4.67 C17.025,4.326 16.834,4.148 16.628,4.03 C16.422,3.912 16.172,3.835 15.75,3.794 C15.311,3.751 14.753,3.75 13.937,3.75 L10.063,3.75 C9.247,3.75 8.688,3.751 8.25,3.794 C7.828,3.835 7.578,3.912 7.372,4.03 Z M12,7.75 C14.347,7.75 16.25,9.653 16.25,12 C16.25,14.347 14.347,16.25 12,16.25 C9.653,16.25 7.75,14.347 7.75,12 C7.75,9.653 9.653,7.75 12,7.75 Z M9.25,12 C9.25,13.519 10.481,14.75 12,14.75 C13.519,14.75 14.75,13.519 14.75,12 C14.75,10.481 13.519,9.25 12,9.25 C10.481,9.25 9.25,10.481 9.25,12 Z"
        ]
    ]
}
