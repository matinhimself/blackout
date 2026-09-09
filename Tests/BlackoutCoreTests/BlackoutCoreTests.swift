import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import BlackoutCore

@MainActor private final class MemoryStore: SettingsStoring {
    var value = SavedSettings()
    func load() -> SavedSettings { value }
    func save(_ settings: SavedSettings) { value = settings }
}
@MainActor private final class FakeDisplays: DisplayDiscovering {
    var onChange: (() -> Void)?
    var displays: [Display] = []
    func currentDisplays() -> [Display] { displays }
    func change(_ value: [Display]) { displays = value; onChange?() }
}
@MainActor private final class FakeCovers: CoverPresenting {
    var visible: [Display] = []
    var appearance: CoverAppearance?
    var wallpaperURL: URL?
    func reconcile(displays: [Display], appearance: CoverAppearance, wallpaperURL: URL?) {
        self.wallpaperURL = wallpaperURL
        visible = displays; self.appearance = appearance
    }
    func removeAll() { visible = [] }
}
@MainActor private final class FakeHotKey: ShortcutRegistering {
    var onPress: (() -> Void)?
    var registered: Shortcut?
    var rejected: Set<UInt32> = []
    var attempts = 0
    func replace(with shortcut: Shortcut) throws {
        attempts += 1
        if rejected.contains(shortcut.keyCode) { throw ShortcutValidationError.unsupported }
        registered = shortcut
    }
    func unregister() { registered = nil }
}

@MainActor private struct Fixture {
    let store = MemoryStore()
    let displays = FakeDisplays()
    let covers = FakeCovers()
    let hotKey = FakeHotKey()
    func model() -> BlackoutModel {
        BlackoutModel(store: store, discovery: displays, covers: covers, hotKey: hotKey)
    }
}

private func display(_ id: String, primary: Bool = false, mirrored: Bool = false,
                     available: Bool = true, systemID: UInt32 = 1, x: Double = 0) -> Display {
    Display(id: id, systemID: systemID, name: id, pixelWidth: 2560, pixelHeight: 1440,
            frame: CGRect(x: x, y: 0, width: 1280, height: 720), isPrimary: primary,
            isMirrored: mirrored, isAvailable: available)
}

@Suite @MainActor struct BlackoutCoreTests {
    @Test func defaultsRequireExplicitSelectionAndStartUncovered() {
        let f = Fixture()
        f.displays.displays = [display("primary", primary: true), display("secondary")]
        let model = f.model()
        #expect(model.isFirstLaunch)
        #expect(model.settings.appearance == .black)
        #expect(model.registeredShortcut == .default)
        #expect(!model.canToggle)
        model.toggle()
        #expect(!model.isCovered)
        #expect(f.store.value.hasLaunched)
    }

    @Test func onlySelectedEligibleDisplaysAreCovered() {
        let f = Fixture()
        f.store.value.selectedDisplayUUIDs = ["primary", "selected", "mirror", "offline"]
        f.displays.displays = [display("primary", primary: true), display("selected"),
                               display("unselected"), display("mirror", mirrored: true),
                               display("offline", available: false)]
        let model = f.model()
        model.toggle()
        #expect(f.covers.visible.map(\.id) == ["primary", "selected"])
        model.toggle()
        #expect(!model.isCovered)
        #expect(f.covers.visible.isEmpty)
    }

    @Test func primaryChangeKeepsSelectedDisplayCovered() {
        let f = Fixture()
        f.store.value.selectedDisplayUUIDs = ["a", "b"]
        f.displays.displays = [display("main", primary: true), display("a"), display("b")]
        let model = f.model()
        model.toggle()
        f.displays.change([display("main"), display("a", primary: true), display("b")])
        #expect(f.covers.visible.map(\.id) == ["a", "b"])
        #expect(model.settings.selectedDisplayUUIDs.contains("a"))
    }

    @Test func reconnectionUsesUUIDAndUpdatedFrame() {
        let f = Fixture()
        f.store.value.selectedDisplayUUIDs = ["a", "b"]
        f.displays.displays = [display("a"), display("b")]
        let model = f.model()
        model.toggle()
        f.displays.change([display("b")])
        #expect(model.isCovered)
        #expect(f.covers.visible.map(\.id) == ["b"])
        let reconnected = display("a", systemID: 99, x: -1280)
        f.displays.change([reconnected, display("b"), display("new")])
        #expect(f.covers.visible == [reconnected, display("b")])
    }

    @Test func losingAllTargetsClearsToggleButRemembersSelections() {
        let f = Fixture()
        f.store.value.selectedDisplayUUIDs = ["a"]
        f.displays.displays = [display("a")]
        let model = f.model()
        model.toggle()
        f.displays.change([])
        #expect(!model.isCovered)
        #expect(!model.canToggle)
        #expect(model.settings.selectedDisplayUUIDs == ["a"])
        f.displays.change([display("a")])
        #expect(model.canToggle)
        #expect(!model.isCovered)
        #expect(f.covers.visible.isEmpty)
    }

