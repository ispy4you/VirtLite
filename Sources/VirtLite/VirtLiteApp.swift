import SwiftUI

@main
struct VirtLiteApp: App {
    var body: some Scene {
        WindowGroup("VirtLite") {
            MachineListView()
        }
        .defaultSize(width: 900, height: 560)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
