# Blackout

A native macOS 26+ menu bar app that covers selected displays, including the primary or only monitor with pure black or a Tahoe-inspired decorative lock screen. Built with Swift 6, AppKit, SwiftUI, and Carbon; no external dependencies or network access.

## Build and run

Requires macOS 26+ and Xcode 26.3+ (Swift 6.2 or newer).

Open `Blackout.xcodeproj`, select the **Blackout** scheme and **My Mac**, and choose Product → Run. No paid developer account is needed for a local build; the project uses ad-hoc signing.

From the repository root:

```sh
rtk proxy xcodebuild -project Blackout.xcodeproj -scheme Blackout \
  -configuration Debug -derivedDataPath build build
rtk proxy open build/Build/Products/Debug/Blackout.app
```

If RTK is not installed, omit `rtk proxy`. The built app can also be opened directly in Finder. This is a local development build, not a notarized distribution package.

Run the unit tests separately through Swift Package Manager (the Xcode app scheme builds the app):

```sh
rtk proxy swift test
```

## Use

1. Settings opens on first launch. Select one or more displays, including the primary. Mirrored displays are disabled because they cannot be covered independently.
2. Choose **Black** or **Lock Screen**. The choice applies to every selected display. Lock Screen uses an original alpine landscape, a large translucent clock, and a decorative password field. Use **Wallpaper → Choose Image…** to pick a local image. The image fills each display with centered cropping. Blackout keeps a downsampled copy (up to 4096 pixels on the longest edge) in Application Support, so the original can be moved or deleted; **Reset** restores the built-in background. Invalid images leave the previous wallpaper unchanged. The lock screen shows no unlock shortcut hint; the configured shortcut remains active.
3. Use **Cover Displays** in settings or the menu bar, or press **Control–Option–Command–B**. Press the shortcut again or choose **Uncover Displays** to remove the covers.
4. To change the shortcut, choose **Record Shortcut…**, then press Command or Control plus a letter, number, or F1–F12. Escape cancels. **Reset** restores the default. Keys use physical US keyboard positions; Caps Lock/keypad/Fn+letter combinations are unsupported.

When you cover the primary display, its menu and settings are covered too; use the global shortcut to uncover. A working registered shortcut is required to cover the primary. If a display becomes primary while no shortcut is registered, covers are removed to keep controls reachable.

Blackout has no Dock icon. Its menu provides appearance selection, Settings, and Quit. Closing settings keeps covers active. Pointer input is absorbed by the covers. The cursor is hidden over the cover, with a text cursor over the Lock Screen password field. Clicking that field gives it keyboard focus; Enter or the arrow declines every entry and clears its masked input. Only a bullet count is retained, with no password storage, logging, clipboard reads, or authentication calls. Until the field is clicked, keyboard input continues going to the previously focused app. Opening settings intentionally activates Blackout.

Display selections are remembered by CoreGraphics UUID. A disconnected selected display is restored when reconnected while other covers remain active. If all eligible targets disappear, Blackout returns to the uncovered state; reconnecting then requires another toggle. New displays are never selected automatically. A selected display remains covered when it becomes primary, provided a global shortcut is registered. Remembered selections can be cleared with **Forget** when disconnected.

The app always starts uncovered. System sleep or display sleep removes all covers, and wake does not restore them. Quit closes every cover and unregisters the shortcut.

## Architecture

- `Blackout/Core`: display descriptors, persisted settings, shortcut validation, and the observable state model. Display discovery, panel presentation, shortcut registration, and storage are injected protocols.
- `Blackout/App`: CoreGraphics discovery, AppKit cover panels, transactional Carbon hotkeys, and the application/menu/settings-window lifecycle.
- `Blackout/Views`: SwiftUI settings and cover content, plus an AppKit shortcut recorder.
- `Tests/BlackoutCoreTests`: deterministic Swift Testing tests with injected services and an isolated UserDefaults suite.

Preferences are a versioned JSON record in `UserDefaults` under the `com.matinhimself.Blackout` domain. The covered state is never persisted. The registrar registers a replacement before removing the previous hotkey. If startup registration fails, a custom saved shortcut falls back to the default when possible; if neither works, the menu remains available and settings reports the error.

## Window behavior and limits

Covers are opaque, borderless, nonactivating panels at the screen-saver window level. They use `canJoinAllSpaces`, `fullScreenAuxiliary`, `canJoinAllApplications`, `stationary`, and `ignoresCycle`. See Apple's [`canJoinAllApplications` documentation](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications) for the application-group behavior used with Stage Manager.

This app draws a cover: it does not switch off a monitor, authenticate anyone, or lock the macOS session. The decorative password field always declines entries; it cannot unlock anything. The cover omits the profile name and explanatory caption. Keyboard input can still affect the active application, including one whose window is covered, until you focus the decorative password field. Use the macOS session lock when authentication is needed.

Window-level and collection-behavior requests are not a security boundary. macOS controls system windows, Mission Control, Space transitions, Stage Manager, the cursor, and secure session UI. Their actual layering must be checked on the intended monitor arrangement; do not assume the cover hides every system surface. Mirrored displays cannot be covered independently and are excluded.

See [VALIDATION.md](VALIDATION.md) for executed checks and the remaining hardware checklist. Launch at login and distribution signing are outside this version.

## Continuous integration

GitHub Actions runs tests and a Release build on macOS 26 with Xcode 26.6 for pushes, pull requests, and manual runs. Successful builds upload `Blackout-macOS.zip` as a downloadable artifact (14-day retention). The app is ad-hoc signed for local testing, not notarized for distribution.

The workflow is in `.github/workflows/build.yml`. Download its artifact from the repository’s **Actions** tab, extract the ZIP, and open `Blackout.app` on macOS 26+.
