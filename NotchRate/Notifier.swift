import SwiftUI
import UserNotifications

/// A short alert. Shown as a banner growing out of the closed island when it can be, else as a system notification.
struct Notice: Equatable {
    var title: String
    var body: String
    var icon: String
    var tint: Color
    var page: Page? = nil  // opened by a click on the banner
}

/// Fires once per upward crossing of the configured thresholds on either rate-limit bucket,
/// plus one pace warning per session window.
enum Notifier {
    /// Set by the app: shows a notice in the island, false when it cannot (card open, badge hidden, setting off).
    @MainActor static var island: ((Notice) -> Bool)?

    @MainActor static func post(_ n: Notice) {
        if island?(n) == true { return }
        post(title: n.title, body: n.body)
    }

    /// Icon and color for a threshold/reset/pace message.
    static func notice(title: String, message msg: String) -> Notice {
        if msg.hasSuffix("limit reset") { return Notice(title: title, body: msg, icon: "arrow.counterclockwise.circle.fill", tint: .green, page: .overview) }
        if msg.hasPrefix("At this pace") { return Notice(title: title, body: msg, icon: "speedometer", tint: .yellow, page: .trends) }
        let full = msg.hasSuffix("100%")
        return Notice(title: title, body: msg, icon: full ? "exclamationmark.octagon.fill" : "gauge.with.dots.needle.67percent",
                      tint: full ? .red : .orange, page: .overview)
    }

    /// Pure: warn once per day when today's API-value spend reaches the budget. `primed` is false for the
    /// first reading after launch, so a budget passed earlier today is history rather than news.
    static func budgetCrossed(today: Double, budget: Double, day: Double, warnedDay: Double, primed: Bool) -> Bool {
        budget > 0 && today >= budget && warnedDay != day && primed
    }
    static func requestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }  // unbundled `swift run` would crash
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Pure: returns messages to post. Kept separate so it is testable.
    static func crossings(old: UsageSnapshot?, new: UsageSnapshot, thresholds: [Double] = [85, 100]) -> [String] {
        let buckets: [(String, Double?, Double?)] = [
            ("Session", old?.sessionUsedPct, new.sessionUsedPct),
            ("Weekly", old?.weeklyUsedPct, new.weeklyUsedPct),
        ]
        return buckets.flatMap { name, before, after -> [String] in
            guard let after else { return [] }
            return thresholds.compactMap { t in
                (before ?? 0) < t && after >= t ? "\(name) usage reached \(Int(t))%" : nil
            }
        }
    }

    /// Pure: a bucket that was at or past `threshold` and dropped back under 10% has rolled over.
    static func resets(old: UsageSnapshot?, new: UsageSnapshot, threshold: Double = 85) -> [String] {
        let buckets: [(String, Double?, Double?)] = [
            ("Session", old?.sessionUsedPct, new.sessionUsedPct),
            ("Weekly", old?.weeklyUsedPct, new.weeklyUsedPct),
        ]
        return buckets.compactMap { name, before, after in
            (before ?? 0) >= threshold && (after ?? 0) < 10 ? "\(name) limit reset" : nil
        }
    }

    /// Pure: message when the current burn rate reaches 100% before the session resets.
    static func pace(_ snap: UsageSnapshot, ratePerHour: Double, now: Date = .now) -> String? {
        guard let pct = snap.sessionUsedPct, let resets = snap.sessionResetsAt, ratePerHour > 0, pct < 100 else { return nil }
        let eta = (100 - pct) / ratePerHour * 3600
        guard eta < resets - now.timeIntervalSince1970 else { return nil }
        let h = eta / 3600
        return "At this pace the session limit hits 100% in ~\(h < 1 ? "\(Int((h * 60).rounded()))m" : "\(Int(h.rounded()))h"), before it resets"
    }

    @MainActor
    static func post(old: [UsageSnapshot], new: [UsageSnapshot]) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let defaults = UserDefaults.standard
        for snap in new {
            let prev = old.first { $0.tool == snap.tool }
            var msgs = crossings(old: prev, new: snap, thresholds: Pref.thresholds)
            if defaults.bool(forKey: Pref.resetNotify) { msgs += resets(old: prev, new: snap, threshold: Pref.thresholds[0]) }
            if defaults.bool(forKey: Pref.paceWarn), let resets = snap.sessionResetsAt, defaults.double(forKey: Pref.paceWarnedFor) != resets,
               let m = pace(snap, ratePerHour: History.rate(History.load(), \.s, hours: 1)) {
                msgs.append(m)
                defaults.set(resets, forKey: Pref.paceWarnedFor)
            }
            for msg in msgs { post(notice(title: snap.tool == "claude-code" ? "Claude" : snap.tool, message: msg)) }
        }
    }

    static func post(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
