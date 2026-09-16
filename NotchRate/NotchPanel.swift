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

    /// Two-finger horizontal swipe; +1 = next page, -1 = previous. One call per gesture.
    var onSwipe: ((Int) -> Void)?
    private var swiped = false

    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began { swiped = false }
        guard !swiped, event.momentumPhase == [], abs(event.scrollingDeltaX) > 20, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }
        swiped = true
        onSwipe?(event.scrollingDeltaX < 0 ? 1 : -1)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
