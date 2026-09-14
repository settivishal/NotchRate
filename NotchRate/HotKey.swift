import Carbon

/// ⌃⌥N via Carbon: works without Accessibility permission, unlike a global NSEvent monitor.
@MainActor
enum HotKey {
    nonisolated(unsafe) private static var handler: (() -> Void)?
    private static var ref: EventHotKeyRef?
    private static var installed = false

    static func set(enabled: Bool, _ action: @escaping () -> Void) {
        handler = action
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        guard enabled else { return }
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                Task { @MainActor in HotKey.handler?() }
                return noErr
            }, 1, &spec, nil, nil)
            installed = true
        }
        let id = EventHotKeyID(signature: 0x4E52_4154, id: 1)  // "NRAT"
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
    }
}
