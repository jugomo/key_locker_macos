import Foundation

/// What the Matrix-rain overlay paints behind the falling glyphs while
/// locked: either a plain black backdrop, or the user's own desktop content
/// showing through a blur mask (same look as the unlock-prompt scrim), in
/// either of two opacities.
enum MatrixBackgroundMode: String {
    case black
    case screenBlur
    case screenBlurSolid
}

/// Small `UserDefaults`-backed store for the user-facing preferences exposed
/// in the Settings window. Unlike the unlock password (kept in the Keychain,
/// see `PasswordStore`), these are just display preferences, so plain
/// `UserDefaults` is appropriate.
enum AppSettings {

    private static let showMatrixKey = "showMatrixWhenLocked"
    private static let matrixModeKey = "matrixBackgroundMode"

    /// Whether the Matrix-code rain animation should cover the screen(s)
    /// while the lock is engaged (and no unlock prompt is on screen).
    static var showMatrixWhenLocked: Bool {
        get { UserDefaults.standard.bool(forKey: showMatrixKey) }
        set { UserDefaults.standard.set(newValue, forKey: showMatrixKey) }
    }

    /// Which background the rain is drawn over. Only meaningful when
    /// `showMatrixWhenLocked` is true. Defaults to `.black`.
    static var matrixBackgroundMode: MatrixBackgroundMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: matrixModeKey),
                  let mode = MatrixBackgroundMode(rawValue: raw) else {
                return .black
            }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: matrixModeKey) }
    }
}
