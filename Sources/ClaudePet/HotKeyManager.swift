import Carbon.HIToolbox
import AppKit

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onPress: () -> Void
    private let id: UInt32

    private static let signature: OSType = 0x5065_7448
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
