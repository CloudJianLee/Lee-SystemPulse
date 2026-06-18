import AppKit
import SwiftUI

@main
struct SystemPulseApp: App {
    @State private var monitor = SystemMonitor()

    init() {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleID
        )
        if let existing = running.first(where: { $0.processIdentifier != getpid() }) {
            existing.activate()
            NSApp.terminate(nil)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MonitorPopover(monitor: monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}
