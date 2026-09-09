# Validation

Environment: macOS 26.2, Xcode 26.6 (17F113), Swift 6.3.3, Apple Silicon. Validation date: 2026-09-09.

## Automated checks

- **Passed:** Debug app build with Xcode 26.6, including the primary-display support update; updated app reopened for user testing.
- **Passed:** 19 Swift Testing tests via `rtk proxy swift test --scratch-path .build`.
- Coverage: explicit selection/default state, primary inclusion, mirror/unavailable exclusion, toggling, primary changes, primary-cover recovery when no shortcut is registered, UUID-based reconnection with changed display IDs and frames, unselected hotplug, loss of all targets, appearance/selection updates while active, sleep/shutdown/relaunch, transactional shortcut failure, validation before registration, startup fallback, recording behavior, UserDefaults round-trip/corruption recovery, compatibility with the removed hint preference, unconditional decorative password rejection, wallpaper import/copy persistence, invalid image recovery, and wallpaper preference migration.
- These tests use injected display/cover/hotkey services. They do not establish physical display layering or real Carbon event delivery.

## Runtime observations

The original build launched and its settings listed the single LF27T35 monitor as primary. Following user feedback, primary displays are now eligible, including a single-monitor setup. The updated build has been reopened for manual acceptance testing. Subsequent computer-use inspection timed out, so physical cover behavior, shortcut delivery, full-screen apps, Spaces, and Stage Manager are not yet marked passed.

## Manual acceptance checklist

Use a primary display plus two extended secondary displays for full coverage. Keep an app with a disposable text document focused on the primary display when checking keyboard behavior.

| Check | Expected result |
| --- | --- |
| First launch | Settings opens on the primary; no Dock icon; no display selected or covered |
| Select primary/only display | Display is selectable and covered; global shortcut uncovers it |
| Select every display | All are covered; global shortcut uncovers all |
| Select two secondary displays | Only selected displays are covered; primary remains usable |
| Black appearance | Full-frame solid black, including secondary menu bar/Dock areas subject to system layering |
| Lock Screen appearance | Alpine landscape, translucent clock/date, profile icon, password field, no explanatory caption |
| Custom wallpaper | Choose an image; centered fill on all covers; survives original-file deletion and relaunch; Reset restores built-in |
| No hint | Lock screen never shows an uncover hint, including with old saved preferences; shortcut still uncovers |
| Password entry | Click field, type dummy text, submit with Enter/arrow; always declined, bullets cleared, covers remain |
| Cursor | Hidden over covers; text cursor over password field; normal cursor after uncover |
| Shortcut with another app focused | One toggle per press; holding does not repeatedly toggle; keyboard focus stays in the other app |
| Click/right-click/scroll a cover | No click-through, focus transfer, or dismissal; typing still reaches the previously focused app |
| Recorder validation | Unsupported keys/modifiers report an error; Escape cancels; supported combination persists |
| Shortcut conflict | Register a combination held by another app; failure leaves old shortcut working |
| Close settings while covered | Covers remain active; menu and shortcut still work |
| Spaces and full-screen app | Covers remain over selected display across Space changes and native full-screen apps |
| Stage Manager | Covers remain visible when changing app groups; shortcut uncovers all selected displays |
| Rearrange displays | Covers adopt full new frames, including negative coordinates |
| Change primary | Selected displays stay covered if a shortcut is registered; otherwise uncover for recovery |
| Mirror selected display | Mirror set is uncovered and disabled for selection |
| Unplug/replug one of two targets | Remaining target stays covered; reconnect uses remembered UUID and new geometry |
| Unplug all selected targets | Covered state clears; reconnection remains uncovered until toggled |
| Attach an unselected display | New display stays uncovered |
| System/display sleep, then wake | All covers removed; wake remains uncovered |
| Quit while covered | All panels disappear; hotkey released |
| Relaunch | Preferences preserved, displays uncovered |

Do not mark physical checks passed based only on the injected unit tests. Record observed system-window limitations here as they are verified.
