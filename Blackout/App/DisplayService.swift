import AppKit
import CoreGraphics

@MainActor final class DisplayService: DisplayDiscovering {
    var onChange: (() -> Void)?
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
    }

    func currentDisplays() -> [Display] {
        let screens = NSScreen.screens
        let primaryID = CGMainDisplayID()
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).compactMap { id -> Display? in
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
            let stableID = CFUUIDCreateString(nil, uuid)! as String
            let screen = screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
            }
            return Display(
                id: stableID, systemID: id,
                name: screen?.localizedName ?? "Display \(id)",
                pixelWidth: CGDisplayPixelsWide(id), pixelHeight: CGDisplayPixelsHigh(id),
                frame: screen?.frame ?? .zero, isPrimary: id == primaryID,
                isMirrored: CGDisplayIsInMirrorSet(id) != 0,
                isAvailable: screen != nil && CGDisplayIsActive(id) != 0
            )
        }.sorted {
            if $0.isPrimary != $1.isPrimary { return $0.isPrimary }
            return $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name
        }
    }

    isolated deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
