import AppKit

/// Per-screen sizing. Real notch: match its exact width/height so the black
/// shape merges with it. No notch: a small pill hugging the menu bar.
struct NotchGeometry {
    static var pillWidth: CGFloat { UserDefaults.standard.bool(forKey: Pref.showWeekly) ? 160 : 130 }
    /// Card size preset: 1 compact, 1.25 spacious, custom from the slider. Scales width and chart heights;
    /// text keeps its size (a scale transform would blur it).
    static var scale: CGFloat {
        let d = UserDefaults.standard
        return switch d.string(forKey: Pref.cardSize) {
        case "spacious": 1.25
        case "custom": min(1.6, max(1, d.double(forKey: Pref.cardScale)))
        default: 1
        }
    }
    static var expandedSize: CGSize { CGSize(width: 380 * scale, height: UserDefaults.standard.bool(forKey: Pref.ringGauges) ? 122 : 150) }

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
    static let cardMargin: CGFloat = 16  // visible black margin around card content, sides and bottom

    static let blobGap: CGFloat = 8
    var blobWidth: CGFloat { topHeight }  // iOS-style side activity: a circle as tall as the notch

    var collapsedSize: CGSize { collapsedSize(blob: false) }

    /// `blob`: detached activity circles beside the badge; the window grows symmetrically so the badge stays centred.
    func collapsedSize(blob: Bool) -> CGSize {
        let badge = hasNotch ? notchWidth + 2 * wingWidth : Self.pillWidth
        return CGSize(width: badge + (blob ? 2 * (blobWidth + Self.blobGap) : 0), height: topHeight)
    }

    /// `tall`: overview has the per-model row. `plan`: approval page shows a plan (needs reading room).
    /// Always at least as wide as the collapsed badge with blobs: a cursor over a blob must stay inside
    /// the card that opens (else it flickers), and the width must not jump when a blob appears mid-card.
    func expandedSize(for page: Page = .overview, tall: Bool = false, plan: Bool = false) -> CGSize {
        let card = switch page {
        case .overview: CGSize(width: Self.expandedSize.width, height: Self.expandedSize.height + 24 + (tall ? 18 : 0))
        case .approval: CGSize(width: Self.expandedSize.width, height: plan ? 300 : 120)
        // Charts grow with the scale: two 70pt charts on Trends, one 120pt on Week, the 68pt activity map on Spend
        // (which only adds height once it outgrows the 98pt model/project lists beside it).
        case .trends: CGSize(width: Self.expandedSize.width, height: 280 + 140 * (Self.scale - 1))
        case .week: CGSize(width: Self.expandedSize.width, height: 240 + 120 * (Self.scale - 1))
        case .spend: CGSize(width: Self.expandedSize.width, height: 230 + max(0, 68 * Self.scale - 98))
        case .caffeine, .focus: CGSize(width: Self.expandedSize.width, height: Self.expandedSize.height + 24)  // same as overview
        }
        return CGSize(width: max(card.width, collapsedSize(blob: true).width), height: topHeight + card.height + Self.tabBar + 4)  // +4: 16pt bottom margin (was 12)
    }

    /// Banner that grows out of the closed island for a notice: one row under the notch.
    var noticeSize: CGSize { CGSize(width: max(collapsedSize(blob: true).width, 320), height: topHeight + 50) }

    /// Top-center frame for a window of `size` on this screen.
    func frame(for size: CGSize) -> NSRect {
        NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
    }

    /// A normal-level window covering the whole display, menu bar included: an app in full screen there.
    /// Window bounds need no Screen Recording permission (only titles do).
    static func hasFullscreenWindow(on screen: NSScreen) -> Bool {
        guard let primary = NSScreen.screens.first?.frame,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let f = screen.frame
        let target = CGRect(x: f.minX, y: primary.maxY - f.maxY, width: f.width, height: f.height)  // Quartz: top-left origin
        return windows.contains { w in
            guard w[kCGWindowLayer as String] as? Int == 0, let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b) else { return false }
            return r.integral == target.integral
        }
    }

    static var notchScreen: NSScreen? { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } }

    static func screen(under point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }
}
