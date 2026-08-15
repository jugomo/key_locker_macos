import AppKit
import Carbon.HIToolbox
import IOKit.pwr_mgt

/// Owns the global `CGEventTap` that blocks keyboard/mouse/trackpad input
/// while the lock is engaged, and drives the toast + unlock-prompt UI.
///
/// Design notes:
/// - While locked, the tap callback returns `nil` for every ordinary
///   keyboard/mouse/trackpad event -- nothing is ever passed through to
///   other apps or to the system there. The one deliberate exception is
///   hardware "system-defined" events (volume, brightness, media, the power
///   key): those are matched against an allow-list of specific media keys
///   in `handleSystemDefinedEvent`, and anything *not* on that list --
///   including the power key, whatever its real code turns out to be on
///   this Mac -- passes through untouched, so sleep/shutdown/restart/Lock
///   Screen always keep working no matter the lock state.
/// - The unlock password is typed "through" the tap: printable characters,
///   Delete, Return and Escape are decoded from the raw `CGEvent` inside the
///   callback and fed into an in-app buffer that only ever lives in memory.
///   No real AppKit window ever becomes key while locked, so there is no
///   window-focus path an app switch could hijack.
/// - Any physical keyboard/mouse/trackpad, regardless of USB or Bluetooth
///   transport, arrives through the same HID event stream that the tap
///   listens to, so no per-device handling is needed.
final class LockController {

    // Both the left and right Cmd key report the same `.maskCommand` flag,
    // so either one can be held to unlock.
    private static let commandKeyCodes: Set<Int64> = [Int64(kVK_Command), Int64(kVK_RightCommand)]
    private static let returnKeyCode: Int64 = Int64(kVK_Return)
    private static let keypadEnterKeyCode: Int64 = Int64(kVK_ANSI_KeypadEnter)
    private static let escapeKeyCode: Int64 = Int64(kVK_Escape)
    private static let deleteKeyCode: Int64 = Int64(kVK_Delete)
    private static let holdToUnlockDuration: TimeInterval = 3.0

    private static let lockedMessage = "Input is locked. Hold \u{2318} for 3s to unlock."
    private static let holdingMessage = "Keep holding \u{2318} to unlock\u{2026}"

    // NX_SYSDEFINED: hardware "special key" events -- volume, brightness,
    // mute, media playback, keyboard illumination, and the F1-F12 row while
    // in its default (Fn-less) media-key mode, including Mission
    // Control/Launchpad/Dashboard when mapped there. Public `CGEventType`
    // has no named case for this, so it's constructed from its raw value.
    private static let systemDefinedEventType = CGEventType(rawValue: 14)!

    // Allow-list of NX_KEYTYPE_* system-defined key codes (top 16 bits of
    // `NSEvent.data1`, when `subtype == NX_SUBTYPE_AUX_CONTROL_BUTTONS`) we
    // deliberately block. This is intentionally an allow-list rather than a
    // deny-list: any system-defined event we *don't* recognize -- wrong
    // subtype, unrecognized code, or the power key under whatever code this
    // particular Mac reports it as -- passes through untouched by default.
    // The power key's exact code/subtype isn't reliably documented across
    // Mac hardware generations (notably the Touch ID/power button on Apple
    // Silicon Macs, which this app must never be able to block), so rather
    // than gamble on recognizing *it*, we only ever gamble on recognizing
    // the ordinary consumer media keys we actually want to intercept.
    private static let blockedSystemDefinedKeyCodes: Set<Int64> = [
        0,  // NX_KEYTYPE_SOUND_UP
        1,  // NX_KEYTYPE_SOUND_DOWN
        2,  // NX_KEYTYPE_BRIGHTNESS_UP
        3,  // NX_KEYTYPE_BRIGHTNESS_DOWN
        7,  // NX_KEYTYPE_MUTE
        13, // NX_KEYTYPE_LAUNCH_PANEL (Dashboard/Launchpad)
        14, // NX_KEYTYPE_EJECT
        15, // NX_KEYTYPE_VIDMIRROR
        16, // NX_KEYTYPE_PLAY
        17, // NX_KEYTYPE_NEXT
        18, // NX_KEYTYPE_PREVIOUS
        19, // NX_KEYTYPE_FAST
        20, // NX_KEYTYPE_REWIND
        21, // NX_KEYTYPE_ILLUMINATION_UP
        22, // NX_KEYTYPE_ILLUMINATION_DOWN
        23  // NX_KEYTYPE_ILLUMINATION_TOGGLE
    ]

