import SwiftUI

private enum PairingStep {
    case selectDevice
    case enterCode
}

struct PairingView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var transportManager: TransportManager
    @Environment(\.dismiss) private var dismiss

    @State private var step: PairingStep = .selectDevice
    @State private var selectedDevice: DiscoveredDevice?
    @State private var code = ""
    @FocusState private var codeFieldFocused: Bool

    var body: some View {
        ViewLayout {
            if step == .enterCode {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        step = .selectDevice
                        code = ""
                        transportManager.pairingError = nil
                        transportManager.startDiscovery()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            HeaderTitle(icon: "antenna.radiowaves.left.and.right", title: step == .selectDevice ? "Pair Device" : "Enter Code")
        } headerRight: {
            if step == .selectDevice {
                if transportManager.ble.discoveredDevices.isEmpty {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                }
            }
        } content: {
            switch step {
            case .selectDevice:
                deviceSelectionContent
                    .transition(.move(edge: .leading).combined(with: .opacity))
            case .enterCode:
                codeEntryContent
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: step)
        .onAppear {
            transportManager.onPairingComplete = { name in
                store.pairedDevice = DeviceInfo(
                    name: name,
                    address: "ble",
                    peripheralIdentifier: transportManager.ble.peripheralIdentifier?.uuidString
                )
                store.save()
            }
            if store.pairedDevice == nil {
                transportManager.startDiscovery()
            }
        }
        .onDisappear {
            if transportManager.isPairing {
                transportManager.cancelPairing()
            }
            transportManager.stopDiscovery()
            transportManager.onPairingComplete = nil
        }
        .onReceive(transportManager.$isPairing) { pairing in
            if !pairing && store.pairedDevice != nil && transportManager.pairingError == nil {
                dismiss()
            }
        }
    }

    // MARK: - Device Selection

    private var deviceSelectionContent: some View {
        Group {
            if transportManager.ble.discoveredDevices.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Searching for devices...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(transportManager.ble.discoveredDevices) { device in
                            Button {
                                selectedDevice = device
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    step = .enterCode
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name)
                                            .font(.system(size: 13, weight: .medium))
                                        Text("Buzzel device")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.tertiary)
                                    }

                                    Spacer()

                                    signalBars(rssi: device.rssi)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - Code Entry

    private var codeEntryContent: some View {
        VStack(spacing: 16) {
            Spacer()

            if let device = selectedDevice {
                Text(device.name)
                    .font(.system(size: 13, weight: .medium))
            }

            Text("Enter the 6-digit code from your phone")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("000000", text: $code)
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .frame(width: 180)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
                .focused($codeFieldFocused)
                .onChange(of: code) { newValue in
                    code = String(newValue.filter { $0.isNumber }.prefix(6))
                }
                .onAppear {
                    codeFieldFocused = true
                }

            if let error = transportManager.pairingError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            Button {
                guard let device = selectedDevice else { return }
                transportManager.connectAndPair(device: device, code: code)
            } label: {
                Text(transportManager.isPairing ? "Pairing..." : "Pair")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(code.count == 6 && !transportManager.isPairing ? Color.accentColor : Color.secondary.opacity(0.2))
                    .foregroundColor(code.count == 6 && !transportManager.isPairing ? .white : .secondary)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(code.count != 6 || transportManager.isPairing)
            .padding(.horizontal, 14)

            Spacer()
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Signal Strength

    private func signalBars(rssi: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(bar: bar, rssi: rssi))
                    .frame(width: 4, height: CGFloat(6 + bar * 4))
            }
        }
    }

    private func barColor(bar: Int, rssi: Int) -> Color {
        let activeBars: Int
        if rssi > -60 {
            activeBars = 3
        } else if rssi > -75 {
            activeBars = 2
        } else {
            activeBars = 1
        }
        return bar < activeBars ? .accentColor : Color.secondary.opacity(0.3)
    }
}
