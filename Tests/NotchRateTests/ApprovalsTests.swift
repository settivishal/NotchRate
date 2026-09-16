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
    try #"{"tool_name":"ExitPlanMode","tool_input":{}}"#.write(to: plan, atomically: true, encoding: .utf8)
    #expect(Approvals.parse(plan)?.isPlan == true)
}
