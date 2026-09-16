import AppKit

/// Transparent, click-through-free panel floating above the menu bar on every Space.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    /// Two-finger horizontal swipe over the panel; +1 = next tab, -1 = previous. One call per gesture.
    /// Local monitor rather than a scrollWheel override: the hosting view swallows scroll events.
    var onSwipe: ((Int) -> Void)? {
        didSet {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            guard onSwipe != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.swipe(event)
                return event
            }
        }
    }
    private var monitor: Any?
    private var swiped = false
    private var accumulated: CGFloat = 0

    private func swipe(_ event: NSEvent) {
        guard event.window === self else { return }
        if event.phase == .began { swiped = false; accumulated = 0 }
        guard !swiped, event.momentumPhase == [] else { return }
        accumulated += event.scrollingDeltaX
        guard abs(accumulated) > 30, abs(accumulated) > abs(event.scrollingDeltaY) else { return }
        swiped = true
        onSwipe?(accumulated < 0 ? 1 : -1)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
