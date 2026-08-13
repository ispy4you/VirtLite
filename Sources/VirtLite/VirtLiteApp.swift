import SwiftUI

@main
struct VirtLiteApp: App {
    @State private var store = MachineStore()

    var body: some Scene {
        // A single window, not a group. There is one library of machines, so there is one window
        // showing it — and a group can be restored with no windows at all, which leaves the app
        // running with nothing on screen and no obvious way back.
        Window("VirtLite", id: "library") {
            MachineListView()
                .environment(store)
        }
        .defaultSize(width: 900, height: 560)
        .commands {
            // Replacing the group rather than removing it: with no File > New at all, a closed
            // window leaves no menu command to get anything back.
            CommandGroup(replacing: .newItem) {
                Button("New Machine…") {
                    store.isCreatingMachine = true
                }
                .keyboardShortcut("n")
            }
        }

        // One window per running machine, so several guests can be watched at once (UI-02).
        WindowGroup(id: MachineScreenWindow.identifier, for: URL.self) { $machineID in
            MachineScreenWindow(machineID: machineID)
                .environment(store)
        }
    }
}
