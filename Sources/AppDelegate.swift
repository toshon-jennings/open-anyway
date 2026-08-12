import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let store = BlockedAppStore()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
            button.addSubview(DropZone(frame: button.bounds) { [weak self] urls in
                urls.forEach { self?.store.unblock(at: $0) }
            })
        }

        popover.behavior = .transient
        let hosting = NSHostingController(
            rootView: PopoverView(
                store: store,
                onChooseApp: { [weak self] in self?.chooseApp() },
                onOpenSettings: { Self.openPrivacyAndSecurity() },
                onQuit: { NSApp.terminate(nil) }
            )
        )
        // Without this the popover picks its own size, which doesn't match the
        // SwiftUI content — the content ends up offset inside the window and
        // its leading edge clips away against the popover's rounded mask.
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting

        // The icon carries the alert, so a blocked app is noticeable without
        // opening anything.
        store.$apps.combineLatest(store.$isScanning)
            .receive(on: RunLoop.main)
            .sink { [weak self] apps, isScanning in
                self?.updateIcon(blockedCount: apps.count, isScanning: isScanning)
            }
            .store(in: &cancellables)

        updateIcon(blockedCount: 0, isScanning: true)
        store.scan()
    }

    private func updateIcon(blockedCount: Int, isScanning: Bool) {
        guard let button = statusItem.button else { return }

        let symbol: String
        let description: String

        if blockedCount > 0 {
            symbol = "lock.open.fill"
            description = "\(blockedCount) blocked app(s)"
        } else if isScanning {
            // A cold scan runs for ~15s. Showing the closed padlock before it
            // finishes reads as a confident "nothing blocked" that isn't known
            // yet — and the user has no way to tell the two states apart.
            symbol = "hourglass"
            description = "Checking for blocked apps…"
        } else {
            symbol = "lock.fill"
            description = "Open Anyway"
        }

        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        button.image?.isTemplate = true
        button.toolTip = description
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        store.scan()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func chooseApp() {
        popover.performClose(nil)

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Unblock"
        panel.message = "Choose an app to remove the Gatekeeper block from."

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.unblock(at: url)
    }

    /// The original destination, kept as an escape hatch for anything the app
    /// can't resolve itself.
    private static func openPrivacyAndSecurity() {
        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")!
        NSWorkspace.shared.open(url)
    }
}

/// Transparent view over the status item button that accepts dropped bundles,
/// so an app can be unblocked without opening the popover at all.
private final class DropZone: NSView {
    private let onDrop: @MainActor ([URL]) -> Void

    init(frame: NSRect, onDrop: @escaping @MainActor ([URL]) -> Void) {
        self.onDrop = onDrop
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func appBundles(in sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.application.identifier],
        ]
        let objects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options)
        return (objects as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        appBundles(in: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = appBundles(in: sender)
        guard !urls.isEmpty else { return false }
        onDrop(urls)
        return true
    }
}
