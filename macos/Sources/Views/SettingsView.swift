import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore

    private let transportOptions: [(method: String, label: String)] = [
        ("auto", "Auto"),
        ("wifi", "WiFi"),
        ("ble", "Bluetooth"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Preferred Transport")
                .font(Brand.font(size: 11))
                .foregroundColor(DesignColor.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            HStack(spacing: 2) {
                ForEach(transportOptions, id: \.method) { option in
                    let selected = store.transportMethod == option.method
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            store.transportMethod = option.method
                            store.save()
                        }
                    } label: {
                        Text(option.label)
                            .font(Brand.font(size: 12))
                            .foregroundColor(selected ? DesignColor.surface : DesignColor.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selected ? DesignColor.accent : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(DesignColor.secondary.opacity(0.08))
            )
            .padding(.horizontal, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
