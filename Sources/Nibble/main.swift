import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var state: AppState!
    var statusController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let state = AppState()
            let panel = NSHostingController(rootView: UsagePanelView(state: state))
            // Without this the popover keeps a default size and crops the content.
            panel.sizingOptions = [.preferredContentSize]
            statusController = StatusItemController(state: state, panel: panel)
            self.state = state
            state.start()
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
