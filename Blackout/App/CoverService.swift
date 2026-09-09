import AppKit
import SwiftUI

final class CoverPanel: NSPanel {
    var allowsPasswordInput = false
    override var canBecomeKey: Bool { allowsPasswordInput }
    override var canBecomeMain: Bool { false }
}

// Explicitly swallow pointer input above the SwiftUI decoration.
final class InputShield: NSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .blackoutInvisible)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {}
    override func otherMouseDragged(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func magnify(with event: NSEvent) {}
    override func rotate(with event: NSEvent) {}
    override func swipe(with event: NSEvent) {}
    override func hitTest(_ point: NSPoint) -> NSView? { self }
}

@MainActor final class CoverService: CoverPresenting {
    private var panels: [String: CoverPanel] = [:]

    func reconcile(displays: [Display], appearance: CoverAppearance, wallpaperURL: URL?) {
        let wallpaper = appearance == .lockScreen ? wallpaperURL.flatMap { NSImage(contentsOf: $0) } : nil
        // Defense in depth: never trust a caller to include only eligible displays.
        let eligible = displays.filter { $0.isEligible }
        let wanted = Set(eligible.map(\.id))
        for id in Array(panels.keys) where !wanted.contains(id) {
            if let panel = panels.removeValue(forKey: id) {
                if panel.frame.contains(NSEvent.mouseLocation) { NSCursor.arrow.set() }
                panel.close()
            }
        }
        for display in eligible {
            let panel = panels[display.id] ?? makePanel(frame: display.frame)
            panel.allowsPasswordInput = appearance == .lockScreen
            if appearance == .black && panel.isKeyWindow { panel.resignKey() }
            panel.setFrame(display.frame, display: true)
            let content = NSView(frame: CGRect(origin: .zero, size: display.frame.size))
            let hosting = CoverHostingView(rootView: CoverView(appearance: appearance, wallpaper: wallpaper))
            hosting.frame = content.bounds
            hosting.autoresizingMask = [.width, .height]
            let shield = InputShield(frame: content.bounds)
            shield.autoresizingMask = [.width, .height]
            content.addSubview(shield)
            content.addSubview(hosting)
            // Black stays inert; Lock Screen exposes its decorative password control.
            if appearance == .black { content.addSubview(shield, positioned: .above, relativeTo: hosting) }
            panel.contentView = content
            panels[display.id] = panel
            panel.orderFrontRegardless()
            if panel.frame.contains(NSEvent.mouseLocation) { NSCursor.blackoutInvisible.set() }
        }
    }

    private func makePanel(frame: CGRect) -> CoverPanel {
        let panel = CoverPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .canJoinAllApplications, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = false
        panel.isRestorable = false
        panel.animationBehavior = .none
        panel.setAccessibilityLabel("Blackout display cover")
        return panel
    }

    func removeAll() {
        if panels.values.contains(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            NSCursor.arrow.set()
        }
        for panel in panels.values { panel.close() }
        panels.removeAll()
    }
}

final class CoverHostingView: NSHostingView<CoverView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .blackoutInvisible)
    }
}

extension NSCursor {
    @MainActor static let blackoutInvisible = NSCursor(
        image: NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill(using: .copy)
            return true
        }, hotSpot: .zero)
}
