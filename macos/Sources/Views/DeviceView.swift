import SwiftUI

struct DeviceView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var transportManager: TransportManager

    var body: some View {
        if let device = store.pairedDevice {
            ScrollView {
                VStack(spacing: 0) {
                    // Device row
                    HStack(spacing: 10) {
                        Circle()
                            .fill(transportManager.isConnected ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.system(size: 13, weight: .medium))
                            Text(transportManager.isConnected ? "Connected" : "Disconnected")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    Divider()
                        .padding(.horizontal, 12)

                    // Unpair row
                    Button {
                        store.unpair()
                        transportManager.unpair()
                    } label: {
                        HStack(spacing: 10) {
                            Text("Unpair Device")
                                .font(.system(size: 13))
                                .foregroundColor(.red)

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        } else {
            VStack(spacing: 4) {
                Text("No device paired")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Use \"Pair Device...\" from the menu bar")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
