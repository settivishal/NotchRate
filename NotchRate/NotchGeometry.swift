import AppKit

/// Per-screen sizing. Real notch: match its exact width/height so the black
/// shape merges with it. No notch: a small pill hugging the menu bar.
struct NotchGeometry {
    static var pillWidth: CGFloat { UserDefaults.standard.bool(forKey: Pref.showWeekly) ? 160 : 130 }
    static var expandedSize: CGSize { CGSize(width: 340, height: UserDefaults.standard.bool(forKey: Pref.ringGauges) ? 122 : 150) }

    let screen: NSScreen
    let hasNotch: Bool
    let notchWidth: CGFloat
    let topHeight: CGFloat   // notch height, or menu bar height on plain displays
    let wingWidth: CGFloat   // badge area on each side of the notch (user setting)

    init(screen: NSScreen) {
        self.screen = screen
        wingWidth = UserDefaults.standard.double(forKey: Pref.wingWidth)
        hasNotch = screen.safeAreaInsets.top > 0
        if hasNotch, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - l.width - r.width
        } else {
            notchWidth = 0
        }
        topHeight = hasNotch ? screen.safeAreaInsets.top : screen.frame.maxY - screen.visibleFrame.maxY
    }

    var collapsedSize: CGSize {
        CGSize(width: hasNotch ? notchWidth + 2 * wingWidth : Self.pillWidth, height: topHeight)
    }

    func expandedSize(for page: Page = .overview) -> CGSize {
        let card = switch page {
        case .overview: Self.expandedSize
        case .trends: CGSize(width: 380, height: 270)
        case .week: CGSize(width: 380, height: 230)
        }
        return CGSize(width: max(card.width, collapsedSize.width), height: topHeight + card.height)
    }

    /// Top-center frame for a window of `size` on this screen.
    func frame(for size: CGSize) -> NSRect {
        NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
    }

    static var notchScreen: NSScreen? { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } }

    static func screen(under point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }
}
