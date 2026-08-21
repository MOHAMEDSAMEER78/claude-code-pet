import Carbon.HIToolbox
import AppKit

/// Registers a system-wide hotkey (default Cmd+Shift+P) via the Carbon Event
/// Manager. Unlike an NSEvent global monitor, RegisterEventHotKey needs no
/// Accessibility/Input Monitoring permission.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onPress: () -> Void
    private let id: UInt32

    private static let signature: OSType = 0x5065_7448 // 'PetH'
    /// Each instance needs a distinct id: InstallEventHandler installs on the
    /// shared application event target, so every installed handler observes
    /// every hotkey press event class-wide - without checking the event's
    /// own hotKeyID, a second registered hotkey (e.g. the command palette's)
    /// would also fire the first instance's (e.g. show/hide)'s callback.
    private static var nextId: UInt32 = 1

    init(keyCode: UInt32,
         modifiers: UInt32,
         onPress: @escaping () -> Void) {
        self.onPress = onPress
        self.id = Self.nextId
        Self.nextId += 1
        register(keyCode: keyCode, modifiers: modifiers)
    }

    convenience init(onPress: @escaping () -> Void) {
        self.init(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | shiftKey), onPress: onPress)
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            // Handlers installed on the shared application event target form
            // a chain; returning noErr tells Carbon "fully handled, stop
            // here" and swallows the event before any earlier-installed
            // handler sees it. Returning eventNotHandledErr on a non-match
            // instead lets the event fall through to the next handler in the
            // chain (e.g. another HotKeyManager instance's), so multiple
            // hotkeys registered this way can coexist.
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var pressedID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &pressedID
            )
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            guard pressedID.id == manager.id else { return OSStatus(eventNotHandledErr) }
            manager.onPress()
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
