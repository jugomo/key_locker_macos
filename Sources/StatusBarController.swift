import AppKit

/// Manages the menu bar (status) item: icon, and the right-click menu with
/// "Activate Lock", "Set Unlock Password...", and "Quit".
final class StatusBarController {

    private let statusItem: NSStatusItem
    private let lockController: LockController
    private let setPasswordWindow = SetPasswordWindow()

    private let lockedImage = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked")
    private let unlockedImage = NSImage(systemSymbolName: "lock.open", accessibilityDescription: "Unlocked")

    init(lockController: LockController) {
        self.lockController = lockController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        configureIcon(locked: false)
        statusItem.menu = buildMenu()

        lockController.onLockStateChanged = { [weak self] locked in
            self?.configureIcon(locked: locked)
        }
    }

    private func configureIcon(locked: Bool) {
        guard let button = statusItem.button else { return }
        button.image = locked ? lockedImage : unlockedImage
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let activateItem = NSMenuItem(
            title: "Activate Lock",
            action: #selector(activateLockTapped),
            keyEquivalent: ""
        )
        activateItem.target = self
        menu.addItem(activateItem)

        let setPasswordItem = NSMenuItem(
            title: "Set Unlock Password\u{2026}",
            action: #selector(setPasswordTapped),
            keyEquivalent: ""
        )
        setPasswordItem.target = self
        menu.addItem(setPasswordItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: "About KeyLocker\u{2026}",
            action: #selector(aboutTapped),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit KeyLocker",
            action: #selector(quitTapped),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func activateLockTapped() {
        switch lockController.activateLock() {
        case .success:
            break
        case .failure(.noPasswordSet):
            showAlert(
                title: "No Unlock Password Set",
                message: "Set an unlock password first (\"Set Unlock Password\u{2026}\") before activating the lock.",
                style: .warning
            )
        case .failure(.permissionDenied):
            showPermissionAlert()
        }
    }

    @objc private func setPasswordTapped() {
        setPasswordWindow.show()
    }

    @objc private func aboutTapped() {
        NSApp.activate(ignoringOtherApps: true)
        // Copyright/credits text comes solely from NSHumanReadableCopyright
        // in Info.plist -- the standard About panel already renders that
        // automatically, so passing a separate .credits string here would
        // show the same line twice.
        NSApp.orderFrontStandardAboutPanel(options: [:])
    }

    @objc private func quitTapped() {
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        KeyLocker needs Accessibility (and Input Monitoring) permission to block keyboard and trackpad input.

        Open System Settings \u{2192} Privacy & Security \u{2192} Accessibility, enable KeyLocker, then try again.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
}
