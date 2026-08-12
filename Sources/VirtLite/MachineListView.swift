import SwiftUI
import VirtLiteCore
import VirtLiteVZ

/// The main window: a sidebar of machines beside whatever is selected (UI-01).
///
/// There are no machines yet — creation arrives with the wizard. Until then this shows what the
/// host actually supports, which is the one thing worth confirming early: the limits come from
/// the framework rather than from constants (HW-01), and they differ between Macs.
struct MachineListView: View {
    private let limits = VZHardwareLimits.current

    var body: some View {
        NavigationSplitView {
            List {
                Section("Virtual machines") {
                    Text("No machines yet")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            HostCapabilitiesView(limits: limits)
        }
    }
}

/// What this Mac can run, straight from `Virtualization.framework`.
private struct HostCapabilitiesView: View {
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
                    Text("\(format(limits.minimumMemoryInBytes)) – \(format(limits.maximumMemoryInBytes))")
                        .monospacedDigit()
                }
            }
            .font(.body)

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}
