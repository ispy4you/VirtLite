import SwiftUI
import VirtLiteVZ

/// A window showing one guest's screen (UI-02).
///
/// Each running machine gets its own, so several can be watched at once.
struct MachineScreenWindow: View {
    static let identifier = "machine-screen"

    @Environment(MachineStore.self) private var store
    let machineID: URL?

    var body: some View {
        Group {
            if let entry, let machine = entry.running as? VZMachine {
                GuestScreen(machine: machine)
                    .navigationTitle(entry.name)
            } else {
                ContentUnavailableView(
                    "Not running",
                    systemImage: "display",
                    description: Text("Start the machine to see its screen.")
                )
            }
        }
        .frame(minWidth: 640, minHeight: 400)
    }

    private var entry: MachineEntry? {
        store.entries.first { $0.id == machineID }
    }
}

/// Wraps the guest's framebuffer.
///
/// The backend hands over an NSView rather than a virtual machine, so the interface never names
/// a framework type (ARC-02).
private struct GuestScreen: NSViewRepresentable {
    let machine: VZMachine

    func makeNSView(context: Context) -> NSView {
        machine.makeScreenView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
