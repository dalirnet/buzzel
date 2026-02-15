import SwiftUI

struct ActivityLogView: View {
    @ObservedObject var transportManager: TransportManager

    var body: some View {
        ViewLayout {
            HeaderTitle(icon: "text.bubble", title: "Activity")
        } headerRight: {
            if !transportManager.logEntries.isEmpty {
                Button {
                    transportManager.logEntries.removeAll()
                } label: {
                    Text("Clear")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        } content: {
            if transportManager.logEntries.isEmpty {
                Text("No activity yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(transportManager.logEntries) { entry in
                                LogEntryRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .onChange(of: transportManager.logEntries.count) { _ in
                        if let last = transportManager.logEntries.last {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                directionIcon
                    .font(.system(size: 10))
                    .frame(width: 16, height: 16)

                Text(entry.message)
                    .font(.system(size: 12))
                    .foregroundStyle(entry.status == .failed ? .red : .primary)
                    .lineLimit(2)

                Spacer()

                if entry.status == .failed {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }

                Text(entry.timeString)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            if let error = entry.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(.leading, 22)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(entry.status == .failed ? Color.red.opacity(0.06) : Color.primary.opacity(0.04))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var directionIcon: some View {
        switch entry.direction {
        case .incoming:
            Image(systemName: "arrow.down.left")
                .foregroundStyle(.blue)
        case .outgoing:
            Image(systemName: "arrow.up.right")
                .foregroundStyle(.green)
        case .local:
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(.secondary)
        }
    }
}
