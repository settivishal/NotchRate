import Foundation
import Testing
@testable import NotchRate

@Test func parsePermissionRequest() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "123.raw")
    try #"{"tool_name":"Bash","tool_input":{"command":"rm -rf build","description":"x"}}"#.write(to: url, atomically: true, encoding: .utf8)
    let r = try #require(Approvals.parse(url))
    #expect(r.id == "123" && r.tool == "Bash" && r.detail == "rm -rf build" && !r.isPlan)
    #expect(r.expires.timeIntervalSinceNow > 10)
    let plan = dir.appending(path: "plan-9.raw")
    try ##"{"tool_name":"ExitPlanMode","tool_input":{"plan":"# Title\n- step"}}"##.write(to: plan, atomically: true, encoding: .utf8)
    let p = try #require(Approvals.parse(plan))
    #expect(p.isPlan && p.plan == "# Title\n- step" && p.expires.timeIntervalSinceNow > 60)
    let out = try #require(JSONSerialization.jsonObject(with: Data(Approvals.planDecision(input: p.input, mode: "acceptEdits").utf8)) as? [String: Any])
    let d = (out["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
    #expect(d?["behavior"] as? String == "allow")
    #expect((d?["updatedInput"] as? [String: Any])?["plan"] as? String == "# Title\n- step")
    #expect(((d?["updatedPermissions"] as? [[String: Any]])?.first?["mode"] as? String) == "acceptEdits")
}

@Test func finishNoticeRespectsMinimumAndTerminal() {
    #expect(AppDelegate.finishNotice(secs: 90, minimum: 60, terminalInFront: false))
    #expect(!AppDelegate.finishNotice(secs: 30, minimum: 60, terminalInFront: false))
    #expect(!AppDelegate.finishNotice(secs: 90, minimum: 60, terminalInFront: true))
    #expect(!AppDelegate.finishNotice(secs: 900, minimum: -1, terminalInFront: false))  // off
    #expect(AppDelegate.finishNotice(secs: 1, minimum: 0, terminalInFront: false))      // always
}
