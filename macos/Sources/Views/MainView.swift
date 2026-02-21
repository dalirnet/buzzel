import SwiftUI

// MARK: - Main View

struct MainView: View {
  @ObservedObject var store: AppStore
  @ObservedObject var transportManager: TransportManager

  @State private var showQR = false
  @State private var showActivityLog = false
  @State private var showSettings = false
  @State private var qrMatrix: [[Bool]]?
  @State private var pairingCode = ""
  @State private var sessionId = ""
  @State private var displayedStatusText = ""
  @State private var statusFlipAngle: Double = 0
  @State private var statusOverride: String?
  private var powerState: PowerButtonState {
    PowerButtonState.current(store: store, transportManager: transportManager)
  }

  private var isSubView: Bool {
    showQR || showActivityLog || showSettings
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
      if state == .connected && showQR {
        closeQR()
      }
    }
  }

  // MARK: - Header

  private var headerTitle: String {
    if showActivityLog { return "Activity Log" }
    if showSettings { return "Settings" }
    if showQR { return "Quick Setup" }
    return "Buzzel"
  }

  private var header: some View {
    HStack(spacing: 8) {
      AppHeaderLabel(title: headerTitle)

      Spacer()

      if isSubView {
        Button {
          if showActivityLog {
            withAnimation(.easeInOut(duration: 0.2)) { showActivityLog = false }
          } else if showSettings {
            withAnimation(.easeInOut(duration: 0.2)) { showSettings = false }
          } else {
            closeQR()
          }
        } label: {
          SVGIconView(
            paths: Self.iconZap,
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
        .help("Back")
      } else {
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

      OrbitRingsView(deviceName: store.pairedDevice?.name, isConnected: powerState == .connected) {
        AnimatedSwitcher(key: showQR) { isQR in
          if isQR {
            qrContent
          } else {
            PowerButtonView(
              state: powerState,
              ready: powerState == .disconnected && !transportManager.hasBeenConnected,
              onTap: { onPowerButtonTap() },
              onUnpairWarning: { onPowerButtonHoldWarning() },
              onUnpair: { onPowerButtonUnpair() },
              onHoldCancel: { onPowerButtonHoldCancel() }
            )
            .frame(width: 94, height: 94)
          }
        }
        .frame(width: showQR ? 150 : 126, height: showQR ? 150 : 126)
      }

      Spacer()

      statusLine
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
  }

  // MARK: - QR Content

  @ViewBuilder
  private var qrContent: some View {
    if let matrix = qrMatrix {
      CircularQRView(matrix: matrix, size: 150)
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
    if showQR {
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
  }

  // MARK: - Actions

  private func openQR() {
    generateQR()
    transportManager.onPairingComplete = { name in
      store.pairedDevice = DeviceInfo(
        name: name,
        address: store.transportMethod,
        peripheralIdentifier: transportManager.ble.peripheralIdentifier?.uuidString
      )
      store.save()
      closeQR()
    }
    transportManager.startPairingMode(sessionId: sessionId, code: pairingCode)
    showQR = true
  }

  private func closeQR() {
    showQR = false
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
      openQR()
    case .connecting:
      transportManager.disconnect()
    case .connected:
      transportManager.disconnect()
    case .disconnected:
      transportManager.start()
    }
  }

  private func generateQR() {
    guard let result = QRGenerator.generateQrPayload(prefer: store.transportMethod) else {
      qrMatrix = nil
      return
    }
    sessionId = BuzzelProtocol.deriveSessionId(result.seed)
    pairingCode = BuzzelProtocol.derivePairingCode(result.seed)
    qrMatrix = QRGenerator.generateQRMatrix(from: result.payload)
  }

  // MARK: - Icon Path Data

  static let iconZap: [[String]] = [[PowerButtonView.ButtonIcon.zapPath]]

  static let iconSettings: [[String]] = [
    [
      "M10.026,2.25 L13.974,2.25 C14.744,2.25 15.376,2.25 15.896,2.301 C16.441,2.355 16.921,2.468 17.376,2.73 C17.831,2.991 18.17,3.349 18.49,3.793 C18.795,4.217 19.111,4.763 19.497,5.428 L21.458,8.808 C21.845,9.475 22.163,10.024 22.38,10.5 C22.608,11 22.75,11.474 22.75,12 C22.75,12.526 22.608,13 22.38,13.5 C22.163,13.976 21.845,14.525 21.458,15.192 L21.458,15.192 L19.497,18.572 L19.497,18.572 C19.111,19.237 18.795,19.783 18.49,20.207 C18.17,20.651 17.831,21.009 17.376,21.27 C16.921,21.532 16.441,21.645 15.896,21.699 C15.376,21.75 14.744,21.75 13.974,21.75 L10.026,21.75 C9.256,21.75 8.624,21.75 8.104,21.699 C7.559,21.645 7.079,21.532 6.624,21.27 C6.169,21.009 5.83,20.651 5.51,20.207 C5.205,19.783 4.889,19.237 4.503,18.572 L2.542,15.192 C2.155,14.525 1.837,13.977 1.62,13.5 C1.392,13 1.25,12.526 1.25,12 C1.25,11.474 1.392,11 1.62,10.5 C1.837,10.024 2.155,9.475 2.542,8.808 L4.503,5.428 C4.889,4.763 5.205,4.217 5.51,3.793 C5.83,3.349 6.169,2.991 6.624,2.73 C7.079,2.468 7.559,2.355 8.104,2.301 C8.624,2.25 9.256,2.25 10.026,2.25 L10.026,2.25 Z M7.372,4.03 C7.166,4.148 6.975,4.326 6.728,4.67 C6.471,5.026 6.191,5.508 5.782,6.213 L3.858,9.528 C3.448,10.236 3.168,10.72 2.985,11.122 C2.809,11.508 2.75,11.763 2.75,12 C2.75,12.237 2.809,12.492 2.985,12.878 C3.168,13.28 3.448,13.764 3.858,14.472 L5.782,17.787 C6.191,18.492 6.471,18.974 6.728,19.33 C6.975,19.674 7.166,19.852 7.372,19.97 C7.578,20.088 7.828,20.165 8.25,20.206 C8.688,20.249 9.247,20.25 10.063,20.25 L13.937,20.25 C14.753,20.25 15.311,20.249 15.75,20.206 C16.172,20.165 16.422,20.088 16.628,19.97 C16.834,19.852 17.025,19.674 17.272,19.33 C17.529,18.974 17.809,18.492 18.218,17.787 L20.142,14.472 C20.552,13.764 20.832,13.28 21.015,12.878 C21.191,12.492 21.25,12.237 21.25,12 C21.25,11.763 21.191,11.508 21.015,11.122 C20.832,10.72 20.552,10.236 20.142,9.528 L18.218,6.213 C17.809,5.508 17.529,5.026 17.272,4.67 C17.025,4.326 16.834,4.148 16.628,4.03 C16.422,3.912 16.172,3.835 15.75,3.794 C15.311,3.751 14.753,3.75 13.937,3.75 L10.063,3.75 C9.247,3.75 8.688,3.751 8.25,3.794 C7.828,3.835 7.578,3.912 7.372,4.03 Z M12,7.75 C14.347,7.75 16.25,9.653 16.25,12 C16.25,14.347 14.347,16.25 12,16.25 C9.653,16.25 7.75,14.347 7.75,12 C7.75,9.653 9.653,7.75 12,7.75 Z M9.25,12 C9.25,13.519 10.481,14.75 12,14.75 C13.519,14.75 14.75,13.519 14.75,12 C14.75,10.481 13.519,9.25 12,9.25 C10.481,9.25 9.25,10.481 9.25,12 Z"
    ]
  ]
}
