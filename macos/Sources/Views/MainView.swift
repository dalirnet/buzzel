import SwiftUI

// MARK: - Main View

struct MainView: View {
  @ObservedObject var store: AppStore
  @ObservedObject var transportManager: TransportManager

  @State private var showQR = false
  @State private var showActivityLog = false
  @State private var qrMatrix: [[Bool]]?
  @State private var pairingCode = ""
  @State private var sessionId = ""
  @State private var displayedStatusText = ""
  @State private var statusFlipAngle: Double = 0
  private var powerState: PowerButtonState {
    PowerButtonState.current(store: store, transportManager: transportManager)
  }

  private var isSubView: Bool {
    showQR || showActivityLog
  }

  var body: some View {
    VStack(spacing: 0) {
      header
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(height: 48)

      if showActivityLog {
        ActivityLogView(transportManager: transportManager)
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
    if showQR { return "QR Code" }
    return "Buzzel"
  }

  private var header: some View {
    HStack(spacing: 8) {
      AppHeaderLabel(title: headerTitle)

      if !isSubView, powerState == .connected, let device = store.pairedDevice {
        Text(device.name)
          .font(Brand.font(size: 10))
          .foregroundColor(DesignColor.secondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(DesignColor.secondary.opacity(0.1))
          .cornerRadius(4)
      }

      if showActivityLog, !transportManager.logEntries.isEmpty {
        Text("\(transportManager.logEntries.count)")
          .font(Brand.font(size: 10))
          .foregroundColor(DesignColor.secondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(DesignColor.secondary.opacity(0.1))
          .cornerRadius(4)
      }

      Spacer()

      Button {
        headerAction()
      } label: {
        SVGIconView(
          paths: isSubView ? Self.iconBack : Self.iconQR,
          size: 20,
          color: isSubView ? DesignColor.text : DesignColor.accent,
          mode: isSubView ? .stroke(width: 1.5) : .mixed,
          opacity: (!isSubView && (powerState == .connected || powerState == .noPermission))
            ? 0.3 : 1.0
        )
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(!isSubView && (powerState == .connected || powerState == .noPermission))
      .onHover { inside in
        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
      }
      .help(isSubView ? "Back" : "QR Code")
    }
  }

  private func headerAction() {
    if showActivityLog {
      withAnimation(.easeInOut(duration: 0.2)) { showActivityLog = false }
    } else {
      toggleQR()
    }
  }

  // MARK: - Main Panel

  private var mainPanel: some View {
    VStack(spacing: 0) {
      Spacer()

      OrbitRingsView {
        AnimatedSwitcher(key: showQR) { isQR in
          if isQR {
            qrContent
          } else {
            PowerButtonView(state: powerState) {
              onPowerButtonTap()
            }
            .frame(width: 94, height: 94)
          }
        }
        .frame(width: 126, height: 126)
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
      CircularQRView(matrix: matrix, size: 120)
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
    if showQR {
      if let error = transportManager.pairingError {
        return error
      } else if transportManager.isPairing {
        return "Waiting for device to connect"
      } else {
        return "Scan QR code with your phone"
      }
    }
    switch powerState {
    case .noPermission:
      return "Tap to grant Bluetooth access"
    case .unpaired:
      return "No device paired yet"
    case .connecting:
      return "Looking for your device"
    case .connected:
      if let last = transportManager.logEntries.last {
        return "\(last.message) · \(last.timeString)"
      }
      return "Connected and ready"
    case .disconnected:
      if let last = transportManager.logEntries.last {
        return "\(last.message) · \(last.timeString)"
      }
      return "Tap to reconnect"
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
        guard powerState == .connected else { return }
        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
      }
      .onTapGesture {
        guard powerState == .connected else { return }
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

  private func toggleQR() {
    if showQR { closeQR() } else { openQR() }
  }

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

  private func onPowerButtonTap() {
    switch powerState {
    case .noPermission:
      transportManager.ble.requestAccess()
    case .unpaired, .connecting:
      break
    case .connected:
      transportManager.stop()
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

  static let iconBack: [[String]] = [
    [
      "M4 7h11c1.87 0 2.804 0 3.5.402A3 3 0 0 1 19.598 8.5C20 9.196 20 10.13 20 12s0 2.804-.402 3.5a3 3 0 0 1-1.098 1.098C17.804 17 16.87 17 15 17H8M4 7l3-3M4 7l3 3"
    ]
  ]

  static let iconQR: [[String]] = [
    [
      "M2 16.9c0-1.31 0-1.964.295-2.445a2 2 0 0 1 .66-.66c.48-.295 1.136-.295 2.445-.295h1.1c1.886 0 2.828 0 3.414.586s.586 1.528.586 3.414v1.1c0 1.31 0 1.964-.295 2.445a2 2 0 0 1-.66.66C9.065 22 8.409 22 7.1 22c-1.964 0-2.946 0-3.667-.442a3 3 0 0 1-.99-.99C2 19.845 2 18.864 2 16.9Z"
    ],
    [
      "M13.5 5.4c0-1.31 0-1.964.295-2.445a2 2 0 0 1 .66-.66C14.935 2 15.591 2 16.9 2c1.964 0 2.946 0 3.668.442a3 3 0 0 1 .99.99C22 4.155 22 5.137 22 7.1c0 1.31 0 1.964-.295 2.445a2 2 0 0 1-.66.66c-.48.295-1.136.295-2.445.295h-1.1c-1.886 0-2.828 0-3.414-.586S13.5 8.386 13.5 6.5z"
    ],
    [
      "M2 7.1c0-1.964 0-2.946.442-3.667a3 3 0 0 1 .99-.99C4.155 2 5.137 2 7.1 2c1.31 0 1.964 0 2.445.295a2 2 0 0 1 .66.66c.295.48.295 1.136.295 2.445v1.1c0 1.886 0 2.828-.586 3.414S8.386 10.5 6.5 10.5H5.4c-1.31 0-1.964 0-2.445-.295a2 2 0 0 1-.66-.66C2 9.065 2 8.409 2 7.1Z"
    ],
    [
      "M16.5 6.25c0-.515 0-.773.13-.955a.7.7 0 0 1 .165-.166C16.977 5 17.235 5 17.75 5s.773 0 .955.13a.7.7 0 0 1 .166.165c.129.182.129.44.129.955s0 .773-.13.955a.7.7 0 0 1-.165.166c-.182.129-.44.129-.955.129s-.773 0-.955-.13a.7.7 0 0 1-.166-.165c-.129-.182-.129-.44-.129-.955"
    ],
    [
      "M5 6.25c0-.515 0-.773.13-.955a.7.7 0 0 1 .165-.166C5.477 5 5.735 5 6.25 5s.773 0 .955.13a.7.7 0 0 1 .166.165c.129.182.129.44.129.955s0 .773-.13.955a.7.7 0 0 1-.165.166c-.182.129-.44.129-.955.129s-.773 0-.955-.13a.7.7 0 0 1-.166-.165C5 7.023 5 6.765 5 6.25"
    ],
    [
      "M5 17.75c0-.515 0-.773.13-.955a.7.7 0 0 1 .165-.166c.182-.129.44-.129.955-.129s.773 0 .955.13a.7.7 0 0 1 .166.165c.129.182.129.44.129.955s0 .773-.13.955a.7.7 0 0 1-.165.166C7.023 19 6.765 19 6.25 19s-.773 0-.955-.13a.7.7 0 0 1-.166-.165C5 18.523 5 18.265 5 17.75"
    ],
    [
      "M16 17.75c0-.702 0-1.053.169-1.306a1 1 0 0 1 .275-.275C16.697 16 17.048 16 17.75 16s1.053 0 1.306.169a1 1 0 0 1 .275.275c.169.253.169.604.169 1.306s0 1.053-.169 1.306a1 1 0 0 1-.275.275c-.253.169-.604.169-1.306.169s-1.053 0-1.306-.169a1 1 0 0 1-.275-.275C16 18.803 16 18.452 16 17.75"
    ],
    ["M12.75 22a.75.75 0 0 0 1.5 0z"],
    ["M14.389 13.837l.417.624z"],
    ["M13.837 14.389l-.623-.417z"],
    [
      "M17 12.75c-.687 0-1.258 0-1.719.046c-.474.048-.913.153-1.309.418l.834 1.247c.108-.073.272-.137.627-.173c.367-.037.85-.038 1.567-.038z"
    ],
    [
      "M14.25 17c0-.718 0-1.2.038-1.567c.036-.355.1-.519.173-.627l-1.248-.834c-.264.396-.369.835-.417 1.309c-.047.461-.046 1.032-.046 1.719z"
    ],
    ["M13.972 14.028c-.3.2-.558.458-.758.758l1.247.834a1.3 1.3 0 0 1 .345-.345z"],
    ["M22.75 13.5a.75.75 0 0 0-1.5 0z"],
    ["M21.052 21.848l.287.693z"],
    ["M22.135 20.765l-.693-.287z"],
    [
      "M19 22.75c.456 0 .835 0 1.145-.02c.317-.022.617-.069.907-.19l-.574-1.385c-.077.032-.194.061-.435.078c-.247.017-.567.017-1.043.017z"
    ],
    [
      "M21.25 19c0 .476 0 .796-.017 1.043c-.017.241-.046.358-.078.435l1.386.574c.12-.29.167-.59.188-.907c.021-.31.021-.69.021-1.145z"
    ],
    ["M21.052 21.54a2.75 2.75 0 0 0 1.489-1.488l-1.386-.574a1.25 1.25 0 0 1-.677.677z"],
  ]
}
