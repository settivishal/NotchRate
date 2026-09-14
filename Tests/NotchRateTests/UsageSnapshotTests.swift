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
