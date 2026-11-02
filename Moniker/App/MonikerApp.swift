import AppKit
import Observation
import SwiftUI

@main
struct MonikerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The menu bar item is managed by AppDelegate (AppKit), which handles a
        // live-updating status item more reliably than MenuBarExtra.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(model: model)
        model.launch()
    }

    /// Opening Moniker again (Finder, Spotlight) shows the panel, in case the icon hides behind the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem?.showPopover()
        return true
    }
}

/// The menu bar item: a tag, sparkles while reading a file. Click opens MenuPanel.
@MainActor
final class StatusItemController: NSObject {
    private let model: AppModel
    private let item: NSStatusItem
    private let popover = NSPopover()

    init(model: AppModel) {
        self.model = model
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        item.autosaveName = "MonikerStatusItem"
        if let button = item.button {
            button.target = self
            button.action = #selector(toggle(_:))
            button.toolTip = "Moniker"
        }

        let hosting = NSHostingController(rootView: MenuPanel().environment(model))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true

        observe()
    }

    func showPopover() {
        guard !popover.isShown, let button = item.button else { return }
        model.refreshAvailability()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate()
    }

    @objc private func toggle(_ sender: Any?) {
        if popover.isShown { popover.performClose(sender) } else { showPopover() }
    }

    /// Re-renders whenever anything the icon reads changes.
    private func observe() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func render() {
        guard let button = item.button else { return }
        let symbol: String
        if model.isWorking {
            symbol = "sparkles"
        } else if !model.pending.isEmpty {
            symbol = "tag.circle.fill"
        } else if model.isWatching, model.availabilityProblem == nil {
            symbol = "tag"
        } else {
            symbol = "tag.slash"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Moniker")
        image?.isTemplate = true
        button.image = image
    }
}
