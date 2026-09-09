import AppKit
import SwiftUI

struct CoverView: View {
    let appearance: CoverAppearance
    var wallpaper: NSImage? = nil
    @State private var password = DecorativePasswordEntry()
    @State private var inputFocused = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if appearance == .lockScreen {
                    if let wallpaper {
                        Image(nsImage: wallpaper).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                            .overlay(LinearGradient(colors: [.black.opacity(0.15), .clear, .black.opacity(0.4)],
                                                    startPoint: .top, endPoint: .bottom))
                    } else {
                        TahoeLandscape()
                    }
                    VStack(spacing: 0) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            VStack(spacing: 0) {
                                Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.9))
                                Text(context.date, format: .dateTime.hour().minute())
                                    .font(.system(size: min(156, geometry.size.height * 0.19), weight: .bold, design: .rounded))
                                    .monospacedDigit().tracking(-6)
                                    .foregroundStyle(LinearGradient(
                                        colors: [.white.opacity(0.95), .white.opacity(0.48)],
                                        startPoint: .top, endPoint: .bottom))
                                    .shadow(color: .white.opacity(0.25), radius: 1, y: 1)
                                    .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
                            }
                        }.padding(.top, max(36, geometry.size.height * 0.075))
                        Spacer(minLength: 24)
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 64, weight: .thin))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.white.opacity(0.95))
                                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                            passwordControl
                            Text(password.wasRejected ? "Password declined. Try again." : "")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(height: 18)
                        }
                        Spacer().frame(height: max(24, geometry.size.height * 0.06))
                        Spacer().frame(height: 42)
                    }.foregroundStyle(.white)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
        }.ignoresSafeArea().preferredColorScheme(.dark)
            .onDisappear { password.clear() }
    }

    private var passwordControl: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Text(password.count == 0 ? "Enter Password" : String(repeating: "•", count: min(password.count, 20)))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(password.count == 0 ? 0.65 : 0.95))
                PasswordCapture(entry: $password, focused: $inputFocused)
            }.frame(width: 178, height: 30)
            Button {
                password.submit()
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 23)).foregroundStyle(.white.opacity(0.85))
            }.buttonStyle(.plain).accessibilityLabel("Submit password (always declined)")
        }.padding(.horizontal, 12).padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(inputFocused ? 0.75 : 0.22), lineWidth: 1))
            .shadow(color: .black.opacity(0.14), radius: 16, y: 4)
    }
}

// Original vector landscape: misty mountain silhouettes over a blue alpine lake.
private struct TahoeLandscape: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [Color(red: 0.12, green: 0.24, blue: 0.43),
                                        Color(red: 0.44, green: 0.59, blue: 0.69),
                                        Color(red: 0.08, green: 0.31, blue: 0.46)],
                               startPoint: .top, endPoint: .bottom)
                Ellipse().fill(Color(red: 0.85, green: 0.79, blue: 0.70).opacity(0.4))
                    .frame(width: geometry.size.width * 0.95, height: geometry.size.height * 0.25)
                    .blur(radius: 70).offset(x: geometry.size.width * 0.2, y: -geometry.size.height * 0.1)
                Canvas { context, size in
                    for layer in 0..<4 {
                        let base = 0.43 + Double(layer) * 0.055
                        var mountain = Path()
                        mountain.move(to: CGPoint(x: 0, y: size.height * base))
                        for step in 0...12 {
                            let x = Double(step) / 12
                            let ridge = sin(x * 10 + Double(layer) * 1.7) * 0.065
                                + sin(x * 23 + Double(layer)) * 0.027
                            mountain.addLine(to: CGPoint(x: size.width * x, y: size.height * (base + ridge)))
                        }
                        mountain.addLine(to: CGPoint(x: size.width, y: size.height * 0.67))
                        mountain.addLine(to: CGPoint(x: 0, y: size.height * 0.67))
                        mountain.closeSubpath()
                        context.fill(mountain, with: .color(Color(
                            red: 0.12 - Double(layer) * 0.02,
                            green: 0.27 - Double(layer) * 0.035,
                            blue: 0.36 - Double(layer) * 0.04).opacity(0.65)))
                    }
                    for line in 0..<38 {
                        let y = size.height * (0.65 + Double(line) * 0.01)
                        var ripple = Path()
                        ripple.move(to: CGPoint(x: 0, y: y))
                        ripple.addQuadCurve(to: CGPoint(x: size.width, y: y + 3),
                                            control: CGPoint(x: size.width * 0.5, y: y - 6))
                        context.stroke(ripple, with: .color(.white.opacity(0.025)), lineWidth: 1)
                    }
                }
                LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
            }
        }.accessibilityHidden(true)
    }
}

/// A masked decorative input, not an authentication field. No entered character is retained.
private struct PasswordCapture: NSViewRepresentable {
    @Binding var entry: DecorativePasswordEntry
    @Binding var focused: Bool

    func makeNSView(context: Context) -> CaptureView { CaptureView() }
    func updateNSView(_ view: CaptureView, context: Context) {
        view.onInsert = { entry.insert(characterCount: $0) }
        view.onDelete = { entry.deleteBackward() }
        view.onSubmit = { entry.submit() }
        view.onClear = { entry.clear() }
        view.onFocus = { focused = $0 }
    }

    final class CaptureView: NSView {
        var onInsert: ((Int) -> Void)?
        var onDelete: (() -> Void)?
        var onSubmit: (() -> Void)?
        var onClear: (() -> Void)?
        var onFocus: ((Bool) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .iBeam) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.makeKey()
            window?.makeFirstResponder(self)
        }
        override func becomeFirstResponder() -> Bool { onFocus?(true); return true }
        override func resignFirstResponder() -> Bool { onClear?(); onFocus?(false); return true }
        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 36, 76: onSubmit?()
            case 51, 117: onDelete?()
            case 53: onClear?()
            default:
                guard event.modifierFlags.intersection([.command, .control]).isEmpty,
                      let characters = event.characters,
                      characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
                      !event.modifierFlags.contains(.function) else { return }
                onInsert?(characters.count)
            }
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            // Consume app commands while typing; Carbon handles the registered uncover shortcut.
            if window?.firstResponder === self, event.modifierFlags.contains(.command) { return true }
            return super.performKeyEquivalent(with: event)
        }
        override func accessibilityRole() -> NSAccessibility.Role? { .textField }
        override func accessibilityLabel() -> String? { "Decorative password input. All entries are declined." }
        override func isAccessibilityElement() -> Bool { true }
    }
}
