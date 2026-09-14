import Foundation
import Testing
@testable import NotchRate

@Suite struct UsageSnapshotTests {
    static let sample = """
    {"tool":"claude-code","session_used_pct":67,"session_resets_at":1789364400,"weekly_used_pct":11,
     "weekly_resets_at":1789884000,"cost_usd":1.83,"context_pct":9,"last_updated":1789361195}
    """.data(using: .utf8)!

    @Test func decodesAdapterOutput() throws {
        let s = try UsageSnapshot.decoder.decode(UsageSnapshot.self, from: Self.sample)
        #expect(s.sessionUsedPct == 67)
        #expect(s.weeklyResetsAt == 1789884000)
        #expect(s.peakPct == 67)
    }

    @Test func decodesNulls() throws {
        let s = try UsageSnapshot.decoder.decode(UsageSnapshot.self, from: Data(#"{"tool":"x","last_updated":1}"#.utf8))
        #expect(s.sessionUsedPct == nil)
        #expect(s.peakPct == 0)
    }

    @Test func levelThresholds() {
        #expect(Level(pct: 59.9) == .green)
        #expect(Level(pct: 60) == .yellow)
        #expect(Level(pct: 84.9) == .yellow)
        #expect(Level(pct: 85) == .red)
    }

    @Test func staleAfterThreshold() throws {
        var s = try UsageSnapshot.decoder.decode(UsageSnapshot.self, from: Self.sample)
        let now = Date(timeIntervalSince1970: s.lastUpdated + 7201)
        #expect(s.level(now: now, staleAfter: 7200) == .stale)
        s.lastUpdated += 2
        #expect(s.level(now: now, staleAfter: 7200) == .yellow)
    }

    @Test func notificationCrossings() throws {
        var old = try UsageSnapshot.decoder.decode(UsageSnapshot.self, from: Self.sample)
        var new = old
        new.sessionUsedPct = 90
        #expect(Notifier.crossings(old: old, new: new) == ["Session usage reached 85%"])
        old.sessionUsedPct = 90; new.sessionUsedPct = 100
        #expect(Notifier.crossings(old: old, new: new) == ["Session usage reached 100%"])
        #expect(Notifier.crossings(old: nil, new: new) == ["Session usage reached 85%", "Session usage reached 100%"])
        #expect(Notifier.crossings(old: new, new: new).isEmpty)
    }
}

@Suite @MainActor struct HistoryTests {
    // day 0: weekly 0→4; session 20→90→100, resets to 5; cost 1→3, new session 0→2. day 1: weekly 4→6.
    static let rows: [Sample] = [
        Sample(ts: 0, s: 20, w: 0, c: 1), Sample(ts: 3600, s: 90, w: 2, c: 3), Sample(ts: 7200, s: 100, w: 4, c: 0),
        Sample(ts: 10800, s: 5, w: 4, c: 2), Sample(ts: 86400 + 3600, s: 30, w: 6, c: 2),
    ]

    @Test func weekStats() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .gmt
        let now = Date(timeIntervalSince1970: 86400 + 7200)
        let st = WeekStats(Self.rows, weeklyResetsAt: 6 * 86400, now: now, calendar: cal)
        #expect(st.daily.map(\.pct).suffix(2) == [4, 2])
        #expect(st.sessions == 1)
        #expect(st.hitLimit == 1)
        #expect(st.cliCost == 4)
        #expect(st.peakSession == 100)
    }

    @Test func rateIgnoresResets() {
        let now = Date(timeIntervalSince1970: 10800)
        #expect(abs(History.rate(Self.rows, \.s, hours: 3, now: now) - 80 / 3) < 0.01, "\(History.rate(Self.rows, \.s, hours: 3, now: now))")
    }
}

extension HistoryTests {
    @Test func usedThisWindowStopsAtReset() {
        #expect(History.usedThisWindow(HistoryTests.rows) == 25)  // 5 → 30 after the 100 → 5 drop
    }
}

@Suite @MainActor struct PollerTests {
    @Test func mergeKeepsCliFieldsAndDecodes() throws {
        let api: [String: Any] = [
            "five_hour": ["utilization": 7.0, "resets_at": "2026-09-14T18:20:00.160841+00:00"],
            "seven_day": ["utilization": 13.0, "resets_at": "2026-09-20T06:00:00.160865+00:00"],
            "extra_usage": ["is_enabled": false, "utilization": 50.0],
        ]
        let existing: [String: Any] = ["cost_usd": 8.2, "context_pct": 7, "session_used_pct": 99]
        let out = UsagePoller.merge(api, into: existing, now: Date(timeIntervalSince1970: 1_789_392_000))
        let snap = try UsageSnapshot.decoder.decode(UsageSnapshot.self, from: JSONSerialization.data(withJSONObject: out))
        #expect(snap.sessionUsedPct == 7)
        #expect(snap.weeklyUsedPct == 13)
        #expect(snap.sessionResetsAt.map { Int($0) } == 1_789_410_000)
        #expect(snap.costUsd == 8.2)
        #expect(snap.contextPct == 7)
        #expect(snap.extraPct == nil)
        #expect(snap.lastUpdated == 1_789_392_000)
    }
}

@Suite struct AlertTests {
    @Test func customThresholds() throws {
        var old = try UsageSnapshot.decoder.decode(UsageSnapshot.self, from: UsageSnapshotTests.sample)
        old.sessionUsedPct = 60
        var new = old; new.sessionUsedPct = 71
        #expect(Notifier.crossings(old: old, new: new, thresholds: [70, 90]) == ["Session usage reached 70%"])
    }

    @Test func paceWarnsOnlyWhenFullBeforeReset() throws {
        var s = try UsageSnapshot.decoder.decode(UsageSnapshot.self, from: UsageSnapshotTests.sample)
        let now = Date(timeIntervalSince1970: 0)
        s.sessionUsedPct = 50; s.sessionResetsAt = 2 * 3600
        #expect(Notifier.pace(s, ratePerHour: 50, now: now) != nil)   // full in 1h, resets in 2h
        #expect(Notifier.pace(s, ratePerHour: 20, now: now) == nil)   // full in 2.5h
        #expect(Notifier.pace(s, ratePerHour: 0, now: now) == nil)
    }
}

extension PollerTests {
    @Test func mergeCollectsModelBuckets() throws {
        let api: [String: Any] = [
            "seven_day_opus": ["utilization": 40.0, "resets_at": "2026-09-20T06:00:00.000000+00:00"],
            "seven_day_sonnet": NSNull(), "seven_day_oauth_apps": ["utilization": 1.0],
        ]
        let out = UsagePoller.merge(api, into: [:])
        let snap = try UsageSnapshot.decoder.decode(UsageSnapshot.self, from: JSONSerialization.data(withJSONObject: out))
        #expect(snap.models?.keys.sorted() == ["opus"])
        #expect(snap.models?["opus"]?.pct == 40)
    }
}
