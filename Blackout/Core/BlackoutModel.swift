import Combine
import Foundation

@MainActor final class BlackoutModel: ObservableObject {
    @Published private(set) var settings: SavedSettings
    @Published private(set) var displays: [Display] = []
    @Published private(set) var isCovered = false
    @Published private(set) var registeredShortcut: Shortcut?
    @Published var shortcutError: String?
    @Published private(set) var wallpaperError: String?
    @Published var isRecordingShortcut = false
    let isFirstLaunch: Bool
    private let store: any SettingsStoring
    private let discovery: any DisplayDiscovering
    private let covers: any CoverPresenting
    private let hotKey: any ShortcutRegistering
    private let wallpaperStore: WallpaperStore

    init(store: any SettingsStoring, discovery: any DisplayDiscovering,
         covers: any CoverPresenting, hotKey: any ShortcutRegistering,
         wallpaperStore: WallpaperStore = WallpaperStore()) {
        self.store = store
        self.discovery = discovery
        self.covers = covers
        self.hotKey = hotKey
        self.wallpaperStore = wallpaperStore
        let loaded = store.load()
        settings = loaded
        isFirstLaunch = !loaded.hasLaunched
        settings.hasLaunched = true
        store.save(settings)
        discovery.onChange = { [weak self] in self?.refreshDisplays() }
        hotKey.onPress = { [weak self] in
            guard let self else { return }
            if self.isRecordingShortcut {
                // Carbon consumes the existing shortcut before the recorder sees it.
                self.isRecordingShortcut = false
            } else {
                self.toggle()
            }
        }
        refreshDisplays()
        do {
            guard settings.shortcut.isSupported else { throw ShortcutValidationError.unsupported }
            try hotKey.replace(with: settings.shortcut)
            registeredShortcut = settings.shortcut
        } catch {
            shortcutError = "Could not register the saved shortcut: \(error.localizedDescription)"
            if settings.shortcut != .default {
                do {
                    try hotKey.replace(with: .default)
                    registeredShortcut = .default
                    settings.shortcut = .default
                    store.save(settings)
                    shortcutError = "The saved shortcut was unavailable. Restored \(Shortcut.default.label)."
                } catch { /* The menu remains an available recovery control. */ }
            }
        }
    }

    var eligibleSelectedDisplays: [Display] {
        displays.filter { $0.isEligible && settings.selectedDisplayUUIDs.contains($0.id) }
    }
    var needsShortcutToCover: Bool {
        eligibleSelectedDisplays.contains(where: \.isPrimary) && registeredShortcut == nil
    }
    var canToggle: Bool {
        isCovered || (!eligibleSelectedDisplays.isEmpty && !needsShortcutToCover)
    }
    var shortcutHint: String {
        registeredShortcut.map { "Press \($0.label) to uncover" } ?? "Use the Blackout menu to uncover"
    }

    func refreshDisplays() {
        displays = discovery.currentDisplays()
        reconcile()
    }
    func setSelected(_ selected: Bool, display: Display) {
        guard !selected || display.isEligible else { return }
        if selected { settings.selectedDisplayUUIDs.insert(display.id) }
        else { settings.selectedDisplayUUIDs.remove(display.id) }
        store.save(settings)
        reconcile()
    }
    func forgetDisconnectedSelections() {
        settings.selectedDisplayUUIDs.formIntersection(Set(displays.map(\.id)))
        store.save(settings)
    }
    func setAppearance(_ appearance: CoverAppearance) {
        settings.appearance = appearance
        store.save(settings)
        reconcile()
    }
    func setWallpaper(from url: URL) {
        do {
            try wallpaperStore.importImage(from: url)
            settings.usesCustomWallpaper = true
            wallpaperError = nil
            store.save(settings)
            reconcile()
        } catch {
            wallpaperError = "Could not use this image. \(error.localizedDescription)"
        }
    }
    func useBuiltInWallpaper() {
        settings.usesCustomWallpaper = false
        wallpaperError = nil
        store.save(settings)
        reconcile()
    }
    func setShortcut(_ shortcut: Shortcut) {
        do {
            guard shortcut.isSupported else { throw ShortcutValidationError.unsupported }
            if registeredShortcut != shortcut { try hotKey.replace(with: shortcut) }
            registeredShortcut = shortcut
            settings.shortcut = shortcut
            store.save(settings)
            shortcutError = nil
            isRecordingShortcut = false
            reconcile()
        } catch {
            shortcutError = "\(error.localizedDescription) Your previous shortcut is unchanged."
        }
    }
    func toggle() {
        guard canToggle else { return }
        isCovered.toggle()
        reconcile()
    }
    func uncover() {
        isCovered = false
        covers.removeAll()
    }
    func systemWillSleep() { uncover() }
    func shutdown() {
        uncover()
        hotKey.unregister()
        discovery.onChange = nil
        hotKey.onPress = nil
    }
    private func reconcile() {
        guard isCovered, !eligibleSelectedDisplays.isEmpty, !needsShortcutToCover else {
            uncover()
            return
        }
        covers.reconcile(displays: eligibleSelectedDisplays,
                         appearance: settings.appearance,
                         wallpaperURL: settings.usesCustomWallpaper ? wallpaperStore.imageURL : nil)
    }
}

enum ShortcutValidationError: LocalizedError {
    case unsupported
    var errorDescription: String? {
        "Use Command or Control with a letter, number, or F1–F12 key."
    }
}
