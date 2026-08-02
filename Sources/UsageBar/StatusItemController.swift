import AppKit
import Combine
import UsageBarCore

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

        state.$windows.combineLatest(state.$needsSetup)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] windows, needsSetup in self?.render(windows, needsSetup: needsSetup) }
            .store(in: &cancellables)

        render(state.windows, needsSetup: state.needsSetup)
    }

    private func render(_ windows: [LimitWindow], needsSetup: Bool) {
        let text = needsSetup ? "✳ Connect" : "✳ " + Formatting.barText(windows)
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
            state.refreshNow()
            state.rescanHistoryIfDue(force: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
