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

    static let tabBar: CGFloat = 56  // 32pt pills + 12pt above and below

    static let blobGap: CGFloat = 8
    var blobWidth: CGFloat { topHeight }  // iOS-style side activity: a circle as tall as the notch

    var collapsedSize: CGSize { collapsedSize(blob: false) }

    /// `blob`: detached activity circles beside the badge; the window grows symmetrically so the badge stays centred.
    func collapsedSize(blob: Bool) -> CGSize {
        let badge = hasNotch ? notchWidth + 2 * wingWidth : Self.pillWidth
        return CGSize(width: badge + (blob ? 2 * (blobWidth + Self.blobGap) : 0), height: topHeight)
    }

    /// `tall`: overview has the per-model row. `plan`: approval page shows a plan (needs reading room).
    /// `blob`: card must stay at least as wide as the collapsed badge+blob, or a cursor over the blob
    /// falls outside the expanded frame and the card flickers open/closed.
    func expandedSize(for page: Page = .overview, tall: Bool = false, plan: Bool = false, blob: Bool = false) -> CGSize {
        let card = switch page {
        case .overview: CGSize(width: Self.expandedSize.width, height: Self.expandedSize.height + 24 + (tall ? 18 : 0))
        case .approval: CGSize(width: Self.expandedSize.width, height: plan ? 300 : 120)
        case .trends: CGSize(width: Self.expandedSize.width, height: 280)
        case .week: CGSize(width: Self.expandedSize.width, height: 240)
        case .caffeine: CGSize(width: Self.expandedSize.width, height: Self.expandedSize.height + 24)  // same as overview
        }
        return CGSize(width: max(card.width, collapsedSize(blob: blob).width), height: topHeight + card.height + Self.tabBar)
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
