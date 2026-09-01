import AppKit
import Carbon.HIToolbox

/// Drives the "View Code" menu item: shows the same Matrix rain backdrop as
/// the lock screen, purely as a visual effect -- unlike
/// `LockController.activateLock()`, this never blocks the keyboard, trackpad
/// or mouse, and needs no unlock password.
///
/// A passive (`.listenOnly`) `CGEventTap` -- as opposed to the lock's
/// blocking tap -- watches for two things without ever swallowing an event:
/// a quick Cmd tap, which cycles the backdrop through its three modes, and
/// Esc, which closes the view. Everything else passes through to whatever
/// app is actually in front, exactly as if this tap didn't exist.
final class CodeViewController {

    // Both the left and right Cmd key report the same `.maskCommand` flag,
    // so either one cycles the mode.
    private static let commandKeyCodes: Set<Int64> = [Int64(kVK_Command), Int64(kVK_RightCommand)]
    private static let escapeKeyCode: Int64 = Int64(kVK_Escape)

    // Unlike the lock's cycle (`LockController.matrixCycleModes`), there's no
    // "off" entry here -- closing the view entirely is Esc's job, not the
    // Cmd cycle's.
    private static let cycleModes: [MatrixBackgroundMode] = [.black, .screenBlur, .screenBlurSolid]

    private static let hintMessage = "\u{2318} to change style \u{00B7} Esc to close"
    private static let modeMessages: [MatrixBackgroundMode: String] = [
        .black: "Code view: Black background",
        .screenBlur: "Code view: Blurred (more transparent)",
        .screenBlurSolid: "Code view: Blurred (less transparent)"
    ]

    // NX_SYSDEFINED, same as `LockController`; unused here beyond mirroring
    // the tap's event mask isn't needed -- this tap only ever asks for
    // keyDown/flagsChanged.
    private static let systemDefinedEventType = CGEventType(rawValue: 14)!

    enum StartFailure: Error {
        case permissionDenied
    }

    private(set) var isVisible = false
    private var cycleIndex = 0
    private var isCommandDown = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let overlay = MatrixRainOverlay()
    private let toast = ToastWindow()

    /// Called whenever `isVisible` changes, so the status bar menu item can
    /// update its title.
    var onStateChanged: ((Bool) -> Void)?

    // MARK: - Public API

    @discardableResult
    func start() -> Result<Void, StartFailure> {
        guard !isVisible else { return .success(()) }
        guard requestPermissionIfNeeded() else { return .failure(.permissionDenied) }
        guard createEventTap() else { return .failure(.permissionDenied) }

        isVisible = true
        isCommandDown = false
        cycleIndex = Self.cycleModes.firstIndex(of: AppSettings.matrixBackgroundMode) ?? 0
        overlay.show(mode: Self.cycleModes[cycleIndex])
        toast.show(Self.hintMessage, duration: 2.5)
        onStateChanged?(true)
        return .success(())
    }

    func stop() {
        guard isVisible else { return }
        isVisible = false
        destroyEventTap()
        overlay.hide()
        toast.hide()
        onStateChanged?(false)
    }

    func toggle() -> Result<Void, StartFailure> {
        if isVisible {
            stop()
            return .success(())
        }
        return start()
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
            (1 << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            // Listen-only: this tap only ever observes, it never returns
            // `nil` to swallow an event -- that's what keeps "View Code"
            // free of the lock's input-blocking behavior.
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: codeViewEventTapCallback,
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
    /// (e.g. after a timeout under heavy load) so it can be re-enabled --
    /// otherwise Cmd/Esc would silently stop being observed.
    fileprivate func reEnableTapIfNeeded() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: - Event handling (called from the C callback, main thread)

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        guard isVisible else { return }

        switch type {
        case .flagsChanged:
            handleFlagsChanged(event: event)
        case .keyDown:
            handleKeyDown(event: event)
        default:
            break
        }
    }

    private func handleFlagsChanged(event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard Self.commandKeyCodes.contains(keyCode) else { return }

        let commandDown = event.flags.contains(.maskCommand)
        if commandDown {
            isCommandDown = true
        } else if isCommandDown {
            // A tap (down then up) of either Cmd key -- advance to the next
            // backdrop mode.
            isCommandDown = false
            cycleMode()
        }
    }

    private func handleKeyDown(event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == Self.escapeKeyCode else { return }
        stop()
    }

    private func cycleMode() {
        cycleIndex = (cycleIndex + 1) % Self.cycleModes.count
        let mode = Self.cycleModes[cycleIndex]
        overlay.show(mode: mode)
        toast.show(Self.modeMessages[mode] ?? "")
    }
}

/// C-compatible trampoline required by `CGEvent.tapCreate`. Forwards to the
/// `CodeViewController` instance passed in `userInfo`.
private func codeViewEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<CodeViewController>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        controller.reEnableTapIfNeeded()
        return Unmanaged.passUnretained(event)
    }

    controller.handle(type: type, event: event)
    // Listen-only taps ignore the returned event, but a real one is handed
    // back regardless, for symmetry with `LockController`'s callback.
    return Unmanaged.passUnretained(event)
}
