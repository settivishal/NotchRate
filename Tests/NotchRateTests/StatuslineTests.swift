import Foundation
import Testing
@testable import NotchRate

private var sample: [String: Any] {
    ["rate_limits": ["five_hour": ["used_percentage": 42.5, "resets_at": 1757900000], "seven_day": ["used_percentage": 18]],
     "cost": ["total_cost_usd": 1.23], "context_window": ["used_percentage": 37]]
}

@Test func mergeFreshFile() {
    let out = Statusline.merge(sample, into: [:], now: Date(timeIntervalSince1970: 100))
    #expect(out["tool"] as? String == "claude-code")
    #expect(out["session_used_pct"] as? Double == 42.5)
    #expect((out["session_resets_at"] as? NSNumber)?.doubleValue == 1757900000)
    #expect(out["weekly_used_pct"] as? Double == 18)
    #expect(out["cost_usd"] as? Double == 1.23)
    #expect(out["context_pct"] as? Int == 37)
    #expect(out["last_updated"] as? Double == 100)
}

@Test func mergeWithoutRateLimits() {
    let out = Statusline.merge(["cost": ["total_cost_usd": 0]], into: ["session_used_pct": 9])
    #expect(out["session_used_pct"] == nil)
    #expect(out["cost_usd"] as? Int == 0)
}

@Test func apiOwnedFileKeepsLimits() {
    let out = Statusline.merge(sample, into: ["source": "api", "session_used_pct": 51, "weekly_used_pct": 20, "cost_usd": 0])
    #expect(out["source"] as? String == "api")
    #expect(out["session_used_pct"] as? Int == 51)
    #expect(out["weekly_used_pct"] as? Int == 20)
    #expect(out["cost_usd"] as? Double == 1.23)
    #expect(out["context_pct"] as? Int == 37)
}

@Test func ingestConvertsRaw() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try JSONSerialization.data(withJSONObject: sample).write(to: dir.appending(path: "claude-code.raw"))
    Statusline.ingest(directory: dir)
    let out = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appending(path: "claude-code.json"))) as? [String: Any]
    #expect(out?["cost_usd"] as? Double == 1.23)
    #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "claude-code.raw").path))
}

@Test func addHooksIsIdempotentAndKeepsExisting() {
    let existing: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]]]
    let once = Statusline.addHooks(to: existing)
    #expect(Statusline.hooksInstalled(once))
    #expect(!Statusline.hooksInstalled(existing))
    let stop = (once["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
    #expect(stop?.count == 2)
    let twice = Statusline.addHooks(to: once)
    #expect(((twice["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.count == 2)
    let perm = ((twice["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]]
    #expect(perm?.first?["timeout"] as? Int == 30)
    #expect((perm?.first?["command"] as? String)?.hasSuffix("claude-code.sh permission") == true)
}
