import AppKit
import Combine
import SwiftUI

@main
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var model: BlackoutModel!
    private var settingsWindow: NSWindow?
    private var observation: AnyCancellable?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var displayObserver: NSObjectProtocol?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model = BlackoutModel(store: DefaultsSettingsStore(), discovery: DisplayService(),
                              covers: CoverService(), hotKey: CarbonShortcutService())
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "Blackout")
        statusItem.button?.toolTip = "Blackout"
        observation = model.objectWillChange.sink { [weak self] _ in
            // ObservableObject publishes before mutation; rebuild using the resulting state.
            DispatchQueue.main.async { self?.updateMenu() }
        }
        updateMenu()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.systemWillSleep() }
            })
        }
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.placeSettingsOnPrimary() } }
        if model.isFirstLaunch { showSettings() }
    }

    private func updateMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let toggle = NSMenuItem(title: model.isCovered ? "Uncover Displays" : "Cover Displays",
                                action: #selector(toggleCovers), keyEquivalent: "")
        toggle.target = self
        toggle.isEnabled = model.canToggle
        menu.addItem(toggle)
        if let shortcut = model.registeredShortcut {
            let hint = NSMenuItem(title: "Shortcut: \(shortcut.label)", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }
        menu.addItem(.separator())
        for appearance in CoverAppearance.allCases {
            let item = NSMenuItem(title: appearance.title, action: #selector(changeAppearance(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = appearance.rawValue
            item.state = model.settings.appearance == appearance ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit Blackout", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.toolTip = model.isCovered ? "Blackout — displays covered" : "Blackout — uncovered"
    }

    @objc private func toggleCovers() { model.toggle() }
    @objc private func changeAppearance(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let appearance = CoverAppearance(rawValue: raw) else { return }
        model.setAppearance(appearance)
    }
    @objc private func showSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: controller)
            window.title = "Blackout Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.delegate = self
            settingsWindow = window
        }
        placeSettingsOnPrimary()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func placeSettingsOnPrimary() {
        guard let window = settingsWindow,
              let screen = NSScreen.screens.first(where: {
                  ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
              }) else { return }
        let area = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2,
                                      y: max(area.minY, area.midY - window.frame.height / 2)))
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = settingsWindow,
              let screen = window.screen,
              (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value != CGMainDisplayID()
        else { return }
        placeSettingsOnPrimary()
    }
    func windowWillClose(_ notification: Notification) { model.isRecordingShortcut = false }
    func applicationDidResignActive(_ notification: Notification) { model.isRecordingShortcut = false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
    }
}
