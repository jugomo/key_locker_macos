# Key Locker macOS

A macOS menu bar utility that blocks keyboard, mouse, and trackpad input
until a password is typed, without ever covering or dimming the screen.
Whatever is on screen (including a full-screen video) keeps playing exactly
as before, only input is blocked. To unlock, hold the Cmd key for 3
seconds to bring up the password prompt, then type the password and press
Return.

## Ownership & contributing

This project was created by [@jugomo](https://github.com/jugomo) and is
licensed under the [MIT License](LICENSE). Anyone is welcome to use this
software at their own risk, copy or fork it as long as the original
author is credited, and contribute back, whether that's opening a pull
request or simply suggesting improvements via an issue. No warranty is
provided.

## Disclaimer

This project is a personal, educational experiment, with no commercial
intent. No binaries or compiled builds are distributed for this project,
only the source code. No support is provided, and use it under your own risk.

## How it works

- A global `CGEventTap` intercepts every keyboard, mouse, and trackpad event
  at the OS session level. Any physical device, built-in trackpad, USB
  mouse/keyboard or Bluetooth peripherals arrives through the same event
  stream, so all of them are blocked uniformly.
- While the lock is engaged, the tap discards ordinary keyboard/mouse/
  trackpad events; nothing is ever forwarded to other apps or the system.
  There is no bypass path (not even Cmd+Tab or clicking the menu bar icon)
  other than the unlock ritual below. The one deliberate exception is the
  physical power key, which is never touched, see Known limitations.
- Pressing any key or moving the mouse while locked shows a small floating
  toast: "Input is locked. Hold ⌘ for 3s to unlock."
- Holding the Cmd key (either side) for 3 continuous seconds brings up a
  floating, blurred full-screen overlay with a password prompt centered on
  it. Typed characters are decoded directly from the event tap
  (not via normal window focus) and shown as masked dots. Press Return to
  submit, or Esc to cancel back to the locked state.
- A correct password immediately restores normal input. An incorrect one
  shows an error and lets you retry.
- An IOKit power assertion keeps the display from sleeping/dimming while
  locked, since the system would otherwise see no input activity at all.
- The unlock password is never stored in plaintext: it's salted and hashed
  (SHA-256) into the Keychain.

## Menu bar

Click the lock icon for a menu with:

- **Activate Lock** Engages the lock. If no password has been set yet,
  you'll get a warning instead and the lock will *not* activate.
- **Set Unlock Password…** Set or change the password used to unlock.
- **About KeyLocker…** The standard macOS About panel, with copyright
  credit.
- **Quit KeyLocker** Quits the app (only reachable while unlocked, since
  the lock blocks clicks on the menu bar too).

## Building

```sh
./build.sh
```

This compiles the sources with `swiftc`, renders the app icon
(`Resources/make_icon.swift` → `AppIcon.icns`), and assembles
`build/KeyLocker.app`, ad-hoc signed. No Xcode project is needed, though you
can also just open the `Sources/` folder in Xcode if you'd rather build
there.

Run it:

```sh
open build/KeyLocker.app
```

Or copy `build/KeyLocker.app` to `/Applications` for regular use.

## Required permissions

The first time you activate the lock, macOS will prompt for **Accessibility**
access. You also need to grant **Input Monitoring**:

System Settings → Privacy & Security → Accessibility → enable KeyLocker
System Settings → Privacy & Security → Input Monitoring → enable KeyLocker

Without both, the event tap can't be created and "Activate Lock" will show a
permission warning with a shortcut to the right settings pane.

Because a global, input-blocking `CGEventTap` is not permitted inside the App
Sandbox, this app is distributed unsandboxed (direct build/run, not Mac App
Store).

## Known limitations

- Volume, brightness, media playback, and the F1-F12 row (in its default
  media-key mode) are blocked too -- they arrive as `NX_SYSDEFINED` events
  rather than ordinary keystrokes, and the event tap listens for those
  specifically.
- The physical **power key is deliberately excluded from the lock**, on
  every Mac including Apple Silicon models where it doubles as Touch ID.
  Rather than trying to specifically recognize the power key's event (its
  exact code/subtype isn't consistently documented across hardware
  generations) and pass just that through, the app does the opposite: it
  only ever blocks system-defined events matching a specific allow-list of
  ordinary consumer media keys (volume, brightness, mute, playback,
  keyboard illumination, eject, Launchpad/Dashboard). Anything not on that
  list, including the power key, under whatever code/subtype this
  particular Mac reports it as, passes through untouched by default. This
  is an intentional carve-out, not a gap.
- The password is captured from raw key events using the current keyboard
  layout's character mapping. Full IME composition (e.g. Pinyin, Kana) is
  not supported while locked, use a password made of directly-typable
  characters.
- If KeyLocker's process is force-killed at the OS level (e.g. via a
  privileged tool) while locked, input blocking stops since the event tap
  goes away with the process. This mirrors the trust model of any
  third-party lock utility: it protects against casual use of the keyboard/
  trackpad, not against a user with admin/root access working around it.
