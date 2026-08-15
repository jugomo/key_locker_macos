import AppKit

/// Ordinary (non-locked-context) window used to set or change the unlock
/// password. This runs while the lock is *not* engaged, so it uses normal
/// AppKit focus and text fields -- no need for the CGEventTap trickery that
/// `LockController` uses while locked.
final class SetPasswordWindow: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var newField: NSSecureTextField!
    private var confirmField: NSSecureTextField!
    private var statusLabel: NSTextField!

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let width: CGFloat = 320
        let height: CGFloat = 190
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Set Unlock Password"
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self

        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let newLabel = NSTextField(labelWithString: "New password:")
        newLabel.frame = NSRect(x: 20, y: height - 40, width: 120, height: 20)
        content.addSubview(newLabel)

        newField = NSSecureTextField(frame: NSRect(x: 140, y: height - 42, width: width - 160, height: 24))
        content.addSubview(newField)

        let confirmLabel = NSTextField(labelWithString: "Confirm password:")
        confirmLabel.frame = NSRect(x: 20, y: height - 76, width: 120, height: 20)
        content.addSubview(confirmLabel)

        confirmField = NSSecureTextField(frame: NSRect(x: 140, y: height - 78, width: width - 160, height: 24))
        content.addSubview(confirmField)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.textColor = .systemRed
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.frame = NSRect(x: 20, y: height - 104, width: width - 40, height: 18)
        content.addSubview(statusLabel)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelButton.frame = NSRect(x: width - 190, y: 16, width: 80, height: 28)
        cancelButton.keyEquivalent = "\u{1b}" // Escape
        content.addSubview(cancelButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        saveButton.frame = NSRect(x: width - 100, y: 16, width: 80, height: 28)
        saveButton.keyEquivalent = "\r" // Return
        saveButton.bezelStyle = .rounded
        content.addSubview(saveButton)

        win.contentView = content
        win.initialFirstResponder = newField

        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func saveTapped() {
        let new = newField.stringValue
        let confirm = confirmField.stringValue

        guard !new.isEmpty else {
            statusLabel.stringValue = "Password cannot be empty."
            return
        }
        guard new == confirm else {
            statusLabel.stringValue = "Passwords do not match."
            return
        }
        guard PasswordStore.setPassword(new) else {
            statusLabel.stringValue = "Could not save password to Keychain."
            return
        }

        window?.close()
    }

    @objc private func cancelTapped() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        newField.stringValue = ""
        confirmField.stringValue = ""
        statusLabel.stringValue = ""
    }
}
