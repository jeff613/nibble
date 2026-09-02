import AppKit
import Combine
import NibbleCore

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private let state: AppState

    init(state: AppState, panel: NSViewController) {
        self.state = state
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover.contentViewController = panel
        popover.behavior = .transient

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        // Template image so AppKit tints it for light and dark menu bars.
        // Absent when running unbundled via `swift run`; the text stands alone.
        if let icon = NSImage(named: "MenuBarIcon") {
            icon.isTemplate = true
            statusItem.button?.image = icon
            statusItem.button?.imagePosition = .imageLeading
        }

        state.$windows.combineLatest(state.$needsSetup, state.$selectedBarProvider)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] windows, needsSetup, provider in
                self?.render(windows, needsSetup: needsSetup, provider: provider)
            }
            .store(in: &cancellables)

        render(state.windows, needsSetup: state.needsSetup, provider: state.selectedBarProvider)
    }

    private func render(_ windows: [LimitWindow], needsSetup: Bool, provider: Provider) {
        let hasIcon = statusItem.button?.image != nil
        let label = needsSetup ? "Connect" : Formatting.barText(windows, provider: provider)
        let text = hasIcon ? " \(label)" : "🍪 \(label)"
        let color: NSColor
        switch Formatting.severity(windows) {
        case .normal: color = .labelColor
        case .warning: color = .systemOrange
        case .critical: color = .systemRed
        }
        statusItem.button?.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            ])
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            state.panelOpened()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
