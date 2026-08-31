import AppKit

/// Settings window: set/change the unlock password, and configure whether a
/// full-screen "Matrix code" rain animation is shown while the lock is
/// engaged, over either a solid black background or the blurred desktop.
///
/// This runs while the lock is *not* engaged, so it uses normal AppKit focus
/// and text fields -- no need for the CGEventTap trickery that
/// `LockController` uses while locked.
final class SettingsWindow: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var newField: NSSecureTextField!
    private var confirmField: NSSecureTextField!
    private var statusLabel: NSTextField!

    private var matrixCheckbox: NSButton!
    private var blackRadio: NSButton!
    private var blurRadio: NSButton!
    private var blurSolidRadio: NSButton!

    func show() {
        if let window = window {
            refreshMatrixControls()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let width: CGFloat = 340
        let height: CGFloat = 380
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Settings"
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self

        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let passwordHeader = NSTextField(labelWithString: "Unlock Password")
        passwordHeader.font = NSFont.boldSystemFont(ofSize: 12)
        passwordHeader.frame = NSRect(x: 20, y: 350, width: width - 40, height: 18)
        content.addSubview(passwordHeader)

        let newLabel = NSTextField(labelWithString: "New password:")
        newLabel.frame = NSRect(x: 20, y: 320, width: 120, height: 20)
        content.addSubview(newLabel)

        newField = NSSecureTextField(frame: NSRect(x: 140, y: 318, width: width - 160, height: 24))
        content.addSubview(newField)

        let confirmLabel = NSTextField(labelWithString: "Confirm password:")
        confirmLabel.frame = NSRect(x: 20, y: 284, width: 120, height: 20)
        content.addSubview(confirmLabel)

        confirmField = NSSecureTextField(frame: NSRect(x: 140, y: 282, width: width - 160, height: 24))
        content.addSubview(confirmField)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.textColor = .systemRed
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.frame = NSRect(x: 20, y: 254, width: width - 40, height: 18)
        content.addSubview(statusLabel)

        let saveButton = NSButton(title: "Save Password", target: self, action: #selector(saveTapped))
        saveButton.frame = NSRect(x: 20, y: 224, width: 150, height: 28)
        saveButton.bezelStyle = .rounded
        content.addSubview(saveButton)

        let divider = NSBox(frame: NSRect(x: 20, y: 184, width: width - 40, height: 1))
        divider.boxType = .separator
        content.addSubview(divider)

        let matrixHeader = NSTextField(labelWithString: "Matrix Effect")
        matrixHeader.font = NSFont.boldSystemFont(ofSize: 12)
        matrixHeader.frame = NSRect(x: 20, y: 158, width: width - 40, height: 18)
        content.addSubview(matrixHeader)

        matrixCheckbox = NSButton(
            checkboxWithTitle: "Show matrix code when locked",
            target: self,
            action: #selector(matrixCheckboxTapped)
        )
        matrixCheckbox.frame = NSRect(x: 20, y: 130, width: width - 40, height: 20)
        content.addSubview(matrixCheckbox)

        blackRadio = NSButton(
            radioButtonWithTitle: "Solid black background",
            target: self,
            action: #selector(radioTapped)
        )
        blackRadio.frame = NSRect(x: 40, y: 102, width: width - 60, height: 20)
        content.addSubview(blackRadio)

        blurRadio = NSButton(
            radioButtonWithTitle: "Blurred screen content (more transparent)",
            target: self,
            action: #selector(radioTapped)
        )
        blurRadio.frame = NSRect(x: 40, y: 78, width: width - 60, height: 20)
        content.addSubview(blurRadio)

        blurSolidRadio = NSButton(
            radioButtonWithTitle: "Blurred screen content (less transparent)",
            target: self,
            action: #selector(radioTapped)
        )
        blurSolidRadio.frame = NSRect(x: 40, y: 54, width: width - 60, height: 20)
        content.addSubview(blurSolidRadio)

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeTapped))
        closeButton.frame = NSRect(x: width - 100, y: 16, width: 80, height: 28)
        closeButton.keyEquivalent = "\r" // Return
        closeButton.bezelStyle = .rounded
        content.addSubview(closeButton)

        win.contentView = content
        win.initialFirstResponder = newField

        window = win
        refreshMatrixControls()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshMatrixControls() {
        let enabled = AppSettings.showMatrixWhenLocked
        matrixCheckbox.state = enabled ? .on : .off
        blackRadio.isEnabled = enabled
        blurRadio.isEnabled = enabled
        blurSolidRadio.isEnabled = enabled

        let mode = AppSettings.matrixBackgroundMode
        blackRadio.state = mode == .black ? .on : .off
        blurRadio.state = mode == .screenBlur ? .on : .off
        blurSolidRadio.state = mode == .screenBlurSolid ? .on : .off
    }

    @objc private func matrixCheckboxTapped() {
        let enabled = matrixCheckbox.state == .on
        AppSettings.showMatrixWhenLocked = enabled
        blackRadio.isEnabled = enabled
        blurRadio.isEnabled = enabled
        blurSolidRadio.isEnabled = enabled
    }

    @objc private func radioTapped(_ sender: NSButton) {
        let mode: MatrixBackgroundMode
        switch sender {
        case blackRadio: mode = .black
        case blurRadio: mode = .screenBlur
        default: mode = .screenBlurSolid
        }
        AppSettings.matrixBackgroundMode = mode
        blackRadio.state = mode == .black ? .on : .off
        blurRadio.state = mode == .screenBlur ? .on : .off
        blurSolidRadio.state = mode == .screenBlurSolid ? .on : .off
    }

    @objc private func saveTapped() {
        let new = newField.stringValue
        let confirm = confirmField.stringValue

        guard !new.isEmpty else {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "Password cannot be empty."
            return
        }
        guard new == confirm else {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "Passwords do not match."
            return
        }
        guard PasswordStore.setPassword(new) else {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "Could not save password to Keychain."
            return
        }

        statusLabel.textColor = .systemGreen
        statusLabel.stringValue = "Password saved."
        newField.stringValue = ""
        confirmField.stringValue = ""
    }

    @objc private func closeTapped() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        newField.stringValue = ""
        confirmField.stringValue = ""
        statusLabel.stringValue = ""
        statusLabel.textColor = .systemRed
    }
}
