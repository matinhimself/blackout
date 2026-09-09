import Foundation
import CoreGraphics

struct Display: Identifiable, Equatable {
    let id: String // Persistent CoreGraphics display UUID, never the transient display ID.
    let systemID: UInt32
    let name: String
    let pixelWidth: Int
    let pixelHeight: Int
    let frame: CGRect
    let isPrimary: Bool
    let isMirrored: Bool
    let isAvailable: Bool
    var isEligible: Bool { !isMirrored && isAvailable }
    var detail: String {
        if isMirrored { return "Mirrored — cannot be covered independently" }
        if !isAvailable { return "Display is not available for covering" }
        if isPrimary { return "Primary display" }
        return "Secondary display"
    }
}

@MainActor protocol DisplayDiscovering: AnyObject {
    var onChange: (() -> Void)? { get set }
    func currentDisplays() -> [Display]
}

@MainActor protocol CoverPresenting: AnyObject {
    func reconcile(displays: [Display], appearance: CoverAppearance, wallpaperURL: URL?)
    func removeAll()
}

@MainActor protocol ShortcutRegistering: AnyObject {
    var onPress: (() -> Void)? { get set }
    /// Failure must leave the previous registration intact.
    func replace(with shortcut: Shortcut) throws
    func unregister()
}
