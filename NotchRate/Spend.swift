import Foundation

/// One billed Claude Code response, reduced to counters. Built from the transcripts Claude Code keeps in
/// ~/.claude/projects: only usage, model, time and working folder are read; message content is never kept.
struct LogRecord: Sendable, Equatable {
    var ts: Double
    var model: String
    var project: String
    var input = 0, write5m = 0, write1h = 0, read = 0, output = 0
    var fast = false

    /// Streamed replies are logged once per content block with running counts: the largest reading is final.
    func merged(_ o: LogRecord) -> LogRecord {
        var r = self
        r.input = max(input, o.input); r.write5m = max(write5m, o.write5m); r.write1h = max(write1h, o.write1h)
        r.read = max(read, o.read); r.output = max(output, o.output)
        return r
    }
}

/// API list prices per million tokens (Anthropic first-party, 2026-09). Cache writes bill 1.25× input for the
/// 5-minute TTL and 2× for 1 hour; reads 0.1× input except where listed; fast mode doubles everything.
enum Pricing {
    struct Rate { let input: Double, output: Double, read: Double }
    static let rates: [String: Rate] = [
        "claude-fable-5-1": Rate(input: 10, output: 50, read: 0.25),
        "claude-fable-5": Rate(input: 10, output: 50, read: 1),
        "claude-mythos-5-1": Rate(input: 10, output: 50, read: 1),
        "claude-mythos-5": Rate(input: 10, output: 50, read: 1),
        "claude-opus-5-5": Rate(input: 4, output: 20, read: 0.2),
        "claude-opus-5": Rate(input: 5, output: 25, read: 0.5),
        "claude-opus-4-8": Rate(input: 5, output: 25, read: 0.5),
        "claude-opus-4-7": Rate(input: 5, output: 25, read: 0.5),
        "claude-opus-4-6": Rate(input: 5, output: 25, read: 0.5),
        "claude-sonnet-5": Rate(input: 2, output: 10, read: 0.2),
        "claude-sonnet-4-6": Rate(input: 3, output: 15, read: 0.3),
        "claude-haiku-4-5": Rate(input: 1, output: 5, read: 0.1),
    ]

    /// Dated snapshots ("claude-haiku-4-5-20251001") price as their base model.
    static func rate(_ model: String) -> Rate? {
        rates[model] ?? rates[model.replacing(/-\d{8}$/, with: "")]
    }

    /// Dollars at API list price; nil for a model without a known price.
    static func cost(_ r: LogRecord) -> Double? {
        guard let p = rate(r.model) else { return nil }
        let tokens = Double(r.input) * p.input + Double(r.write5m) * p.input * 1.25 + Double(r.write1h) * p.input * 2
            + Double(r.read) * p.read + Double(r.output) * p.output
        return tokens / 1_000_000 * (r.fast ? 2 : 1)
    }

