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
        acceptsMouseMovedEvents = true
    }

    /// Two-finger horizontal swipe over the panel; +1 = next tab, -1 = previous. One call per gesture.
    /// Local + global monitors: as an accessory app we are rarely active, so scroll events over the
    /// panel may be routed to whichever app is frontmost; the global monitor still sees them.
    /// The same monitors force the arrow cursor while the mouse is over the panel (cursor rects
    /// of the frontmost app otherwise win and show an I-beam).
    var onSwipe: ((Int) -> Void)? {
        didSet {
            for m in monitors { NSEvent.removeMonitor(m) }
            monitors = []
            guard onSwipe != nil else { return }
            let handle: (NSEvent) -> Void = { [weak self] event in
                guard let self, isVisible, frame.contains(NSEvent.mouseLocation) else { return }
                if event.type == .scrollWheel { swipe(event) } else { NSCursor.arrow.set() }
            }
            let mask: NSEvent.EventTypeMask = [.scrollWheel, .mouseMoved]
            if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { handle($0); return $0 }) { monitors.append(m) }
            if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handle) { monitors.append(m) }
        }
    }
    private var monitors: [Any] = []
    private var swiped = false
    private var accumulated: CGFloat = 0

    private func swipe(_ event: NSEvent) {
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
