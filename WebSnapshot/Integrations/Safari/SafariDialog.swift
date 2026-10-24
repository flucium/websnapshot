import AppKit

@MainActor
func prepareForSafariDialog() {
    if NSApp.isHidden {
        for window in NSApp.windows where !(window is NSPanel) {
            window.orderOut(nil)
        }
        NSApp.unhide(nil)
    }
    NSApp.activate(ignoringOtherApps: true)
}