    private(set) var isLocked = false
    private var isPromptVisible = false
    private var passwordBuffer = ""

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var holdToUnlockTimer: Timer?
    private var holdToUnlockStart: Date?

    private var powerAssertionID: IOPMAssertionID = 0
    private var powerAssertionActive = false

    private let toast = ToastWindow()
    private let prompt = PromptWindow()
    private let blurOverlay = BlurOverlay()

    /// Called whenever `isLocked` changes, so the status bar icon can update.
    var onLockStateChanged: ((Bool) -> Void)?

    // MARK: - Public API

    enum ActivationFailure: Error {
        case noPasswordSet
        case permissionDenied
    }

    /// Attempts to engage the lock. Returns `.failure` without doing anything
    /// if no unlock password has been configured yet, or if the process does
    /// not (yet) have Accessibility / Input Monitoring permission.
    @discardableResult
    func activateLock() -> Result<Void, ActivationFailure> {
        guard !isLocked else { return .success(()) }
        guard PasswordStore.hasPasswordSet() else { return .failure(.noPasswordSet) }
        guard requestPermissionIfNeeded() else { return .failure(.permissionDenied) }
        guard createEventTap() else { return .failure(.permissionDenied) }

        beginPowerAssertion()
        isLocked = true
        passwordBuffer = ""
        isPromptVisible = false
        onLockStateChanged?(true)
        toast.show(Self.lockedMessage)
        return .success(())
    }

    private func deactivateLock() {
        guard isLocked else { return }
        cancelHoldToUnlock()
        destroyEventTap()
        endPowerAssertion()
        isLocked = false
        isPromptVisible = false
        passwordBuffer = ""
        prompt.hide()
        blurOverlay.hide()
        toast.hide()
        onLockStateChanged?(false)
    }

    // MARK: - Permission

    private func requestPermissionIfNeeded() -> Bool {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // MARK: - Event tap lifecycle

    private func createEventTap() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << Self.systemDefinedEventType.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: lockControllerEventTapCallback,
            userInfo: refcon
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func destroyEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    /// Called by the C callback when the tap gets disabled by the system
    /// (e.g. after a timeout under heavy load) so we can re-enable it --
    /// otherwise input would silently stop being blocked.
    fileprivate func reEnableTapIfNeeded() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: - Power assertion (keep the display awake while locked)

    private func beginPowerAssertion() {
        guard !powerAssertionActive else { return }
        let reason = "KeyLocker input lock is active" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &powerAssertionID
        )
        powerAssertionActive = (result == kIOReturnSuccess)
    }

    private func endPowerAssertion() {
        guard powerAssertionActive else { return }
        IOPMAssertionRelease(powerAssertionID)
        powerAssertionActive = false
    }

    // MARK: - Event handling (called from the C callback, main thread)

    /// Returns whether `event` should be swallowed (blocked). The power key
    /// is the one input this app must never touch -- returning `false` for
    /// it tells the trampoline to let the system handle it exactly as if
    /// KeyLocker weren't running, regardless of lock state.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        guard isLocked else { return false }