    @Test func mirrorChangeRemovesCoverAndRejectsSelection() {
        let f = Fixture()
        let target = display("a")
        f.displays.displays = [target]
        let model = f.model()
        model.setSelected(true, display: target)
        model.toggle()
        f.displays.change([display("a", mirrored: true)])
        #expect(!model.isCovered)
        model.setSelected(true, display: display("other", mirrored: true))
        model.setSelected(true, display: display("main", primary: true))
        #expect(model.settings.selectedDisplayUUIDs == ["a", "main"])
    }

    @Test func onlyPrimaryDisplayCanBeSelectedCoveredAndUncoveredByShortcut() {
        let f = Fixture()
        let primary = display("main", primary: true)
        f.displays.displays = [primary]
        let model = f.model()
        model.setSelected(true, display: primary)
        #expect(model.canToggle)
        model.toggle()
        #expect(f.covers.visible == [primary])
        f.hotKey.onPress?()
        #expect(!model.isCovered)
        #expect(f.covers.visible.isEmpty)
    }

    @Test func primaryCoverRequiresWorkingShortcutAndRecoversOnPrimaryChange() {
        let f = Fixture()
        f.hotKey.rejected = [Shortcut.default.keyCode]
        f.store.value.selectedDisplayUUIDs = ["a"]
        f.displays.displays = [display("a", primary: true)]
        let model = f.model()
        #expect(model.needsShortcutToCover)
        #expect(!model.canToggle)
        model.toggle()
        #expect(!model.isCovered)
        f.displays.change([display("a"), display("main", primary: true)])
        model.toggle()
        #expect(model.isCovered)
        f.displays.change([display("a", primary: true), display("main")])
        #expect(!model.isCovered)
        #expect(f.covers.visible.isEmpty)
        model.setShortcut(Shortcut(keyCode: 0, modifiers: [.control, .command]))
        #expect(model.canToggle)
        model.toggle()
        #expect(model.isCovered)
    }

    @Test func selectionAndAppearanceChangesReconcileActiveCovers() {
        let f = Fixture()
        f.displays.displays = [display("a"), display("b")]
        let model = f.model()
        model.setSelected(true, display: display("a"))
        model.toggle()
        model.setSelected(true, display: display("b"))
        model.setAppearance(.lockScreen)
        #expect(f.covers.visible.count == 2)
        #expect(f.covers.appearance == .lockScreen)
        #expect(f.store.value.appearance == .lockScreen)
        model.setSelected(false, display: display("a"))
        model.setSelected(false, display: display("b"))
        #expect(!model.isCovered)
    }

    @Test func sleepAndRelaunchRemainUncovered() {
        let f = Fixture()
        f.store.value.selectedDisplayUUIDs = ["a"]
        f.displays.displays = [display("a")]
        let model = f.model()
        model.toggle()
        model.systemWillSleep()
        model.refreshDisplays()
        #expect(!model.isCovered)
        #expect(f.covers.visible.isEmpty)
        model.toggle()
        model.shutdown()
        #expect(f.hotKey.registered == nil)
        #expect(f.covers.visible.isEmpty)
        let relaunched = f.model()
        #expect(!relaunched.isFirstLaunch)
        #expect(!relaunched.isCovered)
        #expect(relaunched.settings.selectedDisplayUUIDs == ["a"])
    }

    @Test func shortcutConflictPreservesWorkingRegistrationAndPersistence() {
        let f = Fixture()
        let model = f.model()
        f.hotKey.rejected = [0]
        model.setShortcut(Shortcut(keyCode: 0, modifiers: [.command]))
        #expect(model.shortcutError != nil)
        #expect(model.registeredShortcut == .default)
        #expect(f.hotKey.registered == .default)
        #expect(f.store.value.shortcut == .default)
        model.setShortcut(Shortcut(keyCode: 1, modifiers: [.control, .shift]))
        #expect(model.shortcutError == nil)
        #expect(model.registeredShortcut?.keyCode == 1)
        #expect(f.store.value.shortcut.keyCode == 1)
    }

    @Test func unsupportedShortcutNeverReachesRegistrar() {
        let f = Fixture()
        let model = f.model()
        let attempts = f.hotKey.attempts
        for shortcut in [Shortcut(keyCode: 0, modifiers: [.option]),
                         Shortcut(keyCode: 53, modifiers: [.command]),
                         Shortcut(keyCode: 0, modifiers: .init(rawValue: 255))] {
            model.setShortcut(shortcut)
            #expect(model.shortcutError != nil)
        }
        #expect(f.hotKey.attempts == attempts)
    }

