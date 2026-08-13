import SwiftUI
import VirtLiteCore

/// The main window: machines on the left, the selected one on the right (UI-01).
struct MachineListView: View {
    @Environment(MachineStore.self) private var store
    @State private var selection: URL?

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            List(selection: $selection) {
                Section("Virtual machines") {
                    ForEach(store.entries) { entry in
                        MachineRow(entry: entry).tag(entry.id)
                    }
                }

                if !store.damagedBundles.isEmpty {
                    Section("Unreadable") {
                        ForEach(store.damagedBundles, id: \.self) { url in
                            Label(url.deletingPathExtension().lastPathComponent,
                                  systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                                .help("This bundle could not be read. It may have been created by a newer version of VirtLite.")
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .overlay {
                if store.entries.isEmpty && store.damagedBundles.isEmpty {
                    ContentUnavailableView {
                        Label("No machines", systemImage: "desktopcomputer")
                    } description: {
                        Text("Create one to get started.")
                    } actions: {
                        Button("New Machine…") { store.isCreatingMachine = true }
                    }
                }
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        store.isCreatingMachine = true
                    } label: {
                        Label("New Machine", systemImage: "plus")
                    }
                    .help("Create a virtual machine")
                }
            }
        } detail: {
            if let entry = selectedEntry {
                MachineDetailView(entry: entry)
            } else {
                HostCapabilitiesView(limits: store.hardwareLimits)
            }
        }
        .sheet(isPresented: $store.isCreatingMachine) {
            CreateMachineView { entry in
                selection = entry.id
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } }
            )
        ) {
            Button("OK") { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }

    private var selectedEntry: MachineEntry? {
        store.entries.first { $0.id == selection }
    }
}

/// One machine in the sidebar, with what it is doing right now (LC-04).
private struct MachineRow: View {
    @Bindable var entry: MachineEntry

    var body: some View {
        HStack(spacing: 10) {
            StateIndicator(state: entry.state)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                Text(entry.state.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// State shown by shape as well as colour, so it survives a colour-blind reader and a
/// greyscale screenshot (UI-04).
struct StateIndicator: View {
    let state: VMState

    var body: some View {
        Image(systemName: state.symbolName)
            .foregroundStyle(state.tint)
            .symbolEffect(.pulse, isActive: state.isTransitional)
            .frame(width: 16)
            .accessibilityLabel(state.displayName)
    }
}

extension VMState {
    var displayName: String {
        switch self {
        case .stopped:  return "Stopped"
        case .starting: return "Starting…"
        case .running:  return "Running"
        case .pausing:  return "Pausing…"
        case .paused:   return "Paused"
        case .resuming: return "Resuming…"
        case .stopping: return "Stopping…"
        case .error:    return "Failed"
        }
    }

    var symbolName: String {
        switch self {
        case .stopped:            return "stop.circle"
        case .starting, .resuming: return "arrow.triangle.2.circlepath.circle"
        case .running:            return "play.circle.fill"
        case .pausing, .paused:   return "pause.circle.fill"
        case .stopping:           return "stop.circle.fill"
        case .error:              return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .running:            return .green
        case .paused, .pausing:   return .orange
        case .error:              return .red
        case .starting, .resuming, .stopping: return .secondary
        case .stopped:            return .secondary
        }
    }
}

/// Shown when nothing is selected: what this Mac can run, straight from the framework (HW-01).
struct HostCapabilitiesView: View {
    let limits: HardwareLimits

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("This Mac")
                    .font(.title2.weight(.semibold))
                Text("Ranges reported by Virtualization.framework, not hardcoded values.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                GridRow {
                    Text("CPU cores").foregroundStyle(.secondary)
                    Text("\(limits.minimumCPUCount) – \(limits.maximumCPUCount)")
                        .monospacedDigit()
                }
                GridRow {
                    Text("Memory").foregroundStyle(.secondary)
                    Text("\(formatted(limits.minimumMemoryInBytes)) – \(formatted(limits.maximumMemoryInBytes))")
                        .monospacedDigit()
                }
            }

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func formatted(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}
