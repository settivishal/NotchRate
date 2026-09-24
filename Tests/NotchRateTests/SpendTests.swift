import Foundation
import Testing
@testable import NotchRate

@Suite struct SpendTests {
    static func line(id: String, ts: String = "2026-09-24T13:41:48.541Z", model: String = "claude-opus-5", output: Int, speed: String = "standard") -> Data {
        Data(#"{"type":"assistant","timestamp":"\#(ts)","requestId":"req_1","cwd":"/Users/x/Coding/App","message":{"id":"\#(id)","model":"\#(model)","content":[{"type":"text","text":"secret"}],"usage":{"input_tokens":1000,"cache_creation_input_tokens":2000,"cache_read_input_tokens":10000,"output_tokens":\#(output),"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":2000},"speed":"\#(speed)"}}}"#.utf8)
    }

    @Test func parsesCountersOnly() throws {
        let (key, r) = try #require(LogParser.parse(Self.line(id: "m1", output: 500)))
        #expect(key == "m1:req_1" && r.project == "App" && r.model == "claude-opus-5")
        #expect(r.input == 1000 && r.write1h == 2000 && r.write5m == 0 && r.read == 10000 && r.output == 500 && !r.fast)
        #expect(LogParser.parse(Data(#"{"type":"user","message":{"content":"hi"}}"#.utf8)) == nil)
    }

    /// Opus 5 ($5 in / $25 out): 1000×5 + 2000×10 (1h write) + 10000×0.5 + 500×25 = 42,500 per MTok units.
    @Test func pricesAtListRates() throws {
        let r = try #require(LogParser.parse(Self.line(id: "m1", output: 500))).record
        #expect(abs(try #require(Pricing.cost(r)) - 0.0425) < 1e-9)
        let fast = try #require(LogParser.parse(Self.line(id: "m1", output: 500, speed: "fast"))).record
        #expect(abs(try #require(Pricing.cost(fast)) - 0.085) < 1e-9)
        #expect(Pricing.rate("claude-haiku-4-5-20251001") != nil && Pricing.rate("sonnet") == nil)
        #expect(Pricing.displayName("claude-opus-5-5") == "Opus 5.5" && Pricing.displayName("claude-haiku-4-5-20251001") == "Haiku 4.5")
    }

    /// Streamed replies repeat the message with growing output; resumed sessions repeat it in a new file.
    @Test func readerDedupesStreamsAndCopies() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appending(path: "p"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date.now, ts = Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(now)
        let a = [Self.line(id: "m1", ts: ts, output: 100), Self.line(id: "m1", ts: ts, output: 500), Self.line(id: "m2", ts: ts, output: 0)]
        try (a.map { $0 + Data("\n".utf8) }.reduce(Data(), +)).write(to: dir.appending(path: "p/a.jsonl"))
        try (Self.line(id: "m1", ts: ts, output: 500) + Data("\n".utf8)).write(to: dir.appending(path: "p/b.jsonl"))
        let reader = LogReader(root: dir)
        let s = await reader.spend(now: now)
        // m1: 0.0425, m2: 0.0425 - 500×25/1M
        #expect(abs(s.today - (0.0425 + 0.03)) < 1e-9, "\(s.today)")
        #expect(s.byProject.map(\.name) == ["App"] && s.cacheHit.map { abs($0 - 20000.0 / 26000) < 1e-9 } == true)
        // Appended bytes are picked up; a half-written line waits.
        let h = try FileHandle(forWritingTo: dir.appending(path: "p/a.jsonl"))
        h.seekToEndOfFile(); h.write(Self.line(id: "m3", ts: ts, output: 0) + Data("\n".utf8) + Data(#"{"type":"assis"#.utf8)); try h.close()
        #expect(abs(await reader.spend(now: now).today - (0.0425 + 0.03 * 2)) < 1e-9)
    }
}
