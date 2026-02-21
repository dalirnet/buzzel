import SwiftUI

struct SettingsView: View {
  @ObservedObject var store: AppStore

  private let methods = ["auto", "wifi", "ble"]
  private let labels = ["Auto", "WiFi", "Bluetooth"]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Preferred Transport")
        .font(Brand.font(size: 11))
        .foregroundColor(DesignColor.secondary)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)

      HStack(spacing: 2) {
        ForEach(Array(methods.enumerated()), id: \.element) { index, method in
          let selected = store.transportMethod == method
          Button {
            withAnimation(.easeInOut(duration: 0.2)) {
              store.transportMethod = method
              store.save()
            }
          } label: {
            Text(labels[index])
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
