import Carbon.HIToolbox
import AppKit

/// Registers a system-wide hotkey (default Cmd+Shift+P) via the Carbon Event
/// Manager. Unlike an NSEvent global monitor, RegisterEventHotKey needs no
/// Accessibility/Input Monitoring permission.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onPress: () -> Void

    private static let signature: OSType = 0x5065_7448 // 'PetH'

    init(keyCode: UInt32 = UInt32(kVK_ANSI_P),
         modifiers: UInt32 = UInt32(cmdKey | shiftKey),
         onPress: @escaping () -> Void) {
        self.onPress = onPress
        register(keyCode: keyCode, modifiers: modifiers)
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.onPress()
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
