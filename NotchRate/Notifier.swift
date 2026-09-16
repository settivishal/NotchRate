import UserNotifications

/// Fires once per upward crossing of the configured thresholds on either rate-limit bucket,
/// plus one pace warning per session window.
enum Notifier {
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
            if defaults.bool(forKey: Pref.paceWarn), let resets = snap.sessionResetsAt, defaults.double(forKey: Pref.paceWarnedFor) != resets,
               let m = pace(snap, ratePerHour: History.rate(History.load(), \.s, hours: 1)) {
                msgs.append(m)
                defaults.set(resets, forKey: Pref.paceWarnedFor)
            }
            for msg in msgs { post(title: snap.tool == "claude-code" ? "Claude" : snap.tool, body: msg) }
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
