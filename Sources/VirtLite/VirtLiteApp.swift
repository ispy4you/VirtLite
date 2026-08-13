import SwiftUI

@main
struct VirtLiteApp: App {
    @State private var store = MachineStore()

    var body: some Scene {
        WindowGroup("VirtLite") {
            MachineListView()
                .environment(store)
        }
        .defaultSize(width: 900, height: 560)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // One window per running machine, so several guests can be watched at once (UI-02).
        WindowGroup(id: MachineScreenWindow.identifier, for: URL.self) { $machineID in
            MachineScreenWindow(machineID: machineID)
                .environment(store)
        }
    }
}
