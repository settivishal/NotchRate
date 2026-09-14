import AppKit

/// Decides which screen hosts the panel. "Follow mouse" uses a global mouseMoved
/// monitor: costs nothing while idle, and on move only compares against the cached
/// frame of the current screen (NSScreen.screens is expensive to hit every event).
@MainActor
final class ScreenTracker {
    var onChange: (NSScreen?) -> Void
    private(set) var current: NSScreen?
    private var monitor: Any?
    private var followMouse: Bool

    init(followMouse: Bool, onChange: @escaping (NSScreen?) -> Void) {
        self.followMouse = followMouse
        self.onChange = onChange
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reconfigure() }
        }
        reconfigure()
    }

    func setFollowMouse(_ on: Bool) {
        guard on != followMouse else { return }
        followMouse = on
        reconfigure()
    }

    private func reconfigure() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if followMouse && NSScreen.screens.count > 1 {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                MainActor.assumeIsolated { self?.mouseMoved() }
            }
        }
        current = nil
        resolve()
    }

    private func mouseMoved() {
        if let f = current?.frame, f.contains(NSEvent.mouseLocation) { return }
        resolve()
    }

    private func resolve() {
        let target = followMouse
            ? (NotchGeometry.screen(under: NSEvent.mouseLocation) ?? NotchGeometry.notchScreen ?? NSScreen.main)
            : NotchGeometry.notchScreen
        guard target !== current else { return }
        current = target
        onChange(target)
    }
}
