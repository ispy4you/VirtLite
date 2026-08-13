import SwiftUI
import UniformTypeIdentifiers
import VirtLiteCore

/// The selected machine: what it is, and what can be done with it.
struct MachineDetailView: View {
    @Environment(MachineStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Bindable var entry: MachineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("CPU").foregroundStyle(.secondary)
                    Text("\(entry.machine.configuration.cpuCount) cores").monospacedDigit()
                }
                GridRow {
                    Text("Memory").foregroundStyle(.secondary)
                    Text(formatted(entry.machine.configuration.memoryInBytes)).monospacedDigit()
                }
                GridRow {
                    Text("Disk").foregroundStyle(.secondary)
                    Text(formatted(entry.machine.configuration.disks.first?.sizeInBytes ?? 0))
                        .monospacedDigit()
                }
                GridRow {
                    Text("Network").foregroundStyle(.secondary)
                    Text("Shared with the host (NAT)")
                }
                GridRow {
                    Text("Installer").foregroundStyle(.secondary)
                    installerRow
                }
            }

            if let hint = entry.hint {
                Label(hint, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))
            }

            controls

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The installer is shown and controlled explicitly. Nothing on the host can tell a finished
    /// installation from an abandoned one, so detaching is the user's call rather than a guess
    /// the app makes on their behalf (INS-01).
    @ViewBuilder
    private var installerRow: some View {
        if let iso = entry.installerISO {
            HStack(spacing: 8) {
                Text(iso.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button("Eject") {
                    store.ejectInstaller(from: entry)
                }
                .controlSize(.small)
                .disabled(entry.state.isActive)
                .help("Detach the image once the guest is installed, so it boots from its own disk.")
            }
        } else {
            HStack(spacing: 8) {
                Text("None").foregroundStyle(.secondary)

                Button("Attach…", action: attachInstaller)
                    .controlSize(.small)
                    .disabled(entry.state.isActive)
            }
        }
    }

    private func attachInstaller() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "iso") ?? .diskImage]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Attach"

        if panel.runModal() == .OK, let url = panel.url {
            store.attachInstaller(url, to: entry)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            StateIndicator(state: entry.state)
                .font(.title)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.title2.weight(.semibold))
                Text(entry.state.displayName).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 10) {
            switch entry.state {
            case .stopped, .error:
                Button {
                    Task {
                        await store.start(entry)
                        openWindow(id: MachineScreenWindow.identifier, value: entry.id)
                    }
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .keyboardShortcut("r")

            case .running:
                Button {
                    openWindow(id: MachineScreenWindow.identifier, value: entry.id)
                } label: {
                    Label("Show Screen", systemImage: "display")
                }

                Button {
                    Task { await store.pause(entry) }
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }

                Button {
                    Task { await store.requestStop(entry) }
                } label: {
                    Label("Shut Down", systemImage: "power")
                }

            case .paused:
                Button {
                    Task { await store.resume(entry) }
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }

            default:
                // Mid-transition: the framework would refuse anything anyway, so the interface
                // does not offer it.
                ProgressView().controlSize(.small)
            }

            if entry.state.isActive {
                Spacer()
                Button(role: .destructive) {
                    Task { await store.forceStop(entry) }
                } label: {
                    Label("Force Stop", systemImage: "bolt.slash")
                }
                .help("Cuts power to the guest, like unplugging a real machine. Unsaved work in the guest is lost.")
            }
        }
    }

    private func formatted(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}