    /// "claude-opus-5-5" → "Opus 5.5".
    static func displayName(_ model: String) -> String {
        let parts = model.replacing(/-\d{8}$/, with: "").split(separator: "-").dropFirst(model.hasPrefix("claude-") ? 1 : 0)
        guard let family = parts.first else { return model }
        return ([family.capitalized] + [parts.dropFirst().joined(separator: ".")]).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

enum LogParser {
    /// Pure: one transcript line → dedupe key and record, for assistant lines that carry usage.
    static func parse(_ line: Data) -> (key: String, record: LogRecord)? {
        // Cheap byte filter first: most lines are tool output, attachments and user turns.
        guard line.range(of: Data(#""type":"assistant""#.utf8)) != nil, line.range(of: Data(#""usage""#.utf8)) != nil,
              let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let msg = json["message"] as? [String: Any], let usage = msg["usage"] as? [String: Any],
              let model = msg["model"] as? String, model != "<synthetic>",
              let stamp = json["timestamp"] as? String, let date = timestamp(stamp) else { return nil }
        func n(_ d: [String: Any]?, _ k: String) -> Int { (d?[k] as? NSNumber)?.intValue ?? 0 }
        let creation = usage["cache_creation"] as? [String: Any]
        let write1h = n(creation, "ephemeral_1h_input_tokens")
        let write5m = creation == nil ? n(usage, "cache_creation_input_tokens") : n(creation, "ephemeral_5m_input_tokens")
        let cwd = json["cwd"] as? String ?? ""
        let record = LogRecord(ts: date.timeIntervalSince1970, model: model,
                               project: cwd.isEmpty ? "—" : URL(fileURLWithPath: cwd).lastPathComponent,
                               input: n(usage, "input_tokens"), write5m: write5m, write1h: write1h,
                               read: n(usage, "cache_read_input_tokens"), output: n(usage, "output_tokens"),
                               fast: usage["speed"] as? String == "fast")
        let key = (msg["id"] as? String ?? json["uuid"] as? String ?? "") + ":" + (json["requestId"] as? String ?? "")
        return (key, record)
    }

    static func timestamp(_ s: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(s)) ?? (try? Date.ISO8601FormatStyle().parse(s))
    }
}

/// Spend summary for the card, at API list prices (what the same tokens would cost on the API).
struct Spend: Sendable, Equatable {
    struct Row: Sendable, Equatable { let name: String; let cost: Double }
    var today = 0.0, week = 0.0, month = 0.0
    var byModel: [Row] = []    // last 30 days
    var byProject: [Row] = []  // last 30 days
    var daily: [Date: Double] = [:]  // start of day → cost, last 13 weeks
    var cacheHit: Double?      // share of prompt tokens served from cache, last 30 days
    var unpriced = 0           // responses whose model has no known price

    init(_ records: [LogRecord], now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now).timeIntervalSince1970
        let weekStart = today - 6 * 86400, monthStart = today - 29 * 86400
        var models: [String: Double] = [:], projects: [String: Double] = [:]
        var prompt = 0, cached = 0
        for r in records {
            guard let c = Pricing.cost(r) else { unpriced += 1; continue }
            daily[calendar.startOfDay(for: Date(timeIntervalSince1970: r.ts)), default: 0] += c
            if r.ts >= today { self.today += c }
            if r.ts >= weekStart { week += c }
            guard r.ts >= monthStart else { continue }
            month += c
            models[Pricing.displayName(r.model), default: 0] += c
            projects[r.project, default: 0] += c
            prompt += r.input + r.write5m + r.write1h + r.read
            cached += r.read
        }
        byModel = models.map { Row(name: $0.key, cost: $0.value) }.sorted { $0.cost > $1.cost }
        byProject = projects.map { Row(name: $0.key, cost: $0.value) }.sorted { $0.cost > $1.cost }
        cacheHit = prompt > 0 ? Double(cached) / Double(prompt) : nil
    }
}

/// Incremental reader over ~/.claude/projects: each transcript is read once, then only its appended bytes.
actor LogReader {
    static let window: TimeInterval = 91 * 86400  // 13 weeks, the activity map
    private let root: URL
    private var files: [String: (offset: UInt64, records: [String: LogRecord])] = [:]

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects")) { self.root = root }

    func spend(now: Date = .now) -> Spend {
        let cutoff = now.addingTimeInterval(-Self.window)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        var seen = Set<String>()
        for case let url as URL in FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys)) ?? .init()
        where url.pathExtension == "jsonl" {
            guard let v = try? url.resourceValues(forKeys: keys), let size = v.fileSize,
                  (v.contentModificationDate ?? .distantPast) >= cutoff else { continue }
            seen.insert(url.path)
            read(url, size: UInt64(size))
        }
        files = files.filter { seen.contains($0.key) }
        // Resumed sessions copy earlier replies into a new file: dedupe across files too.
        var all: [String: LogRecord] = [:]
        for (_, f) in files { for (k, r) in f.records where r.ts >= cutoff.timeIntervalSince1970 { all[k] = all[k].map { $0.merged(r) } ?? r } }
        return Spend(Array(all.values), now: now)
    }

    private func read(_ url: URL, size: UInt64) {
        var entry = files[url.path] ?? (0, [:])
        if size < entry.offset { entry = (0, [:]) }  // rewritten: start over
        guard size > entry.offset, let h = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? h.close() }
        try? h.seek(toOffset: entry.offset)
        guard let data = try? h.readToEnd(), let lastNewline = data.lastIndex(of: 10) else { return }
        // Only whole lines: a line still being written is read next time.
        for line in data[..<lastNewline].split(separator: 10) {
            guard let (k, r) = LogParser.parse(Data(line)) else { continue }
            entry.records[k] = entry.records[k].map { $0.merged(r) } ?? r
        }
        entry.offset += UInt64(lastNewline - data.startIndex + 1)
        files[url.path] = entry
    }
}
