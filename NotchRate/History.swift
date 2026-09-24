import Foundation

/// One row per usage change, appended to ~/.notch-usage/history.jsonl.
struct Sample: Codable, Equatable {
    var ts: Double
    var s: Double?  // session %
    var w: Double?  // weekly %
    var c: Double?  // CLI cost_usd (cumulative per Claude Code session)
}

@MainActor
enum History {
    static var file = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".notch-usage/history.jsonl")
    static let keepDays = 8.0
    private static var last: Sample?
    private static var cache: (stamp: Date, rows: [Sample])?  // decoded file, keyed by its modification date

    /// Skip rows that add nothing: same values within 5 minutes of the previous row.
    static func append(_ snap: UsageSnapshot) {
        let row = Sample(ts: snap.lastUpdated, s: snap.sessionUsedPct, w: snap.weeklyUsedPct, c: snap.costUsd)
        if let last, last.s == row.s, last.w == row.w, last.c == row.c, row.ts - last.ts < 300 { return }
        last = row
        guard let line = try? JSONEncoder().encode(row) + Data("\n".utf8) else { return }
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile(); h.write(line); try? h.close()
        } else {
            try? line.write(to: file)  // newline too, or the next row would glue onto this one
        }
    }

    /// The open card re-renders every second while a timer runs; only re-read the file when it changed.
    static func load(now: Date = .now) -> [Sample] {
        let stamp = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        let rows: [Sample]
        if let stamp, let cache, cache.stamp == stamp {
            rows = cache.rows
        } else {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
            rows = text.split(separator: "\n").compactMap { try? JSONDecoder().decode(Sample.self, from: Data($0.utf8)) }
            cache = stamp.map { ($0, rows) }
        }
        let cutoff = now.timeIntervalSince1970 - keepDays * 86400
        let kept = rows.filter { $0.ts >= cutoff }
        if kept.count < rows.count { prune(kept) }
        return kept
    }

    private static func prune(_ rows: [Sample]) {
        let lines = rows.compactMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) }
        try? (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    /// % per hour over the trailing window, ignoring reset drops.
    static func rate(_ rows: [Sample], _ key: KeyPath<Sample, Double?>, hours: Double, now: Date = .now) -> Double {
        let since = now.timeIntervalSince1970 - hours * 3600
        let pts = rows.filter { $0.ts >= since && $0.ts <= now.timeIntervalSince1970 }.compactMap { r in r[keyPath: key].map { (r.ts, $0) } }
        guard pts.count >= 2 else { return 0 }
        var gained = 0.0
        for (a, b) in zip(pts, pts.dropFirst()) where b.1 > a.1 { gained += b.1 - a.1 }
        return gained / max((pts.last!.0 - pts.first!.0) / 3600, 1 / 60)
    }

    /// Session % gained since the last reset drop.
    static func usedThisWindow(_ rows: [Sample]) -> Double {
        let s = rows.compactMap(\.s)
        guard let cur = s.last else { return 0 }
        var low = cur
        for (a, b) in zip(s.dropLast().reversed(), s.reversed()) {
            if a > b + 1 { break }
            low = min(low, a)
        }
        return cur - low
    }
}

/// Derived from history rows inside the current weekly window.
struct WeekStats {
    var daily: [(day: Date, pct: Double)] = []  // 7 calendar days ending today
    var projected = 0.0
    var avgPerDay = 0.0
    var peakSession = 0.0
    var sessions = 0
    var hitLimit = 0
    var cliCost = 0.0

    init(_ rows: [Sample], weeklyResetsAt: Double?, now: Date = .now, calendar: Calendar = .current) {
        let start = (weeklyResetsAt ?? now.timeIntervalSince1970 + 7 * 86400) - 7 * 86400
        let week = rows.filter { $0.ts >= start }
        var byDay: [Date: Double] = [:]
        for (a, b) in zip(week, week.dropFirst()) {
            if let x = a.w, let y = b.w, y > x { byDay[calendar.startOfDay(for: Date(timeIntervalSince1970: b.ts)), default: 0] += y - x }
            if let x = a.c, let y = b.c, y > x { cliCost += y - x }
            if let x = a.s, let y = b.s {
                if y < x - 1 { sessions += 1 }
                if y >= 100, x < 100 { hitLimit += 1 }
            }
        }
        let today = calendar.startOfDay(for: now)
        daily = (0..<7).reversed().map { d in
            let day = calendar.date(byAdding: .day, value: -d, to: today)!
            return (day, byDay[day] ?? 0)
        }
        peakSession = week.compactMap(\.s).max() ?? 0
        let elapsedDays = max((now.timeIntervalSince1970 - start) / 86400, 0.25)
        let current = week.last?.w ?? 0
        avgPerDay = current / elapsedDays
        projected = min(100, current + avgPerDay * max(7 - elapsedDays, 0))
    }
}
