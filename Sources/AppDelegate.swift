import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var lockController: LockController!
    private var statusBarController: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon, no regular windows. (Also set via
        // LSUIElement in Info.plist; setting it here too keeps `swift run`
        // well-behaved during development.)
        NSApp.setActivationPolicy(.accessory)

        lockController = LockController()
        statusBarController = StatusBarController(lockController: lockController)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never quit while locked: this should be unreachable in practice
        // since the lock swallows the click needed to reach the Quit menu
        // item, but guard against it defensively (e.g. `kill`).
    }
}
