import AppKit

// A menu bar app: no Dock icon (LSUIElement in the Info.plist), never the active app while the
// search panel is up.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
