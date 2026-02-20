import SwiftUI

struct ActivityLogView: View {
  @ObservedObject var transportManager: TransportManager
  @State private var isAtBottom = true

  var body: some View {
    if transportManager.logEntries.isEmpty {
      VStack(spacing: 12) {
        Spacer()
        WaveBLogoView(size: 32, color: DesignColor.secondary.opacity(0.3))
        Text("No activity yet")
          .font(Brand.font(size: 14))
          .foregroundColor(DesignColor.secondary)
        Text("Events will appear here")
          .font(Brand.font(size: 12))
          .foregroundColor(DesignColor.secondary.opacity(0.6))
        Spacer()
      }
      .frame(maxWidth: .infinity)
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(transportManager.logEntries.enumerated()), id: \.element.id) {
              index, entry in
              if index > 0 {
                Divider()
                  .padding(.leading, 38)
              }
              ActivityLogRow(entry: entry)
            }
            Color.clear
              .frame(height: 1)
              .id("bottom")
              .onAppear { isAtBottom = true }
              .onDisappear { isAtBottom = false }
          }
          .padding(.vertical, 4)
        }
        .onAppear {
          proxy.scrollTo("bottom", anchor: .bottom)
        }
        .onChange(of: transportManager.logEntries.count) { _ in
          if isAtBottom {
            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
          }
        }
      }
    }
  }
}

// MARK: - Log Row

private struct ActivityLogRow: View {
  let entry: LogEntry

  private static let iconArrowDown: [[String]] = [["M12 5v14M5 12l7 7 7-7"]]
  private static let iconArrowUp: [[String]] = [["M12 19V5M5 12l7-7 7 7"]]
  private static let iconDot: [[String]] = [["M12 12m-4 0a4 4 0 1 0 8 0a4 4 0 1 0-8 0"]]

  private var iconPaths: [[String]] {
    switch entry.direction {
    case .incoming: return Self.iconArrowDown
    case .outgoing: return Self.iconArrowUp
    case .local: return Self.iconDot
    }
  }

  private var iconMode: SVGIconView.IconMode {
    entry.direction == .local ? .fill : .stroke(width: 2)
  }

  private var iconColor: Color {
    entry.status == .success ? DesignColor.green : DesignColor.red
  }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      SVGIconView(paths: iconPaths, size: 14, color: iconColor, mode: iconMode)
        .frame(width: 14, height: 14)
        .padding(.top, 3)

      VStack(alignment: .leading, spacing: 2) {
        Text(entry.message)
          .font(Brand.font(size: 13, weight: .regular))
          .foregroundColor(DesignColor.text)
          .lineLimit(2)

        if let error = entry.error {
          Text(error)
            .font(Brand.font(size: 11, weight: .regular))
            .foregroundColor(DesignColor.red)
            .lineLimit(1)
        }
      }

      Spacer()

      Text(entry.timeString)
        .font(Brand.font(size: 11, weight: .regular))
        .foregroundColor(DesignColor.secondary)
        .padding(.top, 2)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }
}
