import AppKit
import Carbon

@MainActor final class CarbonShortcutService: ShortcutRegistering {
    var onPress: (() -> Void)?
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var activeID: UInt32 = 0
    private var nextID: UInt32 = 1
    private var isDown = false
    private let signature: OSType = 0x424C4B54 // BLKT

    func replace(with shortcut: Shortcut) throws {
        guard shortcut.isSupported else { throw ShortcutValidationError.unsupported }
        if handler == nil {
            var events = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
            ]
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                return MainActor.assumeIsolated {
                    let service = Unmanaged<CarbonShortcutService>.fromOpaque(context).takeUnretainedValue()
                    return service.handle(event)
                }
            }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { throw RegistrationError(status: status) }
        }

        var modifiers: UInt32 = 0
        if shortcut.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if shortcut.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        if shortcut.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if shortcut.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let candidateID = nextID
        nextID &+= 1
        var candidate: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, modifiers,
                                        EventHotKeyID(signature: signature, id: candidateID),
                                        GetApplicationEventTarget(), 0, &candidate)
        guard status == noErr, let candidate else { throw RegistrationError(status: status) }
        // Register first. A conflict never destroys the currently working shortcut.
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = candidate
        activeID = candidateID
        isDown = false
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var id = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                       EventParamType(typeEventHotKeyID), nil,
                                       MemoryLayout<EventHotKeyID>.size, nil, &id)
        guard status == noErr, id.signature == signature, id.id == activeID else {
            return OSStatus(eventNotHandledErr)
        }
        if GetEventKind(event) == UInt32(kEventHotKeyReleased) { isDown = false }
        else if !isDown {
            isDown = true
            onPress?()
        }
        return noErr
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        isDown = false
    }

    struct RegistrationError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "This shortcut could not be registered (macOS error \(status)). It may be in use by another app."
        }
    }
}
