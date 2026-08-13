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

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = machine.makeScreenView()
        context.coordinator.observe(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.claimFocus(for: nsView)
    }

    /// Keeps keyboard focus on the guest.
    ///
    /// Without this the guest receives nothing: the window opens with SwiftUI's own hosting view
    /// as first responder, so arrow keys and typing go to the interface and never reach the
    /// virtual machine. The devices are attached and working — the keystrokes simply never
    /// arrive (HW-05).
    @MainActor
    final class Coordinator {
        // Only ever touched on the main actor; the annotation is here so deinit, which is not
        // actor-isolated, can still release it rather than leaking the observer.
        nonisolated(unsafe) private var observer: (any NSObjectProtocol)?

        func observe(_ view: NSView) {
            // A window becoming key is the moment focus has to be taken back, whether that is
            // the first time it opens or the fifth time the user clicks into it.
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak view] notification in
                guard let view, let window = notification.object as? NSWindow,
                      window === view.window else { return }
                MainActor.assumeIsolated {
                    window.makeFirstResponder(view)
                }
            }

            // The window does not exist yet while the view is being made.
            DispatchQueue.main.async { [weak view] in
                guard let view else { return }
                view.window?.makeFirstResponder(view)
            }
        }

        func claimFocus(for view: NSView) {
            guard let window = view.window, window.firstResponder !== view else { return }
            window.makeFirstResponder(view)
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
