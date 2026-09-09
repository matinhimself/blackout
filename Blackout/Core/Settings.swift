import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CoverAppearance: String, Codable, CaseIterable, Identifiable {
    case black, lockScreen
    var id: String { rawValue }
    var title: String { self == .black ? "Black" : "Lock Screen" }
}

struct Shortcut: Codable, Equatable, Sendable {
    struct Modifiers: OptionSet, Codable, Sendable {
        let rawValue: UInt32
        static let command = Self(rawValue: 1 << 0)
        static let control = Self(rawValue: 1 << 1)
        static let option = Self(rawValue: 1 << 2)
        static let shift = Self(rawValue: 1 << 3)
        static let supported: Self = [.command, .control, .option, .shift]
    }

    let keyCode: UInt32
    let modifiers: Modifiers
    static let `default` = Self(keyCode: 11, modifiers: [.control, .option, .command])

    // Restrict recording to predictable ANSI letter/number positions and F1–F12.
    // Labels deliberately describe physical keys, independent of input source.
    static let keyLabels: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 25: "9", 26: "7", 28: "8", 29: "0", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]

    var isSupported: Bool {
        keyLabelsContainsKey && !modifiers.intersection([.command, .control]).isEmpty
            && modifiers.subtracting(.supported).isEmpty
    }
    private var keyLabelsContainsKey: Bool { Self.keyLabels[keyCode] != nil }
    var label: String {
        (modifiers.contains(.control) ? "⌃" : "")
        + (modifiers.contains(.option) ? "⌥" : "")
        + (modifiers.contains(.shift) ? "⇧" : "")
        + (modifiers.contains(.command) ? "⌘" : "")
        + (Self.keyLabels[keyCode] ?? "?")
    }
}

struct SavedSettings: Codable, Equatable {
    var selectedDisplayUUIDs: Set<String> = []
    var appearance: CoverAppearance = .black
    var shortcut: Shortcut = .default
    var hasLaunched = false
    var usesCustomWallpaper = false
}

extension SavedSettings {
    private enum CodingKeys: String, CodingKey {
        case selectedDisplayUUIDs, appearance, shortcut, hasLaunched, usesCustomWallpaper
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        selectedDisplayUUIDs = try values.decodeIfPresent(Set<String>.self, forKey: .selectedDisplayUUIDs) ?? []
        appearance = try values.decodeIfPresent(CoverAppearance.self, forKey: .appearance) ?? .black
        shortcut = try values.decodeIfPresent(Shortcut.self, forKey: .shortcut) ?? .default
        hasLaunched = try values.decodeIfPresent(Bool.self, forKey: .hasLaunched) ?? false
        usesCustomWallpaper = try values.decodeIfPresent(Bool.self, forKey: .usesCustomWallpaper) ?? false
    }
}

/// Keeps an app-owned, downsampled copy so moving the original image doesn't break the cover.
struct WallpaperStore {
    let directory: URL
    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("Blackout", isDirectory: true)) {
        self.directory = directory
    }
    var imageURL: URL { directory.appendingPathComponent("wallpaper.png") }
    func importImage(from sourceURL: URL) throws {
        let access = sourceURL.startAccessingSecurityScopedResource()
        defer { if access { sourceURL.stopAccessingSecurityScopedResource() } }
        let size = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 100 * 1024 * 1024,
              let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096
              ] as CFDictionary) else { throw WallpaperError.invalidImage }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { throw WallpaperError.invalidImage }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw WallpaperError.invalidImage }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try (data as Data).write(to: imageURL, options: .atomic)
    }
    enum WallpaperError: LocalizedError {
        case invalidImage
        var errorDescription: String? { "Choose a readable image smaller than 100 MB." }
    }
}

/// Decorative input keeps only a bullet count, never password contents.
struct DecorativePasswordEntry {
    private(set) var count = 0
    private(set) var wasRejected = false
    mutating func insert(characterCount: Int) {
        count = min(64, count + max(0, characterCount))
        wasRejected = false
    }
    mutating func deleteBackward() { count = max(0, count - 1); wasRejected = false }
    mutating func submit() { count = 0; wasRejected = true }
    mutating func clear() { count = 0; wasRejected = false }
}

@MainActor protocol SettingsStoring {
    func load() -> SavedSettings
    func save(_ settings: SavedSettings)
}

@MainActor final class DefaultsSettingsStore: SettingsStoring {
    private let defaults: UserDefaults
    private let key = "blackout.settings.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() -> SavedSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(SavedSettings.self, from: data)
        else { return SavedSettings() }
        return settings
    }
    func save(_ settings: SavedSettings) {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: key) }
    }
}
