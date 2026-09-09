import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var model: BlackoutModel
    func makeNSView(context: Context) -> RecorderView { RecorderView(model: model) }
    func updateNSView(_ view: RecorderView, context: Context) {
        view.model = model
        if model.isRecordingShortcut, view.window?.firstResponder !== view {
            view.window?.makeFirstResponder(view)
        }
    }

    final class RecorderView: NSView {
        var model: BlackoutModel
        init(model: BlackoutModel) { self.model = model; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if model.isRecordingShortcut { window?.makeFirstResponder(self) }
        }
        override func resignFirstResponder() -> Bool {
            model.isRecordingShortcut = false
            return true
        }
        override func keyDown(with event: NSEvent) {
            guard model.isRecordingShortcut else { super.keyDown(with: event); return }
            guard !event.isARepeat else { return }
            if event.keyCode == 53 { model.isRecordingShortcut = false; return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !flags.contains(.capsLock), !flags.contains(.numericPad), !flags.contains(.help) else {
                model.shortcutError = "Caps Lock, keypad, and Help combinations are not supported."
                return
            }
            // Function is a system flag on F-keys, but Fn+letter is not a registrable modifier.
            guard !flags.contains(.function) || (Shortcut.keyLabels[UInt32(event.keyCode)]?.hasPrefix("F") == true
                    && UInt32(event.keyCode) >= 96) else {
                model.shortcutError = "Fn combinations are only supported with F1–F12."
                return
            }
            var modifiers: Shortcut.Modifiers = []
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.shift) { modifiers.insert(.shift) }
            model.setShortcut(Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers))
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard model.isRecordingShortcut else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }
    }
}
