import UserNotifications

/// Fires once per upward crossing of 85% / 100% on either rate-limit bucket.
enum Notifier {
    static let thresholds: [Double] = [85, 100]

    static func requestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }  // unbundled `swift run` would crash
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Pure: returns messages to post. Kept separate so it is testable.
    static func crossings(old: UsageSnapshot?, new: UsageSnapshot) -> [String] {
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

    static func post(old: [UsageSnapshot], new: [UsageSnapshot]) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        for snap in new {
            let prev = old.first { $0.tool == snap.tool }
            for msg in crossings(old: prev, new: snap) {
                let content = UNMutableNotificationContent()
                content.title = snap.tool == "claude-code" ? "Claude Code" : snap.tool
                content.body = msg
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            }
        }
    }
}