        switch type {
        case .keyDown, .keyUp, .flagsChanged:
            handleKeyEvent(type: type, event: event)
            return true
        case Self.systemDefinedEventType:
            return handleSystemDefinedEvent(event: event)
        default:
            handleMouseEvent()
            return true
        }
    }

    private func handleMouseEvent() {
        guard !isPromptVisible else { return }
        toast.show(Self.lockedMessage)
    }

    /// Handles hardware "special key" events -- volume, brightness, media
    /// playback, and the F-row in its default media-key mode. These never
    /// arrive as `keyDown`/`keyUp`, so they need their own decoding path.
    /// Returns whether the event should be swallowed.
    private func handleSystemDefinedEvent(event: CGEvent) -> Bool {
        guard let nsEvent = NSEvent(cgEvent: event) else { return false }
        let keyCode = Int64((nsEvent.data1 & 0xFFFF0000) >> 16)

        // Only ever block events we can positively identify as one of the
        // specific media keys above. Everything else -- including the power
        // key, whatever its real code/subtype turns out to be on this Mac --
        // is passed through untouched. See the allow-list comment for why.
        guard nsEvent.subtype.rawValue == 8, // NX_SUBTYPE_AUX_CONTROL_BUTTONS
              Self.blockedSystemDefinedKeyCodes.contains(keyCode) else {
            return false
        }

        guard !isPromptVisible else { return true }
        let keyState = (nsEvent.data1 & 0xFF00) >> 8
        guard keyState == 0x0A else { return true } // key-down phase only; still swallow key-up silently
        cancelHoldToUnlock()
        toast.show(Self.lockedMessage)
        return true
    }

    private func handleKeyEvent(type: CGEventType, event: CGEvent) {
        if isPromptVisible {
            guard type == .keyDown else { return }
            handlePromptKeyDown(event: event)
            return
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .flagsChanged, Self.commandKeyCodes.contains(keyCode) {
            // Cmd (either side) has no keyDown/keyUp of its own -- its state
            // is reported as a flag on `flagsChanged` events instead. The
            // flag reflects whether *any* Cmd key is currently held, so this
            // naturally handles holding one side while releasing the other.
            let isCommandDown = event.flags.contains(.maskCommand)
            if isCommandDown {
                if holdToUnlockTimer == nil {
                    beginHoldToUnlock()
                }
            } else if holdToUnlockTimer != nil {
                // Released before the hold completed -- counts as a normal
                // blocked key press.
                cancelHoldToUnlock()
                toast.show(Self.lockedMessage)
            }
            return
        }

        guard type == .keyDown else { return }
        cancelHoldToUnlock()
        toast.show(Self.lockedMessage)
    }

    // MARK: - Hold-Cmd-to-unlock

    private func beginHoldToUnlock() {
        holdToUnlockStart = Date()
        toast.show(Self.holdingMessage, autoHide: false)
        let timer = Timer(timeInterval: Self.holdToUnlockDuration, repeats: false) { [weak self] _ in
            self?.holdToUnlockCompleted()
        }
        holdToUnlockTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelHoldToUnlock() {
        holdToUnlockTimer?.invalidate()
        holdToUnlockTimer = nil
        holdToUnlockStart = nil
    }

    private func holdToUnlockCompleted() {
        holdToUnlockTimer = nil
        holdToUnlockStart = nil
        toast.hide()
        showPrompt()
    }

    // MARK: - Password prompt

    private func showPrompt() {
        isPromptVisible = true
        passwordBuffer = ""
        blurOverlay.show()
        prompt.show()
    }

    private func handlePromptKeyDown(event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        switch keyCode {
        case Self.returnKeyCode, Self.keypadEnterKeyCode:
            submitPassword()
        case Self.escapeKeyCode:
            cancelPrompt()
        case Self.deleteKeyCode:
            if !passwordBuffer.isEmpty {
                passwordBuffer.removeLast()
                prompt.setTypedLength(passwordBuffer.count)
            }
        default:
            if let character = printableCharacter(from: event) {
                passwordBuffer.append(character)
                prompt.setTypedLength(passwordBuffer.count)
            }
        }
    }

    private func printableCharacter(from event: CGEvent) -> String? {
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .keyDown else { return nil }
        guard let characters = nsEvent.characters, !characters.isEmpty else { return nil }
        // Reject control characters (arrow keys, function keys, etc.) --
        // only accept "normal" typable text.
        for scalar in characters.unicodeScalars {
            if scalar.properties.generalCategory == .control { return nil }
        }
        return characters
    }

    private func submitPassword() {
        if PasswordStore.verify(passwordBuffer) {
            deactivateLock()
        } else {
            passwordBuffer = ""
            prompt.setTypedLength(0)
            prompt.showError("Incorrect password")
        }
    }

    private func cancelPrompt() {
        isPromptVisible = false
        passwordBuffer = ""
        prompt.hide()
        blurOverlay.hide()
        toast.show(Self.lockedMessage)
    }
}

/// C-compatible trampoline required by `CGEvent.tapCreate`. Forwards to the
/// `LockController` instance passed in `userInfo`.
private func lockControllerEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return nil }
    let controller = Unmanaged<LockController>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        controller.reEnableTapIfNeeded()
        return nil
    }

    let shouldSwallow = controller.handle(type: type, event: event)
    // Swallow everything while locked, except the handful of events (namely
    // the power key) `handle(type:event:)` explicitly opts out of. A no-op
    // (unlocked) controller reports `false` for everything, passing it all
    // through untouched.
    return shouldSwallow ? nil : Unmanaged.passUnretained(event)
}
