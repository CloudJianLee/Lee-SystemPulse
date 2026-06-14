import SwiftUI

@main
struct SystemPulseApp: App {
    @State private var monitor = SystemMonitor()

    var body: some Scene {
        MenuBarExtra {
            MonitorPopover(monitor: monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}
