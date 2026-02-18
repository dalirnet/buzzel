import SwiftUI

struct ActivityLogView: View {
  @ObservedObject var transportManager: TransportManager

  var body: some View {
    if transportManager.logEntries.isEmpty {
      VStack {
        Spacer()
        Text("No activity yet")
          .font(Brand.font(size: 13))
          .foregroundColor(DesignColor.secondary)
        Spacer()
      }
    } else {
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(transportManager.logEntries.reversed()) { entry in
            ActivityLogRow(entry: entry)

            if entry.id != transportManager.logEntries.first?.id {
              Divider()
                .padding(.leading, 28)
            }
          }
        }
        .padding(.vertical, 4)
      }
    }
  }
}

// MARK: - Log Row

private struct ActivityLogRow: View {
  let entry: LogEntry

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Circle()
        .fill(entry.status == .success ? DesignColor.green : DesignColor.red)
        .frame(width: 8, height: 8)
        .padding(.top, 5)

      VStack(alignment: .leading, spacing: 2) {
        Text(entry.message)
          .font(Brand.font(size: 13))
          .foregroundColor(DesignColor.text)
          .lineLimit(2)

        if let error = entry.error {
          Text(error)
            .font(Brand.font(size: 11))
            .foregroundColor(DesignColor.red)
            .lineLimit(1)
        }
      }

      Spacer()

      VStack(alignment: .trailing, spacing: 2) {
        Text(entry.timeString)
          .font(Brand.font(size: 11))
          .foregroundColor(DesignColor.secondary)

        if entry.direction != .local {
          Text(entry.direction == .incoming ? "IN" : "OUT")
            .font(Brand.font(size: 9, weight: .medium))
            .foregroundColor(DesignColor.secondary)
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }
}