    @Test func startupShortcutFailureFallsBackOrLeavesMenuAvailable() {
        let f = Fixture()
        f.store.value.shortcut = Shortcut(keyCode: 0, modifiers: [.command])
        f.hotKey.rejected = [0]
        let model = f.model()
        #expect(model.registeredShortcut == .default)
        #expect(model.shortcutError != nil)
        model.shutdown()
        f.hotKey.rejected = [11]
        f.store.value.selectedDisplayUUIDs = ["a"]
        f.displays.displays = [display("a")]
        let noShortcut = f.model()
        #expect(noShortcut.registeredShortcut == nil)
        #expect(noShortcut.canToggle)
        noShortcut.toggle()
        #expect(noShortcut.isCovered)
    }

    @Test func hotKeyTogglesExceptWhileRecording() {
        let f = Fixture()
        f.store.value.selectedDisplayUUIDs = ["a"]
        f.displays.displays = [display("a")]
        let model = f.model()
        f.hotKey.onPress?()
        #expect(model.isCovered)
        model.isRecordingShortcut = true
        f.hotKey.onPress?()
        #expect(model.isCovered)
        #expect(!model.isRecordingShortcut)
        f.hotKey.onPress?()
        #expect(!model.isCovered)
    }

    @Test func defaultsRoundTripAndCorruptDataRecovery() throws {
        let suite = "BlackoutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DefaultsSettingsStore(defaults: defaults)
        let settings = SavedSettings(selectedDisplayUUIDs: ["stable-uuid"], appearance: .lockScreen,
                                     shortcut: Shortcut(keyCode: 1, modifiers: [.control]), hasLaunched: true)
        store.save(settings)
        #expect(DefaultsSettingsStore(defaults: defaults).load() == settings)
        defaults.set(Data("bad json".utf8), forKey: "blackout.settings.v1")
        #expect(store.load() == SavedSettings())
    }

    @Test func legacyHintPreferenceIsIgnoredWithoutLosingSelections() throws {
        // Encode the existing shortcut representation instead of assuming OptionSet's wire format.
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedSettings(
            selectedDisplayUUIDs: ["saved-display"], appearance: .lockScreen, hasLaunched: true
        ))) as? [String: Any])
        object["showUncoverHint"] = true
        let decoded = try JSONDecoder().decode(SavedSettings.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.selectedDisplayUUIDs == ["saved-display"])
        #expect(decoded.appearance == .lockScreen)
        #expect(decoded.hasLaunched)
    }

    @Test func decorativePasswordAlwaysClearsAndRejectsEntries() {
        var input = DecorativePasswordEntry()
        for length in [0, 1, 12, 1000] {
            input.insert(characterCount: length)
            #expect(input.count <= 64)
            input.submit()
            #expect(input.count == 0)
            #expect(input.wasRejected)
        }
        input.insert(characterCount: 2)
        #expect(!input.wasRejected)
        input.deleteBackward()
        #expect(input.count == 1)
        input.clear()
        #expect(input.count == 0)
        #expect(!input.wasRejected)
    }

    @Test func wallpaperImportPersistsCopyAndInvalidReplacementKeepsPreviousImage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceURL = directory.appendingPathComponent("source.png")
        let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
                                             bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(sourceURL as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let wallpaper = WallpaperStore(directory: directory.appendingPathComponent("managed"))
        let f = Fixture()
        f.displays.displays = [display("a")]
        f.store.value.selectedDisplayUUIDs = ["a"]
        let model = BlackoutModel(store: f.store, discovery: f.displays, covers: f.covers,
                                  hotKey: f.hotKey, wallpaperStore: wallpaper)
        model.setAppearance(.lockScreen)
        model.toggle()
        model.setWallpaper(from: sourceURL)
        #expect(model.wallpaperError == nil)
        #expect(f.store.value.usesCustomWallpaper)
        #expect(f.covers.wallpaperURL == wallpaper.imageURL)
        let savedData = try Data(contentsOf: wallpaper.imageURL)
        try FileManager.default.removeItem(at: sourceURL)
        #expect(try Data(contentsOf: wallpaper.imageURL) == savedData)
        let invalid = directory.appendingPathComponent("invalid.png")
        try Data("not an image".utf8).write(to: invalid)
        model.setWallpaper(from: invalid)
        #expect(model.wallpaperError != nil)
        #expect(try Data(contentsOf: wallpaper.imageURL) == savedData)
        #expect(model.settings.usesCustomWallpaper)
        model.useBuiltInWallpaper()
        #expect(f.covers.wallpaperURL == nil)
        #expect(!f.store.value.usesCustomWallpaper)
        #expect(model.isCovered)
    }

    @Test func wallpaperPreferenceMigrationAndRoundTrip() throws {
        var settings = SavedSettings()
        settings.usesCustomWallpaper = true
        let encoded = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(SavedSettings.self, from: encoded).usesCustomWallpaper)
        var old = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        old.removeValue(forKey: "usesCustomWallpaper")
        let migrated = try JSONDecoder().decode(SavedSettings.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(!migrated.usesCustomWallpaper)
    }
}
