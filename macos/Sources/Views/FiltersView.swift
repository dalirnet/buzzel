import SwiftUI

struct FiltersView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var transportManager: TransportManager
    @State private var showingAdd = false

    private func logAndSync(_ message: String) {
        transportManager.appendEntry(.filterUpdated, message)
        syncConfig()
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.filters.isEmpty {
                VStack(spacing: 6) {
                    Text("No filters — all SMS forwarded")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(store.filters.enumerated()), id: \.element.id) { index, filter in
                            HStack(spacing: 8) {
                                Text(filter.value)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)

                                Spacer()

                                Text(filter.type == .sender ? "Sender" : "Content")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)

                                Button {
                                    let name = filter.value
                                    store.removeFilter(at: index)
                                    logAndSync("Removed filter \"\(name)\"")
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 20, height: 20)
                                        .background(Color.primary.opacity(0.06))
                                        .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)

                            if index < store.filters.count - 1 {
                                Divider()
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    showingAdd = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Add")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(FilterPreset.all, id: \.name) { preset in
                        Button(preset.name) {
                            store.addPreset(preset)
                            logAndSync("Added \(preset.name) preset")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Preset")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(height: 40)
        }
        .sheet(isPresented: $showingAdd) {
            AddFilterSheet(store: store) { name in
                logAndSync("Added filter \"\(name)\"")
            }
        }
    }

    private func syncConfig() {
        transportManager.syncConfig(store: store)
    }
}

// MARK: - Add Filter Sheet

struct AddFilterSheet: View {
    @ObservedObject var store: AppStore
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var type: FilterType = .sender
    @State private var value = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Filter")
                .font(.system(size: 13, weight: .semibold))

            Picker("", selection: $type) {
                Text("Sender").tag(FilterType.sender)
                Text("Content").tag(FilterType.content)
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            TextField("Pattern (use * as wildcard)", text: $value)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .font(.system(size: 13))

                Spacer()

                Button {
                    let filter = FilterRule(type: type, value: value)
                    store.addFilter(filter)
                    onSave(value)
                    dismiss()
                } label: {
                    Text("Add")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(value.isEmpty ? Color.secondary.opacity(0.2) : Color.accentColor)
                        .foregroundColor(value.isEmpty ? .secondary : .white)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(value.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 280)
    }
}
