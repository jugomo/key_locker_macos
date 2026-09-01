import AppKit

/// Manages the menu bar (status) item: icon, and the right-click menu with
/// "Activate Lock", "View Code", "Settings...", and "Quit".
final class StatusBarController {

    private let statusItem: NSStatusItem
    private let lockController: LockController
    private let codeViewController = CodeViewController()
    private let settingsWindow = SettingsWindow()

    private let lockedImage = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked")
    private let unlockedImage = NSImage(systemSymbolName: "lock.open", accessibilityDescription: "Unlocked")

    private var viewCodeItem: NSMenuItem!

    init(lockController: LockController) {
        self.lockController = lockController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        configureIcon(locked: false)
        statusItem.menu = buildMenu()

        lockController.onLockStateChanged = { [weak self] locked in
            self?.configureIcon(locked: locked)
        }
        codeViewController.onStateChanged = { [weak self] visible in
            self?.viewCodeItem.title = visible ? "Stop Code View" : "View Code"
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
        activateItem.image = menuIcon(systemSymbolName: "lock.fill", accessibilityDescription: "Activate Lock")
        menu.addItem(activateItem)

        let viewCodeItem = NSMenuItem(
            title: "View Code",
            action: #selector(viewCodeTapped),
            keyEquivalent: ""
        )
        viewCodeItem.target = self
        viewCodeItem.image = menuIcon(
            systemSymbolName: "chevron.left.forwardslash.chevron.right",
            accessibilityDescription: "View Code"
        )
        menu.addItem(viewCodeItem)
        self.viewCodeItem = viewCodeItem

        let settingsItem = NSMenuItem(
            title: "Settings\u{2026}",
            action: #selector(settingsTapped),
            keyEquivalent: ""
        )
        settingsItem.target = self
        settingsItem.image = menuIcon(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: "About KeyLocker\u{2026}",
            action: #selector(aboutTapped),
            keyEquivalent: ""
        )
        aboutItem.target = self
        aboutItem.image = menuIcon(systemSymbolName: "info.circle", accessibilityDescription: "About KeyLocker")
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitTapped),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.image = menuIcon(systemSymbolName: "power", accessibilityDescription: "Quit")
        menu.addItem(quitItem)

        return menu
    }

    /// Builds a consistently-sized, template-rendered SF Symbol for use as a
    /// menu item's icon (so it tints correctly in both light and dark mode).
    private func menuIcon(systemSymbolName: String, accessibilityDescription: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: accessibilityDescription)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    @objc private func activateLockTapped() {
        // Avoid two Matrix rain overlays (and two Cmd-tap listeners) at
        // once -- the real lock takes priority over the code-view preview.
        codeViewController.stop()
        switch lockController.activateLock() {
        case .success:
            break
        case .failure(.noPasswordSet):
            showAlert(
                title: "No Unlock Password Set",
                message: "Set an unlock password first (\"Settings\u{2026}\") before activating the lock.",
                style: .warning
            )
        case .failure(.permissionDenied):
            showPermissionAlert()
        }
    }

    @objc private func viewCodeTapped() {
        // Should be unreachable in practice -- the lock swallows the click
        // needed to reach this menu item at all -- but guard defensively.
        guard !lockController.isLocked else { return }
        switch codeViewController.toggle() {
        case .success:
            break
        case .failure(.permissionDenied):
            showPermissionAlert()
        }
    }

    @objc private func settingsTapped() {
        settingsWindow.show()
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
