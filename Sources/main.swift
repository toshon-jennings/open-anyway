import AppKit

// Held at top level because NSApplication doesn't retain its delegate.
let delegate = MainActor.assumeIsolated { AppDelegate() }

MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.delegate = delegate
    application.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
    application.run()
}
