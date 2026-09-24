import AppKit
import SwiftUI

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
        animationBehavior = .none  // the canvas animates; no AppKit window fade on top
        hidesOnDeactivate = false
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

/// Panel content. The black silhouette is a Core Animation shape layer: open, close and page changes
/// spring its path on the render server, while both SwiftUI layers stay laid out at their final size
/// (no per-frame relayout). The card layer is masked by the same moving path and fades in once the
/// shape is mostly open. Approach after vorssaint-utils' island (ideas only; that code is GPL).
final class NotchCanvas: NSView, CAAnimationDelegate {
    enum Fade { case none, `in`, out }

    private let badge: NSView
    private let card: NSView
    private let backdrop = CAShapeLayer()
    private let cardMask = CAShapeLayer()
    private let edge = CAShapeLayer()  // hairline outline for Increase Contrast
    private var silhouette = CGSize.zero
    private var seq = 0  // only the latest spring may report completion
    private var done: (() -> Void)?
    private var pointerArea: NSTrackingArea?
    var notch = true
    var badgeSize = CGSize.zero  // hit area while the card is closed (badge plus blobs)
    var cardVisible = false { didSet { card.isHidden = !cardVisible } }
    var onPointer: (() -> Void)?

    override var isFlipped: Bool { true }

    init(badge: NSView, card: NSView) {
        self.badge = badge
        self.card = card
        super.init(frame: .zero)
        wantsLayer = true
        backdrop.fillColor = NSColor.black.cgColor
        backdrop.zPosition = -1  // under both hosting views
        layer?.addSublayer(backdrop)
        cardMask.fillColor = NSColor.black.cgColor
        edge.fillColor = nil
        edge.lineWidth = 1
        edge.zPosition = 1  // over the card content
        layer?.addSublayer(edge)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPaths() }
        }
        cardMask.opacity = 0
        addSubview(badge)
        addSubview(card)
        card.wantsLayer = true
        card.layer?.mask = cardMask
        card.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        badge.frame = bounds
        card.frame = bounds
        applyPaths()
    }

    /// Model paths for the current bounds; running springs keep animating over them.
    private func applyPaths() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = bounds
        cardMask.frame = bounds
        let r = UserDefaults.standard.double(forKey: Pref.cardRadius)
        backdrop.path = NotchShape.forHeight(silhouette.height, notch: notch, cardRadius: r)
            .path(in: CGRect(x: (bounds.width - silhouette.width) / 2, y: 0, width: silhouette.width, height: silhouette.height)).cgPath
        cardMask.path = backdrop.path
        edge.frame = bounds
        edge.path = backdrop.path
        // Open card only: the closed badge merges with the physical notch and must stay borderless.
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast && silhouette.height > 64
        edge.strokeColor = NSColor.white.withAlphaComponent(contrast ? 0.45 : 0).cgColor
        CATransaction.commit()
    }

    /// Springs the silhouette to `size`. `resize` sets the window (to the union of both ends) inside the
    /// same transaction; `done` runs once the spring settles, or at once when not animated.
    func transition(to size: CGSize, animated: Bool, delay: TimeInterval = 0, fade: Fade,
                    resize: () -> Void, done: @escaping () -> Void) {
        let from = backdrop.presentation()?.path ?? backdrop.path
        let opacity = cardMask.presentation()?.opacity ?? cardMask.opacity
        let oldWidth = bounds.width
        seq += 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        resize()
        silhouette = size
        layoutSubtreeIfNeeded()
        applyPaths()  // bounds may not have changed, so layout() may not have run
        backdrop.removeAnimation(forKey: "path")
        edge.removeAnimation(forKey: "path")
        cardMask.removeAllAnimations()
        if fade != .none { cardMask.opacity = fade == .out ? 0 : 1 }
        guard animated, let from, let to = backdrop.path else {
            CATransaction.commit()
            self.done = nil
            done()
            return
        }
        var shift = CGAffineTransform(translationX: (bounds.width - oldWidth) / 2, y: 0)
        let grows = from.boundingBoxOfPath.height < size.height || from.boundingBoxOfPath.width < size.width
        let spring = CASpringAnimation(perceptualDuration: grows ? 0.34 : 0.26, bounce: 0)  // closing is quicker
        spring.keyPath = "path"
        spring.fromValue = from.copy(using: &shift)
        spring.toValue = to
        spring.duration = spring.settlingDuration
        if delay > 0 {
            spring.beginTime = backdrop.convertTime(CACurrentMediaTime(), from: nil) + delay
            spring.fillMode = .backwards
        }
        cardMask.add(spring.copy() as! CAAnimation, forKey: "path")
        edge.add(spring.copy() as! CAAnimation, forKey: "path")
        spring.delegate = self
        spring.setValue(seq, forKey: "seq")
        backdrop.add(spring, forKey: "path")
        switch fade {
        case .in:  // hold the content back until the shape has most of its size, continuing from what is on screen
            let a = CAKeyframeAnimation(keyPath: "opacity")
            a.values = [opacity, opacity, 1]
            a.keyTimes = [0, 0.625, 1]
            a.duration = 0.4
            a.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeOut)]
            cardMask.add(a, forKey: "opacity")
        case .out:
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = opacity
            a.toValue = 0
            a.duration = 0.15
            a.timingFunction = CAMediaTimingFunction(name: .easeOut)
            cardMask.add(a, forKey: "opacity")
        case .none: break
        }
        self.done = done
        CATransaction.commit()
    }

    /// Also called when AppKit cancels the animation (finished == false): the window must still settle.
    nonisolated func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        let tag = anim.value(forKey: "seq") as? Int
        MainActor.assumeIsolated {
            guard tag == seq, let done else { return }
            self.done = nil
            done()
        }
    }

    /// Open: only the (moving) silhouette takes clicks. Closed: the badge and its blobs.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        let inside = cardVisible
            ? (backdrop.presentation()?.path ?? backdrop.path)?.contains(p) == true
            : CGRect(x: (bounds.width - badgeSize.width) / 2, y: 0, width: badgeSize.width, height: badgeSize.height).contains(p)
        return inside ? super.hitTest(point) : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if pointerArea == nil {
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            pointerArea = area
        }
    }

    override func mouseEntered(with event: NSEvent) { onPointer?() }
    override func mouseExited(with event: NSEvent) { onPointer?() }
    override func mouseMoved(with event: NSEvent) { onPointer?() }
}

/// Non-activating panel: without this the first click on a card button is spent focusing the window.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
